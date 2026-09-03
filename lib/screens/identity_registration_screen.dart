import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/patient_profile_service.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class IdentityRegistrationScreen extends StatefulWidget {
  const IdentityRegistrationScreen({super.key});

  @override
  State<IdentityRegistrationScreen> createState() =>
      _IdentityRegistrationScreenState();
}

class _IdentityRegistrationScreenState
    extends State<IdentityRegistrationScreen> {
  final _supabase = Supabase.instance.client;
  final _hnController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _profileService = PatientProfileService();

  // FocusNodes สำหรับควบคุมการเปิดแป้นพิมพ์บน iOS WebKit
  final _hnFocusNode = FocusNode();
  final _firstNameFocusNode = FocusNode();
  final _lastNameFocusNode = FocusNode();

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);

  bool _isLoading = false;
  bool _isFetchingHospitals = true;
  bool _isExistingPatient = true; // true = มี HN, false = ลงทะเบียนใหม่
  List<Map<String, dynamic>> _hospitals = [];
  String? _selectedHospitalId;

  List<String> _savedHnList = [];
  String? _selectedSavedHn;

  @override
  void initState() {
    super.initState();
    _fetchHospitalsAndAutoFill();

    // ⏱️ Safety Fallback Timer: ป้องกันหน้าจอค้างหมุนเกิน 4 วินาที
    Timer(const Duration(seconds: 4), () {
      if (mounted && _isFetchingHospitals) {
        setState(() {
          _isFetchingHospitals = false;
          _ensureFallbackHospital();
        });
      }
    });
  }

  @override
  void dispose() {
    _hnController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _hnFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    super.dispose();
  }

  void _ensureFallbackHospital() {
    if (_hospitals.isEmpty) {
      _hospitals = [
        {'id': 'default-hospital', 'name': 'โรงพยาบาลทั่วไป / คลินิกบริการ'}
      ];
      _selectedHospitalId = 'default-hospital';
    }
  }

  /// 📍 ดึงรายชื่อโรงพยาบาล พร้อม Auto-fill (จำกัด Timeout 3 วินาที)
  Future<void> _fetchHospitalsAndAutoFill() async {
    try {
      final response = await _supabase
          .from('hospitals')
          .select('id, name, code')
          .order('name')
          .timeout(const Duration(seconds: 3), onTimeout: () => []);

      final hospitalList = List<Map<String, dynamic>>.from(response);

      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2), onTimeout: () => throw 'Timeout');
      final hnHistory = prefs.getStringList('saved_hn_history') ?? [];

      final lastInfo = await _profileService
          .getLastLoginInfo()
          .timeout(const Duration(seconds: 2), onTimeout: () => {});
      final savedHn = lastInfo['hn'] ?? '';
      final savedHospitalId = lastInfo['hospital_id'] ?? '';

      final Set<String> hnSet = {};
      if (savedHn.isNotEmpty) hnSet.add(savedHn);
      hnSet.addAll(hnHistory);
      final List<String> uniqueHnList = hnSet.toList();

      if (mounted) {
        setState(() {
          _hospitals = hospitalList;
          _ensureFallbackHospital();

          _savedHnList = uniqueHnList;

          if (_hospitals.isNotEmpty) {
            _selectedHospitalId = _hospitals.first['id'].toString();
          }

          if (savedHospitalId.isNotEmpty &&
              _hospitals.any((h) => h['id'].toString() == savedHospitalId)) {
            _selectedHospitalId = savedHospitalId;
          }

          if (savedHn.isNotEmpty) {
            _hnController.text = savedHn.replaceAll('HN-', '');
            _selectedSavedHn = savedHn;
            _isExistingPatient = true;
          } else if (uniqueHnList.isNotEmpty) {
            _hnController.text = uniqueHnList.first.replaceAll('HN-', '');
            _selectedSavedHn = uniqueHnList.first;
            _isExistingPatient = true;
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error or Timeout fetching hospitals/memory: $e');
      if (mounted) {
        _ensureFallbackHospital();
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingHospitals = false);
      }
    }
  }

  Future<void> _saveHnToHistory(String hn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hnHistory = prefs.getStringList('saved_hn_history') ?? [];
      if (!hnHistory.contains(hn)) {
        hnHistory.insert(0, hn);
        if (hnHistory.length > 10) hnHistory.removeLast();
        await prefs.setStringList('saved_hn_history', hnHistory);
      }
    } catch (e) {
      debugPrint('Error saving HN history: $e');
    }
  }

  /// 📍 กดยืนยันบันทึกข้อมูล
  Future<void> _saveIdentity() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedHospitalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเลือกสถานพยาบาล'),
          backgroundColor: Color(0xFFD97B4F),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
        final currentUser = _supabase.auth.currentUser ??
          (await AuthService().signInAnonymouslyIfNeeded()).user;
      if (currentUser == null) {
        throw Exception('ไม่พบเซสชันผู้ใช้งาน กำลังเชื่อมต่อใหม่...');
      }

      if (_isExistingPatient) {
        // ==================== กรณีผู้ป่วยเดิม (มี HN) ====================
        String rawInput = _hnController.text.trim();
        final hn = rawInput.toUpperCase().startsWith('HN-')
            ? rawInput.toUpperCase()
            : 'HN-${rawInput.toUpperCase()}';

        debugPrint('🔍 ทำการผูกสิทธิ์ HN: "$hn"');

        final dynamic response = await _supabase.rpc(
          'claim_existing_hn',
          params: {
            'p_hn': hn,
            'p_hospital_id': _selectedHospitalId == 'default-hospital'
                ? null
                : _selectedHospitalId,
          },
        ).timeout(const Duration(seconds: 8), onTimeout: () {
          throw Exception('การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง');
        });

        if (response == null) {
          throw Exception('ไม่พบข้อมูลผู้ป่วยรหัส $hn ในระบบ');
        }

        final Map<String, dynamic> updateResponse =
            Map<String, dynamic>.from(response);

        await _profileService.saveProfile(updateResponse);
        await _saveHnToHistory(hn);
      } else {
        // ==================== กรณีลงทะเบียนผู้ป่วยใหม่ ====================
        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        String rawHn = _hnController.text.trim();

        final newHn = rawHn.isNotEmpty
            ? (rawHn.toUpperCase().startsWith('HN-')
                ? rawHn.toUpperCase()
                : 'HN-${rawHn.toUpperCase()}')
            : 'HN-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

        final newPatientData = {
          'auth_user_id': currentUser.id,
          if (_selectedHospitalId != 'default-hospital')
            'hospital_id': _selectedHospitalId,
          'hn': newHn,
          'first_name': firstName,
          'last_name': lastName,
          'name': '$firstName $lastName',
        };

        final inserted = await _supabase
            .from('patients')
            .insert(newPatientData)
            .select()
            .single()
            .timeout(const Duration(seconds: 8));

        await _profileService.saveProfile(inserted);
        await _saveHnToHistory(newHn);
      }

      if (!mounted) return;

      if (_isExistingPatient) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ Save Identity Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'เกิดข้อผิดพลาด: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(
          'ยืนยันตัวตนผู้ป่วย',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isFetchingHospitals
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: emeraldTheme),
                  SizedBox(height: 12),
                  Text('กำลังเตรียมข้อมูลระบบ...',
                      style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                ],
              ),
            )
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🌟 ส่วนเลือกสถานะผู้ป่วย
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: softCardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEADBCE)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    setState(() => _isExistingPatient = true),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _isExistingPatient
                                        ? emeraldTheme
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'ผู้ป่วยเดิม (มี HN)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: _isExistingPatient
                                            ? Colors.white
                                            : secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    setState(() => _isExistingPatient = false),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: !_isExistingPatient
                                        ? emeraldTheme
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'ผู้ป่วยใหม่ (ไม่มี HN)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: !_isExistingPatient
                                            ? Colors.white
                                            : secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 🏢 กล่องฟอร์มกรอกข้อมูล
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: const Color(0xFFF0E5D8), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. สถานพยาบาล
                            const Text(
                              'สถานพยาบาล / คลินิก',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _hospitals.any((h) =>
                                      h['id'].toString() == _selectedHospitalId)
                                  ? _selectedHospitalId
                                  : (_hospitals.isNotEmpty
                                      ? _hospitals.first['id'].toString()
                                      : null),
                              style: const TextStyle(
                                  color: primaryTextColor, fontSize: 14),
                              decoration: _inputDecoration(
                                'เลือกสถานพยาบาล',
                                Icons.local_hospital_rounded,
                              ),
                              items: _hospitals.map((hospital) {
                                return DropdownMenuItem<String>(
                                  value: hospital['id'].toString(),
                                  child: Text(
                                    hospital['name'] ?? 'สถานพยาบาล',
                                    style: const TextStyle(
                                        fontSize: 14, color: primaryTextColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedHospitalId = val);
                                }
                              },
                            ),
                            const SizedBox(height: 20),

                            // 2. ฟิลด์ข้อมูลตามโหมด
                            if (_isExistingPatient) ...[
                              // โหมดผู้ป่วยเดิม: กรอกเลข HN (มี Prefix HN- ให้อัตโนมัติ)
                              const Text(
                                'รหัส HN (เลขประจำตัวผู้ป่วย)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _hnController,
                                focusNode: _hnFocusNode,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(
                                    color: primaryTextColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                                decoration: _inputDecoration(
                                  'พิมพ์เฉพาะตัวเลข เช่น 16914',
                                  Icons.badge_rounded,
                                  prefixText: 'HN- ',
                                ),
                                validator: (val) =>
                                    (val == null || val.trim().isEmpty)
                                        ? 'กรุณาระบุเลข HN'
                                        : null,
                              ),
                            ] else ...[
                              // โหมดผู้ป่วยใหม่: กรอกชื่อจริง นามสกุล และเลข HN (ถ้ามี)
                              const Text(
                                'ชื่อจริง',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _firstNameController,
                                focusNode: _firstNameFocusNode,
                                keyboardType: TextInputType.name,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                    color: primaryTextColor, fontSize: 15),
                                decoration: _inputDecoration(
                                    'ระบุชื่อจริง', Icons.person_rounded),
                                validator: (val) =>
                                    (val == null || val.trim().isEmpty)
                                        ? 'กรุณากรอกชื่อ'
                                        : null,
                              ),
                              const SizedBox(height: 16),

                              const Text(
                                'นามสกุล',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _lastNameController,
                                focusNode: _lastNameFocusNode,
                                keyboardType: TextInputType.name,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                    color: primaryTextColor, fontSize: 15),
                                decoration: _inputDecoration('ระบุนามสกุล',
                                    Icons.person_outline_rounded),
                                validator: (val) =>
                                    (val == null || val.trim().isEmpty)
                                        ? 'กรุณากรอกนามสกุล'
                                        : null,
                              ),
                              const SizedBox(height: 16),

                              const Text(
                                'รหัส HN (ถ้ามี หรือเว้นว่างให้ระบบสร้าง)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _hnController,
                                focusNode: _hnFocusNode,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(
                                    color: primaryTextColor, fontSize: 15),
                                decoration: _inputDecoration(
                                  'เว้นว่างไว้หากไม่มี HN เดิม',
                                  Icons.pin_rounded,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 🔘 ปุ่มบันทึกและเข้าใช้งาน
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emeraldTheme,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 2,
                          ),
                          onPressed: _isLoading ? null : _saveIdentity,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  _isExistingPatient
                                      ? "ยืนยันและเข้าสู่ระบบ"
                                      : "ลงทะเบียนและเริ่มต้นใช้งาน",
                                  style: const TextStyle(
                                    fontSize: 17,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon,
      {String? prefixText}) {
    return InputDecoration(
      hintText: hint,
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        color: emeraldTheme,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
      hintStyle: const TextStyle(color: mutedTextColor, fontSize: 13),
      prefixIcon: Icon(icon, color: emeraldTheme, size: 20),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEADBCE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEADBCE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: emeraldTheme, width: 1.5),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);

  bool _isLoading = false;
  bool _isFetchingHospitals = true;
  bool _isExistingPatient = true; // Default: ผู้ป่วยเก่า (มี HN)
  List<Map<String, dynamic>> _hospitals = [];
  String? _selectedHospitalId;

  // 🚀 ตัวแปรสำหรับ Smart HN Memory (Dropdown ประวัติ HN)
  List<String> _savedHnList = [];
  String? _selectedSavedHn;

  @override
  void initState() {
    super.initState();
    _fetchHospitalsAndAutoFill();
  }

  @override
  void dispose() {
    _hnController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  /// 📍 ดึงรายชื่อโรงพยาบาล พร้อม Auto-fill ข้อมูล Smart HN Memory
  Future<void> _fetchHospitalsAndAutoFill() async {
    setState(() => _isFetchingHospitals = true);
    try {
      final response = await _supabase
          .from('hospitals')
          .select('id, name, code')
          .order('name');

      final hospitalList = List<Map<String, dynamic>>.from(response);

      final prefs = await SharedPreferences.getInstance();
      final hnHistory = prefs.getStringList('saved_hn_history') ?? [];

      final lastInfo = await _profileService.getLastLoginInfo();
      final savedHn = lastInfo['hn'] ?? '';
      final savedHospitalId = lastInfo['hospital_id'] ?? '';

      final Set<String> hnSet = {};
      if (savedHn.isNotEmpty) hnSet.add(savedHn);
      hnSet.addAll(hnHistory);
      final List<String> uniqueHnList = hnSet.toList();

      setState(() {
        _hospitals = hospitalList;
        _savedHnList = uniqueHnList;

        if (hospitalList.isNotEmpty) {
          _selectedHospitalId = hospitalList.first['id'].toString();
        }

        if (savedHospitalId.isNotEmpty &&
            hospitalList.any((h) => h['id'].toString() == savedHospitalId)) {
          _selectedHospitalId = savedHospitalId;
        }

        if (savedHn.isNotEmpty) {
          _hnController.text = savedHn;
          _selectedSavedHn = savedHn;
          _isExistingPatient = true;
        } else if (uniqueHnList.isNotEmpty) {
          _hnController.text = uniqueHnList.first;
          _selectedSavedHn = uniqueHnList.first;
          _isExistingPatient = true;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error fetching hospitals or HN memory: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingHospitals = false);
      }
    }
  }

  /// 📍 บันทึก HN เข้ารายการประวัติใน SharedPreferences
  Future<void> _saveHnToHistory(String hn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hnHistory = prefs.getStringList('saved_hn_history') ?? [];
      if (!hnHistory.contains(hn)) {
        hnHistory.insert(0, hn);
        if (hnHistory.length > 10) {
          hnHistory.removeLast();
        }
        await prefs.setStringList('saved_hn_history', hnHistory);
      }
    } catch (e) {
      debugPrint('Error saving HN history: $e');
    }
  }

  /// 📍 บันทึก/ยืนยันตัวตน (ระบบ Anonymous Auth)
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
      final currentUser = _supabase.auth.currentUser;

      if (currentUser == null) {
        throw Exception('ไม่พบเซสชันผู้ใช้งาน กรุณาลองใหม่อีกครั้ง');
      }

      if (_isExistingPatient) {
        // ==================== ผู้ป่วยเก่า ====================
        String hnInput = _hnController.text.trim();
        final hn = hnInput.toUpperCase().startsWith('HN-')
            ? hnInput.toUpperCase()
            : 'HN-${hnInput.toUpperCase()}';

        debugPrint('🔍 กำลังเรียก RPC ผูกบัญชีกับ HN: "$hn"');

        final dynamic response = await _supabase.rpc(
          'claim_existing_hn',
          params: {
            'p_hn': hn,
            'p_hospital_id': _selectedHospitalId,
          },
        ).timeout(const Duration(seconds: 10), onTimeout: () {
          throw Exception('การเชื่อมต่อกับเซิร์ฟเวอร์ใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง');
        });

        if (response == null) {
          throw Exception('ไม่พบข้อมูลผู้ป่วยรหัส HN: $hn ในสถานพยาบาลที่เลือก');
        }

        final Map<String, dynamic> updateResponse = Map<String, dynamic>.from(response);

        await _profileService.saveProfile(updateResponse);
        await _saveHnToHistory(hn);
      } else {
        // ==================== ผู้ป่วยใหม่ ====================
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
            .timeout(const Duration(seconds: 10));

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
      debugPrint('❌ เกิดข้อผิดพลาด: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      appBar: AppBar(
        title: const Text(
          'ยืนยันตัวตน / ลงทะเบียนผู้ป่วย',
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
          ? const Center(child: CircularProgressIndicator(color: emeraldTheme))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🌟 Toggle สลับโหมด (ผู้ป่วยเก่า / ผู้ป่วยใหม่)
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _isExistingPatient
                                      ? emeraldTheme
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'ผู้ป่วยเก่า (มี HN)',
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
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

                    // 🏢 กล่องฟอร์มหลัก
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
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
                          // 1. เลือกสถานพยาบาล
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
                            value: _selectedHospitalId,
                            style: const TextStyle(color: primaryTextColor, fontSize: 14),
                            decoration: _inputDecoration(
                              'เลือกสถานพยาบาล',
                              Icons.local_hospital_rounded,
                            ),
                            items: _hospitals.map((hospital) {
                              return DropdownMenuItem<String>(
                                value: hospital['id'].toString(),
                                child: Text(
                                  hospital['name'] ?? 'ไม่ระบุชื่อ',
                                  style: const TextStyle(fontSize: 14, color: primaryTextColor),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedHospitalId = val),
                            validator: (val) =>
                                val == null ? 'กรุณาเลือกสถานพยาบาล' : null,
                          ),
                          const SizedBox(height: 20),

                          // 2. ฟอร์มกรอก HN หรือ ข้อมูลผู้ป่วยใหม่
                          if (_isExistingPatient) ...[
                            if (_savedHnList.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3E4),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF4C7A3F).withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.history_rounded, color: Color(0xFF3E5E33), size: 18),
                                        SizedBox(width: 6),
                                        Text(
                                          'เลือกเลข HN ที่เคยบันทึกไว้',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF3E5E33),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: _savedHnList.contains(_selectedSavedHn)
                                          ? _selectedSavedHn
                                          : null,
                                      hint: const Text(
                                        '-- แตะเลือกเลข HN เดิม --',
                                        style: TextStyle(color: secondaryTextColor, fontSize: 13),
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.white,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFEADBCE)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFEADBCE)),
                                        ),
                                      ),
                                      items: _savedHnList.map((hn) {
                                        return DropdownMenuItem<String>(
                                          value: hn,
                                          child: Text(
                                            'HN: $hn',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: primaryTextColor,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _selectedSavedHn = val;
                                            _hnController.text = val;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Center(
                                child: Text(
                                  '— หรือพิมพ์ระบุเลข HN ด้านล่าง —',
                                  style: TextStyle(fontSize: 12, color: mutedTextColor),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

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
                              style: const TextStyle(color: primaryTextColor, fontSize: 15),
                              decoration: _inputDecoration('เช่น 16914', Icons.badge_rounded),
                              onChanged: (val) {
                                if (_selectedSavedHn != val) {
                                  setState(() => _selectedSavedHn = null);
                                }
                              },
                              validator: (val) => (val == null || val.trim().isEmpty)
                                  ? 'กรุณากรอกรหัส HN'
                                  : null,
                            ),
                          ] else ...[
                            const Text(
                              'ชื่อผู้ป่วย',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _firstNameController,
                              style: const TextStyle(color: primaryTextColor, fontSize: 15),
                              decoration: _inputDecoration('กรอกชื่อจริง', Icons.person_rounded),
                              validator: (val) => (val == null || val.trim().isEmpty)
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
                              style: const TextStyle(color: primaryTextColor, fontSize: 15),
                              decoration: _inputDecoration('กรอกนามสกุล', Icons.person_outline_rounded),
                              validator: (val) => (val == null || val.trim().isEmpty)
                                  ? 'กรุณากรอกนามสกุล'
                                  : null,
                            ),
                            const SizedBox(height: 16),

                            const Text(
                              'รหัส HN (ระบุเอง หรือเว้นว่างไว้)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _hnController,
                              style: const TextStyle(color: primaryTextColor, fontSize: 15),
                              decoration: _inputDecoration(
                                'เว้นว่างไว้หากต้องการให้ระบบสร้างให้อัตโนมัติ',
                                Icons.pin_rounded,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 🔘 ปุ่มยืนยัน
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
                            ? const CircularProgressIndicator(color: Colors.white)
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
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // 🎨 Palette สีตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);

  bool _isLoading = false;
  bool _isFetchingHospitals = true;
  bool _isExistingPatient = true; // Default: ผู้ป่วยเก่า
  List<Map<String, dynamic>> _hospitals = [];
  String? _selectedHospitalId;

  // 🌟 ตัวแปรสำหรับการจดจำตัวตนคนไข้เดิม 100% (Instant Quick Login)
  Map<String, dynamic>? _lastSavedProfile;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _hnController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  /// 📍 ดึงรายชื่อโรงพยาบาล และโหลดประวัติผู้ใช้งานคนล่าสุดเพื่อทำ Instant Card
  Future<void> _fetchInitialData() async {
    setState(() => _isFetchingHospitals = true);
    try {
      final response = await _supabase
          .from('hospitals')
          .select('id, name, code')
          .order('name');

      final hospitalList = List<Map<String, dynamic>>.from(response);

      // โหลดโปรไฟล์เดิมที่เคยล็อกอินไว้ในเครื่อง
      final cachedProfile = await _profileService.getProfile();
      final lastInfo = await _profileService.getLastLoginInfo();
      final savedHn = cachedProfile?['hn'] ?? lastInfo['hn'] ?? '';
      final savedHospitalId =
          cachedProfile?['hospital_id'] ?? lastInfo['hospital_id'] ?? '';

      setState(() {
        _hospitals = hospitalList;

        if (hospitalList.isNotEmpty) {
          _selectedHospitalId = hospitalList.first['id'].toString();
        }

        if (savedHospitalId.isNotEmpty &&
            hospitalList.any((h) => h['id'].toString() == savedHospitalId)) {
          _selectedHospitalId = savedHospitalId;
        }

        if (cachedProfile != null && savedHn.isNotEmpty) {
          _lastSavedProfile = cachedProfile;
          // ล้างคำนำหน้า HN- ออก เพื่อให้แสดงแต่ตัวเลขในกล่องกรอก
          _hnController.text = _cleanHnNumber(savedHn);
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error loading initial identity data: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingHospitals = false);
      }
    }
  }

  /// 🧹 ฟังก์ชันตัดคำว่า HN / HN- ออก ให้เหลือแต่ตัวเลขสำหรับแสดงผล
  String _cleanHnNumber(String raw) {
    String cleaned = raw.trim();
    if (cleaned.toUpperCase().startsWith('HN-')) {
      return cleaned.substring(3).trim();
    } else if (cleaned.toUpperCase().startsWith('HN')) {
      return cleaned.substring(2).trim();
    }
    return cleaned;
  }

  /// 🛠️ ฟังก์ชันจัดรูปแบบ HN ส่งเข้า Database ให้ได้มาตรฐาน HN-XXXXX เสมอ
  String _formatHnForDatabase(String raw) {
    String cleaned = _cleanHnNumber(raw).toUpperCase();
    return 'HN-$cleaned';
  }

  /// 🚀 ทางลัดสำหรับผู้สูงอายุ: ล็อกอินต่อด้วยบัญชีเดิมทันที (ไม่ต้องกรอกอะไร)
  Future<void> _continueWithExistingAccount() async {
    if (_lastSavedProfile == null) return;
    setState(() => _isLoading = true);

    try {
      final hn = _lastSavedProfile!['hn'];
      final hospitalId = _lastSavedProfile!['hospital_id'] ?? _selectedHospitalId;

      // เรียก RPC ผูกสิทธิ์ให้แน่ใจว่าเซสชันยังทำงานได้ปกติ
      final dynamic response = await _supabase.rpc(
        'claim_existing_hn',
        params: {
          'p_hn': hn,
          'p_hospital_id': hospitalId,
        },
      ).timeout(const Duration(seconds: 10));

      if (response != null) {
        await _profileService.saveProfile(Map<String, dynamic>.from(response));
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      debugPrint('Auto-login error: $e');
      // หากเกิดปัญหา ให้เข้าสู่หน้าหลักด้วย Profile ในเครื่องทันที
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 📍 บันทึก/ยืนยันตัวตน
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
        final hn = _formatHnForDatabase(_hnController.text);

        debugPrint('🔍 กำลังยืนยันรหัส HN: "$hn"');

        final dynamic response = await _supabase.rpc(
          'claim_existing_hn',
          params: {
            'p_hn': hn,
            'p_hospital_id': _selectedHospitalId,
          },
        ).timeout(const Duration(seconds: 10), onTimeout: () {
          throw Exception('การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง');
        });

        if (response == null) {
          throw Exception('ไม่พบข้อมูลผู้ป่วยรหัส HN: $hn ในสถานพยาบาลที่เลือก');
        }

        final Map<String, dynamic> updateResponse =
            Map<String, dynamic>.from(response);

        await _profileService.saveProfile(updateResponse);
      } else {
        // ==================== ผู้ป่วยใหม่ ====================
        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();

        String rawHn = _hnController.text.trim();
        final newHn = rawHn.isNotEmpty
            ? _formatHnForDatabase(rawHn)
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
      debugPrint('❌ Error saving identity: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'เกิดข้อผิดพลาด: ${e.toString().replaceAll("Exception: ", "")}',
            style: const TextStyle(fontSize: 14),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          'เข้าสู่ระบบผู้ป่วย NCDs',
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
                    // 🌟 1. การ์ดจดจำคนไข้เดิม 100% (Instant Login Card)
                    if (_lastSavedProfile != null) ...[
                      _buildRememberedPatientCard(),
                      const SizedBox(height: 22),
                      const Center(
                        child: Text(
                          '— หรือระบุข้อมูลใหม่ด้านล่าง —',
                          style: TextStyle(fontSize: 13, color: mutedTextColor),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // 🌟 2. สลับโหมด (ผู้ป่วยเก่า / ผู้ป่วยใหม่)
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
                                    'มีเลข HN แล้ว',
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
                                    'ลงทะเบียนใหม่ (ไม่มี HN)',
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
                    const SizedBox(height: 18),

                    // 🏢 3. กล่องฟอร์มกรอกข้อมูล
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
                          // 3.1 เลือกโรงพยาบาล
                          const Text(
                            'สถานพยาบาล / รพ.สต.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedHospitalId,
                            isExpanded: true,
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
                                  hospital['name'] ?? 'ไม่ระบุชื่อ',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14, color: primaryTextColor),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedHospitalId = val),
                            validator: (val) =>
                                val == null ? 'กรุณาเลือกสถานพยาบาล' : null,
                          ),
                          const SizedBox(height: 20),

                          // 3.2 ช่องกรอกเลข HN หรือข้อมูลผู้ป่วยใหม่
                          if (_isExistingPatient) ...[
                            const Text(
                              'เลขประจำตัวผู้ป่วย (HN)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ช่องกรอกที่ล็อกคำว่า "HN-" ไว้ข้างหน้าอัตโนมัติ
                            TextFormField(
                              controller: _hnController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                color: primaryTextColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                              decoration: InputDecoration(
                                prefixIcon: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  child: const Text(
                                    'HN -',
                                    style: TextStyle(
                                      color: emeraldTheme,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                    minWidth: 0, minHeight: 0),
                                hintText: 'กรอกเฉพาะตัวเลข (เช่น 16914)',
                                hintStyle: const TextStyle(
                                  color: mutedTextColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFFAFAFA),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFEADBCE)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFEADBCE)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: emeraldTheme, width: 2),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'กรุณากรอกตัวเลข HN';
                                }
                                return null;
                              },
                            ),
                          ] else ...[
                            const Text(
                              'ชื่อจริงผู้ป่วย',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _firstNameController,
                              style: const TextStyle(
                                  color: primaryTextColor, fontSize: 15),
                              decoration: _inputDecoration(
                                  'กรอกชื่อจริง', Icons.person_rounded),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                      ? 'กรุณากรอกชื่อจริง'
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
                              style: const TextStyle(
                                  color: primaryTextColor, fontSize: 15),
                              decoration: _inputDecoration(
                                  'กรอกนามสกุล', Icons.person_outline_rounded),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                      ? 'กรุณากรอกนามสกุล'
                                      : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 🔘 ปุ่มบันทึก/เข้าสู่ระบบ
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

  /// 🌟 การ์ดโปรไฟล์เดิมสำหรับผู้สูงอายุ (แตะปุ่มเดียวเข้าแอปได้ทันที)
  Widget _buildRememberedPatientCard() {
    final name = _lastSavedProfile!['first_name'] != null
        ? '${_lastSavedProfile!['first_name']} ${_lastSavedProfile!['last_name'] ?? ''}'
        : (_lastSavedProfile!['name'] ?? 'ผู้ใช้งานเดิม');
    final hn = _lastSavedProfile!['hn'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4C7A3F).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFD9EBCF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_circle_rounded,
                  color: Color(0xFF3E5E33),
                  size: 28,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'พบข้อมูลผู้ป่วยเดิมในเครื่องนี้',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5C7A50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'คุณ $name',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  hn,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: emeraldTheme,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3E5E33),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _continueWithExistingAccount,
              icon: const Icon(Icons.touch_app_rounded, color: Colors.white, size: 20),
              label: const Text(
                'แตะเพื่อเข้าใช้งานต่อทันที',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
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
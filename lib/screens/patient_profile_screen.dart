import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../services/vital_repository.dart';
import '../services/th_cv_risk_calculator.dart';
import '../widgets/bmi_bar_chart.dart';

class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = PatientProfileService();
  final _dbService = PatientDatabaseService();
  final _vitalRepository = VitalRepository();

  final _fNameController = TextEditingController();
  final _lNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _bmiController = TextEditingController();
  final _diseaseController = TextEditingController();

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color earthyBrown = Color(0xFFB37B57);
  static const Color softCardBg = Color(0xFFFBF6EE);

  String _gender = 'ชาย';
  String _activityLevel = 'sedentary';
  double _bmr = 0.0;
  double _tdee = 0.0;

  bool _isSmoker = false;
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _latestLab;
  int _latestSystolic = 120;

  // 🔔 ตัวแปรสำหรับการแจ้งเตือน LINE
  bool _notifyBpInactive = true;
  String? _lineUserId;
  String _lineRecipientRole = 'patient'; // 'patient' หรือ 'caregiver'

  final Map<String, Map<String, dynamic>> _activityOptions = {
    'sedentary': {
      'label': 'นั่งทำงานอยู่กับที่ (ไม่ออกกำลังกาย)',
      'multiplier': 1.2,
    },
    'light': {
      'label': 'ออกกำลังกายเบาๆ (1-3 วัน/สัปดาห์)',
      'multiplier': 1.375,
    },
    'moderate': {
      'label': 'ออกกำลังกายปานกลาง (3-5 วัน/สัปดาห์)',
      'multiplier': 1.55,
    },
    'active': {
      'label': 'ออกกำลังกายหนัก (6-7 วัน/สัปดาห์)',
      'multiplier': 1.725,
    },
    'very_active': {
      'label': 'ใช้แรงงานหนัก / ซ้อมกีฬาหนัก',
      'multiplier': 1.9,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadProfileFast();
  }

  Future<void> _loadProfileFast() async {
    try {
      final profile = await _profileService.getProfile();
      if (profile != null) {
        setState(() {
          _profileData = profile;
          _fNameController.text = profile['first_name'] ?? '';
          _lNameController.text = profile['last_name'] ?? '';
          _ageController.text = (profile['age'] ?? '').toString();
          _weightController.text =
              (profile['weight_kg'] ?? profile['weight'] ?? '').toString();
          _heightController.text =
              (profile['height_cm'] ?? profile['height'] ?? '').toString();
          _bmiController.text = (profile['bmi'] ?? '').toString();
          _diseaseController.text =
              profile['underlying_diseases'] ?? profile['diseases'] ?? '';
          _isSmoker = profile['smokes'] == true || profile['smokers'] == true;
          _gender = profile['gender']?.toString() ?? 'ชาย';
          _activityLevel = profile['activity_level']?.toString() ?? 'sedentary';
          _notifyBpInactive = profile['notify_bp_inactive'] ?? true;
          _lineUserId = profile['line_user_id'];
          _lineRecipientRole = profile['line_recipient_role'] ?? 'patient';

          if (!_activityOptions.containsKey(_activityLevel)) {
            _activityLevel = 'sedentary';
          }

          _calculateMetrics();
          _isLoading = false;
        });

        if (profile['id'] != null) {
          _loadBackgroundData(profile['id'].toString());
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading profile fast: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBackgroundData(String patientId) async {
    try {
      final labs = await _dbService.getLabResults(patientId);
      final vitals = await _vitalRepository.getLast7Days(patientId);

      if (mounted) {
        setState(() {
          if (labs.isNotEmpty) _latestLab = labs.first;
          if (vitals.isNotEmpty) {
            _latestSystolic =
                (vitals.first['systolic'] as num?)?.toInt() ?? 120;
          }
        });
      }
    } catch (e) {
      debugPrint('Background data fetch error: $e');
    }
  }

  void _calculateMetrics() {
    final weight = double.tryParse(_weightController.text) ?? 0.0;
    final height = double.tryParse(_heightController.text) ?? 0.0;
    final age = int.tryParse(_ageController.text) ?? 0;

    double bmi = 0.0;
    if (height > 0 && weight > 0) {
      final heightInMeter = height / 100;
      bmi = weight / (heightInMeter * heightInMeter);
      _bmiController.text = bmi.toStringAsFixed(1);
    }

    double bmr = 0.0;
    if (weight > 0 && height > 0 && age > 0) {
      if (_gender == 'ชาย') {
        bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
      } else {
        bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
      }
    }

    final multiplier =
        _activityOptions[_activityLevel]?['multiplier'] as double? ?? 1.2;
    final tdee = bmr * multiplier;

    _bmr = bmr;
    _tdee = tdee;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    _calculateMetrics();

    final fName = _fNameController.text.trim();
    final lName = _lNameController.text.trim();
    final weight = double.tryParse(_weightController.text) ?? 0.0;
    final height = double.tryParse(_heightController.text) ?? 0.0;
    final age = int.tryParse(_ageController.text) ?? 0;
    final bmi = double.tryParse(_bmiController.text) ?? 0.0;

    final updateData = {
      'first_name': fName,
      'last_name': lName,
      'name': '$fName $lName',
      'age': age,
      'gender': _gender,
      'weight': weight,
      'weight_kg': weight,
      'height': height,
      'height_cm': height,
      'bmi': bmi,
      'bmr': double.parse(_bmr.toStringAsFixed(1)),
      'tdee': double.parse(_tdee.toStringAsFixed(1)),
      'activity_level': _activityLevel,
      'underlying_diseases': _diseaseController.text.trim(),
      'smokes': _isSmoker,
      'notify_bp_inactive': _notifyBpInactive,
      'line_recipient_role': _lineRecipientRole,
    };

    String? errorMessage;

    try {
      final patientId = await _profileService.getCurrentPatientId();
      final currentProfile = await _profileService.getProfile();
      final hn = currentProfile?['hn'];
      final hospitalId = currentProfile?['hospital_id'];

      final supabasePayload = {
        'first_name': updateData['first_name'],
        'last_name': updateData['last_name'],
        'name': updateData['name'],
        'age': updateData['age'],
        'gender': updateData['gender'],
        'weight_kg': updateData['weight_kg'],
        'height_cm': updateData['height_cm'],
        'bmi': updateData['bmi'],
        'bmr': updateData['bmr'],
        'tdee': updateData['tdee'],
        'activity_level': updateData['activity_level'],
        'underlying_diseases': updateData['underlying_diseases'],
        'smokes': updateData['smokes'],
        'notify_bp_inactive': updateData['notify_bp_inactive'],
        'line_recipient_role': updateData['line_recipient_role'],
      };

      if (patientId != null && patientId.isNotEmpty) {
        await Supabase.instance.client
            .from('patients')
            .update(supabasePayload)
            .eq('id', patientId);
      } else if (hn != null && hospitalId != null) {
        await Supabase.instance.client
            .from('patients')
            .update(supabasePayload)
            .eq('hn', hn)
            .eq('hospital_id', hospitalId);
      }

      await _profileService.updateLocalProfile(updateData);
    } catch (e) {
      debugPrint('Error syncing profile: $e');
      errorMessage = e.toString();
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (errorMessage == null) {
          _profileData?.addAll(updateData);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage == null
              ? 'บันทึกข้อมูลเรียบร้อยแล้ว'
              : 'เกิดข้อผิดพลาดในการบันทึก: $errorMessage'),
          backgroundColor: errorMessage == null ? emeraldTheme : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // 🔔 1. การ์ด LINE แบบมินิมอล ไม่รกหน้าจอ
  Widget _buildLineNotificationSettingCard() {
    final bool isLineConnected = _lineUserId != null && _lineUserId!.isNotEmpty;
    final bool isCaregiver = _lineRecipientRole == 'caregiver';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06C755).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF06C755), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'การแจ้งเตือนผ่าน LINE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLineConnected ? const Color(0xFFEAF3E4) : const Color(0xFF06C755),
                  foregroundColor: isLineConnected ? const Color(0xFF2E6325) : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showLineConnectionDialog,
                child: Text(
                  isLineConnected ? 'จัดการ / เปลี่ยน' : 'ตั้งค่าเชื่อมต่อ',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // แถบแสดงสถานะปัจจุบัน
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isLineConnected ? const Color(0xFFF4F9F1) : const Color(0xFFFFF9F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLineConnected ? const Color(0xFF4C7A3F).withValues(alpha: 0.25) : const Color(0xFFFCD34D),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isLineConnected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: isLineConnected ? emeraldTheme : const Color(0xFFD97706),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLineConnected
                        ? 'เชื่อมต่อแล้ว: แจ้งเตือนไปยัง [${isCaregiver ? 'ญาติ/ผู้ดูแล' : 'คนไข้เอง'}]'
                        : 'ยังไม่ได้เชื่อมต่อ LINE (จะไม่ได้รับข้อความเตือนยา/ความดัน)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isLineConnected ? const Color(0xFF3E5E33) : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // สวิตช์เปิด/ปิด เตือนความดัน 24 ชม.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'เตือนเมื่อไม่วัดความดันเกิน 24 ชม.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
            ),
            value: _notifyBpInactive,
            activeColor: emeraldTheme,
            onChanged: (val) async {
              setState(() => _notifyBpInactive = val);
              final patientId = await _profileService.getCurrentPatientId();
              if (patientId != null) {
                await Supabase.instance.client
                    .from('patients')
                    .update({'notify_bp_inactive': val})
                    .eq('id', patientId);
                await _profileService.updateLocalProfile({'notify_bp_inactive': val});
              }
            },
          ),
        ],
      ),
    );
  }

  // 🔔 2. Pop-up Modal จัดการเชื่อมต่อ LINE พร้อมเลือก คนไข้ VS ญาติ
  void _showLineConnectionDialog() {
    String selectedRole = _lineRecipientRole;
    final manualIdCtrl = TextEditingController(text: _lineUserId ?? '');
    String pairingCode = (100000 + Random().nextInt(900000)).toString();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF06C755).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF06C755), size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ตั้งค่าการแจ้งเตือน LINE',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                const Text(
                  '1. เลือกผู้รับการแจ้งเตือน:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 10),

                // ตัวเลือก Role: คนไข้ VS ญาติ
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => selectedRole = 'patient'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: selectedRole == 'patient' ? const Color(0xFFEAF3E4) : const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedRole == 'patient' ? emeraldTheme : const Color(0xFFEADBCE),
                              width: selectedRole == 'patient' ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_rounded,
                                color: selectedRole == 'patient' ? emeraldTheme : secondaryTextColor,
                                size: 22,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'คนไข้เอง',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: selectedRole == 'patient' ? const Color(0xFF2E6325) : secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => selectedRole = 'caregiver'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: selectedRole == 'caregiver' ? const Color(0xFFFEF3C7) : const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedRole == 'caregiver' ? const Color(0xFFD97706) : const Color(0xFFEADBCE),
                              width: selectedRole == 'caregiver' ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.family_restroom_rounded,
                                color: selectedRole == 'caregiver' ? const Color(0xFFD97706) : secondaryTextColor,
                                size: 22,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ญาติ / ผู้ดูแล',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: selectedRole == 'caregiver' ? const Color(0xFF92400E) : secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                const Text(
                  '2. วิธีเชื่อมต่อ LINE OA:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 10),

                // กล่องแสดงรหัส 6 หลัก (Pairing Code)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: softCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEADBCE)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        selectedRole == 'caregiver'
                            ? 'ให้ญาติเปิด LINE OA แล้วพิมพ์รหัส 6 หลักนี้:'
                            : 'เปิด LINE OA แล้วส่งรหัส 6 หลักนี้ในแชท:',
                        style: const TextStyle(fontSize: 12, color: secondaryTextColor),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: emeraldTheme, width: 1.5),
                        ),
                        child: SelectableText(
                          '${pairingCode.substring(0, 3)}-${pairingCode.substring(3)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                            color: emeraldTheme,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '⏱️ รหัสมีอายุ 10 นาที',
                        style: TextStyle(fontSize: 11, color: mutedTextColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // กล่องกรอก User ID ด้วยตนเอง (สำหรับ Manual / Test)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'หรือ ระบุ LINE User ID โดยตรง (ขั้นสูง)',
                    style: TextStyle(fontSize: 12, color: secondaryTextColor, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    TextField(
                      controller: manualIdCtrl,
                      style: const TextStyle(fontSize: 13, color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'เช่น U1234567890abcdef...',
                        hintStyle: const TextStyle(color: mutedTextColor, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ปิด', style: TextStyle(color: mutedTextColor)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emeraldTheme,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final inputId = manualIdCtrl.text.trim();
                      final patientId = await _profileService.getCurrentPatientId();

                      if (patientId != null) {
                        final updatePayload = {
                          'line_recipient_role': selectedRole,
                          'line_pairing_code': pairingCode,
                          'line_pairing_expires_at': DateTime.now()
                              .add(const Duration(minutes: 10))
                              .toUtc()
                              .toIso8601String(),
                          if (inputId.isNotEmpty) 'line_user_id': inputId,
                          if (inputId.isNotEmpty) 'line_linked_at': DateTime.now().toUtc().toIso8601String(),
                        };

                        await Supabase.instance.client
                            .from('patients')
                            .update(updatePayload)
                            .eq('id', patientId);

                        await _profileService.updateLocalProfile(updatePayload);

                        setState(() {
                          _lineRecipientRole = selectedRole;
                          if (inputId.isNotEmpty) _lineUserId = inputId;
                        });
                      }

                      if (mounted) Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('บันทึกการตั้งค่าแจ้งเตือนไปยัง [$selectedRole] แล้ว'),
                          backgroundColor: emeraldTheme,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Text(
                      'บันทึกการตั้งค่า',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: secondaryTextColor, fontSize: 13),
      prefixIcon: Icon(icon, color: earthyBrown, size: 20),
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

  Widget _buildEnergySummaryCard() {
    final deficitTarget = (_tdee - 400).clamp(1200.0, 9999.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2C879).withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: Color(0xFFD97B4F), size: 24),
              SizedBox(width: 8),
              Text(
                'เป้าหมายพลังงานรายวัน (TDEE)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: softCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF0E5D8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BMR (เผาผลาญพื้นฐาน)', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                      const SizedBox(height: 4),
                      Text(
                        '${_bmr.toStringAsFixed(0)} kcal',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: softCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF0E5D8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TDEE (ใช้พลังงานรวม)', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                      const SizedBox(height: 4),
                      Text(
                        '${_tdee.toStringAsFixed(0)} kcal',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD97B4F)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates, color: Color(0xFFB45309), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เป้าหมายลดน้ำหนักที่ปลอดภัย: ไม่เกิน ${deficitTarget.toStringAsFixed(0)} kcal/วัน',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThaiCvdRiskCard() {
    final int age = int.tryParse(_ageController.text) ?? 50;
    final bool hasDiabetes = _diseaseController.text.contains('เบาหวาน');
    final double? cholesterol = _latestLab != null
        ? double.tryParse(_latestLab!['total_cholesterol']?.toString() ?? '')
        : null;
    bool hasLabData = cholesterol != null && cholesterol > 0;

    final riskResult = ThCvRiskCalculator.calculateRisk(
      age: age,
      gender: _gender == 'ชาย' ? 'male' : 'female',
      isSmoker: _isSmoker,
      hasDiabetes: hasDiabetes,
      systolicBP: _latestSystolic.toDouble(),
      totalCholesterol: cholesterol,
      useLabData: hasLabData,
    );

    String riskLevel = riskResult['level'] ?? 'ไม่ระบุ';
    String colorCode = riskResult['color'] ?? 'green';

    Color riskColor = emeraldTheme;
    double progressVal = 0.3;
    if (colorCode == 'red') {
      riskColor = const Color(0xFFEF4444);
      progressVal = 0.85;
    } else if (colorCode == 'orange') {
      riskColor = const Color(0xFFF97316);
      progressVal = 0.65;
    } else if (colorCode == 'yellow') {
      riskColor = const Color(0xFFF59E0B);
      progressVal = 0.45;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: riskColor.withValues(alpha: 0.35), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.favorite_rounded, color: riskColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ประเมินโรคหัวใจ (Thai CVD Risk)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasLabData ? const Color(0xFFEAF3E4) : softCardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasLabData ? const Color(0xFF4C7A3F).withValues(alpha: 0.3) : const Color(0xFFEADBCE),
                  ),
                ),
                child: Text(
                  hasLabData ? '✨ มีผลแล็บ' : '📋 ไม่มีผลแล็บ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasLabData ? const Color(0xFF3E5E33) : secondaryTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ระดับความเสี่ยงใน 10 ปีข้างหน้า:',
                  style: TextStyle(color: secondaryTextColor, fontSize: 12)),
              Text(
                riskLevel,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: riskColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progressVal,
              minHeight: 10,
              backgroundColor: const Color(0xFFF0E5D8),
              valueColor: AlwaysStoppedAnimation<Color>(riskColor),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: softCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF0E5D8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRiskFactor('อายุ', '$age ปี'),
                _buildRiskFactor('สูบบุหรี่', _isSmoker ? 'สูบ' : 'ไม่สูบ'),
                _buildRiskFactor('ความดันตัวบน', '$_latestSystolic mmHg'),
                _buildRiskFactor(
                  'ไขมันรวม (TC)',
                  hasLabData ? '${cholesterol.toStringAsFixed(0)} mg%' : 'ยังไม่มีแล็บ',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskFactor(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: secondaryTextColor)),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _fNameController.dispose();
    _lNameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _bmiController.dispose();
    _diseaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      appBar: AppBar(
        title: const Text(
          'ข้อมูลของฉัน & สุขภาพ',
          style: TextStyle(
            color: primaryTextColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldTheme))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildEnergySummaryCard(),
                    const SizedBox(height: 16),

                    _buildThaiCvdRiskCard(),
                    const SizedBox(height: 16),

                    // 🌟 การ์ดจัดการแจ้งเตือน LINE (Minimal)
                    _buildLineNotificationSettingCard(),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.badge_outlined, color: earthyBrown, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'ข้อมูลร่างกายและกิจกรรม',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, color: Color(0xFFF5ECE1)),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _fNameController,
                                  style: const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration('ชื่อ', Icons.person_outline),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'กรุณากรอกชื่อ' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _lNameController,
                                  style: const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration('นามสกุล', Icons.person),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'กรุณากรอกนามสกุล' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _gender,
                                  style: const TextStyle(color: primaryTextColor, fontSize: 15),
                                  decoration: _inputDecoration('เพศกำเนิด', Icons.wc_outlined),
                                  items: const [
                                    DropdownMenuItem(value: 'ชาย', child: Text('ชาย')),
                                    DropdownMenuItem(value: 'หญิง', child: Text('หญิง')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _gender = val;
                                        _calculateMetrics();
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _ageController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration('อายุ (ปี)', Icons.cake_outlined),
                                  onChanged: (_) => setState(() => _calculateMetrics()),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'ระบุอายุ' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _weightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration('น้ำหนัก (กก.)', Icons.monitor_weight_outlined),
                                  onChanged: (_) => setState(() => _calculateMetrics()),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'ระบุน้ำหนัก' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _heightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration('ส่วนสูง (ซม.)', Icons.height),
                                  onChanged: (_) => setState(() => _calculateMetrics()),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'ระบุส่วนสูง' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _bmiController,
                                  readOnly: true,
                                  style: const TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                                  decoration: _inputDecoration('BMI', Icons.analytics_outlined),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (double.tryParse(_bmiController.text) != null &&
                              double.parse(_bmiController.text) > 0) ...[
                            BmiBarChart(bmi: double.parse(_bmiController.text)),
                            const SizedBox(height: 16),
                          ],

                          DropdownButtonFormField<String>(
                            value: _activityLevel,
                            isExpanded: true,
                            decoration: _inputDecoration('กิจกรรมและการออกกำลังกาย', Icons.directions_run_rounded),
                            items: _activityOptions.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(
                                  e.value['label'],
                                  style: const TextStyle(fontSize: 13, color: primaryTextColor),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _activityLevel = val;
                                  _calculateMetrics();
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _diseaseController,
                            style: const TextStyle(color: primaryTextColor),
                            decoration: _inputDecoration('โรคประจำตัว', Icons.medical_services_outlined),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: softCardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFF0E5D8)),
                            ),
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'ประวัติการสูบบุหรี่',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                _isSmoker
                                    ? '🚬 สูบบุหรี่ (มีความเสี่ยงต่อหลอดเลือด)'
                                    : '✨ ไม่สูบบุหรี่ / เลิกสูบแล้ว',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isSmoker ? const Color(0xFFEF4444) : emeraldTheme,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              secondary: Icon(
                                Icons.smoking_rooms,
                                color: _isSmoker ? const Color(0xFFEF4444) : emeraldTheme,
                              ),
                              value: _isSmoker,
                              activeColor: const Color(0xFFEF4444),
                              onChanged: (val) => setState(() => _isSmoker = val),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: earthyBrown,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'บันทึกข้อมูลและเป้าหมายพลังงาน',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
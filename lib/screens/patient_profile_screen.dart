import 'dart:math';
import 'package:flutter/material.dart';
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

  // 🩺 ตัวแปรภาวะสุขภาพเฉพาะทางสำหรับ CDSS 6 มิติ
  bool _hasCad = false;
  bool _hasHeartFailure = false;
  bool _hasProteinuria = false;
  bool _hasGout = false;
  bool _hasOsa = false;
  bool _isPregnant = false;

  bool _isSmoker = false;
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _latestLab;
  int _latestSystolic = 120;

  // 🔔 ตัวแปรสำหรับการแจ้งเตือน LINE
  bool _notifyBpInactive = true;
  String? _lineUserId;
  String _lineRecipientRole = 'patient';

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

          _hasCad = profile['has_cad'] == true;
          _hasHeartFailure = profile['has_heart_failure'] == true;
          _hasProteinuria = profile['has_proteinuria'] == true;
          _hasGout = profile['has_gout'] == true;
          _hasOsa = profile['has_osa'] == true;
          _isPregnant = profile['is_pregnant'] == true;

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
      'has_cad': _hasCad,
      'has_heart_failure': _hasHeartFailure,
      'has_proteinuria': _hasProteinuria,
      'has_gout': _hasGout,
      'has_osa': _hasOsa,
      'is_pregnant': _gender == 'หญิง' ? _isPregnant : false,
      'has_cvd': _hasCad || _hasHeartFailure,
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
        'has_cad': updateData['has_cad'],
        'has_heart_failure': updateData['has_heart_failure'],
        'has_proteinuria': updateData['has_proteinuria'],
        'has_gout': updateData['has_gout'],
        'has_osa': updateData['has_osa'],
        'is_pregnant': updateData['is_pregnant'],
        'has_cvd': updateData['has_cvd'],
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
          backgroundColor:
              errorMessage == null ? emeraldTheme : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // 🔔 1. การ์ด LINE แบบมินิมอล
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
                    child: CustomPaint(
                      size: const Size(20, 20),
                      painter: _BellVectorPainter(color: const Color(0xFF06C755)),
                    ),
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
                  backgroundColor: isLineConnected
                      ? const Color(0xFFEAF3E4)
                      : const Color(0xFF06C755),
                  foregroundColor:
                      isLineConnected ? const Color(0xFF2E6325) : Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showLineConnectionDialog,
                child: Text(
                  isLineConnected ? 'จัดการ / เปลี่ยน' : 'ตั้งค่าเชื่อมต่อ',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isLineConnected
                  ? const Color(0xFFF4F9F1)
                  : const Color(0xFFFFF9F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLineConnected
                    ? const Color(0xFF4C7A3F).withValues(alpha: 0.25)
                    : const Color(0xFFFCD34D),
              ),
            ),
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(16, 16),
                  painter: isLineConnected
                      ? _CheckCircleVectorPainter(color: emeraldTheme)
                      : _InfoCircleVectorPainter(color: const Color(0xFFD97706)),
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
                      color: isLineConnected
                          ? const Color(0xFF3E5E33)
                          : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'เตือนเมื่อไม่วัดความดันเกิน 24 ชม.',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor),
            ),
            value: _notifyBpInactive,
            activeThumbColor: emeraldTheme,
            onChanged: (val) async {
              setState(() => _notifyBpInactive = val);
              final patientId = await _profileService.getCurrentPatientId();
              if (patientId != null) {
                await Supabase.instance.client
                    .from('patients')
                    .update({'notify_bp_inactive': val}).eq('id', patientId);
                await _profileService
                    .updateLocalProfile({'notify_bp_inactive': val});
              }
            },
          ),
        ],
      ),
    );
  }

  // 🔔 2. Pop-up Modal เชื่อมต่อ LINE
  Future<void> _showLineConnectionDialog() async {
    String selectedRole = _lineRecipientRole;
    final manualIdCtrl = TextEditingController(text: _lineUserId ?? '');
    
    final String pairingCode = (100000 + Random().nextInt(900000)).toString();

    final patientId = await _profileService.getCurrentPatientId();
    if (patientId == null || patientId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่พบข้อมูลผู้ป่วย กรุณาเข้าสู่ระบบใหม่อีกครั้ง'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    try {
      await Supabase.instance.client.from('patients').update({
        'line_recipient_role': selectedRole,
        'line_pairing_code': pairingCode,
        'line_pairing_expires_at': DateTime.now()
            .add(const Duration(minutes: 10))
            .toUtc()
            .toIso8601String(),
      }).eq('id', patientId);
    } catch (e) {
      debugPrint("Error saving pairing code to DB: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถสร้างรหัสเชื่อมต่อได้: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

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
                child: CustomPaint(
                  size: const Size(22, 22),
                  painter: _ChatBubbleVectorPainter(color: const Color(0xFF06C755)),
                ),
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
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          setDialogState(() => selectedRole = 'patient');
                          await Supabase.instance.client
                              .from('patients')
                              .update({'line_recipient_role': 'patient'})
                              .eq('id', patientId);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: selectedRole == 'patient'
                                ? const Color(0xFFEAF3E4)
                                : const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedRole == 'patient'
                                  ? emeraldTheme
                                  : const Color(0xFFEADBCE),
                              width: selectedRole == 'patient' ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              CustomPaint(
                                size: const Size(22, 22),
                                painter: _UserVectorPainter(
                                  color: selectedRole == 'patient'
                                      ? emeraldTheme
                                      : secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'คนไข้เอง',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: selectedRole == 'patient'
                                      ? const Color(0xFF2E6325)
                                      : secondaryTextColor,
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
                        onTap: () async {
                          setDialogState(() => selectedRole = 'caregiver');
                          await Supabase.instance.client
                              .from('patients')
                              .update({'line_recipient_role': 'caregiver'})
                              .eq('id', patientId);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: selectedRole == 'caregiver'
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedRole == 'caregiver'
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFFEADBCE),
                              width: selectedRole == 'caregiver' ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              CustomPaint(
                                size: const Size(22, 22),
                                painter: _FamilyVectorPainter(
                                  color: selectedRole == 'caregiver'
                                      ? const Color(0xFFD97706)
                                      : secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ญาติ / ผู้ดูแล',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: selectedRole == 'caregiver'
                                      ? const Color(0xFF92400E)
                                      : secondaryTextColor,
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
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor),
                ),
                const SizedBox(height: 10),

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
                        style: const TextStyle(
                            fontSize: 12, color: secondaryTextColor),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: emeraldTheme, width: 1.5),
                        ),
                        child: SelectableText(
                          '${pairingCode.substring(0, 3)}-${pairingCode.substring(3)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3.0,
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

                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'หรือ ระบุ LINE User ID โดยตรง (ขั้นสูง)',
                    style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600),
                  ),
                  children: [
                    TextField(
                      controller: manualIdCtrl,
                      style: const TextStyle(
                          fontSize: 13, color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'เช่น U1234567890abcdef...',
                        hintStyle: const TextStyle(
                            color: mutedTextColor, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFA),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
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
                    child: const Text('ปิด',
                        style: TextStyle(color: mutedTextColor)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emeraldTheme,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final inputId = manualIdCtrl.text.trim();
                      if (inputId.isNotEmpty) {
                        final updatePayload = {
                          'line_recipient_role': selectedRole,
                          'line_user_id': inputId,
                          'line_linked_at': DateTime.now().toUtc().toIso8601String(),
                        };

                        await Supabase.instance.client
                            .from('patients')
                            .update(updatePayload)
                            .eq('id', patientId);

                        await _profileService.updateLocalProfile(updatePayload);

                        setState(() {
                          _lineRecipientRole = selectedRole;
                          _lineUserId = inputId;
                        });
                      }

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                              'บันทึกการตั้งค่าแจ้งเตือนไปยัง [${selectedRole == 'caregiver' ? 'ญาติ/ผู้ดูแล' : 'คนไข้'}] แล้ว'),
                          backgroundColor: emeraldTheme,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Text(
                      'เสร็จสิ้น',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
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

  Widget _buildSpecificConditionsCard() {
    return Container(
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
          Row(
            children: [
              CustomPaint(
                size: const Size(22, 22),
                painter: _ShieldPulseVectorPainter(color: earthyBrown),
              ),
              const SizedBox(width: 8),
              const Text(
                'ประวัติโรคและภาวะเฉพาะทาง (CDSS Support)',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'แตะเลือกภาวะที่แพทย์เคยระบุ เพื่อให้ระบบ CDSS แนะนำสูตรยาที่ปลอดภัย:',
            style: TextStyle(fontSize: 12, color: secondaryTextColor),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildConditionChip('หลอดเลือดหัวใจ (CAD)', _hasCad,
                  (v) => setState(() => _hasCad = v)),
              _buildConditionChip(
                  'หัวใจล้มเหลว (Heart Failure)',
                  _hasHeartFailure,
                  (v) => setState(() => _hasHeartFailure = v)),
              _buildConditionChip('ไตเรื้อรัง/โปรตีนรั่ว', _hasProteinuria,
                  (v) => setState(() => _hasProteinuria = v)),
              _buildConditionChip('โรคเกาต์ / กรดยูริกสูง', _hasGout,
                  (v) => setState(() => _hasGout = v)),
              _buildConditionChip('นอนกรนรุนแรง (OSA)', _hasOsa,
                  (v) => setState(() => _hasOsa = v)),
            ],
          ),
          if (_gender == 'หญิง') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _isPregnant ? const Color(0xFFFDF2F8) : softCardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isPregnant
                      ? const Color(0xFFF472B6)
                      : const Color(0xFFF0E5D8),
                ),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'อยู่ในช่วงตั้งครรภ์ (Pregnancy)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                      fontSize: 13),
                ),
                subtitle: const Text(
                  'จำเป็นสำหรับการคัดกรองยาความดันที่ปลอดภัยต่อทารก',
                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                ),
                value: _isPregnant,
                activeThumbColor: const Color(0xFFDB2777),
                onChanged: (val) => setState(() => _isPregnant = val),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConditionChip(
      String label, bool isSelected, ValueChanged<bool> onSelected) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : primaryTextColor,
        ),
      ),
      selected: isSelected,
      selectedColor: emeraldTheme,
      backgroundColor: softCardBg,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isSelected ? emeraldTheme : const Color(0xFFEADBCE)),
      ),
      onSelected: onSelected,
    );
  }

  InputDecoration _inputDecoration(String label, ProfileVectorIconType iconType) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: secondaryTextColor, fontSize: 13),
      prefixIcon: Padding(
        padding: const EdgeInsets.all(12),
        child: CustomPaint(
          size: const Size(20, 20),
          painter: _ProfileVectorIconPainter(type: iconType, color: earthyBrown),
        ),
      ),
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
        border: Border.all(
            color: const Color(0xFFF2C879).withValues(alpha: 0.5), width: 1.2),
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
            children: [
              CustomPaint(
                size: const Size(24, 24),
                painter: _FlameVectorPainter(color: const Color(0xFFD97B4F)),
              ),
              const SizedBox(width: 8),
              const Text(
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
                      const Text('BMR (เผาผลาญพื้นฐาน)',
                          style: TextStyle(
                              fontSize: 11, color: secondaryTextColor)),
                      const SizedBox(height: 4),
                      Text(
                        '${_bmr.toStringAsFixed(0)} kcal',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor),
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
                      const Text('TDEE (ใช้พลังงานรวม)',
                          style: TextStyle(
                              fontSize: 11, color: secondaryTextColor)),
                      const SizedBox(height: 4),
                      Text(
                        '${_tdee.toStringAsFixed(0)} kcal',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD97B4F)),
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
                CustomPaint(
                  size: const Size(18, 18),
                  painter: _LightbulbVectorPainter(color: const Color(0xFFB45309)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เป้าหมายลดน้ำหนักที่ปลอดภัย: ไม่เกิน ${deficitTarget.toStringAsFixed(0)} kcal/วัน',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600),
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
        border:
            Border.all(color: riskColor.withValues(alpha: 0.35), width: 1.3),
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
                    child: CustomPaint(
                      size: const Size(20, 20),
                      painter: _HeartVectorPainter(color: riskColor),
                    ),
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
                    color: hasLabData
                        ? const Color(0xFF4C7A3F).withValues(alpha: 0.3)
                        : const Color(0xFFEADBCE),
                  ),
                ),
                child: Text(
                  hasLabData ? '✨ มีผลแล็บ' : '📋 ไม่มีผลแล็บ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasLabData
                        ? const Color(0xFF3E5E33)
                        : secondaryTextColor,
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
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: riskColor),
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
                  hasLabData
                      ? '${cholesterol.toStringAsFixed(0)} mg%'
                      : 'ยังไม่มีแล็บ',
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
        Text(label,
            style: const TextStyle(fontSize: 10, color: secondaryTextColor)),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primaryTextColor),
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
          icon: CustomPaint(
            size: const Size(18, 18),
            painter: _ArrowBackVectorPainter(color: primaryTextColor),
          ),
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

                    _buildLineNotificationSettingCard(),
                    const SizedBox(height: 16),
                    _buildSpecificConditionsCard(),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFF0E5D8), width: 1.2),
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
                            children: [
                              CustomPaint(
                                size: const Size(22, 22),
                                painter: _BadgeVectorPainter(color: earthyBrown),
                              ),
                              const SizedBox(width: 8),
                              const Text(
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
                                  style:
                                      const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration(
                                      'ชื่อ', ProfileVectorIconType.personOutline),
                                  validator: (v) => v!.trim().isEmpty
                                      ? 'กรุณากรอกชื่อ'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _lNameController,
                                  style:
                                      const TextStyle(color: primaryTextColor),
                                  decoration:
                                      _inputDecoration('นามสกุล', ProfileVectorIconType.personFill),
                                  validator: (v) => v!.trim().isEmpty
                                      ? 'กรุณากรอกนามสกุล'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _gender,
                                  style: const TextStyle(
                                      color: primaryTextColor, fontSize: 15),
                                  decoration: _inputDecoration(
                                      'เพศกำเนิด', ProfileVectorIconType.gender),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'ชาย', child: Text('ชาย')),
                                    DropdownMenuItem(
                                        value: 'หญิง', child: Text('หญิง')),
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
                                  style:
                                      const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration(
                                      'อายุ (ปี)', ProfileVectorIconType.cake),
                                  onChanged: (_) =>
                                      setState(() => _calculateMetrics()),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style:
                                      const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration('น้ำหนัก (กก.)',
                                      ProfileVectorIconType.weightScale),
                                  onChanged: (_) =>
                                      setState(() => _calculateMetrics()),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'ระบุน้ำหนัก' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _heightController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style:
                                      const TextStyle(color: primaryTextColor),
                                  decoration: _inputDecoration(
                                      'ส่วนสูง (ซม.)', ProfileVectorIconType.heightRuler),
                                  onChanged: (_) =>
                                      setState(() => _calculateMetrics()),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'ระบุส่วนสูง' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _bmiController,
                                  readOnly: true,
                                  style: const TextStyle(
                                      color: primaryTextColor,
                                      fontWeight: FontWeight.bold),
                                  decoration: _inputDecoration(
                                      'BMI', ProfileVectorIconType.analytics),
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
                            initialValue: _activityLevel,
                            isExpanded: true,
                            decoration: _inputDecoration(
                                'กิจกรรมและการออกกำลังกาย',
                                ProfileVectorIconType.running),
                            items: _activityOptions.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(
                                  e.value['label'],
                                  style: const TextStyle(
                                      fontSize: 13, color: primaryTextColor),
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
                            decoration: _inputDecoration(
                                'โรคประจำตัว', ProfileVectorIconType.medicalBriefcase),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: softCardBg,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFF0E5D8)),
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
                                  color: _isSmoker
                                      ? const Color(0xFFEF4444)
                                      : emeraldTheme,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              secondary: CustomPaint(
                                size: const Size(22, 22),
                                painter: _SmokingVectorPainter(
                                  color: _isSmoker
                                      ? const Color(0xFFEF4444)
                                      : emeraldTheme,
                                ),
                              ),
                              value: _isSmoker,
                              activeThumbColor: const Color(0xFFEF4444),
                              onChanged: (val) =>
                                  setState(() => _isSmoker = val),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
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

// =========================================================================
// 🎨 Pure Canvas Vector Painters (100% Canvas Vector - No Icon Font Needed)
// =========================================================================

enum ProfileVectorIconType {
  personOutline,
  personFill,
  gender,
  cake,
  weightScale,
  heightRuler,
  analytics,
  running,
  medicalBriefcase,
}

class _ProfileVectorIconPainter extends CustomPainter {
  final ProfileVectorIconType type;
  final Color color;

  _ProfileVectorIconPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (type) {
      case ProfileVectorIconType.personOutline:
        canvas.drawCircle(Offset(w * 0.5, h * 0.32), w * 0.22, stroke);
        final body = Path()
          ..moveTo(w * 0.18, h * 0.86)
          ..cubicTo(w * 0.18, h * 0.60, w * 0.82, h * 0.60, w * 0.82, h * 0.86);
        canvas.drawPath(body, stroke);
        break;

      case ProfileVectorIconType.personFill:
        canvas.drawCircle(Offset(w * 0.5, h * 0.32), w * 0.22, fill);
        final bodyFill = Path()
          ..moveTo(w * 0.18, h * 0.86)
          ..cubicTo(w * 0.18, h * 0.60, w * 0.82, h * 0.60, w * 0.82, h * 0.86)
          ..close();
        canvas.drawPath(bodyFill, fill);
        break;

      case ProfileVectorIconType.gender:
        // สัญลักษณ์เพศรวม ชาย-หญิง
        canvas.drawCircle(Offset(w * 0.40, h * 0.50), w * 0.26, stroke);
        // ลูกศรชายขึ้นขวา
        canvas.drawLine(Offset(w * 0.60, h * 0.35), Offset(w * 0.85, h * 0.15), stroke);
        canvas.drawLine(Offset(w * 0.68, h * 0.15), Offset(w * 0.85, h * 0.15), stroke);
        canvas.drawLine(Offset(w * 0.85, h * 0.15), Offset(w * 0.85, h * 0.32), stroke);
        // ไม้กางเขนหญิงลงล่าง
        canvas.drawLine(Offset(w * 0.40, h * 0.76), Offset(w * 0.40, h * 0.95), stroke);
        canvas.drawLine(Offset(w * 0.28, h * 0.86), Offset(w * 0.52, h * 0.86), stroke);
        break;

      case ProfileVectorIconType.cake:
        // เค้กและเทียนวันเกิด
        final cakeBody = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.15, h * 0.45, w * 0.70, h * 0.45),
          const Radius.circular(3),
        );
        canvas.drawRRect(cakeBody, stroke);
        canvas.drawLine(Offset(w * 0.5, h * 0.25), Offset(w * 0.5, h * 0.45), stroke);
        canvas.drawCircle(Offset(w * 0.5, h * 0.16), 2, fill);
        break;

      case ProfileVectorIconType.weightScale:
        // เครื่องชั่งน้ำหนัก
        final scale = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.12, h * 0.15, w * 0.76, h * 0.72),
          const Radius.circular(4),
        );
        canvas.drawRRect(scale, stroke);
        canvas.drawArc(
          Rect.fromCenter(center: Offset(w * 0.5, h * 0.38), width: w * 0.32, height: h * 0.28),
          pi,
          pi,
          false,
          stroke,
        );
        canvas.drawLine(Offset(w * 0.5, h * 0.38), Offset(w * 0.56, h * 0.30), stroke);
        break;

      case ProfileVectorIconType.heightRuler:
        // ไม้วัดส่วนสูง
        canvas.drawLine(Offset(w * 0.35, h * 0.10), Offset(w * 0.35, h * 0.90), stroke);
        canvas.drawLine(Offset(w * 0.35, h * 0.15), Offset(w * 0.65, h * 0.15), stroke);
        canvas.drawLine(Offset(w * 0.35, h * 0.35), Offset(w * 0.55, h * 0.35), stroke);
        canvas.drawLine(Offset(w * 0.35, h * 0.55), Offset(w * 0.65, h * 0.55), stroke);
        canvas.drawLine(Offset(w * 0.35, h * 0.75), Offset(w * 0.55, h * 0.75), stroke);
        canvas.drawLine(Offset(w * 0.35, h * 0.90), Offset(w * 0.65, h * 0.90), stroke);
        break;

      case ProfileVectorIconType.analytics:
        // กราฟสถิติ BMI
        canvas.drawLine(Offset(w * 0.15, h * 0.85), Offset(w * 0.85, h * 0.85), stroke);
        canvas.drawLine(Offset(w * 0.15, h * 0.15), Offset(w * 0.15, h * 0.85), stroke);
        final line = Path()
          ..moveTo(w * 0.22, h * 0.70)
          ..lineTo(w * 0.45, h * 0.48)
          ..lineTo(w * 0.62, h * 0.58)
          ..lineTo(w * 0.82, h * 0.28);
        canvas.drawPath(line, stroke);
        break;

      case ProfileVectorIconType.running:
        // คนวิ่ง
        canvas.drawCircle(Offset(w * 0.62, h * 0.20), w * 0.12, stroke);
        final runner = Path()
          ..moveTo(w * 0.55, h * 0.35)
          ..lineTo(w * 0.45, h * 0.52)
          ..lineTo(w * 0.65, h * 0.65)
          ..lineTo(w * 0.75, h * 0.85)
          ..moveTo(w * 0.45, h * 0.52)
          ..lineTo(w * 0.30, h * 0.68)
          ..lineTo(w * 0.22, h * 0.85)
          ..moveTo(w * 0.52, h * 0.40)
          ..lineTo(w * 0.35, h * 0.36)
          ..moveTo(w * 0.52, h * 0.40)
          ..lineTo(w * 0.68, h * 0.48);
        canvas.drawPath(runner, stroke);
        break;

      case ProfileVectorIconType.medicalBriefcase:
        // กล่องยา/ประวัติโรค
        final caseBox = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.15, h * 0.32, w * 0.70, h * 0.56),
          const Radius.circular(4),
        );
        canvas.drawRRect(caseBox, stroke);
        final handle = Path()
          ..moveTo(w * 0.38, h * 0.32)
          ..lineTo(w * 0.38, h * 0.18)
          ..lineTo(w * 0.62, h * 0.18)
          ..lineTo(w * 0.62, h * 0.32);
        canvas.drawPath(handle, stroke);
        canvas.drawLine(Offset(w * 0.5, h * 0.46), Offset(w * 0.5, h * 0.74), stroke);
        canvas.drawLine(Offset(w * 0.36, h * 0.60), Offset(w * 0.64, h * 0.60), stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ProfileVectorIconPainter old) =>
      old.type != type || old.color != color;
}

class _ArrowBackVectorPainter extends CustomPainter {
  final Color color;
  _ArrowBackVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(w * 0.65, h * 0.15)
      ..lineTo(w * 0.30, h * 0.50)
      ..lineTo(w * 0.65, h * 0.85);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowBackVectorPainter old) => old.color != color;
}

class _BellVectorPainter extends CustomPainter {
  final Color color;
  _BellVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.12)
      ..cubicTo(w * 0.30, h * 0.15, w * 0.22, h * 0.40, w * 0.22, h * 0.65)
      ..lineTo(w * 0.12, h * 0.75)
      ..lineTo(w * 0.88, h * 0.75)
      ..lineTo(w * 0.78, h * 0.65)
      ..cubicTo(w * 0.78, h * 0.40, w * 0.70, h * 0.15, w * 0.5, h * 0.12)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.82), width: w * 0.22, height: h * 0.16),
      0,
      pi,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _BellVectorPainter old) => old.color != color;
}

class _CheckCircleVectorPainter extends CustomPainter {
  final Color color;
  _CheckCircleVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.46, fill);

    final check = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(w * 0.28, h * 0.50)
      ..lineTo(w * 0.44, h * 0.68)
      ..lineTo(w * 0.72, h * 0.35);
    canvas.drawPath(path, check);
  }

  @override
  bool shouldRepaint(covariant _CheckCircleVectorPainter old) => old.color != color;
}

class _InfoCircleVectorPainter extends CustomPainter {
  final Color color;
  _InfoCircleVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.44, stroke);

    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.5, h * 0.30), w * 0.07, fill);
    canvas.drawRect(Rect.fromLTWH(w * 0.43, h * 0.44, w * 0.14, h * 0.30), fill);
  }

  @override
  bool shouldRepaint(covariant _InfoCircleVectorPainter old) => old.color != color;
}

class _ChatBubbleVectorPainter extends CustomPainter {
  final Color color;
  _ChatBubbleVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bubble = Path()
      ..moveTo(w * 0.2, h * 0.2)
      ..lineTo(w * 0.8, h * 0.2)
      ..quadraticBezierTo(w * 0.9, h * 0.2, w * 0.9, h * 0.35)
      ..lineTo(w * 0.9, h * 0.65)
      ..quadraticBezierTo(w * 0.9, h * 0.80, w * 0.8, h * 0.80)
      ..lineTo(w * 0.4, h * 0.80)
      ..lineTo(w * 0.2, h * 0.95)
      ..lineTo(w * 0.25, h * 0.80)
      ..lineTo(w * 0.2, h * 0.80)
      ..quadraticBezierTo(w * 0.1, h * 0.80, w * 0.1, h * 0.65)
      ..lineTo(w * 0.1, h * 0.35)
      ..quadraticBezierTo(w * 0.1, h * 0.2, w * 0.2, h * 0.2)
      ..close();
    canvas.drawPath(bubble, paint);
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleVectorPainter old) => old.color != color;
}

class _UserVectorPainter extends CustomPainter {
  final Color color;
  _UserVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(w * 0.5, h * 0.32), w * 0.20, stroke);
    final body = Path()
      ..moveTo(w * 0.18, h * 0.86)
      ..cubicTo(w * 0.18, h * 0.58, w * 0.82, h * 0.58, w * 0.82, h * 0.86);
    canvas.drawPath(body, stroke);
  }

  @override
  bool shouldRepaint(covariant _UserVectorPainter old) => old.color != color;
}

class _FamilyVectorPainter extends CustomPainter {
  final Color color;
  _FamilyVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // บุคคลที่ 1 (ซ้าย)
    canvas.drawCircle(Offset(w * 0.34, h * 0.32), w * 0.15, stroke);
    final body1 = Path()
      ..moveTo(w * 0.10, h * 0.86)
      ..cubicTo(w * 0.10, h * 0.60, w * 0.58, h * 0.60, w * 0.58, h * 0.86);
    canvas.drawPath(body1, stroke);

    // บุคคลที่ 2 (ขวา)
    canvas.drawCircle(Offset(w * 0.66, h * 0.40), w * 0.13, stroke);
    final body2 = Path()
      ..moveTo(w * 0.46, h * 0.86)
      ..cubicTo(w * 0.46, h * 0.65, w * 0.88, h * 0.65, w * 0.88, h * 0.86);
    canvas.drawPath(body2, stroke);
  }

  @override
  bool shouldRepaint(covariant _FamilyVectorPainter old) => old.color != color;
}

class _ShieldPulseVectorPainter extends CustomPainter {
  final Color color;
  _ShieldPulseVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shield = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.88, h * 0.22)
      ..cubicTo(w * 0.88, h * 0.64, w * 0.55, h * 0.88, w * 0.5, h * 0.96)
      ..cubicTo(w * 0.45, h * 0.88, w * 0.12, h * 0.64, w * 0.12, h * 0.22)
      ..close();
    canvas.drawPath(shield, stroke);

    final pulse = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.42, h * 0.52)
      ..lineTo(w * 0.48, h * 0.36)
      ..lineTo(w * 0.54, h * 0.66)
      ..lineTo(w * 0.60, h * 0.52)
      ..lineTo(w * 0.72, h * 0.52);
    canvas.drawPath(pulse, stroke);
  }

  @override
  bool shouldRepaint(covariant _ShieldPulseVectorPainter old) => old.color != color;
}

class _FlameVectorPainter extends CustomPainter {
  final Color color;
  _FlameVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.05)
      ..cubicTo(w * 0.65, h * 0.25, w * 0.85, h * 0.45, w * 0.85, h * 0.68)
      ..cubicTo(w * 0.85, h * 0.88, w * 0.70, h * 0.95, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.30, h * 0.95, w * 0.15, h * 0.88, w * 0.15, h * 0.68)
      ..cubicTo(w * 0.15, h * 0.48, w * 0.32, h * 0.30, w * 0.42, h * 0.20)
      ..cubicTo(w * 0.40, h * 0.38, w * 0.52, h * 0.48, w * 0.58, h * 0.38)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _FlameVectorPainter old) => old.color != color;
}

class _LightbulbVectorPainter extends CustomPainter {
  final Color color;
  _LightbulbVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(w * 0.35, h * 0.70)
      ..cubicTo(w * 0.15, h * 0.55, w * 0.15, h * 0.20, w * 0.50, h * 0.15)
      ..cubicTo(w * 0.85, h * 0.20, w * 0.85, h * 0.55, w * 0.65, h * 0.70)
      ..close();
    canvas.drawPath(path, stroke);

    canvas.drawLine(Offset(w * 0.40, h * 0.82), Offset(w * 0.60, h * 0.82), stroke);
    canvas.drawLine(Offset(w * 0.45, h * 0.92), Offset(w * 0.55, h * 0.92), stroke);
  }

  @override
  bool shouldRepaint(covariant _LightbulbVectorPainter old) => old.color != color;
}

class _HeartVectorPainter extends CustomPainter {
  final Color color;
  _HeartVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.85)
      ..cubicTo(w * 0.20, h * 0.60, w * 0.05, h * 0.40, w * 0.05, h * 0.25)
      ..cubicTo(w * 0.05, h * 0.10, w * 0.20, h * 0.05, w * 0.35, h * 0.05)
      ..cubicTo(w * 0.44, h * 0.05, w * 0.50, h * 0.15, w * 0.50, h * 0.20)
      ..cubicTo(w * 0.50, h * 0.15, w * 0.56, h * 0.05, w * 0.65, h * 0.05)
      ..cubicTo(w * 0.80, h * 0.05, w * 0.95, h * 0.10, w * 0.95, h * 0.25)
      ..cubicTo(w * 0.95, h * 0.40, w * 0.80, h * 0.60, w * 0.50, h * 0.85)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _HeartVectorPainter old) => old.color != color;
}

class _BadgeVectorPainter extends CustomPainter {
  final Color color;
  _BadgeVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.20, w * 0.76, h * 0.70),
      const Radius.circular(4),
    );
    canvas.drawRRect(card, stroke);
    canvas.drawCircle(Offset(w * 0.35, h * 0.48), w * 0.10, stroke);
    canvas.drawLine(Offset(w * 0.52, h * 0.42), Offset(w * 0.75, h * 0.42), stroke);
    canvas.drawLine(Offset(w * 0.52, h * 0.54), Offset(w * 0.75, h * 0.54), stroke);
    canvas.drawLine(Offset(w * 0.25, h * 0.72), Offset(w * 0.75, h * 0.72), stroke);
  }

  @override
  bool shouldRepaint(covariant _BadgeVectorPainter old) => old.color != color;
}

class _SmokingVectorPainter extends CustomPainter {
  final Color color;
  _SmokingVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final fill = Paint()..color = color;

    // บุหรี่
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.15, h * 0.65, w * 0.50, h * 0.18),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawRect(Rect.fromLTWH(w * 0.52, h * 0.65, w * 0.13, h * 0.18), fill);

    // ควันบุหรี่โค้ง
    final smoke1 = Path()
      ..moveTo(w * 0.75, h * 0.72)
      ..cubicTo(w * 0.85, h * 0.65, w * 0.70, h * 0.45, w * 0.85, h * 0.35);
    canvas.drawPath(smoke1, paint);

    final smoke2 = Path()
      ..moveTo(w * 0.85, h * 0.72)
      ..cubicTo(w * 0.95, h * 0.60, w * 0.80, h * 0.35, w * 0.95, h * 0.20);
    canvas.drawPath(smoke2, paint);
  }

  @override
  bool shouldRepaint(covariant _SmokingVectorPainter old) => old.color != color;
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/voice_health_service.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../widgets/image_input_field.dart';
import '../widgets/save_confirmation_dialog.dart';

class VitalSignRecordScreen extends StatefulWidget {
  const VitalSignRecordScreen({super.key});

  @override
  State<VitalSignRecordScreen> createState() => _VitalSignRecordScreenState();
}

class _VitalSignRecordScreenState extends State<VitalSignRecordScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final PatientDatabaseService _dbService = PatientDatabaseService();

  late VoiceHealthService _voiceService;

  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  final TextEditingController _pulseController = TextEditingController();

  bool _isProcessing = false;
  bool _showAdviceText = false;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _voiceService = VoiceHealthService(AppConfig.geminiApiKey);
  }

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleAdviceText() {
    setState(() => _showAdviceText = !_showAdviceText);
  }

  Future<void> _handleManualInput() async {
    final systolic = int.tryParse(_systolicController.text.trim());
    final diastolic = int.tryParse(_diastolicController.text.trim());
    final pulse = int.tryParse(_pulseController.text.trim());

    if (systolic == null || diastolic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณากรอกค่าความดัน (บน/ล่าง) ให้ครบถ้วน'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final healthData = {
      'systolic': systolic,
      'diastolic': diastolic,
      'pulse': pulse,
      'spoken_feedback': 'ข้อมูลความดันที่กรอกโดยผู้ใช้',
      'urgency_level': 'NORMAL',
      'is_valid_health_data': true,
    };

    await _validateAndRouteData(healthData);
  }

  Future<void> _showHypotensionAlert({
    required String patientId,
    required int sys,
    required int dia,
    required String spokenFeedback,
    required Map<String, dynamic> healthData,
  }) async {
    try {
      await _dbService.saveAlertComplication(
        patientId: patientId,
        alertType: 'HYPOTENSION',
        severity: 'HIGH',
        symptomsReported: 'ความดันโลหิตต่ำ ($sys/$dia mmHg)',
      );
    } catch (e) {
      debugPrint('Error saving hypotension alert: $e');
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.orange.shade50,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ระวังภาวะความดันต่ำ!',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ค่าวัดความดัน: $sys/$dia mmHg',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'ค่าวัดนี้ต่ำกว่าเกณฑ์ปกติ (90/60 mmHg)',
                style: TextStyle(fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              const Text(
                '⚠️ หากมีอาการหน้ามืด วูบ หรือใจสั่น ให้นอนราบยกขาขึ้นสูง เปลี่ยนอิริยาบถช้าๆ และรีบแจ้งญาติหรือพบแพทย์ทันที',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'ยกเลิก / วัดใหม่',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                healthData['urgency_level'] = 'HYPOTENSION';
                _showSaveConfirmation(healthData);
              },
              child: const Text(
                'ยืนยันค่านี้ถูกต้อง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleEmergencyAlert({
    required String patientId,
    required int sys,
    required int dia,
    required String spokenFeedback,
    List<dynamic>? symptoms,
  }) async {
    try {
      await _dbService.saveAlertComplication(
        patientId: patientId,
        alertType: 'HYPERTENSIVE_CRISIS',
        severity: 'CRISIS',
        symptomsReported: symptoms != null && symptoms.isNotEmpty
            ? symptoms.join(', ')
            : 'ความดันสูงระดับวิกฤต ($sys/$dia mmHg)',
      );
      await _dbService.saveVitalSigns(
        patientId: patientId,
        systolic: sys,
        diastolic: dia,
        pulse: null,
        spokenFeedback: spokenFeedback,
        urgencyLevel: 'CRISIS',
        imageUrl: null,
      );
    } catch (e) {
      debugPrint('Error saving emergency data: $e');
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.red.shade50,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 36),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'เตือนภัยระดับวิกฤต!',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ค่าวัดความดัน: $sys/$dia mmHg',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                spokenFeedback,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              const Text(
                '⚠️ หากมีอาการแน่นหน้าอก ปากเบี้ยว แขนขาอ่อนแรง หรือปวดศีรษะรุนแรง ให้รีบกดโทร 1669 เพื่อขอความช่วยเหลือด่วน',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text(
                'รับทราบ',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.phone_in_talk, color: Colors.white),
              label: const Text(
                'โทร 1669 ด่วน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final Uri launchUri = Uri(scheme: 'tel', path: '1669');
                if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
              },
            ),
          ],
        ),
      );
    }
  }

  Future<void> _validateAndRouteData(Map<String, dynamic> healthData) async {
    final sys = healthData['systolic'];
    final dia = healthData['diastolic'];
    final urgency = healthData['urgency_level'];
    final feedback = healthData['spoken_feedback'];
    final symptoms = healthData['symptoms'];

    final sysInt = (sys is int) ? sys : int.tryParse(sys?.toString() ?? '') ?? 0;
    final diaInt = (dia is int) ? dia : int.tryParse(dia?.toString() ?? '') ?? 0;

    bool isValidBP = (sysInt > diaInt) &&
        (sysInt >= 50 && sysInt <= 300) &&
        (diaInt >= 30 && diaInt <= 200);

    if (!isValidBP) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.error_outline, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('ข้อมูลไม่สมเหตุสมผล'),
            ]),
            content: Text(
              'ค่าความดัน $sysInt/$diaInt mmHg ที่รับเข้ามาไม่ถูกต้องตามหลักการแพทย์ กรุณาวัดหรือระบุค่าใหม่อีกครั้งค่ะ',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final patientId = await _profileService.getCurrentPatientId() ?? '';

    bool canSave = await _dbService.canSaveVitalSignToday(patientId);
    if (!canSave) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.pan_tool_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('บันทึกครบโควต้าแล้ว'),
            ]),
            content: const Text(
              'คุณบันทึกค่าความดันครบ 3 ครั้งในวันนี้แล้ว ตามมาตรฐานทางการแพทย์ไม่ควรวัดความดันพร่ำเพรื่อเพื่อลดความวิตกกังวลค่ะ',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (sysInt >= 135 || diaInt >= 85) {
      DateTime? lastTime = await _dbService.getLastMeasurementTimeToday(patientId);

      if (lastTime != null) {
        final nowLocal = DateTime.now();
        final diffMinutes = nowLocal.difference(lastTime).inMinutes;

        if (diffMinutes < 3) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(children: [
                  Icon(Icons.timer_rounded, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('กรุณาพักก่อนวัดใหม่'),
                ]),
                content: const Text(
                  'การวัดซ้ำควรเว้นระยะห่างอย่างน้อย 3 นาที กรุณานั่งพักผ่อนให้สบายใจ แล้วค่อยทำการวัดใหม่อีกครั้งนะคะ',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ตกลง'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      } else {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.blue.shade50,
              title: const Row(children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: 30),
                SizedBox(width: 8),
                Text('ข้อแนะนำการวัดซ้ำ', style: TextStyle(color: Colors.blue)),
              ]),
              content: const Text(
                'พบว่าค่าความดันครั้งแรกของคุณค่อนข้างสูง กรุณานั่งพักผ่อนทำใจให้สบาย 3 นาที แล้วจึงทำการวัดครั้งที่ 2 เพื่อยืนยันผลนะคะ (ระบบกำลังบันทึกค่าแรกนี้ไว้เป็นสถิติ)',
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showSaveConfirmation(healthData);
                  },
                  child: const Text('รับทราบ'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    if (sysInt < 90 || diaInt < 60) {
      await _showHypotensionAlert(
        patientId: patientId,
        sys: sysInt,
        dia: diaInt,
        spokenFeedback: feedback?.toString() ?? 'ความดันโลหิตต่ำกว่าปกติ',
        healthData: healthData,
      );
      return;
    }

    if (urgency == 'CRISIS' || sysInt >= 180 || diaInt >= 110) {
      await _handleEmergencyAlert(
        patientId: patientId,
        sys: sysInt,
        dia: diaInt,
        spokenFeedback: feedback?.toString() ?? 'ความดันโลหิตสูงระดับวิกฤต',
        symptoms: symptoms is List ? symptoms : null,
      );
      return;
    }

    _showSaveConfirmation(healthData);
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _imageFile = imageFile;
      _isProcessing = true;
    });

    try {
      final healthData = await _voiceService.processLcdImageInput(imageFile);
      if (healthData != null && healthData['is_valid_health_data'] == true) {
        if (mounted) await _validateAndRouteData(healthData);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถอ่านค่าความดันจากรูปภาพได้ กรุณาถ่ายใหม่อีกครั้ง'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการอ่านรูปภาพ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSaveConfirmation(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => SaveConfirmationDialog(
        healthData: data,
        imageFile: _imageFile,
        onConfirm: (updatedData) => _saveDataToDb(updatedData),
      ),
    );
  }

  Future<void> _saveDataToDb(Map<String, dynamic> data) async {
    setState(() => _isProcessing = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null || patientId.isEmpty) {
        throw Exception('ไม่พบรหัสผู้ป่วย กรุณาเข้าสู่ระบบใหม่');
      }

      String? uploadedUrl;
      if (_imageFile != null) {
        uploadedUrl = await _dbService.uploadHealthImage(_imageFile!, patientId);
      }

      await _dbService.saveVitalSigns(
        patientId: patientId,
        systolic: data['systolic'] ?? 0,
        diastolic: data['diastolic'] ?? 0,
        pulse: data['pulse'],
        spokenFeedback: data['spoken_feedback'],
        urgencyLevel: data['urgency_level'],
        imageUrl: uploadedUrl,
      );

      double? weight = data['weight_kg'] ?? double.tryParse(data['weight']?.toString() ?? '');
      double? height = data['height_cm'] ?? double.tryParse(data['height']?.toString() ?? '');
      String? disease = data['underlying_diseases']?.toString();

      double? bmi;
      if (weight != null && height != null && weight > 0 && height > 0) {
        double heightInMeters = height / 100;
        bmi = weight / (heightInMeters * heightInMeters);
        bmi = double.parse(bmi.toStringAsFixed(2));
      }

      final updateData = <String, dynamic>{};
      if (weight != null && weight > 0) updateData['weight_kg'] = weight;
      if (height != null && height > 0) updateData['height_cm'] = height;
      if (bmi != null && bmi > 0) updateData['bmi'] = bmi;
      if (disease != null && disease.isNotEmpty) {
        updateData['underlying_diseases'] = disease;
      }

      if (updateData.isNotEmpty) {
        await Supabase.instance.client
            .from('patients')
            .update(updateData)
            .eq('id', patientId);
        await _profileService.updateLocalProfile(updateData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกข้อมูลและอัปเดตโปรไฟล์สำเร็จ'),
            backgroundColor: emeraldColor,
          ),
        );
        setState(() {
          _imageFile = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: slateColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'บันทึกความดันโลหิต',
          style: TextStyle(
            color: slateColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: _toggleAdviceText,
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _showAdviceText ? Colors.blue.shade700 : Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _showAdviceText ? Icons.info : Icons.info_outline_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _showAdviceText ? 'ซ่อนคำแนะนำ' : 'ดูคำแนะนำก่อนวัดความดัน',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showAdviceText)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คำแนะนำก่อนวัดความดัน:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: slateColor,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• นั่งพักผ่อนในที่เงียบๆ อย่างน้อย 5 นาที\n'
                      '• ห้ามพูดคุยหรือใช้โทรศัพท์ขณะวัด\n'
                      '• งดสารกระตุ้น ห้ามสูบบุหรี่ ชา กาแฟ 30 นาทีก่อน\n'
                      '• ห้ามออกกำลังกาย ทานอาหารมื้อใหญ่ 30 นาทีก่อน\n'
                      '• นั่งหลังพิงเก้าอี้ วางเท้าราบพื้น\n'
                      '• วางแขนสูงเท่ากับหัวใจ\n'
                      '• สวมปลอกแขนเหนือข้อพับศอก 2-3 ซม.',
                      style: TextStyle(
                        fontSize: 13,
                        color: slateColor,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'กรอกค่าความดันและชีพจรของคุณ',
                    style: TextStyle(
                      color: slateColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _systolicController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'ความดันบน (Systolic) mmHg',
                      hintText: 'เช่น 120',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.favorite, color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _diastolicController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'ความดันล่าง (Diastolic) mmHg',
                      hintText: 'เช่น 80',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.favorite_border, color: Colors.redAccent),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pulseController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'ชีพจร (Pulse) beats/min (ไม่บังคับ)',
                      hintText: 'เช่น 75',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.favorite, color: Colors.pink),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _handleManualInput,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emeraldColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(
                      _isProcessing ? 'กำลังประมวลผล...' : 'บันทึกความดัน',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'หรือ อัพโหลดรูปภาพหน้าจอเครื่องวัดความดัน:',
              style: TextStyle(
                color: slateColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ImageInputField(
              onImageSelected: (file) {
                _processImage(file);
              },
            ),
          ],
        ),
      ),
    );
  }
}
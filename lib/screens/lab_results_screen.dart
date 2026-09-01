import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../services/voice_health_service.dart';

class LabResultsScreen extends StatefulWidget {
  const LabResultsScreen({super.key});

  @override
  State<LabResultsScreen> createState() => _LabResultsScreenState();
}

class _LabResultsScreenState extends State<LabResultsScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final PatientDatabaseService _dbService = PatientDatabaseService();
  late VoiceHealthService _voiceService;

  List<Map<String, dynamic>> _labResults = [];
  bool _isLoading = true;
  bool _isProcessingImage = false;

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);

  @override
  void initState() {
    super.initState();
    _voiceService = VoiceHealthService(AppConfig.geminiApiKey);
    _loadLabResults();
  }

  // 1. ดึงประวัติผลแล็บ
  Future<void> _loadLabResults() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null) {
        final labs = await _dbService.getLabResults(patientId);
        setState(() => _labResults = labs);
      }
    } catch (e) {
      debugPrint("Load labs error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Uint8List> _prepareLabImageBytes(Uint8List imageBytes) async {
    const int maxBytes = 1200000;
    if (imageBytes.lengthInBytes <= maxBytes) {
      return imageBytes;
    }

    try {
      final compressed = await FlutterImageCompress.compressWithList(
        imageBytes,
        quality: 70,
        minWidth: 1024,
        minHeight: 1024,
      );

      if (compressed.lengthInBytes > 0 && compressed.lengthInBytes < imageBytes.lengthInBytes) {
        return compressed;
      }
    } catch (e) {
      debugPrint('Lab image compression fallback: $e');
    }

    return imageBytes;
  }

  // 2. ฟังก์ชันถ่ายภาพใบแล็บพร้อมจำกัดขนาด (Web & PWA Safe)
  Future<void> _scanLabReport() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );

    if (image == null) return;

    setState(() => _isProcessingImage = true);

    try {
      final Uint8List rawBytes = await image.readAsBytes();
      final Uint8List imageBytes = await _prepareLabImageBytes(rawBytes);
      final labData = await _voiceService.processLabReportImage(imageBytes);

      if (labData != null && mounted) {
        _showConfirmLabDialog(labData, imageBytes);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AI ไม่สามารถอ่านใบแล็บได้ กรุณาถ่ายภาพให้ชัดเจนขึ้น'),
              backgroundColor: Color(0xFFD97B4F),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  // 3. Popup ยืนยันข้อมูลผลแล็บก่อนบันทึก
  void _showConfirmLabDialog(Map<String, dynamic> labData, Uint8List imageBytes) {
    final double? tcVal = (labData['total_cholesterol'] as num?)?.toDouble();
    final double? hdlVal = (labData['hdl'] as num?)?.toDouble();
    final double? ldlVal = (labData['ldl'] as num?)?.toDouble();
    final double? fbsVal = (labData['fasting_blood_sugar'] as num?)?.toDouble();
    final double? crVal = (labData['creatinine'] as num?)?.toDouble();

    final tcCtrl = TextEditingController(text: (tcVal != null && tcVal > 0) ? tcVal.toString() : '');
    final hdlCtrl = TextEditingController(text: (hdlVal != null && hdlVal > 0) ? hdlVal.toString() : '');
    final ldlCtrl = TextEditingController(text: (ldlVal != null && ldlVal > 0) ? ldlVal.toString() : '');
    final fbsCtrl = TextEditingController(text: (fbsVal != null && fbsVal > 0) ? fbsVal.toString() : '');
    final crCtrl = TextEditingController(text: (crVal != null && crVal > 0) ? crVal.toString() : '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.science_rounded, color: emeraldTheme),
            SizedBox(width: 8),
            Text(
              'ตรวจสอบผลตรวจเลือด (Lab)',
              style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    imageBytes,
                    height: 130,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'AI ได้ดึงค่าตัวเลขจากใบแล็บ กรุณาตรวจสอบความถูกต้อง',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: tcCtrl,
                  style: const TextStyle(color: primaryTextColor),
                  decoration: _dialogInputDecoration('Total Cholesterol (mg/dL)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hdlCtrl,
                  style: const TextStyle(color: primaryTextColor),
                  decoration: _dialogInputDecoration('HDL (mg/dL)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ldlCtrl,
                  style: const TextStyle(color: primaryTextColor),
                  decoration: _dialogInputDecoration('LDL (mg/dL)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fbsCtrl,
                  style: const TextStyle(color: primaryTextColor),
                  decoration: _dialogInputDecoration('Fasting Blood Sugar (mg/dL)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: crCtrl,
                  style: const TextStyle(color: primaryTextColor),
                  decoration: _dialogInputDecoration('Creatinine (mg/dL)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: mutedTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: emeraldTheme,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveLabResult(
                totalCholesterol: double.tryParse(tcCtrl.text.trim()),
                hdl: double.tryParse(hdlCtrl.text.trim()),
                ldl: double.tryParse(ldlCtrl.text.trim()),
                fastingBloodSugar: double.tryParse(fbsCtrl.text.trim()),
                creatinine: double.tryParse(crCtrl.text.trim()),
                imageBytes: imageBytes,
              );
            },
            child: const Text('บันทึกผลแล็บ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: secondaryTextColor, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEADBCE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEADBCE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: emeraldTheme, width: 1.5),
      ),
    );
  }

  // 4. บันทึกผลแล็บลง Database
  Future<void> _saveLabResult({
    double? totalCholesterol,
    double? hdl,
    double? ldl,
    double? fastingBloodSugar,
    double? creatinine,
    required Uint8List imageBytes,
  }) async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null) throw Exception('ไม่พบรหัสผู้ป่วย กรุณาเข้าสู่ระบบใหม่');

      final imagePath = await _dbService.uploadLabImageBytes(imageBytes, patientId);

      await _dbService.saveLabResult(
        patientId: patientId,
        totalCholesterol: totalCholesterol,
        hdl: hdl,
        ldl: ldl,
        fastingBloodSugar: fastingBloodSugar,
        creatinine: creatinine,
        imageUrl: imagePath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกผลแล็บสำเร็จ! พร้อมนำไปคำนวณ Thai CV Risk'),
            backgroundColor: emeraldTheme,
          ),
        );
      }
      _loadLabResults();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ผลตรวจสุขภาพและแล็บ',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldTheme))
          : _isProcessingImage
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: emeraldTheme),
                      SizedBox(height: 16),
                      Text(
                        'AI กำลังสกัดค่าผลแล็บจากรูปภาพ...',
                        style: TextStyle(color: primaryTextColor, fontSize: 15),
                      ),
                    ],
                  ),
                )
              : _labResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.science_rounded, size: 70, color: const Color(0xFFEADBCE)),
                          const SizedBox(height: 14),
                          const Text(
                            'ยังไม่มีประวัติผลตรวจแล็บ',
                            style: TextStyle(fontSize: 16, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
                      itemCount: _labResults.length,
                      itemBuilder: (context, index) {
                        final lab = _labResults[index];
                        final double? tcVal = (lab['total_cholesterol'] as num?)?.toDouble();
                        final double? hdlVal = (lab['hdl'] as num?)?.toDouble();
                        final double? ldlVal = (lab['ldl'] as num?)?.toDouble();
                        final double? fbsVal = (lab['fasting_blood_sugar'] as num?)?.toDouble();
                        final double? crVal = (lab['creatinine'] as num?)?.toDouble();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
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
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.science_outlined, color: emeraldTheme, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'ผลตรวจเลือด (Lab Report)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      lab['test_date']?.toString().substring(0, 10) ?? '',
                                      style: const TextStyle(fontSize: 12, color: mutedTextColor),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20, color: Color(0xFFF5ECE1)),
                                _buildMetricRow('Total Cholesterol', tcVal, 'mg/dL'),
                                const SizedBox(height: 6),
                                _buildMetricRow('HDL', hdlVal, 'mg/dL'),
                                const SizedBox(height: 6),
                                _buildMetricRow('LDL', ldlVal, 'mg/dL'),
                                const SizedBox(height: 6),
                                _buildMetricRow('Fasting Blood Sugar', fbsVal, 'mg/dL'),
                                if (crVal != null && crVal > 0) ...[
                                  const SizedBox(height: 6),
                                  _buildMetricRow('Creatinine', crVal, 'mg/dL'),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: emeraldTheme,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _scanLabReport,
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text(
          'ถ่ายรูปใบแล็บ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double? value, String unit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: secondaryTextColor, fontSize: 13)),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value != null ? value.toStringAsFixed(1) : '-',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: const TextStyle(color: mutedTextColor, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import '../services/pdf_export_service.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../services/vital_repository.dart';

enum HistoryViewState { loading, success, empty, error }

enum DateRangeFilter { last7Days, last1Month, last3Months }

enum DisplayTab { vitals, labs }

class HealthHistoryScreen extends StatefulWidget {
  const HealthHistoryScreen({super.key});

  @override
  State<HealthHistoryScreen> createState() => _HealthHistoryScreenState();
}

class _HealthHistoryScreenState extends State<HealthHistoryScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final VitalRepository _vitalRepository = VitalRepository();
  final PatientDatabaseService _dbService = PatientDatabaseService();
  final supabase = Supabase.instance.client;

  HistoryViewState _viewState = HistoryViewState.loading;
  DateRangeFilter _selectedFilter = DateRangeFilter.last7Days;
  DisplayTab _currentTab = DisplayTab.vitals;

  List<Map<String, dynamic>> _vitalHistory = [];
  List<Map<String, dynamic>> _labHistory = [];
  String _errorMessage = '';

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);
  static const Color dangerColor = Color(0xFFD85A30);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _viewState = HistoryViewState.loading);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null || patientId.isEmpty) {
        setState(() {
          _errorMessage = 'ไม่พบข้อมูลประจำตัวผู้ป่วย';
          _viewState = HistoryViewState.error;
        });
        return;
      }

      List<Map<String, dynamic>> vitals = [];
      switch (_selectedFilter) {
        case DateRangeFilter.last7Days:
          vitals = await _vitalRepository.getLast7Days(patientId);
          break;
        case DateRangeFilter.last1Month:
          vitals = await _vitalRepository.getLast1Month(patientId);
          break;
        case DateRangeFilter.last3Months:
          vitals = await _vitalRepository.getLast3Months(patientId);
          break;
      }

      final labs = await _dbService.getLabResults(patientId);
      setState(() {
        _vitalHistory = vitals;
        _labHistory = labs;
        _viewState = (_vitalHistory.isEmpty && _labHistory.isEmpty)
            ? HistoryViewState.empty
            : HistoryViewState.success;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e';
        _viewState = HistoryViewState.error;
      });
    }
  }

  // 🗑️ ฟังก์ชันลบข้อมูลความดันออกจากตาราง vital_signs ใน Supabase
  Future<void> _deleteVitalRecord(dynamic recordId) async {
    if (recordId == null) return;
    try {
      // 1. ลบจากฐานข้อมูล Supabase โดยอิง Primary Key (id)
      await _vitalRepository.deleteVitalSign(recordId);

      // 2. อัปเดตรายการใน State เพื่อให้กราฟและการ์ดสรุปคำนวณใหม่ทันที
      setState(() {
        _vitalHistory.removeWhere((item) => item['id'] == recordId);
        if (_vitalHistory.isEmpty && _labHistory.isEmpty) {
          _viewState = HistoryViewState.empty;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('ลบข้อมูลผลการวัดเรียบร้อยแล้ว'),
              ],
            ),
            backgroundColor: emeraldTheme,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting vital record: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการลบข้อมูล: $e'),
            backgroundColor: dangerColor,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // 🛡️ กล่องยืนยันก่อนทำการลบผลความดัน
  void _confirmDeleteDialog(Map<String, dynamic> item) {
    final int? sys = (item['systolic'] as num?)?.toInt();
    final int? dia = (item['diastolic'] as num?)?.toInt();
    final String recordedAt =
        item['recorded_at']?.toString().substring(0, 16).replaceAll('T', ' ') ??
            '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: dangerColor, size: 26),
            SizedBox(width: 8),
            Text(
              'ยืนยันการลบข้อมูล',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'คุณต้องการลบผลการบันทึกความดันนี้ใช่หรือไม่?',
              style: TextStyle(color: secondaryTextColor, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: softCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF0E5D8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: dangerColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ความดัน: ${sys ?? '-'}/${dia ?? '-'} mmHg',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: primaryTextColor,
                          ),
                        ),
                        Text(
                          recordedAt,
                          style: const TextStyle(
                              fontSize: 12, color: mutedTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '* ข้อมูลจะถูกลบออกจากฐานข้อมูล Supabase ถาวร และระบบจะคำนวณค่าเฉลี่ยใหม่ทันที',
              style: TextStyle(fontSize: 11, color: mutedTextColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ยกเลิก', style: TextStyle(color: mutedTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteVitalRecord(item['id']);
            },
            child: const Text('ยืนยันลบ',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdfReport() async {
    try {
      final profile = await _profileService.getProfile();
      final patientName = profile != null
          ? '${profile['first_name']} ${profile['last_name']}'
          : 'ผู้ป่วย';
      final hn = profile?['hn'] ?? 'N/A';
      final age = profile?['age'];
      final weight = profile?['weight'];
      final height = profile?['height'];
      final diseases = profile?['underlying_diseases'];
      String filterText = '7 วันย้อนหลัง';
      if (_selectedFilter == DateRangeFilter.last1Month)
        filterText = '1 เดือนย้อนหลัง';
      if (_selectedFilter == DateRangeFilter.last3Months)
        filterText = '3 เดือนย้อนหลัง';

      final pdfBytes = await PdfExportService.generateHealthReport(
        patientName: patientName,
        hn: hn,
        age: age,
        weight: weight,
        height: height,
        underlyingDiseases: diseases,
        hospitalName: "hospitalName",
        filterTitle: filterText,
        vitalHistory: _vitalHistory,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'Health_Report_$hn.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการพิมพ์ PDF: $e')));
      }
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('เอกสารใบผลตรวจ',
                  style: TextStyle(
                      fontSize: 16,
                      color: primaryTextColor,
                      fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              foregroundColor: primaryTextColor,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Column(
                    children: [
                      Icon(Icons.broken_image, size: 60, color: mutedTextColor),
                      SizedBox(height: 8),
                      Text('ไม่สามารถโหลดรูปภาพได้',
                          style: TextStyle(color: secondaryTextColor)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'สมุดสุขภาพ & ประวัติผลตรวจ',
          style: TextStyle(
              color: primaryTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: emeraldTheme),
            onPressed: _vitalHistory.isNotEmpty ? _exportPdfReport : null,
            tooltip: 'พิมพ์รายงาน PDF',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: softCardBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label:
                              const Center(child: Text('สัญญาณชีพ (Vitals)')),
                          selected: _currentTab == DisplayTab.vitals,
                          selectedColor: emeraldTheme,
                          backgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          labelStyle: TextStyle(
                            color: _currentTab == DisplayTab.vitals
                                ? Colors.white
                                : secondaryTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          onSelected: (selected) {
                            if (selected)
                              setState(() => _currentTab = DisplayTab.vitals);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          label:
                              const Center(child: Text('ผลแล็บ (Lab Reports)')),
                          selected: _currentTab == DisplayTab.labs,
                          selectedColor: emeraldTheme,
                          backgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          labelStyle: TextStyle(
                            color: _currentTab == DisplayTab.labs
                                ? Colors.white
                                : secondaryTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          onSelected: (selected) {
                            if (selected)
                              setState(() => _currentTab = DisplayTab.labs);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentTab == DisplayTab.vitals) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFilterChip(
                          '7 วันล่าสุด', DateRangeFilter.last7Days),
                      _buildFilterChip(
                          '1 เดือนล่าสุด', DateRangeFilter.last1Month),
                      _buildFilterChip(
                          '3 เดือนล่าสุด', DateRangeFilter.last3Months),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEADBCE)),
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, DateRangeFilter filter) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : secondaryTextColor,
        ),
      ),
      selected: isSelected,
      selectedColor: emeraldTheme,
      backgroundColor: softCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? emeraldTheme : const Color(0xFFEADBCE),
          width: 1,
        ),
      ),
      showCheckmark: false,
      onSelected: (bool selected) {
        if (selected) {
          setState(() => _selectedFilter = filter);
          _loadData();
        }
      },
    );
  }

  Widget _buildMainContent() {
    if (_viewState == HistoryViewState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: emeraldTheme));
    }

    if (_viewState == HistoryViewState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: dangerColor, size: 56),
              const SizedBox(height: 16),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: secondaryTextColor)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: emeraldTheme,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loadData,
                child: const Text('ลองใหม่อีกครั้ง',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentTab == DisplayTab.vitals) {
      if (_vitalHistory.isEmpty) {
        return const Center(
          child: Text('ไม่พบประวัติค่าวัดสัญญาณชีพในช่วงเวลานี้',
              style: TextStyle(color: secondaryTextColor)),
        );
      }

      double avgSys = 0;
      double avgDia = 0;
      double avgPulse = 0;
      int pulseCount = 0;
      for (var item in _vitalHistory) {
        avgSys += (item['systolic'] as num?)?.toDouble() ?? 0;
        avgDia += (item['diastolic'] as num?)?.toDouble() ?? 0;
        final p = (item['pulse'] as num?)?.toDouble();
        if (p != null && p > 0) {
          avgPulse += p;
          pulseCount++;
        }
      }
      if (_vitalHistory.isNotEmpty) {
        avgSys = avgSys / _vitalHistory.length;
        avgDia = avgDia / _vitalHistory.length;
        if (pulseCount > 0) avgPulse = avgPulse / pulseCount;
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vitalHistory.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildPremiumGradientSummaryCard(avgSys, avgDia, avgPulse);
          }

          final item = _vitalHistory[index - 1];
          final int? sys = (item['systolic'] as num?)?.toInt();
          final int? dia = (item['diastolic'] as num?)?.toInt();
          final int? pulse = (item['pulse'] as num?)?.toInt();
          final String recordedAt = item['recorded_at']
                  ?.toString()
                  .substring(0, 16)
                  .replaceAll('T', ' ') ??
              '';
          final String urgency = item['urgency_level']?.toString() ?? 'NORMAL';

          Color statusColor = emeraldTheme;
          String statusThai = 'ปกติ';
          if (urgency == 'YELLOW' || urgency == 'MODERATE') {
            statusColor = const Color(0xFFE8A33D);
            statusThai = 'เฝ้าระวัง';
          } else if (urgency == 'ELEVATED' || urgency == 'HIGH') {
            statusColor = const Color(0xFFD97B4F);
            statusThai = 'ความดันสูง';
          } else if (urgency == 'CRITICAL' || urgency == 'CRISIS') {
            statusColor = const Color(0xFFEF4444);
            statusThai = 'วิกฤต';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
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
                        const Icon(Icons.access_time_rounded,
                            size: 16, color: mutedTextColor),
                        const SizedBox(width: 6),
                        Text(
                          recordedAt,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            statusThai,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 🗑️ ปุ่มลบการบันทึก (Trash Icon)
                        InkWell(
                          onTap: () => _confirmDeleteDialog(item),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: dangerColor.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: dangerColor,
                              size: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFF5ECE1)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.favorite,
                            color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                  text: 'ความดัน: ',
                                  style: TextStyle(
                                      color: secondaryTextColor, fontSize: 14)),
                              TextSpan(
                                  text: '${sys ?? '-'}/${dia ?? '-'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                      fontSize: 16)),
                              const TextSpan(
                                  text: ' mmHg',
                                  style: TextStyle(
                                      color: mutedTextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.monitor_heart_outlined,
                            color: Color(0xFFD97B4F), size: 18),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                  text: 'ชีพจร: ',
                                  style: TextStyle(
                                      color: secondaryTextColor, fontSize: 14)),
                              TextSpan(
                                  text: '${pulse ?? '-'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                      fontSize: 15)),
                              const TextSpan(
                                  text: ' bpm',
                                  style: TextStyle(
                                      color: mutedTextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } else {
      if (_labHistory.isEmpty) {
        return const Center(
          child: Text('ยังไม่มีประวัติผลตรวจแล็บในระบบ',
              style: TextStyle(color: secondaryTextColor)),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _labHistory.length,
        itemBuilder: (context, index) {
          final lab = _labHistory[index];
          final double? tc = (lab['total_cholesterol'] as num?)?.toDouble();
          final double? hdl = (lab['hdl'] as num?)?.toDouble();
          final double? ldl = (lab['ldl'] as num?)?.toDouble();
          final double? fbs = (lab['fasting_blood_sugar'] as num?)?.toDouble();
          final double? cr = (lab['creatinine'] as num?)?.toDouble();
          final String testDate =
              lab['test_date']?.toString().substring(0, 10) ?? '';
          final String? imageUrl = lab['image_url'];

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ผลตรวจแล็บ (Lab Report)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: primaryTextColor)),
                    Text(testDate,
                        style: const TextStyle(
                            fontSize: 12, color: mutedTextColor)),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFF5ECE1)),
                _buildLabRow('Total Cholesterol', tc, 'mg/dL'),
                _buildLabRow('HDL', hdl, 'mg/dL'),
                _buildLabRow('LDL', ldl, 'mg/dL'),
                _buildLabRow('Fasting Blood Sugar (FBS)', fbs, 'mg/dL'),
                _buildLabRow('Creatinine', cr, 'mg/dL'),
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: emeraldTheme,
                        side: const BorderSide(color: emeraldTheme),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _showImageDialog(imageUrl),
                      icon:
                          const Icon(Icons.document_scanner_outlined, size: 18),
                      label: const Text('ดูใบผลตรวจแล็บที่อัปโหลด'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }
  }

  Widget _buildPremiumGradientSummaryCard(
      double avgSys, double avgDia, double avgPulse) {
    String title = 'ภาพรวมความดัน 7 วันล่าสุด';
    if (_selectedFilter == DateRangeFilter.last1Month)
      title = 'ภาพรวมความดัน 1 เดือนล่าสุด';
    if (_selectedFilter == DateRangeFilter.last3Months)
      title = 'ภาพรวมความดัน 3 เดือนล่าสุด';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D6E5A), Color(0xFF2F9E82), Color(0xFF52B79A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: emeraldTheme.withValues(alpha: 0.35),
            blurRadius: 15,
            offset: const Offset(0, 6),
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
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.analytics_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'ค่าเฉลี่ย',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAverageItem('ความดันตัวบน',
                  avgSys > 0 ? avgSys.toStringAsFixed(0) : '-', 'mmHg'),
              Container(
                  height: 36,
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.25)),
              _buildAverageItem('ความดันตัวล่าง',
                  avgDia > 0 ? avgDia.toStringAsFixed(0) : '-', 'mmHg'),
              Container(
                  height: 36,
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.25)),
              _buildAverageItem('ชีพจร',
                  avgPulse > 0 ? avgPulse.toStringAsFixed(0) : '-', 'bpm'),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _vitalHistory.take(7).map((item) {
                final sysVal = (item['systolic'] as num?)?.toDouble() ?? 120;
                double factor = (sysVal / 180.0).clamp(0.2, 1.0);

                Color barColor = Colors.white;
                if (sysVal < 90) {
                  barColor = const Color(0xFF93C5FD);
                } else if (sysVal >= 160) {
                  barColor = const Color(0xFFEF4444);
                } else if (sysVal >= 140) {
                  barColor = const Color(0xFFF59E0B);
                } else if (sysVal >= 120) {
                  barColor = const Color(0xFFFDE047);
                } else {
                  barColor = Colors.white;
                }

                return _buildBarItem(factor, barColor);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAverageItem(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBarItem(double heightFactor, Color barColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            width: 10,
            height: 55 * heightFactor,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '•',
          style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildLabRow(String title, dynamic value, String unit) {
    if (value == null) return const SizedBox.shrink();
    final String displayVal =
        (value is num) ? value.toStringAsFixed(1) : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(color: secondaryTextColor, fontSize: 13)),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                    text: '$displayVal ',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                        fontSize: 14)),
                TextSpan(
                    text: unit,
                    style:
                        const TextStyle(color: mutedTextColor, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

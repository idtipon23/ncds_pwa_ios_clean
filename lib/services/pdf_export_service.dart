import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfExportService {
  /// ฟังก์ชันสร้างไฟล์ PDF ประวัติสุขภาพ
  static Future<Uint8List> generateHealthReport({
    required String patientName,
    required String hn,
    dynamic age, 
    dynamic weight, // น้ำหนัก
    dynamic height, // ส่วนสูง
    String? underlyingDiseases, // โรคประจำตัว
    required String hospitalName,
    required String filterTitle,
    required List<Map<String, dynamic>> vitalHistory,
  }) async {
    final pdf = pw.Document();

    // โหลดฟอนต์ภาษาไทย Sarabun
    final font = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();

    // 📍 1. แปลงค่าข้อมูลทั่วไปของผู้ป่วยอย่างปลอดภัยก่อนนำไปแสดงผล
    final int? ageVal = (age as num?)?.toInt();
    final double? weightVal = (weight as num?)?.toDouble();
    final double? heightVal = (height as num?)?.toDouble();

    // คำนวณสถิติภาพรวม
    double totalSys = 0;
    double totalDia = 0;
    int maxSys = 0;
    int minSys = 999;
    int count = 0;
    int elevatedCount = 0;
    int crisisCount = 0;

    // 📍 2. ปรับปรุง Loop คำนวณสถิติด้วย (as num?) เพื่อรับค่า int/double ได้ปลอดภัย
    for (var item in vitalHistory) {
      final int sys = (item['systolic'] as num?)?.toInt() ?? 0;
      final int dia = (item['diastolic'] as num?)?.toInt() ?? 0;

      if (sys > 0) {
        totalSys += sys;
        totalDia += dia;
        count++;

        if (sys > maxSys) maxSys = sys;
        if (sys < minSys) minSys = sys;

        if (sys >= 180 || dia >= 120) {
          crisisCount++;
        } else if (sys >= 130 || dia >= 80) {
          elevatedCount++;
        }
      }
    }

    final String avgSys = count > 0 ? (totalSys / count).toStringAsFixed(1) : '-';
    final String avgDia = count > 0 ? (totalDia / count).toStringAsFixed(1) : '-';
    final String maxSysStr = maxSys > 0 ? '$maxSys' : '-';
    final String minSysStr = (minSys < 999 && minSys > 0) ? '$minSys' : '-';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('รายงานประวัติสัญญาณชีพและสุขภาพ',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
                  pw.Text('พิมพ์เมื่อ: ${_formatCurrentDate()}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('สถานพยาบาล: $hospitalName', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
              pw.Divider(thickness: 1, color: PdfColors.teal200),
              pw.SizedBox(height: 6),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // โซนข้อมูลผู้ป่วย
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('ชื่อผู้ป่วย: $patientName', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text('HN: $hn', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('อายุ: ${ageVal != null ? "$ageVal ปี" : "ไม่ระบุ"}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('น้ำหนัก: ${weightVal != null ? "$weightVal กก." : "ไม่ระบุ"}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('ส่วนสูง: ${heightVal != null ? "$heightVal ซม." : "ไม่ระบุ"}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  if (underlyingDiseases != null && underlyingDiseases.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text('โรคประจำตัว: $underlyingDiseases', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // โซนสถิติสรุป
            pw.Text('สรุปสถิติความดันโลหิต ($filterTitle)',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                _buildStatBox('ค่าเฉลี่ยตัวบน/ตัวล่าง', '$avgSys / $avgDia', PdfColors.teal50, PdfColors.teal900),
                pw.SizedBox(width: 8),
                _buildStatBox('ตัวบนสูงสุด / ต่ำสุด', '$maxSysStr / $minSysStr', PdfColors.grey200, PdfColors.black),
                pw.SizedBox(width: 8),
                _buildStatBox('ความดันสูง / วิกฤต', '$elevatedCount / $crisisCount ครั้ง', PdfColors.amber50, PdfColors.amber900),
              ],
            ),
            pw.SizedBox(height: 16),

            // ตารางบันทึกประวัติ
            pw.Text('รายการบันทึกประวัติสัญญาณชีพ', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),

            pw.Table.fromTextArray(
              headers: ['วัน-เวลา', 'ความดัน (mmHg)', 'ชีพจร', 'ระดับความเสี่ยง', 'คำแนะนำระบบ'],
              data: vitalHistory.map((item) {
                final int sys = (item['systolic'] as num?)?.toInt() ?? 0;
                final int dia = (item['diastolic'] as num?)?.toInt() ?? 0;
                final int pulse = (item['pulse'] as num?)?.toInt() ?? 0;
                final String dateStr = _formatIsoDate(item['recorded_at']?.toString());
                final String bpStr = '$sys/$dia';
                final String pulseStr = pulse > 0 ? '$pulse' : '-';
                final String urgency = item['urgency_level']?.toString() ?? 'NORMAL';
                final String feedback = item['spoken_feedback']?.toString() ?? '-';

                return [dateStr, bpStr, pulseStr, urgency, feedback];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 8),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(1.0),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(3.0),
              },
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildStatBox(String label, String value, PdfColor bgColor, PdfColor textColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }

  static String _formatCurrentDate() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  static String _formatIsoDate(String? isoString) {
    if (isoString == null) return '-';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}
import 'package:flutter/material.dart';

/// โมเดลเก็บข้อมูลสถานะเชิงสัญลักษณ์และคำแนะนำ
class HealthFeedbackModel {
  final String
      statusTitle; // เช่น "วิกฤติ", "ความดันสูง", "ค่อนข้างสูง", "ปกติ"
  final String adviceText; // คำแนะนำสั้นๆ รายวัน
  final IconData iconData; // ไอคอนสัญลักษณ์
  final Color themeColor; // สีประจำสถานะ (แดง/ส้ม/เหลือง-เขียว/เขียว)
  final Color bgColor; // สีพื้นหลังการ์ด

  HealthFeedbackModel({
    required this.statusTitle,
    required this.adviceText,
    required this.iconData,
    required this.themeColor,
    required this.bgColor,
  });
}

class HealthFeedbackEvaluator {
  /// 📍 ฟังก์ชันประเมินสถานะจากค่าความดัน + ข้อมูลอาหาร + AI Spoken Feedback
  static HealthFeedbackModel evaluate({
    required int systolicAvg,
    required int diastolicAvg,
    required List<Map<String, dynamic>> todayFoodLogs,
    required String? latestAiSpokenFeedback,
  }) {
    // 1. จำแนก 4 ระดับความดันตามสมาคมความดันโลหิตสูงแห่งประเทศไทย
    int tier = 4; // 1 = วิกฤติ, 2 = สูง, 3 = ค่อนข้างสูง, 4 = ปกติ
    if (systolicAvg >= 180 || diastolicAvg >= 110) {
      tier = 1;
    } else if (systolicAvg >= 140 || diastolicAvg >= 90) {
      tier = 2;
    } else if (systolicAvg >= 130 || diastolicAvg >= 85) {
      tier = 3;
    } else {
      tier = 4;
    }

    // 2. ดึงคำแนะนำจากอาหาร หรือ Fallback ไปยัง AI Spoken Feedback
    String dynamicAdvice = '';

    // กรณี A: มีการบันทึกอาหารวันนี้
    if (todayFoodLogs.isNotEmpty) {
      List<String> allWarnings = [];
      for (var log in todayFoodLogs) {
        if (log['warning_flags'] != null && log['warning_flags'] is List) {
          allWarnings.addAll(List<String>.from(log['warning_flags']));
        }
      }

      if (allWarnings.isNotEmpty) {
        dynamicAdvice = 'อาหารวันนี้: ${allWarnings.first}';
      } else {
        dynamicAdvice = 'การคุมอาหารวันนี้อยู่ในเกณฑ์ดี ทานตามแผนต่อได้เลยครับ';
      }
    }
    // กรณี B: ไม่ได้บันทึกอาหาร -> ดึงจากคำแนะนำ AI ล่าสุดในหน้า Vital Sign
    else if (latestAiSpokenFeedback != null &&
        latestAiSpokenFeedback.trim().isNotEmpty) {
      // ตัดข้อความให้สั้นกระชับ ไม่เกิน 70 ตัวอักษร
      String cleanText = latestAiSpokenFeedback.replaceAll('\n', ' ').trim();
      if (cleanText.length > 70) {
        cleanText = '${cleanText.substring(0, 67)}...';
      }
      dynamicAdvice = 'คำแนะนำหมอ: $cleanText';
    }
    // กรณี C: ไม่มีข้อมูลทั้งสองอย่าง -> ใช้คำแนะนำมาตรฐานตามระดับความดัน
    else {
      switch (tier) {
        case 1:
          dynamicAdvice =
              'ความดันระดับวิกฤติ! ควรงดกิจกรรมหนักและรีบพบแพทย์ทันที';
          break;
        case 2:
          dynamicAdvice =
              'ความดันสูง! อย่าลืมทานยาให้ตรงเวลา เลี่ยงอาหารรสเค็มจัด';
          break;
        case 3:
          dynamicAdvice =
              'ความดันเริ่มค่อนข้างสูง ระวังเรื่องโซเดียมและพักผ่อนให้เพียงพอ';
          break;
        case 4:
        default:
          dynamicAdvice =
              'สุขภาพความดันอยู่ในเกณฑ์ดีเยี่ยม รักษาวินัยต่อไปครับ!';
          break;
      }
    }

    // 3. ประกอบเป็นรูปสัญลักษณ์ สี และข้อความ
    switch (tier) {
      case 1:
        return HealthFeedbackModel(
          statusTitle: 'วิกฤติ! ต้องพบแพทย์',
          adviceText: dynamicAdvice,
          iconData:
              Icons.warning_amber_rounded, // 🔴 การ์ตูน/สัญลักษณ์แดงอันตราย
          themeColor: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEF2F2),
        );

      case 2:
        return HealthFeedbackModel(
          statusTitle: 'ความดันระดับสูง',
          adviceText: dynamicAdvice,
          iconData:
              Icons.sentiment_dissatisfied_rounded, // 🟠 สัญลักษณ์แสดงความกังวล
          themeColor: const Color(0xFFF97316),
          bgColor: const Color(0xFFFFF7ED),
        );

      case 3:
        return HealthFeedbackModel(
          statusTitle: 'เฝ้าระวัง (ค่อนข้างสูง)',
          adviceText: dynamicAdvice,
          iconData:
              Icons.sentiment_neutral_rounded, // 🟡 สัญลักษณ์เน้นความระมัดระวัง
          themeColor: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEFCE8),
        );

      case 4:
      default:
        return HealthFeedbackModel(
          statusTitle: 'ความดันปกติ (ดีเยี่ยม)',
          adviceText: dynamicAdvice,
          iconData: Icons
              .sentiment_very_satisfied_rounded, // 🟢 สัญลักษณ์ยิ้มให้กำลังใจ
          themeColor: const Color(0xFF10B981),
          bgColor: const Color(0xFFECFDF5),
        );
    }
  }
}

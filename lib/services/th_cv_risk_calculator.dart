import 'dart:math' as math;

class ThCvRiskCalculator {
  /// คำนวณ Thai CV Risk Score (อ้างอิงสมการ RAMA-EGAT Study สำหรับประชากรไทย)
  /// [useLabData] = true: คำนวณโดยใช้ผลเลือด Total Cholesterol ร่วมด้วย (RAMA-EGAT Lab-based)
  /// [useLabData] = false: คำนวณแบบไม่ใช้ผลเลือด ประเมินเบื้องต้น (RAMA-EGAT Non-lab based)
  static Map<String, dynamic> calculateRisk({
    required int age,
    required String gender, // 'male' หรือ 'female'
    required bool isSmoker,
    required bool hasDiabetes,
    required double systolicBP,
    double? totalCholesterol, // เป็น Option สามารถส่งมาหรือไม่ส่งก็ได้
    required bool useLabData,
  }) {
    bool isMale = gender.toLowerCase() == 'male';
    double riskPercent = 0.0;

    // 🚀 คำนวณความเสี่ยง 10 ปี ตามสมการอ้างอิง RAMA-EGAT Risk Score
    if (useLabData && totalCholesterol != null && totalCholesterol > 0) {
      // 1. กรณีใช้ผลเลือด (Lab-based Model)
      double tc = totalCholesterol;

      if (isMale) {
        double index = (0.0689 * age) +
            (0.0125 * systolicBP) +
            (0.0028 * tc) +
            (hasDiabetes ? 0.4101 : 0) +
            (isSmoker ? 0.3804 : 0);
        double meanIndex = 5.25;
        riskPercent = (1 - math.pow(0.957, math.exp(index - meanIndex))) * 100;
      } else {
        double index = (0.0701 * age) +
            (0.0152 * systolicBP) +
            (0.0031 * tc) +
            (hasDiabetes ? 0.5821 : 0) +
            (isSmoker ? 0.4215 : 0);
        double meanIndex = 5.40;
        riskPercent = (1 - math.pow(0.968, math.exp(index - meanIndex))) * 100;
      }
    } else {
      // 2. กรณีไม่ใช้ผลเลือด (Non-lab Model)
      if (isMale) {
        double index = (0.0712 * age) +
            (0.0141 * systolicBP) +
            (hasDiabetes ? 0.4851 : 0) +
            (isSmoker ? 0.4012 : 0);
        double meanIndex = 4.85;
        riskPercent = (1 - math.pow(0.955, math.exp(index - meanIndex))) * 100;
      } else {
        double index = (0.0735 * age) +
            (0.0165 * systolicBP) +
            (hasDiabetes ? 0.6120 : 0) +
            (isSmoker ? 0.4510 : 0);
        double meanIndex = 5.10;
        riskPercent = (1 - math.pow(0.965, math.exp(index - meanIndex))) * 100;
      }
    }

    // Sanity Check: ปรับให้อยู่ในจำกัดช่วงเปอร์เซ็นต์ที่สมเหตุสมผล
    riskPercent = riskPercent.clamp(0.5, 75.0);
    double scoreValue = double.parse(riskPercent.toStringAsFixed(1));

    // แปลงเปอร์เซ็นต์ความเสี่ยงเป็นระดับความเสี่ยง (Risk Level) ตามเกณฑ์กระทรวงสาธารณสุข
    String riskLevel;
    String colorCode;

    if (scoreValue >= 30.0) {
      riskLevel = 'สูงมาก (≥ 30%)';
      colorCode = 'red';
    } else if (scoreValue >= 20.0) {
      riskLevel = 'สูง (20 - <30%)';
      colorCode = 'orange';
    } else if (scoreValue >= 10.0) {
      riskLevel = 'ปานกลาง (10 - <20%)';
      colorCode = 'yellow';
    } else {
      riskLevel = 'ต่ำ (< 10%)';
      colorCode = 'green';
    }

    String calculationType = (useLabData && totalCholesterol != null)
        ? 'ประเมินตามมาตรฐาน RAMA-EGAT (ใช้ผลเลือด)'
        : 'ประเมินตามมาตรฐาน RAMA-EGAT (ไม่ใช้ผลเลือด)';

    return {
      'score': scoreValue, // คืนค่าเป็น % ความเสี่ยงจริง เช่น 12.5 (%)
      'level': riskLevel,
      'color': colorCode,
      'type': calculationType,
    };
  }
}
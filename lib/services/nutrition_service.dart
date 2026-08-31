import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_proxy_service.dart';

/// NutritionService (Hybrid / V3)
/// -------------------------------------------------------------
/// เก็บ public API, prompt เนื้อหา, JSON schema/field names (food_name,
/// carbs_g, protein_g, fat_g, trans_fat_g, fiber_g, meal_type,
/// warning_flags ฯลฯ) และ logic การบันทึก/ดึงข้อมูลจาก Supabase
/// ให้ "เหมือนเดิม 100%" กับ Version 1 (full-Gemini) เพื่อไม่ให้กระทบ
/// nutrition_screen.dart (UI คาดหวัง field name ชุดนี้เท่านั้น)
/// — มีแค่ transport layer ของ 2 ฟังก์ชันที่เรียก AI
/// (analyzeFoodFromAudio / analyzeFoodInput) ที่เปลี่ยนจาก GenerativeModel
/// เป็น AiProxyService.generateContent (ผ่าน Supabase Edge Function)
class NutritionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AiProxyService _aiProxy = AiProxyService();

  NutritionService();

  /// 🎙️ 1. AI วิเคราะห์อาหารจาก "ไฟล์เสียงพูด" (Multimodal Audio)
  Future<Map<String, dynamic>?> analyzeFoodFromAudio({
    required File audioFile,
    required String underlyingDiseases,
  }) async {
    final now = DateTime.now();
    final isLateNight = now.hour >= 20 || now.hour < 4;

    final prompt = '''
คุณคือนักโภชนาการทางการแพทย์สำหรับผู้ป่วยโรคเรื้อรัง (NCDs)
จงฟังเสียงบันทึกของผู้ป่วย แล้ววิเคราะห์รายการอาหารและเครื่องดื่มที่ผู้ป่วยพูด

ข้อมูลผู้ป่วย:
- โรคประจำตัว: $underlyingDiseases
- เวลาที่รับประทานปัจจุบัน: ${now.hour}:${now.minute.toString().padLeft(2, '0')} น. (ช่วงหลัง 20.00 น. = $isLateNight)

กรุณาถอดเสียงเป็นชื่ออาหาร คำนวณสารอาหารโดยอ้างอิงจากฐานข้อมูลอาหารไทยและอาหารร้านสะดวกซื้อ และส่งกลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "food_name": "ชื่ออาหารทั้งหมดที่ผู้ป่วยพูด เช่น ข้าวกะเพราหมูกรอบไข่ดาว และ ชาไทยหวานน้อย",
  "calories": 450.0,
  "carbs_g": 55.0,
  "protein_g": 20.0,
  "fat_g": 16.0,
  "sodium_mg": 850.0,
  "sugar_g": 15.0,
  "trans_fat_g": 0.0,
  "fiber_g": 2.5,
  "meal_type": "มื้ออาหาร",
  "warning_flags": [
    "ข้อความเตือนทางการแพทย์ เช่น โซเดียมสูงเกิน 600mg (ระวังในโรคความดัน/ไต), น้ำตาลสูง (ระวังในเบาหวาน), ไขมันทรานส์, หรือทานมื้อดึกหลัง 20.00 น."
  ],
  "nutrition_advice": "คำแนะนำสั้นๆ 1 ประโยคสำหรับมื้อนี้"
}
''';

    try {
      final audioBytes = await audioFile.readAsBytes();
      final String mimeType =
          audioFile.path.endsWith('.wav') ? 'audio/wav' : 'audio/m4a';

      final responseText = await _aiProxy.generateContent(
        serviceType: 'nutrition',
        prompt: prompt,
        structured: true,
        contextData: {'underlying_diseases': underlyingDiseases},
        fileData: {
          'mime_type': mimeType,
          'data': base64Encode(audioBytes),
        },
      );

      final cleanedJson = responseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      return jsonDecode(cleanedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ Nutrition Audio (Edge) Error: $e');
    }
    return null;
  }

  /// 📝 2. AI วิเคราะห์อาหารจาก "ข้อความพิมพ์"
  Future<Map<String, dynamic>?> analyzeFoodInput({
    required String textInput,
    required String underlyingDiseases,
  }) async {
    final now = DateTime.now();
    final isLateNight = now.hour >= 20 || now.hour < 4;

    final prompt = '''
คุณคือนักโภชนาการทางการแพทย์สำหรับผู้ป่วยโรคเรื้อรัง (NCDs)
จงวิเคราะห์เมนูอาหารต่อไปนี้: "$textInput"

ข้อมูลผู้ป่วย:
- โรคประจำตัว: $underlyingDiseases
- เวลาที่รับประทานปัจจุบัน: ${now.hour}:${now.minute.toString().padLeft(2, '0')} น. (ช่วงหลัง 20.00 น. = $isLateNight)

กรุณาคำนวณสารอาหารโดยอ้างอิงจากฐานข้อมูลอาหารไทยและอาหารร้านสะดวกซื้อ และส่งกลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "food_name": "ชื่ออาหารที่ระบุ",
  "calories": 350.0,
  "carbs_g": 45.0,
  "protein_g": 18.0,
  "fat_g": 12.0,
  "sodium_mg": 850.0,
  "sugar_g": 6.0,
  "trans_fat_g": 0.0,
  "fiber_g": 3.0,
  "meal_type": "มื้ออาหาร",
  "warning_flags": [
    "ข้อความเตือนถ้ามี เช่น โซเดียมสูงเกิน 600mg (ระวังในโรคความดัน/ไต), มีน้ำตาลสูง (ระวังในเบาหวาน), มีไขมันทรานส์, หรือทานมื้อดึกหลัง 20.00 น."
  ],
  "nutrition_advice": "คำแนะนำสั้นๆ 1 ประโยคสำหรับมื้อนี้"
}
''';

    try {
      final responseText = await _aiProxy.generateContent(
        serviceType: 'nutrition',
        prompt: prompt,
        structured: true,
        contextData: {'underlying_diseases': underlyingDiseases},
      );

      final cleanedJson = responseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      return jsonDecode(cleanedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ Nutrition Text (Edge) Error: $e');
    }
    return null;
  }
  /// 📷 AI วิเคราะห์อาหารจาก "ภาพถ่าย" (Multimodal Vision)
  Future<Map<String, dynamic>?> analyzeFoodFromImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    required String underlyingDiseases,
  }) async {
    final now = DateTime.now();
    final isLateNight = now.hour >= 20 || now.hour < 4;

    final prompt = '''
คุณคือนักโภชนาการทางการแพทย์สำหรับผู้ป่วยโรคเรื้อรัง (NCDs)
จงดูภาพถ่ายอาหารนี้ แล้ววิเคราะห์รายการอาหาร ปริมาณ และประเมินคุณค่าทางโภชนาการ

ข้อมูลผู้ป่วย:
- โรคประจำตัว: $underlyingDiseases
- เวลาที่รับประทานปัจจุบัน: ${now.hour}:${now.minute.toString().padLeft(2, '0')} น. (ช่วงหลัง 20.00 น. = $isLateNight)

กรุณาประเมินชื่ออาหาร คำนวณสารอาหารโดยอ้างอิงจากฐานข้อมูลอาหารไทย/ร้านสะดวกซื้อ และส่งกลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "food_name": "ชื่ออาหารและส่วนประกอบที่ตรวจพบในรูป เช่น ข้าวราดกะเพราไก่ไข่ดาว",
  "calories": 450.0,
  "carbs_g": 55.0,
  "protein_g": 20.0,
  "fat_g": 16.0,
  "sodium_mg": 850.0,
  "sugar_g": 4.0,
  "trans_fat_g": 0.0,
  "fiber_g": 2.5,
  "meal_type": "มื้ออาหาร",
  "warning_flags": [
    "ข้อความเตือนทางการแพทย์ เช่น โซเดียมสูงเกิน 600mg (ระวังในโรคความดัน/ไต), มีน้ำตาลสูง (ระวังในเบาหวาน), หรือทานมื้อดึกหลัง 20.00 น."
  ],
  "nutrition_advice": "คำแนะนำสั้นๆ 1 ประโยคสำหรับมื้อนี้"
}
''';

    try {
      final responseText = await _aiProxy.generateContent(
        serviceType: 'nutrition',
        prompt: prompt,
        structured: true,
        contextData: {'underlying_diseases': underlyingDiseases},
        fileData: {
          'mime_type': mimeType,
          'data': base64Encode(imageBytes),
        },
      );

      final cleanedJson = responseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      return jsonDecode(cleanedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ Nutrition Image (Vision) Error: $e');
    }
    return null;
  }

  /// 💾 3. บันทึกมื้ออาหารลง Supabase
  Future<void> saveFoodLog({
    required String patientId,
    required Map<String, dynamic> foodData,
  }) async {
    await _supabase.from('food_logs').insert({
      'patient_id': patientId,
      'food_name': foodData['food_name'] ?? 'อาหาร',
      'calories': foodData['calories'] ?? 0.0,
      'carbs_g': foodData['carbs_g'] ?? 0.0,
      'protein_g': foodData['protein_g'] ?? 0.0,
      'fat_g': foodData['fat_g'] ?? 0.0,
      'sodium_mg': foodData['sodium_mg'] ?? 0.0,
      'sugar_g': foodData['sugar_g'] ?? 0.0,
      'trans_fat_g': foodData['trans_fat_g'] ?? 0.0,
      'fiber_g': foodData['fiber_g'] ?? 0.0,
      'meal_type': foodData['meal_type'] ?? 'มื้ออาหาร',
      'warning_flags': foodData['warning_flags'] ?? [],
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// 💾 4. บันทึกการออกกำลังกายลง Supabase
  Future<void> saveExerciseLog({
    required String patientId,
    required String exerciseName,
    required int durationMinutes,
    required double caloriesBurned,
  }) async {
    await _supabase.from('exercise_logs').insert({
      'patient_id': patientId,
      'exercise_name': exerciseName,
      'duration_minutes': durationMinutes,
      'calories_burned': caloriesBurned,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// 📊 5. ดึงบันทึกอาหารของวันนี้ (แก้ปัญหา Timezone)
  Future<List<Map<String, dynamic>>> getTodayFoodLogs(String patientId) async {
    final now = DateTime.now();
    // สร้างช่วงเวลา 00:00:00 ถึง 23:59:59 ตามเวลาไทย แล้วแปลงเป็น UTC
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();

    final res = await _supabase
        .from('food_logs')
        .select()
        .eq('patient_id', patientId)
        .gte('recorded_at', startOfDay)
        .lte('recorded_at', endOfDay)
        .order('recorded_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// 🏃‍♂️ 6. ดึงบันทึกออกกำลังกายของวันนี้ (แก้ปัญหา Timezone UTC)
  Future<List<Map<String, dynamic>>> getTodayExerciseLogs(String patientId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();

    final res = await _supabase
        .from('exercise_logs')
        .select()
        .eq('patient_id', patientId)
        .gte('recorded_at', startOfDay)
        .lte('recorded_at', endOfDay)
        .order('recorded_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// 📈 7. ดึงสถิติโภชนาการและเผาผลาญย้อนหลัง 7 วัน (สำหรับกราฟ Donut Chart)
  Future<Map<String, dynamic>> getLast7DaysSummary(String patientId) async {
    final now = DateTime.now();
    final sevenDaysAgo = DateTime(now.year, now.month, now.day - 6).toUtc().toIso8601String();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();

    // ดึงข้อมูลอาหาร 7 วัน
    final foods = await _supabase
        .from('food_logs')
        .select()
        .eq('patient_id', patientId)
        .gte('recorded_at', sevenDaysAgo)
        .lte('recorded_at', todayEnd);

    // ดึงข้อมูลออกกำลังกาย 7 วัน
    final exercises = await _supabase
        .from('exercise_logs')
        .select()
        .eq('patient_id', patientId)
        .gte('recorded_at', sevenDaysAgo)
        .lte('recorded_at', todayEnd);

    double totalFoodCals = 0;
    double totalBurnedCals = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    for (var f in foods) {
      totalFoodCals += ((f['calories'] as num?)?.toDouble() ?? 0.0);
      totalProtein += ((f['protein_g'] as num?)?.toDouble() ?? 0.0);
      totalCarbs += ((f['carbs_g'] as num?)?.toDouble() ?? 0.0);
      totalFat += ((f['fat_g'] as num?)?.toDouble() ?? 0.0);
    }

    for (var e in exercises) {
      totalBurnedCals += ((e['calories_burned'] as num?)?.toDouble() ?? 0.0);
    }

    return {
      'avgDailyFoodCals': totalFoodCals / 7,
      'avgDailyBurnedCals': totalBurnedCals / 7,
      'totalProtein': totalProtein,
      'totalCarbs': totalCarbs,
      'totalFat': totalFat,
      'foodCount': foods.length,
      'exerciseCount': exercises.length,
    };
  }

  /// 🗑️ รีเซ็ตข้อมูลโภชนาการและการออกกำลังกาย 7 วันย้อนหลัง
  Future<void> resetWeeklyLogs(String patientId) async {
    try {
      final supabase = Supabase.instance.client;
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();

      // 1. ลบข้อมูลอาหาร (food_logs) 7 วันย้อนหลัง
      await supabase
          .from('food_logs')
          .delete()
          .eq('patient_id', patientId)
          .gte('recorded_at', sevenDaysAgo)
          .lte('recorded_at', todayEnd);

      // 2. ลบข้อมูลการออกกำลังกาย (exercise_logs) 7 วันย้อนหลัง
      await supabase
          .from('exercise_logs')
          .delete()
          .eq('patient_id', patientId)
          .gte('recorded_at', sevenDaysAgo)
          .lte('recorded_at', todayEnd);

    } catch (e) {
      debugPrint('❌ Error resetting weekly logs in NutritionService: $e');
      throw Exception('ไม่สามารถรีเซ็ตข้อมูล 7 วันได้: $e');
    }
  }
}

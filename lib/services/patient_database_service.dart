import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientDatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// บันทึกค่าวัดสัญญาณชีพ (Vital Signs) เชื่อมกับ Patient UUID
  Future<void> saveVitalSigns({
    required String patientId,
    required int systolic,
    required int diastolic,
    int? pulse,
    int? heartRate,
    double? fbs,
    double? waistCm,
    String? urgencyLevel,
    String? spokenFeedback,
    String? imageUrl, // 📍 ตอนนี้จะรับเป็น File Path แทน Signed URL
  }) async {
    try {
      if (patientId.isEmpty) {
        throw Exception('Patient ID is required to save vital signs');
      }

      final finalPulse = pulse ?? heartRate;
      await _supabase.from('vital_signs').insert({
        'patient_id': patientId,
        'systolic': systolic,
        'diastolic': diastolic,
        'pulse': finalPulse,
        'fbs': fbs,
        'waist_cm': waistCm,
        'urgency_level': urgencyLevel,
        'spoken_feedback': spokenFeedback,
        'image_url': imageUrl,
        // 📍 [Fix Timezone]: บังคับแปลงเป็นเวลา UTC เสมอก่อนลง DB
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('✅ บันทึก Vital Signs ลง Supabase เรียบร้อย (UTC Timestamp)');
    } catch (e) {
      debugPrint('❌ Error ในการบันทึก Vital Signs: $e');
      rethrow;
    }
  }

  /// ดึง Signed URL ของรูปภาพชั่วคราว (อายุ 1 ชั่วโมง)
  /// รองรับทั้ง File Path และ URL เก่า (Backward Compatibility)
  Future<String?> getImageUrl(String? imagePathOrUrl) async {
    if (imagePathOrUrl == null || imagePathOrUrl.trim().isEmpty) {
      return null;
    }

    // กรณีเป็น URL เก่าที่ขึ้นต้นด้วย http หรือ https ให้ส่งกลับค่าเดิมทันที
    if (imagePathOrUrl.startsWith('http://') || imagePathOrUrl.startsWith('https://')) {
      return imagePathOrUrl;
    }

    try {
      // สร้าง Signed URL อายุ 1 ชั่วโมง (3,600 วินาที) จาก Supabase Storage
      final String signedUrl = await _supabase.storage
          .from('health_images')
          .createSignedUrl(imagePathOrUrl, 60 * 60);
      return signedUrl;
    } catch (e) {
      debugPrint('⚠️ ไม่สามารถสร้าง Signed URL สำหรับ $imagePathOrUrl: $e');
      return null;
    }
  }

  /// 📍 ตรวจสอบว่าผู้ป่วยวัดความดันเกิน 3 ครั้งต่อวันหรือไม่ (ป้องกันการวัดซ้ำซ้อนด้วยความวิตกกังวล)
  Future<bool> canSaveVitalSignToday(String patientId) async {
    try {
      // หาวันที่ปัจจุบัน (เริ่มตั้งแต่ 00:00:00 น.) ของเวลา Local
      final now = DateTime.now();
      final startOfDayLocal = DateTime(now.year, now.month, now.day);
      // แปลงเป็น UTC เพื่อไป Query ในฐานข้อมูลให้ถูกต้อง
      final startOfDayUtc = startOfDayLocal.toUtc();

      final response = await _supabase
          .from('vital_signs')
          .select('id')
          .eq('patient_id', patientId)
          .gte('recorded_at', startOfDayUtc.toIso8601String());

      final records = List<dynamic>.from(response);
      return records.length < 3; // ถ้าวัดไปแล้วน้อยกว่า 3 ครั้ง ถือว่าเซฟได้ (true)
    } catch (e) {
      debugPrint('⚠️ Error checking daily limit: $e');
      return true; // ถ้าเน็ตหลุดหรือมี Error ยอมให้เซฟไว้ก่อน เพื่อความปลอดภัย
    }
  }
  /// 📍 ดึงเวลาที่บันทึกความดันครั้งล่าสุดของผู้ป่วยในวันนี้
  Future<DateTime?> getLastMeasurementTimeToday(String patientId) async {
    try {
      final now = DateTime.now();
      final startOfDayUtc = DateTime(now.year, now.month, now.day).toUtc();

      final response = await _supabase
          .from('vital_signs')
          .select('recorded_at')
          .eq('patient_id', patientId)
          .gte('recorded_at', startOfDayUtc.toIso8601String())
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && response['recorded_at'] != null) {
        return DateTime.parse(response['recorded_at'].toString()).toLocal();
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Error getting last measurement time: $e');
      return null;
    }
  }

  /// บันทึกข้อมูลการแจ้งเตือนวิกฤตลงตาราง alerts_complications
  Future<void> saveAlertComplication({
    required String patientId,
    required String alertType,
    required String severity,
    required String symptomsReported,
  }) async {
    try {
      await _supabase.from('alerts_complications').insert({
        'patient_id': patientId,
        'alert_type': alertType,
        'severity': severity,
        'symptoms_reported': symptomsReported,
        'is_resolved': false,
        // 📍 [Fix Timezone]: ใช้ UTC
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint('✅ บันทึกการแจ้งเตือนวิกฤตลงตาราง alerts_complications เรียบร้อย');
    } catch (e) {
      debugPrint('❌ เกิดข้อผิดพลาดในการบันทึก alerts_complications: $e');
      rethrow;
    }
  }

  /// ย่อขนาดรูปภาพก่อนอัปโหลด
  Future<File> _compressImage(File file) async {
    try {
      final tempDir = await path_provider.getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 80,
        minWidth: 1024,
        minHeight: 1024,
      );

      return result != null ? File(result.path) : file;
    } catch (e) {
      debugPrint('⚠️ ย่อขนาดรูปภาพล้มเหลว ใช้ไฟล์เดิม: $e');
      return file;
    }
  }

  /// 📍 [Fix Storage]: อัปโหลดรูปแล้ว คืนค่าเฉพาะ "File Path" (ไม่ใช่ Signed URL ยั่งยืนกว่า)
  Future<String?> uploadHealthImage(File imageFile, String patientId) async {
    try {
      if (patientId.isEmpty) {
        debugPrint('❌ ไม่พบ Patient ID สำหรับอัปโหลดรูปภาพ');
        return null;
      }

      final fileToUpload = await _compressImage(imageFile);
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String path = '$patientId/$fileName';

      await _supabase.storage.from('health_images').upload(
            path,
            fileToUpload,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // 📍 คืนเฉพาะ Path เพื่อบันทึกลง DB ป้องกันปัญหาลิงก์หมดอายุในอนาคต
      debugPrint('✅ อัปโหลดรูปภาพสำเร็จ Path: $path');
      return path;
    } catch (e) {
      debugPrint('❌ Error ในการอัปโหลดรูปภาพ: $e');
      return null;
    }
  }

  /// 📍 [เพิ่มใหม่]: ฟังก์ชันสร้าง Signed URL ชั่วคราว (อายุ 1 ชั่วโมง) เมื่อจะดึงรูปไปแสดงบน UI
  Future<String?> getSignedImageUrl(String? imagePathOrUrl) async {
    if (imagePathOrUrl == null || imagePathOrUrl.isEmpty) return null;
    
    // ถ้าเป็น URL แบบเก่าที่มี http/https อยู่แล้ว ให้ใช้ค่านั้นได้เลย (รองรับ Backward Compatibility)
    if (imagePathOrUrl.startsWith('http://') || imagePathOrUrl.startsWith('https://')) {
      return imagePathOrUrl;
    }

    try {
      final String signedUrl = await _supabase.storage
          .from('health_images')
          .createSignedUrl(imagePathOrUrl, 60 * 60); // 1 ชั่วโมง
      return signedUrl;
    } catch (e) {
      debugPrint('⚠️ ไม่สามารถสร้าง Signed URL สำหรับ $imagePathOrUrl: $e');
      return null;
    }
  }

  /// ฟังก์ชันสำหรับอัปเดตข้อมูลสุขภาพและวิถีชีวิตจากหน้า Onboarding ลงตาราง patients
  Future<void> updatePatientOnboardingData({
    required String patientId,
    int? age,
    String? gender,
    String? firstName,
    String? lastName,
    double? weight,
    double? height,
    double? bmi,
    String? underlyingDiseases,
    String? lifestyleNotes,
    String? medicationsText,
  }) async {
    try {
      if (patientId.isEmpty) {
        throw Exception('Patient ID is required to update onboarding data');
      }

      await _supabase.from('patients').update({
        if (age != null) 'age': age,
        if (gender != null && gender.trim().isNotEmpty) 'gender': gender,
        if (firstName != null && firstName.trim().isNotEmpty) 'first_name': firstName,
        if (lastName != null && lastName.trim().isNotEmpty) 'last_name': lastName,
        if (weight != null) 'weight_kg': weight,
        if (height != null) 'height_cm': height,
        if (bmi != null) 'bmi': bmi,
        if (underlyingDiseases != null) 'underlying_diseases': underlyingDiseases,
        if (lifestyleNotes != null) 'lifestyle_notes': lifestyleNotes,
      }).eq('id', patientId);

      if (medicationsText != null && medicationsText.trim().isNotEmpty) {
        await saveMedicationLog(
          patientId: patientId,
          medicationName: medicationsText.trim(),
          dosageInstruction: 'ระบุจาก onboarding',
          indication: 'ข้อมูลคนไข้จาก onboarding',
        );
      }

      debugPrint('✅ อัปเดตข้อมูล Onboarding ลง Supabase เรียบร้อย');
    } catch (e) {
      debugPrint('❌ Error ในการอัปเดต Onboarding: $e');
      rethrow;
    }
  }
  // =========================================================================
  // 📍 ส่วนของ Phase 3: การจัดการข้อมูลห้องยา (Medication History)
  // =========================================================================

  /// อัปโหลดรูปซองยาลง Bucket medication_images
  Future<String?> uploadMedicationImage(File imageFile, String patientId) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '$patientId/$fileName';

      // บีบอัดรูปก่อนอัปโหลดเพื่อประหยัดพื้นที่ (ถ้ามีแพ็กเกจ compress, ถ้าไม่มีใช้ไฟล์สด)
      await _supabase.storage.from('medication_images').upload(filePath, imageFile);
      return filePath;
    } catch (e) {
      debugPrint('⚠️ Error uploading medication image: $e');
      return null;
    }
  }

  /// บันทึกข้อมูลยาลงตาราง medication_logs
  Future<void> saveMedicationLog({
    required String patientId,
    required String medicationName,
    String? dosageInstruction,
    String? indication,
    String? imageUrl,
  }) async {
    try {
      await _supabase.from('medication_logs').insert({
        'patient_id': patientId,
        'medication_name': medicationName,
        'dosage_instruction': dosageInstruction,
        'indication': indication,
        'image_url': imageUrl,
      });
    } catch (e) {
      throw Exception('ไม่สามารถบันทึกข้อมูลยาได้: $e');
    }
  }

  /// ดึงข้อมูลยาทั้งหมดของผู้ป่วยมาแสดง
  Future<List<Map<String, dynamic>>> getMedicationLogs(String patientId) async {
    try {
      final response = await _supabase
          .from('medication_logs')
          .select()
          .eq('patient_id', patientId)
          //.eq('is_currently_taking', true)
          .order('recorded_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('⚠️ Error fetching medications: $e');
      return [];
    }
  }

  /// ดึง Signed URL ของรูปยา
  Future<String?> getMedicationImageUrl(String imagePath) async {
    if (imagePath.startsWith('http')) return imagePath;
    try {
      return await _supabase.storage.from('medication_images').createSignedUrl(imagePath, 60 * 60);
    } catch (e) {
      return null;
    }
  }
  // 📍 ฟังก์ชันใหม่: บันทึกข้อมูลว่า "กินยาแล้ว" ลงฐานข้อมูล
  Future<void> logMedicationTaken({
    required String patientId,
    required String medicationId,
    required String medicationName,
  }) async {
    try {
      await _supabase.from('medication_adherence_logs').insert({
        'patient_id': patientId,
        'medication_id': medicationId,
        'medication_name': medicationName,
        'taken_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      throw Exception('ไม่สามารถบันทึกประวัติการกินยาได้: $e');
    }
  }

  // 📍 อัปเดต: ฟังก์ชันอัปเดตยา ให้รองรับการบันทึกสถานะ 3 เวลา
  Future<void> updateMedicationLog({
    required String id,
    required String medicationName,
    required String dosageInstruction,
    required String indication,
    bool? isMorningActive,
    String? timeMorning,
    bool? isNoonActive,
    String? timeNoon,
    bool? isEveningActive,
    String? timeEvening,
  }) async {
    try {
      await _supabase.from('medication_logs').update({
        'medication_name': medicationName,
        'dosage_instruction': dosageInstruction,
        'indication': indication,
        if (isMorningActive != null) 'is_morning_active': isMorningActive,
        if (timeMorning != null) 'time_morning': timeMorning,
        if (isNoonActive != null) 'is_noon_active': isNoonActive,
        if (timeNoon != null) 'time_noon': timeNoon,
        if (isEveningActive != null) 'is_evening_active': isEveningActive,
        if (timeEvening != null) 'time_evening': timeEvening,
      }).eq('id', id);
    } catch (e) {
      throw Exception('ไม่สามารถอัปเดตข้อมูลยาได้: $e');
    }
  }

  // 2. ฟังก์ชันลบข้อมูลยา
  Future<void> deleteMedicationLog(String id) async {
    try {
      await _supabase.from('medication_logs').delete().eq('id', id);
    } catch (e) {
      throw Exception('ไม่สามารถลบข้อมูลยาได้: $e');
    }
  }
  // 1. ดึงประวัติผลแล็บของผู้ป่วย
  Future<List<Map<String, dynamic>>> getLabResults(String patientId) async {
    try {
      final response = await _supabase
          .from('lab_results')
          .select()
          .eq('patient_id', patientId)
          .order('test_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('ไม่สามารถดึงข้อมูลผลแล็บได้: $e');
    }
  }
  /// อัปโหลดรูปภาพใบแล็บจาก Memory Bytes (Web / PWA Safe)
  Future<String?> uploadLabImageBytes(Uint8List imageBytes, String patientId) async {
    try {
      if (patientId.isEmpty) return null;

      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = '$patientId/$fileName';

      await _supabase.storage.from('medication_images').uploadBinary(
            filePath,
            imageBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '3600',
              upsert: false,
            ),
          );

      debugPrint('✅ อัปโหลดรูปภาพใบแล็บสำเร็จ Path: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Error uploadLabImageBytes: $e');
      return null;
    }
  }
  
  // 2. บันทึกผลแล็บใหม่ (รองรับค่า Total Cholesterol สำหรับคำนวณ Thai CV Risk)
  Future<void> saveLabResult({
  required String patientId,
  double? totalCholesterol,
  double? hdl,
  double? ldl,
  double? triglyceride,
  double? fastingBloodSugar,
  double? hba1c,
  double? creatinine,
  double? bun,
  double? egfr,
  double? sgpt,
  double? uricAcid,
  String? imageUrl,
}) async {
  try {
    final Map<String, dynamic> data = {
      'patient_id': patientId,
      'test_date': DateTime.now().toUtc().toIso8601String(),
    };

    // Helper เช็คค่า > 0
    void addIfValid(String key, double? val) {
      if (val != null && val > 0) data[key] = val;
    }

    addIfValid('total_cholesterol', totalCholesterol);
    addIfValid('hdl', hdl);
    addIfValid('ldl', ldl);
    addIfValid('triglyceride', triglyceride);
    addIfValid('fasting_blood_sugar', fastingBloodSugar);
    addIfValid('hba1c', hba1c);
    addIfValid('creatinine', creatinine);
    addIfValid('bun', bun);
    addIfValid('egfr', egfr);
    addIfValid('sgpt', sgpt);
    addIfValid('uric_acid', uricAcid);

    if (imageUrl != null && imageUrl.isNotEmpty) {
      data['image_url'] = imageUrl;
    }

    await _supabase.from('lab_results').insert(data);
    debugPrint('✅ บันทึกผลแล็บลง Supabase สำเร็จ: $data');
  } catch (e) {
    debugPrint('❌ Error saveLabResult: $e');
    rethrow;
  }
}
  // ==========================================
  // ส่วนที่ 1: จัดการลบและบันทึกออกกำลังกาย
  // ==========================================

  /// 🗑️ ลบข้อมูลอาหาร
  Future<void> deleteFoodLog(String id) async {
    try {
      await _supabase.from('food_logs').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting food: $e');
      throw Exception('ไม่สามารถลบข้อมูลอาหารได้: $e');
    }
  }

  /// 🗑️ ลบข้อมูลออกกำลังกาย
  Future<void> deleteExerciseLog(String id) async {
    try {
      await _supabase.from('exercise_logs').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting exercise: $e');
      throw Exception('ไม่สามารถลบข้อมูลออกกำลังกายได้: $e');
    }
  }

  /// 🏃‍♂️ บันทึกข้อมูลออกกำลังกายด่วน (บังคับ Timezone)
  Future<void> saveQuickExercise({
    required String patientId,
    required String exerciseName,
    required int durationMinutes,
    required int intensityZone,
    required double caloriesBurned,
  }) async {
    try {
      // 📍 บังคับแปลงเวลาเครื่องให้เป็น UTC ก่อนบันทึกเสมอ (Time Zone Strict)
      final recordedAt = DateTime.now().toUtc().toIso8601String();

      await _supabase.from('exercise_logs').insert({
        'patient_id': patientId,
        'exercise_name': exerciseName, // 📍 เปลี่ยนจาก exercise_type เป็น exercise_name
        'duration_minutes': durationMinutes,
        'intensity_zone': intensityZone, // เก็บ Zone (2-5)
        'calories_burned': caloriesBurned,
        'recorded_at': recordedAt,
      });
    } catch (e) {
      throw Exception('ไม่สามารถบันทึกการออกกำลังกายได้: $e');
    }
  }
  /// 🗑️ รีเซ็ตข้อมูลโภชนาการและการออกกำลังกาย 7 วันย้อนหลัง
  Future<void> resetWeeklyLogs(String patientId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();

      // ลบ food_logs 7 วันล่าสุด
      await _supabase
          .from('food_logs')
          .delete()
          .eq('patient_id', patientId)
          .gte('recorded_at', sevenDaysAgo)
          .lte('recorded_at', todayEnd);

      // ลบ exercise_logs 7 วันล่าสุด
      await _supabase
          .from('exercise_logs')
          .delete()
          .eq('patient_id', patientId)
          .gte('recorded_at', sevenDaysAgo)
          .lte('recorded_at', todayEnd);
    } catch (e) {
      debugPrint('❌ Error resetting weekly logs: $e');
      throw Exception('ไม่สามารถรีเซ็ตข้อมูล 7 วันได้: $e');
    }
  }
}
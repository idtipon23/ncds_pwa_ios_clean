import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientProfileService {
  static const String _patientIdKey = 'current_patient_id';
  static const String _profileKey = 'patient_profile_data';
  static const String _isRegisteredKey = 'is_registered';
  static const String _onboardedKey = 'is_onboarded';

  // 📍 คีย์หลักสำหรับระบบ Smart HN Memory
  static const String _lastHnKey = 'last_used_hn';
  static const String _lastHospitalIdKey = 'last_used_hospital_id';

  final SupabaseClient _supabase = Supabase.instance.client;

  /// ดึง ID ผู้ป่วยปัจจุบัน (ลำดับความสำคัญ: ID ที่ผูกสำเร็จ -> Auth User ID -> Local ID)
  Future<String?> getCurrentPatientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? localId = prefs.getString(_patientIdKey);
    if (localId != null && localId.isNotEmpty) {
      return localId;
    }
    return null;
  }

  /// 📍 ตรวจสอบว่าโปรไฟล์มีข้อมูล HN และ hospital_id สมบูรณ์หรือไม่
  bool isProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final hn = profile['hn']?.toString() ?? '';
    final hospitalId = profile['hospital_id']?.toString() ?? '';
    return profile['id'] != null && hn.isNotEmpty && hospitalId.isNotEmpty;
  }

  /// 📍 ฟังก์ชันดึงโปรไฟล์อัจฉริยะ
  Future<Map<String, dynamic>?> validateAndLoadProfile() async {
    final currentUser = _supabase.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();

    try {
      // 1. ระบบ Auto login ตรวจสอบเบื้องหลังด้วย Auth User ID ก่อน
      if (currentUser != null) {
        final data = await _supabase
            .from('patients')
            .select()
            // 📍 [แก้ไขแล้ว]: เปลี่ยนจาก 'id' เป็น 'auth_user_id'
            .eq('auth_user_id', currentUser.id)
            .maybeSingle();

        if (data != null && isProfileComplete(data)) {
          await _saveSmartMemory(
            patientId: data['id']
                .toString(), // 📍 ใช้ 'id' (Primary Key) ในการเซฟลงเครื่องตามปกติ
            hn: data['hn'].toString(),
            hospitalId: data['hospital_id'].toString(),
            profileData: data,
          );
          return data;
        }
      }

      // 2. 🚀 ดึงจาก Smart HN Memory ในเครื่องทันที! (กรณีตกหล่น)
      final cachedHn = prefs.getString(_lastHnKey);
      final cachedHospitalId = prefs.getString(_lastHospitalIdKey);

      if (cachedHn != null &&
          cachedHn.isNotEmpty &&
          cachedHospitalId != null &&
          cachedHospitalId.isNotEmpty) {
        final cachedData = await _supabase
            .from('patients')
            .select()
            .eq('hn', cachedHn)
            .eq('hospital_id', cachedHospitalId)
            .maybeSingle();

        if (cachedData != null && isProfileComplete(cachedData)) {
          // ดึงเจอข้อมูลผู้ป่วยเดิม -> บันทึกการผูกสิทธิ์แล้วคืนค่าข้อมูลทันที!
          await _saveSmartMemory(
            patientId: cachedData['id'].toString(),
            hn: cachedHn,
            hospitalId: cachedHospitalId,
            profileData: cachedData,
          );
          return cachedData;
        }
      }

      // 3. อ่านจาก Cache สำรองในเครื่องกรณีไม่มีเน็ต
      final cachedProfile = await getProfile();
      if (cachedProfile != null && isProfileComplete(cachedProfile)) {
        return cachedProfile;
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ Error validating profile: $e');
      return await getProfile();
    }
  }
  /// จัดรูปแบบ HN ให้เป็นมาตรฐาน (เช่น '12345' -> 'HN-12345' หรือตัดช่องว่างทิ้ง)
  String formatHN(String rawHn) {
    String clean = rawHn.trim().toUpperCase();
    if (clean.isEmpty) return clean;
    if (!clean.startsWith('HN-')) {
      // ถ้าระบบของคุณใช้ฟอร์แมต HN- นำหน้าเสมอ
      return 'HN-$clean';
    }
    return clean;
  }

  /// บันทึกข้อมูลโปรไฟล์และความจำ HN ลงเครื่อง
  Future<void> _saveSmartMemory({
    required String patientId,
    required String hn,
    required String hospitalId,
    required Map<String, dynamic> profileData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_patientIdKey, patientId);
    await prefs.setString(_lastHnKey, hn);
    await prefs.setString(_lastHospitalIdKey, hospitalId);
    await prefs.setString(_profileKey, jsonEncode(profileData));
    await prefs.setBool(_isRegisteredKey, true);
  }

  Future<void> saveExistingSession(Map<String, dynamic> patientData) async {
    final patientId = patientData['id'].toString();
    final hn = patientData['hn']?.toString() ?? '';
    final hospitalId = patientData['hospital_id']?.toString() ?? '';

    await _saveSmartMemory(
      patientId: patientId,
      hn: hn,
      hospitalId: hospitalId,
      profileData: patientData,
    );
  }

  Future<void> updateLocalProfile(Map<String, dynamic> newData) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProfile = await getProfile() ?? {};

    currentProfile.addAll(newData);
    await prefs.setString(_profileKey, jsonEncode(currentProfile));

    final patientId = await getCurrentPatientId();
    if (patientId != null && patientId.isNotEmpty) {
      try {
        final Map<String, dynamic> updatePayload = {};

        // ข้อมูลส่วนตัวพื้นฐาน
        if (newData.containsKey('first_name'))
          updatePayload['first_name'] = newData['first_name'];
        if (newData.containsKey('last_name'))
          updatePayload['last_name'] = newData['last_name'];
        if (newData.containsKey('name'))
          updatePayload['name'] = newData['name'];
        if (newData.containsKey('age')) updatePayload['age'] = newData['age'];
        if (newData.containsKey('gender'))
          updatePayload['gender'] = newData['gender'];

        // สัดส่วนร่างกาย
        if (newData.containsKey('weight_kg')) {
          updatePayload['weight_kg'] = newData['weight_kg'];
        } else if (newData.containsKey('weight')) {
          updatePayload['weight_kg'] = newData['weight'];
        }

        if (newData.containsKey('height_cm')) {
          updatePayload['height_cm'] = newData['height_cm'];
        } else if (newData.containsKey('height')) {
          updatePayload['height_cm'] = newData['height'];
        }

        // ค่าคำนวณ BMI, BMR, TDEE
        if (newData.containsKey('bmi')) updatePayload['bmi'] = newData['bmi'];
        if (newData.containsKey('bmr')) updatePayload['bmr'] = newData['bmr'];
        if (newData.containsKey('tdee'))
          updatePayload['tdee'] = newData['tdee'];
        if (newData.containsKey('activity_level'))
          updatePayload['activity_level'] = newData['activity_level'];

        // โรคประจำตัวและพฤติกรรม
        if (newData.containsKey('underlying_diseases')) {
          updatePayload['underlying_diseases'] = newData['underlying_diseases'];
        } else if (newData.containsKey('diseases')) {
          updatePayload['underlying_diseases'] = newData['diseases'];
        }

        if (newData.containsKey('smokes'))
          updatePayload['smokes'] = newData['smokes'];

        if (updatePayload.isNotEmpty) {
          await _supabase
              .from('patients')
              .update(updatePayload)
              .eq('id', patientId);
        }
      } catch (e) {
        debugPrint('⚠️ Error Syncing Profile to Supabase: $e');
      }
    }
  }

  Future<void> updateProfileData(Map<String, dynamic> newData) async =>
      updateLocalProfile(newData);

  Future<Map<String, dynamic>?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String? profileStr = prefs.getString(_profileKey);

    // 1. ลองดึงจาก Local Storage (กรณีใช้งานปกติ)
    if (profileStr != null && profileStr.isNotEmpty) {
      try {
        return jsonDecode(profileStr) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('⚠️ Error decoding cached profile: $e');
      }
    }

    // 2. 📍 [เพิ่มใหม่]: กู้คืนข้อมูลจาก Supabase กรณีลบแอป / Cache หาย
    try {
      final patientId = await getCurrentPatientId();
      if (patientId != null) {
        final response = await _supabase
            .from('patients')
            .select()
            .eq('id', patientId)
            .maybeSingle();

        if (response != null) {
          // 3. 📍 เซฟข้อมูลกลับลงเครื่องแบบเนียนๆ (Self-Healing)
          await prefs.setString(_profileKey, jsonEncode(response));
          await prefs.setString(_patientIdKey, patientId);

          if (response['hn'] != null) {
            await prefs.setString(_lastHnKey, response['hn'].toString());
          }
          if (response['hospital_id'] != null) {
            await prefs.setString(
                _lastHospitalIdKey, response['hospital_id'].toString());
          }

          debugPrint('✅ กู้คืนโปรไฟล์ผู้ป่วยและ HN สำเร็จ!');
          return response;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching profile from Supabase: $e');
    }

    return null;
  }

  Future<Map<String, String>> getLastLoginInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'hn': prefs.getString(_lastHnKey) ?? '',
      'hospital_id': prefs.getString(_lastHospitalIdKey) ?? '',
    };
  }

  Future<String> getProfilePromptContext() async {
    final profile = await getProfile();
    if (profile == null) return '[ไม่พบข้อมูลโปรไฟล์ผู้ป่วย]';
    return '''
[บริบทประจำตัวผู้ป่วย (User Profile Context)]
- ID: ${profile['id'] ?? 'N/A'}
- HN: ${profile['hn'] ?? 'N/A'}
- อายุ: ${profile['age'] ?? 'ไม่ระบุ'} ปี
- น้ำหนัก: ${profile['weight'] ?? 'ไม่ระบุ'} กก.
- ส่วนสูง: ${profile['height'] ?? 'ไม่ระบุ'} ซม.
- โรคประจำตัว: ${profile['underlying_diseases'] ?? profile['diseases'] ?? 'ไม่มี'}
''';
  }

  Future<void> clearLocalIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_patientIdKey);
    await prefs.remove(_profileKey);
    await prefs.setBool(_isRegisteredKey, false);
    await prefs.setBool(_onboardedKey, false);
    await prefs.remove(_lastHnKey);
    await prefs.remove(_lastHospitalIdKey);
    await _supabase.auth.signOut();
  }

  Future<void> fullLogout() async {
    final prefs = await SharedPreferences.getInstance();

    // 🛠️ [Fix]: สำรองข้อมูล Smart HN Memory ไว้ก่อน
    final List<String>? savedHnHistory =
        prefs.getStringList('saved_hn_history');

    // กวาดล้างข้อมูล Session เก่าทิ้ง
    await prefs.clear();

    // 🚀 เขียน Smart HN Memory กลับเข้าไปใหม่ให้ผู้สูงอายุใช้งานต่อได้
    if (savedHnHistory != null && savedHnHistory.isNotEmpty) {
      await prefs.setStringList('saved_hn_history', savedHnHistory);
    }

    // สั่ง Logout ออกจาก Supabase
    await _supabase.auth.signOut();
  }

  /// 📍 บันทึกข้อมูลโปรไฟล์และ Smart HN ลงความจำเครื่อง
  Future<void> saveProfile(Map<String, dynamic> profileData) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. บันทึก ID ผู้ป่วย (Patient UUID)
    if (profileData['id'] != null) {
      await prefs.setString(_patientIdKey, profileData['id'].toString());
    }

    // 2. บันทึก Smart HN Memory (จำรหัสเพื่อ Auto-fill ครั้งหน้า)
    if (profileData['hn'] != null) {
      await prefs.setString(_lastHnKey, profileData['hn'].toString());
    }
    if (profileData['hospital_id'] != null) {
      await prefs.setString(
          _lastHospitalIdKey, profileData['hospital_id'].toString());
    }

    // 3. บันทึกข้อมูล Profile ทั้งหมดเป็น JSON
    await prefs.setString(_profileKey, jsonEncode(profileData));

    // 4. อัปเดตสถานะว่าเข้าสู่ระบบและลงทะเบียนแล้ว
    await prefs.setBool(_isRegisteredKey, true);
    await prefs.setBool(_onboardedKey, true);
  }

  /// ตรวจสอบว่า Patient ID นี้ยังมีอยู่ในฐานข้อมูลจริงหรือไม่ (คืนค่า true/false)
  Future<bool> verifySessionInDatabase(String patientId) async {
    try {
      final data = await _supabase
          .from('patients')
          .select('id')
          .eq('id', patientId)
          .maybeSingle();

      return data != null;
    } catch (e) {
      debugPrint('❌ Error verifying session in database: $e');
      return false;
    }
  }
  /// 📍 อัปเดตข้อมูลโปรไฟล์กลับไปยัง Supabase
  Future<void> updateProfileInDatabase(String patientId, Map<String, dynamic> updatedData) async {
    try {
      await _supabase
          .from('patients') // 🔴 เช็กชื่อ Table ให้ตรงกับของคุณ (เช่น 'patients' หรือ 'patient_profiles')
          .update(updatedData)
          .eq('id', patientId);
          
      // เซฟลงในเครื่องอีกรอบเพื่อให้อัปเดตตรงกัน
      await saveProfile(updatedData); 
    } catch (e) {
      throw Exception('ไม่สามารถอัปเดตข้อมูลได้: $e');
    }
  }
}

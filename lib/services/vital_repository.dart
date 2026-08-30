import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VitalRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 1. ดึงค่าวัดสัญญาณชีพล่าสุด
  Future<Map<String, dynamic>?> getLatestVitalSigns(String patientId) async {
    try {
      if (patientId.isEmpty) return null;

      final response = await _supabase
          .from('vital_signs')
          .select()
          .eq('patient_id', patientId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('❌ Error in getLatestVitalSigns: $e');
      rethrow;
    }
  }

  /// 2. ดึงประวัติสัญญาณชีพตามช่วงเวลา (recorded_at >= startDate AND recorded_at <= endDate)
  Future<List<Map<String, dynamic>>> getVitalSignsByDateRange(
    String patientId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      if (patientId.isEmpty) return [];

      // 📍 [Fix Timezone]: แปลง startDate และ endDate เป็น UTC เสมอก่อน Query
      final response = await _supabase
          .from('vital_signs')
          .select()
          .eq('patient_id', patientId)
          .gte('recorded_at', startDate.toUtc().toIso8601String())
          .lte('recorded_at', endDate.toUtc().toIso8601String())
          .order('recorded_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error in getVitalSignsByDateRange: $e');
      rethrow;
    }
  }

  /// 3. ดึงประวัติ 7 วันย้อนหลัง (ใช้อ้างอิงเวลา UTC)
  Future<List<Map<String, dynamic>>> getLast7Days(String patientId) {
    final now = DateTime.now().toUtc();
    final startDate = now.subtract(const Duration(days: 7));
    return getVitalSignsByDateRange(patientId, startDate: startDate, endDate: now);
  }

  /// 4. ดึงประวัติ 1 เดือนย้อนหลัง (30 วัน)
  Future<List<Map<String, dynamic>>> getLast1Month(String patientId) {
    final now = DateTime.now().toUtc();
    final startDate = now.subtract(const Duration(days: 30));
    return getVitalSignsByDateRange(patientId, startDate: startDate, endDate: now);
  }

  /// 5. ดึงประวัติ 3 เดือนย้อนหลัง (90 วัน)
  Future<List<Map<String, dynamic>>> getLast3Months(String patientId) {
    final now = DateTime.now().toUtc();
    final startDate = now.subtract(const Duration(days: 90));
    return getVitalSignsByDateRange(patientId, startDate: startDate, endDate: now);
  }

  /// 6. ดึงประวัติ 6 เดือนย้อนหลัง (180 วัน)
  Future<List<Map<String, dynamic>>> getLast6Months(String patientId) {
    final now = DateTime.now().toUtc();
    final startDate = now.subtract(const Duration(days: 180));
    return getVitalSignsByDateRange(patientId, startDate: startDate, endDate: now);
  }
}
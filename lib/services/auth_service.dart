import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // เพิ่มฟังก์ชันใหม่สำหรับจัดการ Anonymous Auth
  Future<AuthResponse> signInAnonymouslyIfNeeded() async {
    try {
      // a) เช็คก่อนว่ามี session อยู่แล้วหรือไม่
      if (_supabase.auth.currentSession != null) {
        return AuthResponse(
          session: _supabase.auth.currentSession,
          user: _supabase.auth.currentUser,
        );
      }
      
      // b) ถ้ายังไม่มี ให้เรียก signInAnonymously และคืนค่า
      return await _supabase.auth.signInAnonymously();
    } catch (e) {
      // c) จัดการ error
      print('Error signing in anonymously: $e');
      rethrow;
    }
  }

  // ฟังก์ชันออกจากระบบ
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ดึงข้อมูล User ปัจจุบัน
  User? get currentUser => _supabase.auth.currentUser;
}
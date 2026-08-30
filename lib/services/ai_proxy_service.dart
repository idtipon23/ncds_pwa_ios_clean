import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AiProxyService {
  // 1. Singleton Pattern ตามมาตรฐาน
  static final AiProxyService _instance = AiProxyService._internal();
  factory AiProxyService() => _instance;
  AiProxyService._internal();

  final _supabase = Supabase.instance.client;

  /// ฟังก์ชันเรียก AI ผ่าน Supabase Edge Function (Proxy)
  Future<String> generateContent({
    required String serviceType,
    String prompt = '', // 📍 ปรับให้มีค่า default เพื่อรองรับการส่งไฟล์เสียง/รูปอย่างเดียว
    bool structured = false,
    Map<String, dynamic>? contextData,
    Map<String, String>? fileData, // รูปแบบ: {'mime_type': 'image/jpeg', 'data': 'base64...'}
  }) async {
    try {
      // 📍 ครอบ timeout กันเคส Edge Function ค้าง (cold start / Gemini ฝั่ง server ช้า)
      // ถ้าไม่ตอบภายในเวลานี้ ให้ throw ออกมาแทนที่จะรอเฉยๆ ไม่มีวันจบ
      final response = await _supabase.functions
          .invoke(
            'ai-proxy',
            body: {
              'service_type': serviceType,
              'prompt': prompt,
              'structured': structured,
              'context_data': contextData ?? {},
              if (fileData != null) 'file_data': fileData,
            },
          )
          .timeout(const Duration(seconds: 12));

      // ตรวจสอบ Status 200
      if (response.status != 200) {
        throw Exception('AI Proxy Server status error: ${response.status}');
      }

      final data = response.data;
      Map<String, dynamic> jsonMap;

      if (data is String) {
        // 📍 [JSON Parser Shielding]: ล้าง Markdown Tag ก่อน Decode
        String cleanedData = data
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        jsonMap = jsonDecode(cleanedData) as Map<String, dynamic>;
      } else if (data is Map) {
        jsonMap = Map<String, dynamic>.from(data);
      } else {
        throw Exception('Invalid response structure from server');
      }

      if (jsonMap.containsKey('error')) {
        throw Exception(jsonMap['error']);
      }

      // ดึงข้อความคำตอบจาก AI
      final resultText = jsonMap['text'] as String? ?? '';
      
      if (resultText.isEmpty) {
        return 'ขออภัยครับ ระบบไม่สามารถประมวลผลข้อมูลได้ในขณะนี้';
      }

      return resultText;

    } on FunctionException catch (fe) {
      // 📍 จุดสำคัญ: ดักจับ Error จาก Supabase Function โดยเฉพาะ
      debugPrint('❌ Supabase FunctionException: status=${fe.status}, details=${fe.details}');
      
      // พยายามแกะข้อความ Fallback ที่ Edge Function ส่งกลับมา
      try {
        if (fe.details is Map && fe.details['fallback_ui_message'] != null) {
          return fe.details['fallback_ui_message'] as String;
        } else if (fe.details is String) {
          // 📍 [JSON Parser Shielding]: ล้าง Markdown Tag กรณี Error ส่งมาเป็น String
          String cleanedError = (fe.details as String)
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          final parsed = jsonDecode(cleanedError);
          if (parsed['fallback_ui_message'] != null) {
            return parsed['fallback_ui_message'] as String;
          }
        }
      } catch (_) {}

      return 'ขณะนี้ระบบ AI มีผู้ใช้งานหนาแน่น กรุณาลองใหม่อีกครั้งในครู่ครับ';

    } on TimeoutException catch (e) {
      // 📍 แยก log ของเคส timeout ออกจาก error ทั่วไป เพื่อให้เห็นชัดตอนไล่ log จริง
      // ว่าเป็น Edge Function ค้าง ไม่ใช่เน็ตหลุดหรือ error อื่น
      debugPrint('⏱️ AiProxyService Timeout (12s exceeded): $e');
      return 'ระบบ AI ตอบช้ากว่าปกติ กรุณาลองใหม่อีกครั้งครับ';
    } catch (e) {
      debugPrint('❌ AiProxyService General Error: $e');
      // กรณีเน็ตหลุด หรือเกิดข้อยกเว้นอื่นๆ
      return 'ไม่สามารถเชื่อมต่อระบบ AI ได้ กรุณาตรวจสอบสัญญาณอินเทอร์เน็ตแล้วลองใหม่อีกครั้งครับ';
    }
  }
}
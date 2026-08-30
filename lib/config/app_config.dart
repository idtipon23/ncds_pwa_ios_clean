import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // ดึง Key จากไฟล์ .env ทำให้ปลอดภัยมากยิ่งขึ้น
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
}
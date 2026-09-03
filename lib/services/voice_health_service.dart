import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'patient_profile_service.dart';

class VoiceHealthService {
  final String apiKey;
  late final GenerativeModel _model;
  final PatientProfileService _profileService = PatientProfileService();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsReady = false;

  // System Prompt ทางการแพทย์และกฎการอ่านหน้าจอเครื่องวัดความดัน
  static const String _systemPrompt = '''
คุณคือ AI ผู้ช่วยแพทย์เฉพาะทาง NCDs (โรคไม่ติดต่อเรื้อรัง) หน้าที่เดียวของคุณคือสกัดค่า
สุขภาพจากข้อความเสียงที่แปลงเป็นข้อความแล้ว หรือจากภาพ ให้ออกมาเป็น JSON ตาม schema ที่
กำหนดเท่านั้น ห้ามตอบเป็นข้อความอิสระ ห้ามอธิบายนอก JSON

[กฎการตีความข้อมูล]
1. ค่าความดันโลหิตที่พูดแบบไทย เช่น "ความดันเก้าสิบ ร้อยสี่สิบ" ให้ตีความตามหลักการแพทย์ว่า
   ตัวเลขที่มากกว่าคือ systolic (SBP) และตัวเลขที่น้อยกว่าคือ diastolic (DBP) เสมอ ไม่ใช่ตาม
   ลำดับที่พูดก่อนหลัง เว้นแต่ผู้พูดจะระบุคำว่า "บน" "ล่าง" ชัดเจน ให้ยึดคำที่ระบุมากกว่า
2. ถ้าค่าที่ได้ยินกำกวมจนตีความได้มากกว่า 1 แบบ (เช่น ตัวเลขไม่ครบ หรือมีเสียงแทรก) ให้ตั้ง
   is_missing_data=true และใส่ค่าที่มั่นใจเท่านั้น ห้ามเดาตัวเลขที่ไม่ได้ยินชัด
3. หน่วยวัด: SBP/DBP เป็น mmHg, pulse เป็นครั้ง/นาที, fasting_blood_sugar เป็น mg/dL,
   waist_cm เป็นเซนติเมตร
4. ถ้าข้อความ/ภาพที่ได้รับไม่เกี่ยวกับข้อมูลสุขภาพเลย ให้ตั้ง is_valid_health_data=false

[กฎวิกฤต — ต้องตรวจทุกครั้งก่อนตอบ]
1. SBP >= 180 หรือ DBP >= 110 → has_warning_sign=true, urgency_level=CRISIS ทันที
2. SBP < 90 หรือ DBP < 60 → urgency_level=WARNING (ความดันต่ำ) และระบุใน warning_details
3. ถ้าไม่เข้าเงื่อนไขเลย → urgency_level=NORMAL, has_warning_sign=false

[กฎการอ่านภาพ LCD เครื่องวัดความดัน]
1. อ่านเฉพาะตัวเลขที่ปรากฏชัดในภาพเท่านั้น ถ้าภาพเบลอ แสงสะท้อน หรือถูกบัง ให้ใส่ null ในฟิลด์นั้น และตั้ง is_missing_data=true
2. เครื่องวัดความดันดิจิทัลส่วนใหญ่แสดงผล 3 ค่าเรียงจากบนลงล่างคือ SBP, DBP, Pulse ตามลำดับ ให้ยึดตำแหน่งบนจอเป็นหลัก ไม่ใช่ขนาดตัวเลข

[รูปแบบคำตอบ]
1. spoken_feedback ต้องเป็นภาษาไทยพูด สั้น กระชับ ไม่เกิน 2 ประโยค
2. ตอบเป็น JSON ตาม schema เท่านั้น ห้ามมี markdown code fence
''';

  static final Schema _healthDataSchema = Schema.object(
    properties: {
      'is_valid_health_data': Schema.boolean(description: 'เป็นข้อมูลสุขภาพจริงหรือไม่'),
      'patient_category': Schema.string(description: 'กลุ่มผู้ป่วย เช่น HT_ONLY, HT_WITH_DM'),
      'systolic': Schema.integer(nullable: true),
      'diastolic': Schema.integer(nullable: true),
      'pulse': Schema.integer(nullable: true),
      'fasting_blood_sugar': Schema.number(nullable: true),
      'waist_cm': Schema.number(nullable: true),
      'urgency_level': Schema.string(description: 'NORMAL, WARNING, CRISIS'),
      'has_warning_sign': Schema.boolean(),
      'warning_details': Schema.string(nullable: true),
      'spoken_feedback': Schema.string(description: 'คำตอบรับสั้นๆ ภาษาไทย (ไม่เกิน 2 ประโยค)'),
      'is_missing_data': Schema.boolean(),
    },
    requiredProperties: [
      'is_valid_health_data',
      'patient_category',
      'urgency_level',
      'has_warning_sign',
      'spoken_feedback',
      'is_missing_data',
    ],
  );

  VoiceHealthService(this.apiKey) {
    // กำหนดให้ใช้ Model เดียวกันทั้งบน Mobile และ Web/PWA โดยตรง
    _model = GenerativeModel(
      model: 'gemini-3.7-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _healthDataSchema,
        temperature: 0.1,
      ),
    );
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("th-TH");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isTtsReady = true;
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  Future<void> speakFeedback(String text) async {
    if (!_isTtsReady || text.isEmpty) return;
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Error in speakFeedback: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
  }

  /// 📍 1. สกัดข้อมูลจากการพูดหรือข้อความ
  Future<Map<String, dynamic>?> processSpeechToHealthData(String speechText) async {
    try {
      final profileContext = await _profileService.getProfilePromptContext();
      final prompt = 'ข้อความ: "$speechText"\nบริบท: $profileContext\nสกัดค่าสุขภาพเป็น JSON';

      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text;

      if (text != null && text.isNotEmpty) {
        String cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error processing speech data: $e');
      return null;
    }
  }

  /// 📍 2. อ่านหน้าจอเครื่องวัดความดัน (LCD OCR) — ทำงานตรงเหมือน .apk 100%
  Future<Map<String, dynamic>?> processLcdImageInput(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final content = [
        Content.multi([
          TextPart('สกัดค่า SYS, DIA, PUL จากภาพเครื่องวัดความดันนี้เป็น JSON ตาม schema ที่กำหนด'),
          DataPart(mimeType, imageBytes),
        ])
      ];

      final response = await _model.generateContent(content);
      final text = response.text;

      if (text != null && text.isNotEmpty) {
        String cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error processing LCD Image: $e');
      return null;
    }
  }

  /// 📍 3. ฟังก์ชันสกัดข้อมูลใบแล็บ (รองรับ Web & Mobile Direct)
  Future<Map<String, dynamic>?> processLabReportImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final visionModel = GenerativeModel(
        model: 'gemini-3.7-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
        ),
      );

      final content = [
        Content.multi([
          TextPart(
            'สกัดค่าตัวเลขผลแล็บจากรูปภาพนี้เป็น JSON (หากไม่มีให้เป็น null):\n'
            '{\n'
            '  "total_cholesterol": number หรือ null,\n'
            '  "hdl": number หรือ null,\n'
            '  "ldl": number หรือ null,\n'
            '  "triglyceride": number หรือ null,\n'
            '  "fasting_blood_sugar": number หรือ null,\n'
            '  "hba1c": number หรือ null,\n'
            '  "creatinine": number หรือ null,\n'
            '  "bun": number หรือ null,\n'
            '  "egfr": number หรือ null,\n'
            '  "sgpt": number หรือ null,\n'
            '  "uric_acid": number หรือ null\n'
            '}',
          ),
          DataPart(mimeType, imageBytes),
        ])
      ];

      final response = await visionModel.generateContent(content);
      final text = response.text;

      if (text != null && text.isNotEmpty) {
        String cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Lab Report OCR Error: $e');
      return null;
    }
  }

  /// 📍 4. ฟังก์ชันสกัดข้อมูลฉลากยา (รองรับ Web & Mobile Direct)
  Future<Map<String, dynamic>?> processDrugLabelImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final visionModel = GenerativeModel(
      model: 'gemini-3.7-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
      ),
    );

    final content = [
      Content.multi([
        TextPart(
            'สกัดข้อมูลฉลากยาเป็น JSON รูปแบบนี้:\n'
            '{"medication_name":"ชื่อยา","dosage_instruction":"วิธีใช้","is_morning_active":true/false,"time_morning":"08:00","is_noon_active":true/false,"time_noon":"12:00","is_evening_active":true/false,"time_evening":"18:00"}\n'
            'หากมื้อไหนไม่ระบุให้เป็น false และ 08:00'),
        DataPart(mimeType, imageBytes),
      ])
    ];

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await visionModel.generateContent(content);
        final text = response.text;

        if (text != null && text.isNotEmpty) {
          String cleanedJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
          return jsonDecode(cleanedJson) as Map<String, dynamic>;
        }
        return null;
      } catch (e) {
        final errStr = e.toString();
        if ((errStr.contains('503') || errStr.contains('UNAVAILABLE') || errStr.contains('429')) && attempt < 2) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        debugPrint('❌ Error processDrugLabelImage: $e');
        return null;
      }
    }
    return null;
  }
}
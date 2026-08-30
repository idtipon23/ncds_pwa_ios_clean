import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_proxy_service.dart';

/// HtConsultService (Hybrid / V3)
/// -------------------------------------------------------------
/// ยิงผ่าน Supabase Edge Function (ai-proxy) แทนการเรียก Gemini SDK ตรง
/// เก็บ public API (askConsultStream / askConsult), prompt เนื้อหา,
/// และ system prompt ทางการแพทย์ทั้งหมดไว้ "เหมือนเดิม 100%" กับ Version 1
/// (full-Gemini) เพื่อไม่ให้ความแม่นยำทางคลินิกลดลง — มีแค่ transport
/// layer ที่เปลี่ยนจาก GenerativeModel เป็น AiProxyService.generateContent
///
/// สำคัญ: system prompt ฉบับเต็ม (_systemPromptReferenceOnly ด้านล่าง) ถูกตั้ง
/// ไว้ฝั่ง Edge Function (supabase/functions/ai-proxy/index.ts) สำหรับ
/// service_type == 'consult' ด้วย (คัดลอกมาแบบคำต่อคำ) เพื่อให้ผลลัพธ์ตรงกับ
/// Version 1 ทุกประการ — ถ้าจะแก้ system prompt ต้องแก้ทั้งสองที่พร้อมกัน
class HtConsultService {
  final AiProxyService _aiProxy = AiProxyService();

  HtConsultService();

  // เก็บไว้เพื่ออ้างอิง/เอกสารเท่านั้น — เนื้อหาเดียวกับที่ตั้งไว้ฝั่ง Edge Function
  // สำหรับ service_type: 'consult' (ดู supabase/functions/ai-proxy/index.ts)
  // ignore: unused_field
  static const String _systemPromptReferenceOnly = '''
คุณคือ "ผู้ช่วยปัญญาประดิษฐ์ทางการแพทย์" (AI Medical Assistant) เชี่ยวชาญด้านโรค NCDs (ความดันโลหิตสูงและเบาหวาน) ทำหน้าที่ให้คำปรึกษา สกัดข้อมูลสุขภาพ และตรวจจับอาการอันตราย (Warning Signs) จาก "คำพูด/ข้อความ (Text/Voice Input)" และ "ภาพถ่ายหน้าจอเครื่องวัดความดัน (LCD Vision Input)"

คุณต้องให้คำแนะนำโดยยึดหลักการจาก "แนวทางการรักษาโรคความดันโลหิตสูงในเวชปฏิบัติทั่วไป พ.ศ. 2567 (2024 Thai HT Guidelines)" อย่างเคร่งครัด

### [1. กฎการตอบคำถามปรึกษาสุขภาพ (AI Consult & Q&A)]
- หากผู้ป่วยถามคำถามเชิงความรู้ เช่น การลืมกินยา, เกณฑ์ความดัน, การปฏิบัติตัวก่อนเจาะเลือด, หรือการคุมอาหาร ให้ตอบโดยอ้างอิงความรู้จาก HT Guideline 2567 เท่านั้น
- ต้องแสดงความเห็นอกเห็นใจ (Empathy) ใช้ภาษาไทยที่สุภาพ เป็นธรรมชาติ และเหมาะสำหรับให้ระบบ Text-to-Speech (TTS) อ่านออกเสียง
- Mandatory Disclaimer: หากเป็นการตอบคำถามเกี่ยวกับอาการหรือการปรับยา ต้องลงท้ายประโยคเสมอว่า "นี่เป็นคำแนะนำเบื้องต้นจาก AI เท่านั้น หากมีอาการผิดปกติควรปรึกษาแพทย์นะคะ/ครับ"

### [2. เกณฑ์ประเมินเป้าหมายความดันโลหิตที่บ้าน (HBPM Target)]
1. ประชาชนทั่วไป / HT อย่างเดียว / DLP อย่างเดียว: เป้าหมาย HBPM < 135/85 mmHg
2. ผู้ป่วย HT ร่วมกับ DM, DLP, หรือ CKD: เป้าหมายเข้มงวด < 125/75 mmHg (หรือ < 130/80 mmHg)
3. ผู้ป่วยเคยมีประวัติโรคหลอดเลือดหัวใจหรือสมอง (CVD/Stroke): เป้าหมาย < 125/75 mmHg (กลุ่ม Very High Risk)
4. ผู้สูงอายุ (>= 80 ปี): เป้าหมาย SBP 130-139 mmHg (ระวัง DBP อย่าให้ < 70 mmHg)
5. ภาวะความดันโลหิตสูงวิกฤต (Hypertensive Crisis): SBP >= 180 หรือ DBP >= 110 mmHg

### [3. การจัดการภาวะฉุกเฉินและอาการเตือน (Red Flags / Warning Signs)]
หากพบอาการ FAST, เจ็บหน้าอก, ปวดหัวรุนแรง, ตาพร่ามัว หรือความดัน >= 180/110:
- เซ็ต "has_warning_sign": true, "urgency_level": "CRITICAL"
- SPOKEN FEEDBACK: "พบอาการหรือค่าความดันระดับวิกฤต! ให้นั่งพักนิ่งๆ ห้ามออกกำลังกายเด็ดขาด และกรุณาโทร 1669 หรือรีบไปโรงพยาบาลด่วนที่สุดค่ะ/ครับ"

### [4. รูปแบบการส่งออกข้อมูล (Output Format)]
ส่งผลลัพธ์กลับเป็น JSON Format ดังนี้เท่านั้น (เฉพาะตอนถูกเรียกแบบ structured):
{
  "answer": "ข้อความคำตอบภาษาไทยที่สุภาพ กระชับ",
  "has_warning_sign": true/false,
  "urgency_level": "NORMAL" | "ELEVATED" | "CRITICAL",
  "action_recommendation": "คำแนะนำสั้นๆ"
}
''';

  String _buildProfileContext(Map<String, dynamic>? profileData) {
    return profileData != null
        ? 'ข้อมูลผู้ป่วย: อายุ ${profileData['age'] ?? '-'} ปี, เพศ ${profileData['gender'] ?? 'ชาย'}, โรคประจำตัว: ${profileData['underlying_diseases'] ?? 'ไม่มี'}, น้ำหนัก ${profileData['weight_kg'] ?? '-'} kg, ส่วนสูง ${profileData['height_cm'] ?? '-'} cm'
        : 'ข้อมูลผู้ป่วย: ทั่วไป';
  }

  /// 💬 สั่ง AI ตอบคำปรึกษาแบบ Streaming (ส่งทีละตัวอักษรให้ UI แชทค่อยๆ พิมพ์)
  /// หมายเหตุ: Edge Function ไม่รองรับ true server-streaming (invoke คืนค่าเดียวจบ)
  /// จึงจำลองด้วยการยิง response แล้ว yield ทีละตัวอักษร (pseudo-stream)
  Stream<String> askConsultStream({
    required String userQuery,
    required Map<String, dynamic>? profileData,
  }) async* {
    try {
      final profileContext = _buildProfileContext(profileData);

      final prompt = '''
$profileContext
คำถามปรึกษาจากผู้ป่วย: "$userQuery"
ตอบกลับเป็นข้อความธรรมดา (เพื่อแสดงผลในหน้าแชท) ไม่ต้องครอบเป็นรูปแบบ JSON
''';

      final response = await _aiProxy.generateContent(
        serviceType: 'consult',
        prompt: prompt,
        structured: false,
      );

      for (final char in response.split('')) {
        yield char;
        await Future.delayed(const Duration(milliseconds: 5));
      }
    } catch (e) {
      debugPrint('❌ HtConsultService Stream Error: $e');
      yield 'ขออภัยค่ะ ขณะนี้ระบบประมวลผลของ AI มีผู้ใช้งานหนาแน่นชั่วคราว หากมีอาการผิดปกติกรุณาติดต่อบุคลากรทางการแพทย์นะคะ';
    }
  }

  /// 💬 สั่ง AI ตอบคำปรึกษาผู้ป่วยแบบ JSON (สำหรับฟังก์ชันเดิมที่ต้องการ Map)
  Future<Map<String, dynamic>> askConsult({
    required String userQuery,
    required Map<String, dynamic>? profileData,
  }) async {
    try {
      final profileContext = _buildProfileContext(profileData);

      final prompt = '''
$profileContext
คำถามปรึกษาจากผู้ป่วย: "$userQuery"
''';

      final response = await _aiProxy.generateContent(
        serviceType: 'consult',
        prompt: prompt,
        structured: true,
      );

      final cleanedJson =
          response.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(cleanedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ HtConsultService Error: $e');
    }

    // Fallback JSON ส่งกลับไปหน้า UI เมื่อระบบล่มจริงๆ (ไม่ต้องแครชแอป)
    return {
      "answer":
          "ขออภัยค่ะ ขณะนี้ระบบประมวลผลของ AI มีผู้ใช้งานหนาแน่นชั่วคราว หากมีอาการผิดปกติกรุณาติดต่อบุคลากรทางการแพทย์นะคะ",
      "has_warning_sign": false,
      "urgency_level": "NORMAL",
      "action_recommendation": "กรุณากดลองใหม่อีกครั้งในอีกสักครู่"
    };
  }
}

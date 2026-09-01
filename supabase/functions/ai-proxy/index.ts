import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ฟังก์ชันสร้าง Hash สำหรับ Cache Key ปลอดภัยตาม PDPA (รวม context_data ป้องกันสลับคนไข้)
async function generateHash(str: string): Promise<string> {
  const msgUint8 = new TextEncoder().encode(str);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgUint8);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ฟังก์ชันหน่วงเวลาพร้อม Jitter กระจาย Traffic
const delayWithJitter = (ms: number) => {
  const jitter = Math.floor(Math.random() * 400) + 100;
  return new Promise((resolve) => setTimeout(resolve, ms + jitter));
};

// System Prompts ทางการแพทย์ตาม Guideline 2567
//
// 📍 สำคัญ: prompt ของ "consult" ด้านล่างนี้คัดลอกมาแบบคำต่อคำจาก
// HtConsultService._systemPromptReferenceOnly ฝั่งแอป (lib/services/ht_consult_service.dart)
// ซึ่งเดิมทีเป็น systemInstruction ที่ยิงตรงกับ Gemini SDK ใน Version 1 (full-Gemini)
// เพื่อให้ผลลัพธ์ทางคลินิก (HBPM targets, red flags, JSON schema) เหมือนกันทุก
// ประการไม่ว่าจะยิงตรงหรือผ่าน Edge Function — ถ้าจะแก้ prompt นี้ ต้องแก้ให้ตรงกับ
// ฝั่งแอปด้วยเสมอ (2 จุดต้องตรงกัน)
function getSystemInstruction(serviceType: string, contextData?: any): string {
  const contextStr = contextData ? `\nข้อมูลบริบทผู้ป่วย: ${JSON.stringify(contextData)}` : "";

  switch (serviceType) {
    case "nutrition":
      // หมายเหตุ: nutrition_service.dart ฝั่งแอปส่ง prompt แบบละเอียดครบ
      // (persona + schema) มาเองอยู่แล้วในทุกครั้งที่เรียก ข้อความนี้เป็นแค่
      // system context เสริมเท่านั้น ไม่ได้ override รายละเอียดที่ client ส่งมา
      return `คุณคือนักโภชนาการผู้เชี่ยวชาญด้านอาหารสำหรับผู้ป่วย NCDs (ความดัน, เบาหวาน, ไต) วิเคราะห์ปริมาณโซเดียม น้ำตาล แคลอรี่ และให้คำแนะนำที่เข้าใจง่ายสำหรับผู้สูงอายุ หากผู้ใช้ขอรูปแบบ JSON ให้ตอบเฉพาะ JSON ที่ถูกต้องเท่านั้น${contextStr}`;

    case "vitals":
      return `คุณคือผู้ช่วยทางการแพทย์สำหรับสกัดข้อมูลสัญญาณชีพ (ความดันตัวบน/ล่าง, ชีพจร, ค่าน้ำตาล) จากข้อความหรือเสียงพูดของผู้สูงอายุ ให้ตอบกลับในรูปแบบ JSON โครงสร้าง: {"sys": 120, "dia": 80, "pul": 75, "sugar_level": null, "has_warning_sign": false, "urgency_level": "NORMAL", "feedback_message": "..."}${contextStr}`;

    case "lab":
      return `คุณคือ AI สำหรับอ่านผลตรวจทางห้องปฏิบัติการใบแล็บ ความรับผิดชอบคือสกัดค่าเฉพาะตัวเลขที่ชัดเจนจากภาพใบแล็บและตอบกลับเป็น JSON เท่านั้น โดยต้องใช้คีย์ภาษาอังกฤษตามชื่อฟิลด์ที่กำหนด: { "total_cholesterol": number หรือ null, "hdl": number หรือ null, "ldl": number หรือ null, "fasting_blood_sugar": number หรือ null, "creatinine": number หรือ null } ถ้าตัวเลขไม่ชัดเจน ให้ใส่ null ไม่ใช่ค่าเดา${contextStr}`;

    case "consult":
    default:
      return `คุณคือ "ผู้ช่วยปัญญาประดิษฐ์ทางการแพทย์" (AI Medical Assistant) เชี่ยวชาญด้านโรค NCDs (ความดันโลหิตสูงและเบาหวาน) ทำหน้าที่ให้คำปรึกษา สกัดข้อมูลสุขภาพ และตรวจจับอาการอันตราย (Warning Signs) จาก "คำพูด/ข้อความ (Text/Voice Input)" และ "ภาพถ่ายหน้าจอเครื่องวัดความดัน (LCD Vision Input)"

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
ถ้าถูกขอให้ตอบเป็น JSON ให้ส่งผลลัพธ์กลับเป็น JSON Format ดังนี้เท่านั้น:
{
  "answer": "ข้อความคำตอบภาษาไทยที่สุภาพ กระชับ",
  "has_warning_sign": true/false,
  "urgency_level": "NORMAL" | "ELEVATED" | "CRITICAL",
  "action_recommendation": "คำแนะนำสั้นๆ"
}
ถ้าผู้เรียกขอคำตอบเป็นข้อความธรรมดา (ไม่ครอบ JSON) ให้ตอบเป็นข้อความธรรมดาตามที่ขอแทน${contextStr}`;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // 0. ตรวจสอบสิทธิ์ (Authentication Check) ป้องกันการยิง API ข้ามระบบสาธารณะ
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    // ยืนยันตัวตน User ผ่าน Token ให้ถูกต้องตามหลักความปลอดภัย
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized access: Invalid or expired token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { service_type = "consult", prompt = "", structured = false, context_data, file_data } = await req.json();
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) throw new Error("GEMINI_API_KEY environment variable is missing");

    // 1. ตรวจสอบ Caching (รวม context_data เข้าใน Hash Key เพื่อป้องกันคำตอบสลับคนไข้)
    const isCacheable = (service_type === "consult" || service_type === "nutrition") && !file_data;
    let cacheKey = "";

    if (isCacheable && prompt) {
      const contextString = context_data ? JSON.stringify(context_data) : "";
      cacheKey = await generateHash(`${service_type}_${prompt.trim().toLowerCase()}_${contextString}`);
      
      const { data: cached, error: cacheError } = await supabaseClient
        .from("ai_query_cache")
        .select("response_payload, created_at")
        .eq("cache_key", cacheKey)
        .maybeSingle();

      if (cached && !cacheError) {
        const cacheAgeHours = (Date.now() - new Date(cached.created_at).getTime()) / (1000 * 60 * 60);
        if (cacheAgeHours < 1) {
          return new Response(
            JSON.stringify({ ...cached.response_payload, source: "cache" }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }
    }

    // 2. เตรียม Payload ส่งหา Gemini
    const parts: any[] = [];
    if (prompt) parts.push({ text: prompt });
    
    if (file_data?.mime_type && file_data?.data) {
      parts.push({
        inlineData: {
          mimeType: file_data.mime_type,
          data: file_data.data,
        },
      });
    }

    const systemInstructionText = getSystemInstruction(service_type, context_data);
    
    // ใช้โมเดลตามที่คุณกำหนดโดยเฉพาะ (ห้ามเปลี่ยน)
    const models = ["gemini-3.5-flash-lite", "gemini-3.7-flash"];
    let resultPayload = null;
    let lastError: any = null;

    // 3. Retry Loop + Fallback Model
    for (const model of models) {
      let attempts = 0;
      const maxAttemptsPerModel = 2;

      while (attempts < maxAttemptsPerModel) {
        attempts++;
        try {
          const response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
            {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                contents: [{ parts }],
                systemInstruction: { parts: [{ text: systemInstructionText }] },
                generationConfig: structured ? { responseMimeType: "application/json" } : undefined,
              }),
            }
          );

          if (response.ok) {
            const data = await response.json();
            const responseText = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
            
            resultPayload = {
              text: responseText,
              model_used: model,
              source: "gemini",
            };
            break;
          }

          const status = response.status;
          const errorBody = await response.text();
          console.warn(`[Gemini Error] Model: ${model} | Status: ${status} | Body: ${errorBody}`);

          if (status === 429) {
            await delayWithJitter(attempts * 1500);
          } else if (status >= 500) {
            await delayWithJitter(1000);
          } else {
            throw new Error(`API Client Error: [${status}] ${errorBody}`);
          }
        } catch (err) {
          lastError = err;
          await delayWithJitter(800);
        }
      }

      if (resultPayload) break;
    }

    if (!resultPayload) {
      throw lastError || new Error("ระบบ AI ไม่สามารถตอบสนองได้ กรุณาลองใหม่อีกครั้ง");
    }

    // 4. บันทึก Cache (ตรวจสอบและยกเว้นเคสฉุกเฉิน/วิกฤตเพื่อความปลอดภัยผู้ป่วย)
    if (isCacheable && cacheKey) {
      const text = resultPayload.text || "";
      
      // ตรวจสอบแบบเข้มงวดทั้ง Structured หรือ String-matching เพื่อป้องกันการ Cache เคสวิกฤต
      let isEmergency = text.includes("CRITICAL") || text.includes("วิกฤต") || text.includes("1669");
      try {
        const parsedJson = JSON.parse(text);
        if (parsedJson.urgency_level === "CRITICAL" || parsedJson.has_warning_sign === true) {
          isEmergency = true;
        }
      } catch (_) {
        // หากไม่ใช่ JSON ให้ใช้การตรวจสอบข้อความปกติ
      }

      if (!isEmergency) {
        await supabaseClient.from("ai_query_cache").upsert(
          {
            cache_key: cacheKey,
            service_type: service_type,
            response_payload: resultPayload,
            created_at: new Date().toISOString(),
          },
          { onConflict: "cache_key" }
        );
      }
    }

    return new Response(JSON.stringify(resultPayload), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error: any) {
    console.error("[Fatal Function Error]:", error.message);
    return new Response(
      JSON.stringify({ 
        error: error.message || "เกิดข้อผิดพลาดภายในระบบ",
        fallback_ui_message: "ขณะนี้ระบบ AI มีผู้ใช้งานหนาแน่น กรุณาลองใหม่อีกครั้งในครู่ครับ"
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
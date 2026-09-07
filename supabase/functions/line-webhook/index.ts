import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LINE_CHANNEL_ACCESS_TOKEN = Deno.env.get("LINE_CHANNEL_ACCESS_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

serve(async (req) => {
  // 1. รองรับ CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { 
      headers: { 
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization"
      } 
    });
  }

  try {
    const body = await req.json();
    const events = body.events ?? [];

    for (const event of events) {
      if (event.type === "message" && event.message?.type === "text") {
        const replyToken = event.replyToken;
        const lineUserId = event.source?.userId;
        
        // สกัดเฉพาะตัวเลข (รองรับทั้ง 123456 และ 123-456)
        const textMessage = event.message.text.trim().replace(/[^0-9]/g, "");

        // 2. ตรวจสอบเมื่อได้รับรหัสตัวเลข 6 หลัก
        if (/^\d{6}$/.test(textMessage) && lineUserId) {
          const nowIso = new Date().toISOString();

          // ค้นหาคนไข้ที่ถือรหัสนี้และรหัสยังไม่หมดอายุ
          const { data: patient, error: findError } = await supabase
            .from("patients")
            .select("id, first_name, line_recipient_role")
            .eq("line_pairing_code", textMessage)
            .gte("line_pairing_expires_at", nowIso)
            .maybeSingle();

          if (findError) {
            console.error("DB Query Error:", findError);
            await replyLine(
              replyToken,
              "⚠️ ระบบฐานข้อมูลขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้งในภายหลังค่ะ"
            );
            continue;
          }

          if (!patient) {
            await replyLine(
              replyToken,
              "❌ รหัสเชื่อมต่อไม่ถูกต้อง หรือหมดอายุแล้ว (อายุรหัส 10 นาที)\n\nกรุณากดเปิดเมนู 'ข้อมูลของฉัน' ในแอปเพื่อขอรับรหัส 6 หลักใหม่อีกครั้งค่ะ 🌱"
            );
            continue;
          }

          // 3. ผูก line_user_id สำเร็จ แล้วล้างรหัส pairing ทิ้งทันที
          const { error: updateError } = await supabase
            .from("patients")
            .update({
              line_user_id: lineUserId,
              line_linked_at: nowIso,
              line_pairing_code: null, // เคลียร์รหัสทิ้งป้องกันนำมาใช้ซ้ำ
            })
            .eq("id", patient.id);

          if (updateError) {
            console.error("Update Error:", updateError);
            await replyLine(
              replyToken,
              "⚠️ ไม่สามารถบันทึกการเชื่อมต่อได้ กรุณาลองใหม่อีกครั้งค่ะ"
            );
            continue;
          }

          const roleText = patient.line_recipient_role === "caregiver" ? "ญาติ/ผู้ดูแล" : "คนไข้";
          await replyLine(
            replyToken,
            `✅ เชื่อมต่อระบบแจ้งเตือน NCDs สำเร็จ!\n\nผู้รับแจ้งเตือน: ${roleText}\nคนไข้: คุณ${patient.first_name || "ผู้รับบริการ"}\n\nระบบจะเริ่มส่งข้อความเตือนเวลากินยาและตรวจวัดความดันผ่านช่องทางนี้ค่ะ 🌱`
          );
        } else {
          // ข้อความทั่วไป
          await replyLine(
            replyToken,
            "สวัสดีค่ะ หากต้องการเชื่อมต่อระบบแจ้งเตือน กรุณาพิมพ์รหัส 6 หลักที่ได้รับจากหน้าแอป NCDs ส่งเข้ามาในช่องแชทนี้ได้เลยนะคะ 😊"
          );
        }
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: any) {
    console.error("Webhook Handler Error:", err.message);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});

async function replyLine(replyToken: string, text: string) {
  if (!replyToken || !LINE_CHANNEL_ACCESS_TOKEN) return;
  try {
    await fetch("https://api.line.me/v2/bot/message/reply", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${LINE_CHANNEL_ACCESS_TOKEN}`,
      },
      body: JSON.stringify({
        replyToken: replyToken,
        messages: [{ type: "text", text: text }],
      }),
    });
  } catch (e) {
    console.error("LINE reply fetch error:", e);
  }
}
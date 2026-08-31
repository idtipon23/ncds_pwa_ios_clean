import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LINE_CHANNEL_ACCESS_TOKEN = Deno.env.get("LINE_CHANNEL_ACCESS_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

serve(async (req) => {
  // รองรับ CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*" } });
  }

  try {
    const body = await req.json();
    const events = body.events ?? [];

    for (const event of events) {
      if (event.type === "message" && event.message?.type === "text") {
        const replyToken = event.replyToken;
        const lineUserId = event.source?.userId;
        const textMessage = event.message.text.trim().replace(/[-\s]/g, "");

        // ตรวจสอบรหัส 6 หลัก
        if (/^\d{6}$/.test(textMessage) && lineUserId) {
          const nowIso = new Date().toISOString();

          // ค้นหาคนไข้ที่รหัสตรงกัน
          const { data: patient, error: findError } = await supabase
            .from("patients")
            .select("id, first_name, line_recipient_role")
            .eq("line_pairing_code", textMessage)
            .gte("line_pairing_expires_at", nowIso)
            .maybeSingle();

          if (findError || !patient) {
            await replyLine(
              replyToken,
              "❌ รหัสเชื่อมต่อไม่ถูกต้อง หรือหมดอายุแล้ว\n\nกรุณาเปิดหน้าแอป PWA เพื่อสร้างรหัส 6 หลักใหม่อีกครั้งค่ะ"
            );
            continue;
          }

          // บันทึก line_user_id ผูกกับบัญชีคนไข้
          await supabase
            .from("patients")
            .update({
              line_user_id: lineUserId,
              line_linked_at: nowIso,
              line_pairing_code: null,
            })
            .eq("id", patient.id);

          const roleText = patient.line_recipient_role === "caregiver" ? "ญาติ/ผู้ดูแล" : "คนไข้";
          await replyLine(
            replyToken,
            `✅ เชื่อมต่อระบบแจ้งเตือน NCDs สำเร็จ!\n\nผู้รับแจ้งเตือน: ${roleText}\nคนไข้: คุณ${patient.first_name || "ผู้รับบริการ"}\n\nระบบจะเริ่มส่งข้อความเตือนเวลากินยาและตรวจวัดความดันผ่านช่องทางนี้ค่ะ 🌱`
          );
        } else {
          await replyLine(
            replyToken,
            "สวัสดีค่ะ กรุณาระบุรหัสเชื่อมต่อ 6 หลักที่ได้จากหน้าแอป NCDs PWA เพื่อเปิดรับการแจ้งเตือนนะคะ 😊"
          );
        }
      }
    }

    // ส่งคืน HTTP 200 OK กลับไปให้ LINE Platform เสมอ (รวมถึงตอนกดปุ่ม Verify)
    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: any) {
    console.error("Webhook Error:", err.message);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});

async function replyLine(replyToken: string, text: string) {
  if (!replyToken || !LINE_CHANNEL_ACCESS_TOKEN) return;
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
}
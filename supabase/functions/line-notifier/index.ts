import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const LINE_CHANNEL_ACCESS_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

// 🕒 ฟังก์ชันคำนวณจุดเริ่มต้นของวันปัจจุบันตามเวลาประเทศไทย (Asia/Bangkok UTC+7)
function getBangkokStartOfDayUtc(): string {
  const now = new Date()
  // ดึงวันที่ปัจจุบันตามโซนเวลาประเทศไทย (YYYY-MM-DD)
  const bkkDateStr = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now)

  // แปลงเวลา 00:00:00 น. ของไทย ให้เป็น ISO String (UTC) สำหรับค้นหาในฐานข้อมูล
  return new Date(`${bkkDateStr}T00:00:00+07:00`).toISOString()
}

serve(async (req) => {
  try {
    const { action, mealType } = await req.json()

    if (action === 'check_medications') {
      await sendMedicationReminders(mealType)
    } else if (action === 'check_bp_inactivity') {
      await sendBpInactivityAlerts()
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    })
  }
})

// 💊 1. ระบบตรวจเช็กและแจ้งเตือนมื้อยาตามเวลาไทย
async function sendMedicationReminders(mealType: string) {
  const activeCol = `is_${mealType}_active`
  const startOfDayUtc = getBangkokStartOfDayUtc()

  const { data: meds, error } = await supabase
    .from('medication_logs')
    .select(`
      id,
      medication_name,
      dosage_instruction,
      patient_id,
      patients!inner ( id, line_user_id, first_name, line_recipient_role )
    `)
    .eq(activeCol, true)
    .not('patients.line_user_id', 'is', null)

  if (error || !meds) return

  for (const med of meds) {
    const patient = med.patients as any
    const lineUserId = patient.line_user_id

    // ตรวจสอบว่าในวันนี้ (นับตั้งแต่ 00:00 น. เวลาไทย) มีการกดยืนยันกินยาไปแล้วหรือยัง
    const { data: adherence } = await supabase
      .from('medication_adherence_logs')
      .select('id')
      .eq('patient_id', med.patient_id)
      .eq('medication_id', med.id)
      .gte('taken_at', startOfDayUtc)
      .maybeSingle()

    if (!adherence && lineUserId) {
      const mealLabel = mealType === 'morning' ? 'มื้อเช้า' : mealType === 'noon' ? 'มื้อกลางวัน' : 'มื้อเย็น'
      const isCaregiver = patient.line_recipient_role === 'caregiver'
      
      const message = isCaregiver
        ? `💊 [แจ้งเตือนผู้ดูแล] ถึงเวลาทานยา (${mealLabel})\n\nสวัสดีค่ะ กรุณาดูแลคุณ ${patient.first_name}\nทานยา: ${med.medication_name}\nวิธีใช้: ${med.dosage_instruction || 'ตามแพทย์สั่ง'}\n\nเปิดแอป NCDs เพื่อบันทึกการทานยานะคะ 😊`
        : `💊 ได้เวลาทานยา (${mealLabel}) แล้วค่ะ\n\nสวัสดีค่ะ คุณ ${patient.first_name}\nอย่าลืมทานยา: ${med.medication_name}\nวิธีใช้: ${med.dosage_instruction || 'ตามแพทย์สั่ง'}\n\nเปิดแอป NCDs เพื่อกดบันทึกการทานยานะคะ 😊`

      await pushLineMessage(lineUserId, message)
    }
  }
}

// 🩺 2. ระบบตรวจเช็กความดันที่ไม่ได้วัดเกิน 24 ชั่วโมง
async function sendBpInactivityAlerts() {
  const cutoffTime = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

  const { data: patients, error } = await supabase
    .from('patients')
    .select('id, first_name, line_user_id, line_recipient_role')
    .eq('notify_bp_inactive', true)
    .not('line_user_id', 'is', null)

  if (error || !patients) return

  for (const patient of patients) {
    const { data: latestVital } = await supabase
      .from('vital_signs')
      .select('recorded_at')
      .eq('patient_id', patient.id)
      .order('recorded_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    const lastRecordedAt = latestVital?.recorded_at

    if (!lastRecordedAt || lastRecordedAt < cutoffTime) {
      const isCaregiver = patient.line_recipient_role === 'caregiver'
      const message = isCaregiver
        ? `🩺 [แจ้งเตือนผู้ดูแล] แจ้งเตือนการวัดความดัน\n\nสวัสดีค่ะ คุณ ${patient.first_name} ยังไม่ได้บันทึกค่าความดันใน 24 ชม. ที่ผ่านมา\n\nกรุณาช่วยวัดและบันทึกผลลงระบบเพื่อติดตามสุขภาพนะคะ 🌱`
        : `🩺 แจ้งเตือนการตรวจวัดความดัน\n\nสวัสดีค่ะ คุณ ${patient.first_name}\nคุณยังไม่ได้บันทึกค่าความดันโลหิตใน 24 ชั่วโมงที่ผ่านมา\n\nเพื่อการติดตามสุขภาพที่ต่อเนื่อง กรุณานั่งพัก 5 นาทีแล้ววัดความดันพร้อมบันทึกลงระบบนะคะ 🌱`

      await pushLineMessage(patient.line_user_id, message)
    }
  }
}

async function pushLineMessage(to: string, text: string) {
  await fetch('https://api.line.me/v2/bot/message/push', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LINE_CHANNEL_ACCESS_TOKEN}`,
    },
    body: JSON.stringify({
      to: to,
      messages: [{ type: 'text', text: text }],
    }),
  })
}
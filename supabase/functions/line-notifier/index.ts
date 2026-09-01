import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const LINE_CHANNEL_ACCESS_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

serve(async (req) => {
  try {
    const { action, mealType } = await req.json().catch(() => ({ action: 'check_dynamic' }))
    console.log(`[Trigger Received]: Action = ${action}`)

    let result: any = null

    if (action === 'check_dynamic' || action === 'check_medications') {
      result = await checkDynamicMedications()
    } else if (action === 'check_bp_inactivity') {
      result = await sendBpInactivityAlerts()
    }

    return new Response(JSON.stringify({ success: true, details: result }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error: any) {
    console.error("[Fatal Error]:", error.message)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    })
  }
})

// 🕒 ระบบตรวจเช็กมื้อยาตามเวลาอิสระระดับนาที (Bangkok Time)
async function checkDynamicMedications() {
  const now = new Date()

  // 1. ดึงเวลาและวันที่ปัจจุบันของไทย (HH:mm และ YYYY-MM-DD)
  const timeFormatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Bangkok',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
  const dateFormatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })

  const currentBkkTime = timeFormatter.format(now) // เช่น "08:31"
  const currentBkkDate = dateFormatter.format(now) // เช่น "2026-09-01"

  console.log(`[Dynamic Check] Current BKK Time: ${currentBkkTime} | Date: ${currentBkkDate}`)

  // 2. ดึงรายการยาทั้งหมดที่ผู้ป่วยเชื่อม LINE ไว้
  const { data: meds, error } = await supabase
    .from('medication_logs')
    .select(`
      id,
      medication_name,
      dosage_instruction,
      patient_id,
      is_morning_active,
      time_morning,
      is_noon_active,
      time_noon,
      is_evening_active,
      time_evening,
      patients!inner ( id, line_user_id, first_name, line_recipient_role )
    `)
    .not('patients.line_user_id', 'is', null)

  if (error) {
    console.error("[Database Error]:", error.message)
    return { error: error.message }
  }

  let matchedAndSent = 0

  for (const med of meds || []) {
    const patient = med.patients as any
    const lineUserId = patient.line_user_id

    // ตรวจสอบทั้ง 3 มื้อ ว่ามื้อไหนตรงกับเวลาปัจจุบัน (currentBkkTime)
    const activeMealsToAlert: { mealType: string; label: string }[] = []

    if (med.is_morning_active && med.time_morning === currentBkkTime) {
      activeMealsToAlert.push({ mealType: 'morning', label: 'มื้อเช้า' })
    }
    if (med.is_noon_active && med.time_noon === currentBkkTime) {
      activeMealsToAlert.push({ mealType: 'noon', label: 'มื้อกลางวัน' })
    }
    if (med.is_evening_active && med.time_evening === currentBkkTime) {
      activeMealsToAlert.push({ mealType: 'evening', label: 'มื้อเย็น' })
    }

    for (const meal of activeMealsToAlert) {
      // 3. ตรวจสอบว่าเคยกดทานมื้อนี้ไปแล้วในวันนี้หรือไม่
      const { data: adherence } = await supabase
        .from('medication_adherence_logs')
        .select('id')
        .eq('patient_id', med.patient_id)
        .eq('medication_id', med.id)
        .eq('meal_type', meal.mealType)
        .eq('taken_date', currentBkkDate)
        .maybeSingle()

      if (adherence) {
        console.log(`[Skipped] ${patient.first_name} already took ${med.medication_name} (${meal.label}) today.`)
        continue
      }

      // 4. ส่งข้อความเข้า LINE
      const isCaregiver = patient.line_recipient_role === 'caregiver'
      const message = isCaregiver
        ? `💊 [แจ้งเตือนผู้ดูแล] ได้เวลาทานยา (${meal.label}) เวลา ${currentBkkTime} น.\n\nกรุณาช่วยดูแลคุณ ${patient.first_name || 'ผู้รับบริการ'}\nทานยา: ${med.medication_name}\nวิธีใช้: ${med.dosage_instruction || 'ตามแพทย์สั่ง'}\n\nเปิดแอป NCDs เพื่อบันทึกการทานยานะคะ 🌱`
        : `💊 ได้เวลาทานยา (${meal.label}) เวลา ${currentBkkTime} น. แล้วค่ะ\n\nสวัสดีค่ะ คุณ ${patient.first_name || 'ผู้รับบริการ'}\nอย่าลืมทานยา: ${med.medication_name}\nวิธีใช้: ${med.dosage_instruction || 'ตามแพทย์สั่ง'}\n\nเปิดแอป NCDs เพื่อกดบันทึกการทานยานะคะ 🌱`

      console.log(`[Sending LINE] -> ${patient.first_name} (${lineUserId}) for ${med.medication_name}`)
      await pushLineMessage(lineUserId, message)
      matchedAndSent++
    }
  }

  return { checked_time: currentBkkTime, messages_sent: matchedAndSent }
}

// 🩺 ตรวจสอบความดันค้างเกิน 24 ชม.
async function sendBpInactivityAlerts() {
  const cutoffTime = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

  const { data: patients, error } = await supabase
    .from('patients')
    .select('id, first_name, line_user_id, line_recipient_role')
    .eq('notify_bp_inactive', true)
    .not('line_user_id', 'is', null)

  if (error || !patients) return { error: error?.message }

  let sentCount = 0
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
        ? `🩺 [แจ้งเตือนผู้ดูแล] แจ้งเตือนการวัดความดัน\n\nคุณ ${patient.first_name || 'ผู้รับบริการ'} ยังไม่ได้บันทึกค่าความดันใน 24 ชม. ที่ผ่านมา\n\nกรุณาช่วยตรวจวัดและบันทึกลงระบบนะคะ 🌱`
        : `🩺 แจ้งเตือนการตรวจวัดความดัน\n\nสวัสดีค่ะ คุณ ${patient.first_name || 'ผู้รับบริการ'}\nคุณยังไม่ได้บันทึกค่าความดันโลหิตใน 24 ชั่วโมงที่ผ่านมา\n\nกรุณานั่งพัก 5 นาทีแล้ววัดความดันพร้อมบันทึกลงระบบนะคะ 🌱`

      await pushLineMessage(patient.line_user_id, message)
      sentCount++
    }
  }

  return { inactive_patients_alerted: sentCount }
}

async function pushLineMessage(to: string, text: string) {
  if (!LINE_CHANNEL_ACCESS_TOKEN) return { error: "Missing Token" }

  const res = await fetch('https://api.line.me/v2/bot/message/push', {
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

  return { status: res.status, body: await res.text() }
}
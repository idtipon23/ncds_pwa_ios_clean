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
    } else if (action === 'check_appointments') {
      result = await sendAppointmentReminders()
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

// 🕒 1. ระบบตรวจเช็กมื้อยาตามเวลาอิสระระดับนาที (Bangkok Time)
async function checkDynamicMedications() {
  const now = new Date()

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

  const currentBkkTime = timeFormatter.format(now)
  const currentBkkDate = dateFormatter.format(now)

  console.log(`[Dynamic Check] Current BKK Time: ${currentBkkTime} | Date: ${currentBkkDate}`)

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

// 🩺 2. ระบบตรวจเช็กความดันค้างเกิน 24 ชม.
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

// 📅 3. ระบบตรวจเช็กและแจ้งเตือนวันนัดหมาย (ล่วงหน้า 3 วัน และ 1 วัน)
async function sendAppointmentReminders() {
  const now = new Date()
  const dateFormatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })

  const todayStr = dateFormatter.format(now)
  const today = new Date(`${todayStr}T00:00:00+07:00`)

  // วันพรุ่งนี้ (+1 วัน)
  const in1Day = new Date(today)
  in1Day.setDate(today.getDate() + 1)
  const dateIn1Day = dateFormatter.format(in1Day)

  // อีก 3 วัน (+3 วัน)
  const in3Days = new Date(today)
  in3Days.setDate(today.getDate() + 3)
  const dateIn3Days = dateFormatter.format(in3Days)

  console.log(`[Appointment Check] Today: ${todayStr} | In 1 Day: ${dateIn1Day} | In 3 Days: ${dateIn3Days}`)

  let sentCount = 0

  // --- แจ้งเตือนล่วงหน้า 3 วัน ---
  const { data: appts3Days, error: err3 } = await supabase
    .from('appointments')
    .select(`
      id, appointment_date, appointment_time, clinic_name, doctor_name, reason, need_fasting,
      patients!inner ( id, line_user_id, first_name, line_recipient_role )
    `)
    .eq('appointment_date', dateIn3Days)
    .eq('status', 'scheduled')
    .eq('is_notified_3days', false)
    .not('patients.line_user_id', 'is', null)

  if (err3) console.error('[Appt 3-Day Error]:', err3.message)

  for (const appt of appts3Days || []) {
    const patient = appt.patients as any
    const isCaregiver = patient.line_recipient_role === 'caregiver'
    const fastingNote = appt.need_fasting ? '\n⚠️ หมายเหตุ: มีเจาะเลือด ต้องงดน้ำและอาหารล่วงหน้า 8-10 ชม.' : ''
    
    const message = isCaregiver
      ? `📅 [แจ้งเตือนผู้ดูแล] คุณ ${patient.first_name || 'ผู้รับบริการ'} มีนัดตรวจในอีก 3 วัน\n\n🗓️ วันที่: ${appt.appointment_date}\n⏰ เวลา: ${appt.appointment_time || '09:00'} น.\n🏥 สถานที่: ${appt.clinic_name || 'คลินิก NCDs'}\n📋 สาเหตุที่นัด: ${appt.reason || 'ตรวจติดตามอาการ'}${fastingNote}\n\nกรุณาช่วยเตรียมความพร้อมและบัตรประชาชนนะคะ 🌱`
      : `📅 แจ้งเตือนวันนัดหมาย (อีก 3 วัน)\n\nสวัสดีค่ะ คุณ ${patient.first_name || 'ผู้รับบริการ'}\nท่านมีนัดตรวจที่: ${appt.clinic_name || 'คลินิก NCDs'}\n🗓️ วันที่: ${appt.appointment_date}\n⏰ เวลา: ${appt.appointment_time || '09:00'} น.\n📋 นัดเพื่อ: ${appt.reason || 'ตรวจติดตามอาการ'}${fastingNote}\n\nอย่าลืมเตรียมตัวให้พร้อมนะคะ 😊`

    console.log(`[Sending 3-Day Appt LINE] -> ${patient.first_name} (${patient.line_user_id})`)
    await pushLineMessage(patient.line_user_id, message)
    await supabase.from('appointments').update({ is_notified_3days: true }).eq('id', appt.id)
    sentCount++
  }

  // --- แจ้งเตือนล่วงหน้า 1 วัน (วันพรุ่งนี้) ---
  const { data: appts1Day, error: err1 } = await supabase
    .from('appointments')
    .select(`
      id, appointment_date, appointment_time, clinic_name, doctor_name, reason, need_fasting,
      patients!inner ( id, line_user_id, first_name, line_recipient_role )
    `)
    .eq('appointment_date', dateIn1Day)
    .eq('status', 'scheduled')
    .eq('is_notified_1day', false)
    .not('patients.line_user_id', 'is', null)

  if (err1) console.error('[Appt 1-Day Error]:', err1.message)

  for (const appt of appts1Day || []) {
    const patient = appt.patients as any
    const isCaregiver = patient.line_recipient_role === 'caregiver'
    const fastingNote = appt.need_fasting ? '\n🚨 คำเตือนสำคัญ: คืนนี้ต้องงดน้ำและอาหารหลัง 20:00 น. (จิบน้ำเปล่าได้เล็กน้อย) เพื่อเจาะเลือดในวันพรุ่งนี้ค่ะ' : ''
    
    const message = isCaregiver
      ? `🚨 [แจ้งเตือนผู้ดูแล] พรุ่งนี้คุณ ${patient.first_name || 'ผู้รับบริการ'} มีนัดพบแพทย์!\n\n🗓️ วันที่: ${appt.appointment_date}\n⏰ เวลา: ${appt.appointment_time || '09:00'} น.\n🏥 สถานที่: ${appt.clinic_name || 'คลินิก NCDs'}\n📋 เพื่อ: ${appt.reason || 'ตรวจติดตามอาการ'}${fastingNote}\n\nกรุณาพายาเดิมทั้งหมดไปด้วยนะคะ 🌱`
      : `🚨 เตือนความจำ: พรุ่งนี้มีนัดพบแพทย์!\n\nสวัสดีค่ะ คุณ ${patient.first_name || 'ผู้รับบริการ'}\n🗓️ วันที่: ${appt.appointment_date}\n⏰ เวลา: ${appt.appointment_time || '09:00'} น.\n🏥 ${appt.clinic_name || 'คลินิก NCDs'}${fastingNote}\n\nกรุณานำสมุดประจำตัวและยาเดิมทั้งหมดมาด้วยนะคะ 😊`

    console.log(`[Sending 1-Day Appt LINE] -> ${patient.first_name} (${patient.line_user_id})`)
    await pushLineMessage(patient.line_user_id, message)
    await supabase.from('appointments').update({ is_notified_1day: true }).eq('id', appt.id)
    sentCount++
  }

  return { checked_date: todayStr, appointments_alerted: sentCount }
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
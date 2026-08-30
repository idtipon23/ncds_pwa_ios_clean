#!/bin/bash
set -e

# 1. ติดตั้ง Flutter SDK (ถ้ายังไม่มี)
if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi

# 2. ตั้งค่า Path ให้เรียกใช้ flutter
export PATH="$PATH:$(pwd)/_flutter/bin"

# 3. เตรียมไฟล์ .env สำหรับคีย์ระบบ
echo "SUPABASE_URL=$SUPABASE_URL" > .env
echo "SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" >> .env

# 4. ดาวน์โหลด Dependencies และคอมไพล์เป็น Web Release
flutter config --no-analytics
flutter pub get
flutter build web --release
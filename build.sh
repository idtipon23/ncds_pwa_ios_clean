#!/bin/bash
set -e

# 1. ติดตั้ง Flutter SDK
if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi

export PATH="$PATH:$(pwd)/_flutter/bin"

# 2. เตรียม Environment Variables
echo "SUPABASE_URL=$SUPABASE_URL" > .env
echo "SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" >> .env
echo "GEMINI_API_KEY=$GEMINI_API_KEY" >> .env

# 3. สั่ง Build สำหรับ Web PWA
flutter config --no-analytics
flutter pub get
flutter build web --release --no-tree-shake-icons
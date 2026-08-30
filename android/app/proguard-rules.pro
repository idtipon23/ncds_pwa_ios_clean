# 1. รักษา Metadata (Signature) ไว้ไม่ให้ถูกลบ (บรรทัดนี้คือหัวใจสำคัญที่แก้ Missing type parameter)
-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*
-keepattributes EnclosingMethod

# 2. ป้องกันไม่ให้ R8 ยุ่งกับคลาสของ Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# 3. เผื่อกรณีปลั๊กอินใช้ Gson หรือตัวแปลงข้อมูลอื่นๆ ภายใน
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
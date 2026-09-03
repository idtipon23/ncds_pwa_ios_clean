# แก้บั๊ก: "Unsupported operation: _Namespace" ตอนอ่านภาพ LCD/ฉลากยา

## สาเหตุ
`dart:io File` ใช้งานบน Flutter Web ไม่ได้ การเรียก `File(path)` บนเว็บจะโยน
`Unsupported operation: _Namespace` ทันที โค้ดเดิมสร้าง `File(pickedFile.path)`
ตั้งแต่ตอนเลือกรูป ก่อนจะส่งต่อไปให้ AI ประมวลผลด้วยซ้ำ

## ไฟล์ที่แก้ (เปลี่ยนจาก File → Uint8List ทั้งเชน)
1. lib/widgets/image_input_field.dart
   - เลือกรูปแล้วอ่านเป็น Uint8List ทันที (readAsBytes) แทนการห่อด้วย File
   - Image.file → Image.memory
   - callback เปลี่ยนจาก Function(File) เป็น Function(Uint8List bytes, String fileName)

2. lib/services/voice_health_service.dart
   - processLcdImageInput(File) → processLcdImageInput(Uint8List, {mimeType})
   - processDrugLabelImage(File) → processDrugLabelImage(Uint8List, {mimeType})
   - เอา import 'dart:io' ออก เพิ่ม import 'dart:typed_data'

3. lib/screens/vital_sign_record_screen.dart
   - _imageFile (File?) → _imageBytes (Uint8List?) + _imageMimeType
   - _processImage(File) → _processImage(Uint8List, String fileName)

4. lib/widgets/save_confirmation_dialog.dart
   - imageFile (File?) → imageBytes (Uint8List?)

5. lib/services/patient_database_service.dart
   - uploadHealthImage(File, ...) → uploadHealthImage(Uint8List, ..., {mimeType})
   - _compressImage(File) ใช้ path_provider (พังบนเว็บ) → _compressImageBytes(Uint8List)
     ใช้ FlutterImageCompress.compressWithList (รองรับเว็บ)
   - storage.upload(File) → storage.uploadBinary(Uint8List)
   - เอา import path_provider ออก (ไม่ได้ใช้แล้ว)

6. lib/screens/medication_history_screen.dart
   - จุดสแกนฉลากยา (_scanMedication) มีบั๊กแบบเดียวกัน แก้ให้อ่าน
     XFile.readAsBytes() ตรงๆ แทนการสร้าง File(photo.path)

## หมายเหตุ (ยังไม่ได้แตะ เพราะเป็นโค้ดที่ไม่ถูกเรียกใช้งานจริง / dead code)
- lib/services/patient_database_service.dart: uploadMedicationImage(File) — ไม่มีจุดใดในแอปเรียกใช้ฟังก์ชันนี้
- lib/services/nutrition_service.dart: analyzeFoodFromAudio(File) — nutrition_screen.dart
  เรียกแค่ analyzeFoodInput ไม่ได้เรียกฟังก์ชันนี้
ถ้าจะเปิดใช้ฟีเจอร์เหล่านี้ในอนาคตบนเว็บ ต้องแก้ด้วยแพทเทิร์นเดียวกัน (Uint8List แทน File)

## สิ่งที่ควรทำต่อ
รัน `flutter pub get && flutter analyze` แล้ว `flutter build web` เพื่อยืนยัน
คอมไพล์ผ่าน 100% ก่อน deploy จริง (สภาพแวดล้อมนี้ไม่มี Flutter SDK ให้รันตรวจสอบ)

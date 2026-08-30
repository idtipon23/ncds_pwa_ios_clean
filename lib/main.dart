import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'services/auth_service.dart';
import 'services/patient_profile_service.dart';
import 'package:ncds_voice_app_vol1/services/notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/medication_history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  
  // 1. เปิดใช้งานระบบแจ้งเตือนกินยา
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // 2. ตั้งค่า Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // 📍 3. ระบบ Lock-in: Anonymous Auth (ใช้ได้เหมือนกันทั้ง Web/iOS PWA/Android/iOS Native)
  // สร้าง/กู้คืน anonymous session ทันทีที่เปิดแอป — session นี้ (JWT) จะถูก Supabase SDK
  // persist ไว้ในเครื่อง (SharedPreferences บนมือถือ, localStorage บนเว็บ) โดยอัตโนมัติ
  // ทำให้เครื่อง/browser เดิม กลับเข้ามาใช้ anon identity เดิมเสมอ (= lock-in)
  // ไม่ต้องพึ่ง LINE Login หรือ third-party SDK ใดๆ อีกต่อไป
  try {
    await AuthService().signInAnonymouslyIfNeeded();
    debugPrint('✅ Anonymous Auth session ready: ${Supabase.instance.client.auth.currentUser?.id}');
  } catch (e) {
    debugPrint('❌ Anonymous Auth Error: $e');
  }

  // 4. ระบบตรวจสอบ Session และเช็ก Patient ID กับฐานข้อมูลจริง
  final profileService = PatientProfileService();
  bool hasValidSession = false;

  try {
    final patientId = await profileService.getCurrentPatientId();
    if (patientId != null && patientId.isNotEmpty) {
      final isValid = await profileService.verifySessionInDatabase(patientId);
      if (isValid) {
        hasValidSession = true;
      } else {
        await profileService.clearLocalIdentity();
      }
    } else {
      await profileService.clearLocalIdentity();
    }
  } catch (e) {
    debugPrint('Error verifying session: $e');
    await profileService.clearLocalIdentity();
  }

  runApp(MyApp(
    isRegistered: hasValidSession,
  ));
}

class MyApp extends StatefulWidget {
  final bool isRegistered;

  const MyApp({
    super.key,
    required this.isRegistered,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 📍 1. สร้างตัวแปรดักจับสถานะ Auth
  late StreamSubscription<AuthState> _authStateSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    // 📍 2. ดักจับการเปลี่ยนแปลงของ Session ตลอดเวลาที่เปิดแอป
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      
      // ถ้า Token หมดอายุ, ถูกลบ, หรือผู้ใช้กดออกจากระบบ
      if (event == AuthChangeEvent.signedOut) {
        debugPrint('🔒 ระบบตรวจพบว่า Session หมดอายุ หรือกดออกจากระบบ -> เด้งไปหน้า Login');
        
        // ใช้ navigatorKey ที่คุณมีอยู่แล้ว เพื่อบังคับเปลี่ยนหน้าจอจากที่ไหนก็ได้
        NotificationService.navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    // 📍 3. คืนค่าหน่วยความจำเมื่อปิดแอป
    _authStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget initialScreen = widget.isRegistered ? const HomeScreen() : const LoginPage();

    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey, 
      routes: {
        '/medication': (context) => const MedicationHistoryScreen(),
      },
      title: 'NCD Voice App',
      debugShowCheckedModeBanner: false,
      // สามารถใส่ theme เดิมของคุณต่อตรงนี้ได้เลยครับ
      theme: ThemeData(
        useMaterial3: true,
        // ... (ตั้งค่า theme เดิมของคุณ)
      ),
      home: initialScreen,
    );
  }
}
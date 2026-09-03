import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'screens/medication_history_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/patient_profile_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. โหลด .env พร้อม Timeout ป้องกันค้าง
  try {
    await dotenv.load(fileName: ".env").timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('⚠️ Dotenv load warning: $e');
  }

  // 2. เริ่มระบบแจ้งเตือน
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('⚠️ Notification init warning: $e');
  }

  // 3. เริ่มต้น Supabase พร้อม Timeout
  try {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    ).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('⚠️ Supabase initialize error: $e');
  }

  // 4. แสดงผลแอปทันที ไม่รอ Network Auth ใน main()
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<AuthState>? _authStateSubscription;

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color emeraldTheme = Color(0xFF2F9E82);

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authStateSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;

      if (event == AuthChangeEvent.signedOut) {
        debugPrint('🔒 ผู้ใช้ทำการออกจากระบบ -> นำทางไปหน้า Login');
        NotificationService.navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'NCDs Care & Health',
      debugShowCheckedModeBanner: false,
      routes: {
        '/medication': (context) => const MedicationHistoryScreen(),
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomeScreen(),
      },
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: creamBgColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: emeraldTheme,
          primary: emeraldTheme,
          surface: creamBgColor,
        ),
        fontFamilyFallback: const [
          'Thonburi',
          'Sarabun',
          'Noto Sans Thai',
          'Tahoma',
          'sans-serif',
        ],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: primaryTextColor),
          bodyMedium: TextStyle(color: primaryTextColor),
          titleMedium:
              TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600),
          titleLarge:
              TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: emeraldTheme,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFF0E5D8), width: 1.2),
          ),
        ),
      ),
      home: const AppStartupGate(),
    );
  }
}

/// 🚀 Widget สำหรับตรวจสอบตัวตนเบื้องหลัง พร้อมแสดงหน้าจอดาวน์โหลดชั่วคราว
class AppStartupGate extends StatefulWidget {
  const AppStartupGate({super.key});

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  @override
  void initState() {
    super.initState();
    _bootstrapApp();
  }

  Future<void> _bootstrapApp() async {
    final profileService = PatientProfileService();
    bool hasValidSession = false;

    try {
      // 1. ตรวจสอบ/กู้คืน Anonymous Session แบบมี Timeout (ไม่เกิน 5 วินาที)
      await AuthService()
          .signInAnonymouslyIfNeeded()
          .timeout(const Duration(seconds: 5));

      // 2. ตรวจสอบ HN ใน Local Storage และ Database
      final patientId = await profileService
          .getCurrentPatientId()
          .timeout(const Duration(seconds: 3));

      if (patientId != null && patientId.isNotEmpty) {
        final isValid = await profileService
            .verifySessionInDatabase(patientId)
            .timeout(const Duration(seconds: 5));

        if (isValid) {
          hasValidSession = true;
        } else {
          await profileService.clearLocalIdentity();
        }
      } else {
        await profileService.clearLocalIdentity();
      }
    } catch (e) {
      debugPrint('⚠️ App Bootstrap Exception: $e');
      await profileService.clearLocalIdentity();
    }

    if (!mounted) return;

    // 3. เปลี่ยนหน้าจอทันทีเมื่อตรวจสอบเสร็จสิ้น
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            hasValidSession ? const HomeScreen() : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF8F0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF2F9E82),
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'กำลังเข้าสู่ระบบสุขภาพ...',
              style: TextStyle(
                color: Color(0xFF8A7568),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
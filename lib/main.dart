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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. โหลด Environment Variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('⚠️ Dotenv load warning: $e');
  }

  // 2. เปิดใช้งานระบบแจ้งเตือน
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // 3. ตั้งค่า Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // 4. Anonymous Auth Lock-in
  try {
    await AuthService().signInAnonymouslyIfNeeded();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    debugPrint('✅ Anonymous Auth session ready: $currentUserId');
  } catch (e) {
    debugPrint('❌ Anonymous Auth Error: $e');
  }

  // 5. ตรวจสอบ Session และ HN ผู้ป่วย
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
    final Widget initialScreen =
        widget.isRegistered ? const HomeScreen() : const LoginPage();

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
        // ✅ แก้ไขเป็น CardThemeData เพื่อรองรับ Flutter M3 ได้ถูกต้อง
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFF0E5D8), width: 1.2),
          ),
        ),
      ),
      home: initialScreen,
    );
  }
}

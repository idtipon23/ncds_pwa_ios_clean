import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/patient_profile_service.dart';
import '../screens/identity_registration_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final PatientProfileService _profileService = PatientProfileService();

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);

  bool _isLoading = false;

  Future<void> _handleEnterApp() async {
    setState(() => _isLoading = true);

    try {
      final authResponse = await _authService.signInAnonymouslyIfNeeded();
      if (authResponse.user == null) {
        throw Exception('ไม่สามารถเริ่มต้น session การใช้งานได้');
      }

      final profile = await _profileService.validateAndLoadProfile();
      if (!mounted) return;

      if (_profileService.isProfileComplete(profile)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const IdentityRegistrationScreen(),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Login Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเข้าสู่ระบบ: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            right: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF2C879).withValues(alpha: 0.35),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: const Color(0xFFF0E5D8), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 🛡️ โลโก้โล่ป้องกันสุขภาพสีเขียว (Green Guard Logo)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF3E4),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: emeraldTheme.withValues(alpha: 0.35),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.health_and_safety_rounded,
                              size: 72,
                              color: emeraldTheme,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'NCDs Care & Health',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ระบบบันทึกและติดตามสุขภาพ\nสำหรับผู้สูงอายุและผู้ป่วย NCDs',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryTextColor,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    _isLoading
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: emeraldTheme))
                        : SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: _handleEnterApp,
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 22),
                              label: const Text(
                                'เริ่มต้นใช้งาน',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emeraldTheme,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

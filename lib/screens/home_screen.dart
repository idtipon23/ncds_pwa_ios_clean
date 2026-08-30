import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/patient_profile_service.dart';
import '../services/auth_service.dart';
import 'vital_sign_record_screen.dart';
import 'health_history_screen.dart';
import 'patient_profile_screen.dart';
import 'medication_history_screen.dart';
import 'nutrition_screen.dart';
import 'ht_consult_screen.dart';
import 'login_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PatientProfileService _profileService = PatientProfileService();

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);

  bool _isLoading = true;
  String _patientName = "ผู้ใช้งาน";
  double _avgSys7Days = 0;
  double _avgDia7Days = 0;
  bool _hasVitalData = false;
  int _recordCount = 0;

  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMedicalDisclaimerDialog();
    });
  }

  // 🔄 ดึงข้อมูลผู้ป่วยและสัญญาณชีพโดยตรงจากฐานข้อมูล (Direct Supabase Query)
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      // 1. โหลดข้อมูลโปรไฟล์ผู้ป่วย
      final profile = await _profileService.getProfile();
      _profileData = profile;

      String? patientId = await _profileService.getCurrentPatientId();
      if (patientId == null || patientId.isEmpty) {
        patientId = profile?['id']?.toString() ?? user?.id;
      }

      if (profile != null) {
        _patientName = profile['first_name'] ??
            profile['name'] ??
            profile['fullName'] ??
            "ผู้ใช้งาน";
      }

      // 2. ดึงรายการความดันล่าสุดจากตาราง vital_signs แบบเดียวกับหน้า HealthHistory
      List<dynamic> vitals = [];
      if (patientId != null && patientId.isNotEmpty) {
        try {
          final res = await supabase
              .from('vital_signs')
              .select('*')
              .eq('patient_id', patientId)
              .order('recorded_at', ascending: false)
              .limit(14);
          vitals = res as List<dynamic>;
        } catch (e) {
          debugPrint('Query by patient_id failed, trying auth_user_id: $e');
        }
      }

      // Fallback: ดึงด้วย auth_user_id หาก patient_id ยังไม่มี
      if (vitals.isEmpty && user != null) {
        try {
          final res = await supabase
              .from('vital_signs')
              .select('*')
              .eq('auth_user_id', user.id)
              .order('recorded_at', ascending: false)
              .limit(14);
          vitals = res as List<dynamic>;
        } catch (_) {}
      }

      // 3. ประมวลผลค่าเฉลี่ย
      if (vitals.isNotEmpty) {
        _hasVitalData = true;
        _recordCount = vitals.length;

        double sumSys = 0;
        double sumDia = 0;
        int validCount = 0;

        for (var v in vitals) {
          final sys = (v['systolic'] as num?)?.toDouble() ??
              (v['systolic_bp'] as num?)?.toDouble() ??
              (v['sys'] as num?)?.toDouble();
          final dia = (v['diastolic'] as num?)?.toDouble() ??
              (v['diastolic_bp'] as num?)?.toDouble() ??
              (v['dia'] as num?)?.toDouble();

          if (sys != null && dia != null && sys > 0 && dia > 0) {
            sumSys += sys;
            sumDia += dia;
            validCount++;
          }
        }

        if (validCount > 0) {
          _avgSys7Days = sumSys / validCount;
          _avgDia7Days = sumDia / validCount;
        }
      } else {
        _hasVitalData = false;
        _avgSys7Days = 0;
        _avgDia7Days = 0;
        _recordCount = 0;
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMedicalDisclaimerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFFD97B4F), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'ข้อกำหนดทางการแพทย์',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Color(0xFFB45309), size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'แอปพลิเคชันนี้ไม่ใช่เครื่องมือแพทย์',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '• วัตถุประสงค์: บันทึกและติดตามแนวโน้มสุขภาพเบื้องต้นของผู้ป่วยโรคไม่ติดต่อเรื้อรัง (NCDs) เท่านั้น\n\n'
                '• การรักษา: ข้อมูลจากระบบไม่มีผลต่อการวินิจฉัยทางการแพทย์ การปรับขนาดยาต้องอยู่ภายใต้ดุลยพินิจของแพทย์ผู้รักษา\n\n'
                '• ภาวะฉุกเฉิน: หากมีอาการวิกฤต เจ็บแน่นหน้าอก กรุณาไปโรงพยาบาลหรือโทร 1669 ทันที',
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: emeraldTheme,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'รับทราบและเข้าใจแล้ว',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'สวัสดีตอนเช้าค่ะ ☀️';
    if (hour >= 12 && hour < 17) return 'สวัสดีตอนบ่ายค่ะ 🌤️';
    if (hour >= 17 && hour < 20) return 'สวัสดีตอนเย็นค่ะ 🌅';
    return 'สวัสดีตอนค่ำค่ะ 🌙';
  }

  String _getThaiFormattedDate() {
    final now = DateTime.now();
    const thaiWeekdays = [
      'วันจันทร์',
      'วันอังคาร',
      'วันพุธ',
      'วันพฤหัสบดี',
      'วันศุกร์',
      'วันเสาร์',
      'วันอาทิตย์'
    ];
    const thaiMonths = [
      '',
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม'
    ];

    final weekday = thaiWeekdays[now.weekday - 1];
    final day = now.day;
    final month = thaiMonths[now.month];
    final year = now.year + 543;

    return '$weekdayที่ $day $month $year';
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xFFD85A30)),
            SizedBox(width: 8),
            Text(
              'ออกจากระบบ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
          ],
        ),
        content: const Text(
          'คุณต้องการออกจากระบบใช่หรือไม่?',
          style: TextStyle(color: secondaryTextColor, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ยกเลิก', style: TextStyle(color: mutedTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD85A30),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await PatientProfileService().clearLocalIdentity();
                await AuthService().signOut();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              } catch (e) {
                debugPrint('Logout error: $e');
              }
            },
            child:
                const Text('ออกจากระบบ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBgColor,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF2C879).withValues(alpha: 0.3),
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: emeraldTheme),
                  )
                : RefreshIndicator(
                    color: emeraldTheme,
                    onRefresh: _loadDashboardData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderSection(),
                          const SizedBox(height: 18),

                          // 🌳 1. ต้นไม้สุขภาพ (Pure Vector Canvas)
                          _buildHealthTreeBanner(),
                          const SizedBox(height: 18),

                          // 🧸 2. การ์ดความดัน + ตุ๊กตาสุขภาพมาสคอต (Pure Vector Canvas)
                          _buildHealthIndicatorCard(),
                          const SizedBox(height: 26),

                          const Text(
                            'เมนูบริการสุขภาพ',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 🛡️ 3. เมนูกริดพร้อมไอคอนเวกเตอร์คมชัด 100%
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.96,
                            children: [
                              // 1. บันทึกความดัน
                              _buildMenuCard(
                                title: 'บันทึกความดัน',
                                subtitle: 'พิมพ์ค่าความดัน / ถ่ายรูปจอ LCD',
                                imagePath: 'assets/images/menu_bp.jpg',
                                iconType: _MenuIconType.bloodPressure,
                                barColor: const Color(0xFF2F9E82),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const VitalSignRecordScreen(),
                                    ),
                                  );
                                  _loadDashboardData();
                                },
                              ),

                              // 2. ห้องยาประจำตัว
                              _buildMenuCard(
                                title: 'ห้องยาประจำตัว',
                                subtitle: 'สแกนฉลากยา & ตั้งเตือนทานยา',
                                imagePath: 'assets/images/menu_drug.jpg',
                                iconType: _MenuIconType.medication,
                                barColor: const Color(0xFFE8A33D),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const MedicationHistoryScreen(),
                                  ),
                                ),
                              ),

                              // 3. อาหาร & กิจกรรม
                              _buildMenuCard(
                                title: 'อาหาร & กิจกรรม',
                                subtitle: 'พิมพ์บันทึกอาหาร / ถ่ายรูปมื้ออาหาร',
                                imagePath: 'assets/images/menu_fd.jpg',
                                iconType: _MenuIconType.nutrition,
                                barColor: const Color(0xFFD97B4F),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const NutritionScreen(),
                                    ),
                                  );
                                  _loadDashboardData();
                                },
                              ),

                              // 4. ปรึกษาหมอ AI
                              _buildMenuCard(
                                title: 'ปรึกษาหมอ AI',
                                subtitle: 'ถามตอบอิง HT Guideline 2567',
                                imagePath: 'assets/images/menu_ai.jpg',
                                iconType: _MenuIconType.aiDoctor,
                                barColor: const Color(0xFF4C8FA6),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HtConsultScreen(),
                                  ),
                                ),
                              ),

                              // 5. สมุดสุขภาพ
                              _buildMenuCard(
                                title: 'สมุดสุขภาพ',
                                subtitle: 'ดูกราฟ 7 วัน & ประวัติความเสี่ยง',
                                imagePath: 'assets/images/menu_graph.jpg',
                                iconType: _MenuIconType.healthBook,
                                barColor: const Color(0xFF6B9E5C),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HealthHistoryScreen(),
                                  ),
                                ),
                              ),

                              // 6. ข้อมูลของฉัน
                              _buildMenuCard(
                                title: 'ข้อมูลของฉัน',
                                subtitle: 'คำนวณ TDEE & คัดกรองโรค',
                                imagePath: 'assets/images/menu_risk.jpg',
                                iconType: _MenuIconType.profile,
                                barColor: const Color(0xFFB37B57),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PatientProfileScreen(),
                                    ),
                                  );
                                  _loadDashboardData();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: softCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFEADBCE),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, color: emeraldTheme, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Chaiyaphod Laochumni (RN Developer)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTimeBasedGreeting(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'คุณ $_patientName',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getThaiFormattedDate(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: mutedTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFFD85A30).withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: IconButton(
                onPressed: _handleLogout,
                icon: const Icon(
                  Icons.logout,
                  color: Color(0xFFD85A30),
                  size: 20,
                ),
                tooltip: 'ออกจากระบบ',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 🌳 แบนเนอร์ต้นไม้สุขภาพ วาดด้วย Pure Canvas Vector
  Widget _buildHealthTreeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF4C7A3F).withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFD9EBCF),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(30, 30),
                painter: _HealthTreePainter(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ต้นไม้สุขภาพของคุณ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3E5E33),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _hasVitalData
                      ? 'บันทึกสะสม $_recordCount ครั้งแล้ว ต้นไม้สุขภาพกำลังเติบโตแข็งแรง 🌱'
                      : 'เริ่มบันทึกสุขภาพวันนี้ เพื่อให้ต้นไม้เริ่มเติบโตกันนะคะ 🌱',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5C7A50),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🧸 การ์ดสรุปความดัน + ตุ๊กตาสุขภาพมาสคอต (Mascot Canvas)
  Widget _buildHealthIndicatorCard() {
    final int sys = _avgSys7Days.round();
    final int dia = _avgDia7Days.round();

    final feedback = HealthFeedbackEvaluator.evaluate(
      systolicAvg: sys,
      diastolicAvg: dia,
      hasData: _hasVitalData,
      profile: _profileData,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: emeraldTheme.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ความดันเฉลี่ย 7 วันล่าสุด',
                    style: TextStyle(
                      fontSize: 13,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _hasVitalData ? '$sys/$dia' : '--/--',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: feedback.themeColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'mmHg',
                        style: TextStyle(fontSize: 12, color: mutedTextColor),
                      ),
                    ],
                  ),
                ],
              ),
              // 🧸 ตุ๊กตามาสคอตแสดงอารมณ์ความดัน (Mascot Canvas Avatar)
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: feedback.themeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: feedback.themeColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(36, 36),
                    painter: _HealthMascotPainter(
                      tier: feedback.tier,
                      mainColor: feedback.themeColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF6EE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFF2C879).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb,
                  size: 22,
                  color: feedback.themeColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feedback.statusTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: feedback.themeColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        feedback.adviceText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: primaryTextColor,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🖼️ การ์ดเมนูพร้อมไอคอน Vector Canvas
  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required _MenuIconType iconType,
    required String imagePath,
    required Color barColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: barColor.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: barColor.withValues(alpha: 0.15),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              // 🛡️ ป้ายไอคอนเวกเตอร์มุมซ้ายบน
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CustomPaint(
                    painter: _MenuVectorIconPainter(iconType: iconType),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.95),
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// 🌳 CustomPainter: ต้นไม้สุขภาพ (Health Tree Vector)
// =========================================================================
class _HealthTreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. ลำต้น (Trunk)
    final trunkPaint = Paint()..color = const Color(0xFF8B5A2B);
    final trunkPath = Path();
    trunkPath.moveTo(w * 0.42, h);
    trunkPath.lineTo(w * 0.58, h);
    trunkPath.lineTo(w * 0.54, h * 0.5);
    trunkPath.lineTo(w * 0.46, h * 0.5);
    trunkPath.close();
    canvas.drawPath(trunkPath, trunkPaint);

    // 2. พุ่มใบไม้ 3 ชั้น (Foliage)
    final foliagePaint = Paint()..color = const Color(0xFF4C7A3F);
    canvas.drawCircle(Offset(w * 0.5, h * 0.38), w * 0.35, foliagePaint);
    canvas.drawCircle(Offset(w * 0.32, h * 0.44), w * 0.24, foliagePaint);
    canvas.drawCircle(Offset(w * 0.68, h * 0.44), w * 0.24, foliagePaint);

    // ประกายใบไม้สีอ่อน
    final lightFoliage = Paint()..color = const Color(0xFF76A857);
    canvas.drawCircle(Offset(w * 0.45, h * 0.32), w * 0.16, lightFoliage);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =========================================================================
// 🧸 CustomPainter: ตุ๊กตาสุขภาพมาสคอต (Health Mascot Face)
// =========================================================================
class _HealthMascotPainter extends CustomPainter {
  final int tier;
  final Color mainColor;

  _HealthMascotPainter({required this.tier, required this.mainColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // 1. หัวมาสคอต (Face Background)
    final facePaint = Paint()..color = mainColor;
    canvas.drawCircle(center, radius, facePaint);

    final whitePaint = Paint()..color = Colors.white;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // 2. วาดหน้าตาตาม Tier สุขภาพ
    if (tier == 4) {
      // 😊 Tier 4: ความดันปกติ (ตายิ้มโค้ง + ปากยิ้มกว้าง)
      final eyePathLeft = Path()
        ..moveTo(w * 0.25, h * 0.45)
        ..quadraticBezierTo(w * 0.35, h * 0.32, w * 0.45, h * 0.45);
      final eyePathRight = Path()
        ..moveTo(w * 0.55, h * 0.45)
        ..quadraticBezierTo(w * 0.65, h * 0.32, w * 0.75, h * 0.45);
      canvas.drawPath(eyePathLeft, strokePaint);
      canvas.drawPath(eyePathRight, strokePaint);

      // ปากยิ้ม
      final mouthPath = Path()
        ..moveTo(w * 0.32, h * 0.62)
        ..quadraticBezierTo(w * 0.5, h * 0.85, w * 0.68, h * 0.62);
      canvas.drawPath(mouthPath, strokePaint);
    } else if (tier == 3) {
      // 😐 Tier 3: เฝ้าระวัง (ตากลม + ปากตรง)
      canvas.drawCircle(Offset(w * 0.35, h * 0.42), 2.8, whitePaint);
      canvas.drawCircle(Offset(w * 0.65, h * 0.42), 2.8, whitePaint);
      canvas.drawLine(
          Offset(w * 0.35, h * 0.68), Offset(w * 0.65, h * 0.68), strokePaint);
    } else if (tier == 2) {
      // 😟 Tier 2: ความดันสูง (ตาตก + ปากคว่ำ)
      canvas.drawCircle(Offset(w * 0.35, h * 0.42), 2.8, whitePaint);
      canvas.drawCircle(Offset(w * 0.65, h * 0.42), 2.8, whitePaint);
      final mouthPath = Path()
        ..moveTo(w * 0.32, h * 0.72)
        ..quadraticBezierTo(w * 0.5, h * 0.58, w * 0.68, h * 0.72);
      canvas.drawPath(mouthPath, strokePaint);
    } else {
      // 🚨 Tier 1: วิกฤติ (ตา X + ปากตกใจ)
      canvas.drawLine(
          Offset(w * 0.28, h * 0.35), Offset(w * 0.42, h * 0.47), strokePaint);
      canvas.drawLine(
          Offset(w * 0.42, h * 0.35), Offset(w * 0.28, h * 0.47), strokePaint);

      canvas.drawLine(
          Offset(w * 0.58, h * 0.35), Offset(w * 0.72, h * 0.47), strokePaint);
      canvas.drawLine(
          Offset(w * 0.72, h * 0.35), Offset(w * 0.58, h * 0.47), strokePaint);

      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.7), width: w * 0.26, height: h * 0.2),
        whitePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// =========================================================================
// 🛡️ CustomPainter: เวกเตอร์ไอคอนประจำ 6 เมนู (Vector Canvas Icons)
// =========================================================================
enum _MenuIconType {
  bloodPressure,
  medication,
  nutrition,
  aiDoctor,
  healthBook,
  profile
}

class _MenuVectorIconPainter extends CustomPainter {
  final _MenuIconType iconType;

  _MenuVectorIconPainter({required this.iconType});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    switch (iconType) {
      case _MenuIconType.bloodPressure:
        // คลื่นหัวใจ EKG
        final path = Path()
          ..moveTo(0, h * 0.5)
          ..lineTo(w * 0.25, h * 0.5)
          ..lineTo(w * 0.4, h * 0.15)
          ..lineTo(w * 0.6, h * 0.85)
          ..lineTo(w * 0.75, h * 0.5)
          ..lineTo(w, h * 0.5);
        canvas.drawPath(path, p);
        break;

      case _MenuIconType.medication:
        // แคปซูลยา
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.15, h * 0.25, w * 0.7, h * 0.5),
            Radius.circular(w * 0.25),
          ),
          p,
        );
        canvas.drawLine(
            Offset(w * 0.5, h * 0.25), Offset(w * 0.5, h * 0.75), p);
        break;

      case _MenuIconType.nutrition:
        // ช้อนส้อม
        canvas.drawLine(Offset(w * 0.3, h * 0.1), Offset(w * 0.3, h * 0.9), p);
        canvas.drawLine(Offset(w * 0.7, h * 0.1), Offset(w * 0.7, h * 0.9), p);
        canvas.drawCircle(Offset(w * 0.7, h * 0.25), w * 0.15, fill);
        break;

      case _MenuIconType.aiDoctor:
        // กล่องแชทสนทนา
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.1, h * 0.15, w * 0.8, h * 0.6),
            const Radius.circular(5),
          ),
          p,
        );
        final tail = Path()
          ..moveTo(w * 0.3, h * 0.75)
          ..lineTo(w * 0.2, h * 0.95)
          ..lineTo(w * 0.5, h * 0.75);
        canvas.drawPath(tail, fill);
        break;

      case _MenuIconType.healthBook:
        // กราฟแท่งสถิติ
        canvas.drawRect(
            Rect.fromLTWH(w * 0.15, h * 0.5, w * 0.18, h * 0.4), fill);
        canvas.drawRect(
            Rect.fromLTWH(w * 0.41, h * 0.25, w * 0.18, h * 0.65), fill);
        canvas.drawRect(
            Rect.fromLTWH(w * 0.67, h * 0.4, w * 0.18, h * 0.5), fill);
        break;

      case _MenuIconType.profile:
        // รูปคน/โปรไฟล์
        canvas.drawCircle(Offset(w * 0.5, h * 0.3), w * 0.2, fill);
        final body = Path()
          ..moveTo(w * 0.15, h * 0.9)
          ..quadraticBezierTo(w * 0.5, h * 0.55, w * 0.85, h * 0.9);
        canvas.drawPath(body, p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =========================================================================
// 🚀 Evaluator Class
// =========================================================================
class HealthFeedbackModel {
  final int tier;
  final String statusTitle;
  final String adviceText;
  final Color themeColor;

  HealthFeedbackModel({
    required this.tier,
    required this.statusTitle,
    required this.adviceText,
    required this.themeColor,
  });
}

class HealthFeedbackEvaluator {
  static HealthFeedbackModel evaluate({
    required int systolicAvg,
    required int diastolicAvg,
    required bool hasData,
    required Map<String, dynamic>? profile,
  }) {
    if (!hasData) {
      return HealthFeedbackModel(
        tier: 4,
        statusTitle: 'ยังไม่มีข้อมูลความดัน',
        adviceText:
            'แนะนำวัดความดันช่วงเช้า (หลังตื่นนอน) อย่างน้อยวันละ 1 ครั้งค่ะ',
        themeColor: const Color(0xFF2F9E82),
      );
    }

    int tier = 4;
    if (systolicAvg >= 180 || diastolicAvg >= 110) {
      tier = 1;
    } else if (systolicAvg >= 140 || diastolicAvg >= 90) {
      tier = 2;
    } else if (systolicAvg >= 130 || diastolicAvg >= 85) {
      tier = 3;
    } else {
      tier = 4;
    }

    switch (tier) {
      case 1:
        return HealthFeedbackModel(
          tier: 1,
          statusTitle: 'วิกฤติ! ต้องพบแพทย์',
          adviceText:
              '🚨 ความดันสูงวิกฤติ งดกิจกรรมหนัก สังเกตอาการหน้ามืด/เจ็บอก และรีบพบแพทย์ด่วน',
          themeColor: const Color(0xFFEF4444),
        );
      case 2:
        return HealthFeedbackModel(
          tier: 2,
          statusTitle: 'ความดันระดับสูง',
          adviceText:
              '💊 ทานยาให้ตรงเวลาอย่างเคร่งครัด งดของเค็ม/ปรุงรสจัด ช่วยลดความดันได้ 5 mmHg',
          themeColor: const Color(0xFFF97316),
        );
      case 3:
        return HealthFeedbackModel(
          tier: 3,
          statusTitle: 'เฝ้าระวัง (ค่อนข้างสูง)',
          adviceText:
              '🥗 ปรับพฤติกรรม ลดอาหารหวานมันเค็ม ขยับร่างกายสม่ำเสมอเพื่อหลอดเลือดแข็งแรง',
          themeColor: const Color(0xFFEAB308),
        );
      case 4:
      default:
        return HealthFeedbackModel(
          tier: 4,
          statusTitle: 'ความดันปกติ (ดีเยี่ยม)',
          adviceText:
              '✨ สุขภาพอยู่ในเกณฑ์ดีเยี่ยม ดื่มน้ำสะอาดให้เพียงพอ และเดินออกกำลังกายวันละ 30 นาทีค่ะ',
          themeColor: const Color(0xFF2F9E82),
        );
    }
  }
}

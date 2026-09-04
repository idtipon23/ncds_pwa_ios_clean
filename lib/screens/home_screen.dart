import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/patient_profile_service.dart';
import '../services/vital_repository.dart';
import '../services/nutrition_service.dart';
import 'vital_sign_record_screen.dart';
import 'health_history_screen.dart';
import 'patient_profile_screen.dart';
import 'medication_history_screen.dart';
import 'nutrition_screen.dart';
import 'ht_consult_screen.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final VitalRepository _vitalRepo = VitalRepository();
  final NutritionService _nutritionService = NutritionService();
  final SupabaseClient _supabase = Supabase.instance.client;

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
  int _streakDays = 1;

  Map<String, dynamic>? _profileData;
  List<Map<String, dynamic>> _todayFoodLogs = [];
  Map<String, dynamic>? _upcomingAppointment; // 📅 ข้อมูลวันนัดหมายถัดไป
  Map<String, dynamic>? _nextAppointment;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMedicalDisclaimerDialog();
    });
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      // 🚀 timeout ทุก query กัน UI ค้างถาวรถ้า request ไม่ error แต่ก็ไม่ตอบกลับ
      // (พบได้บน iOS standalone WKWebView เมื่อเพิ่มไอคอนไว้หน้าจอหลัก)
      final patientId = await _profileService
          .getCurrentPatientId()
          .timeout(const Duration(seconds: 8));
      final profile = await _profileService
          .getProfile()
          .timeout(const Duration(seconds: 8));
      _profileData = profile;

      if (profile != null) {
        _patientName = profile['first_name'] ?? profile['name'] ?? "ผู้ใช้งาน";
      }

      if (patientId != null && patientId.isNotEmpty) {
        // 1. ดึงข้อมูลความดัน 7 วันล่าสุด
        try {
          final vitals = await _vitalRepo
              .getLast7Days(patientId)
              .timeout(const Duration(seconds: 8));
          if (vitals.isNotEmpty) {
            _hasVitalData = true;
            _streakDays = vitals.length;
            double sumSys = 0;
            double sumDia = 0;
            for (var v in vitals) {
              sumSys += (v['systolic'] as num?)?.toDouble() ?? 0;
              sumDia += (v['diastolic'] as num?)?.toDouble() ?? 0;
            }
            _avgSys7Days = sumSys / vitals.length;
            _avgDia7Days = sumDia / vitals.length;
          }
        } catch (e) {
          debugPrint('⚠️ Error/timeout loading vitals: $e');
        }

        // 2. ดึงบันทึกอาหารวันนี้
        try {
          _todayFoodLogs = await _nutritionService
              .getTodayFoodLogs(patientId)
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('⚠️ Error/timeout loading today food logs: $e');
        }

        // 3. 📅 ดึงวันนัดหมายถัดไปที่ยังไม่ถึงกำหนด (นับตั้งแต่วันนี้เป็นต้นไป)
        try {
          final todayStr = DateTime.now().toIso8601String().split('T').first;
          final apptRes = await _supabase
              .from('appointments')
              .select('*')
              .eq('patient_id', patientId)
              .eq('status', 'scheduled')
              .gte('appointment_date', todayStr)
              .order('appointment_date', ascending: true)
              .limit(1)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));

          if (apptRes != null) {
            _upcomingAppointment = Map<String, dynamic>.from(apptRes);
          }
        } catch (e) {
          debugPrint('⚠️ Error/timeout loading appointment: $e');
        }
        // 4. ดึงวันนัดหมายถัดไป (นัดที่ยังไม่ถึง และสถานะ scheduled)
        try {
          final todayStr = DateTime.now().toIso8601String().split('T').first;
          final appts = await Supabase.instance.client
              .from('appointments')
              .select()
              .eq('patient_id', patientId)
              .eq('status', 'scheduled')
              .gte('appointment_date', todayStr)
              .order('appointment_date', ascending: true)
              .limit(1);

          if (appts.isNotEmpty) {
            _nextAppointment = appts.first;
          } else {
            _nextAppointment = null;
          }
        } catch (e) {
          debugPrint('Error loading appointment: $e');
          _nextAppointment = null;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error/timeout loading dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🛡️ Pop-up ข้อจำกัดความรับผิดชอบทางการแพทย์ (Medical Disclaimer)
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
                    Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 22),
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
                '• วัตถุประสงค์: พัฒนาขึ้นเพื่อการบันทึก รวบรวม และติดตามแนวโน้มภาวะสุขภาพเบื้องต้นของผู้ป่วยโรคไม่ติดต่อเรื้อรัง (NCDs) เท่านั้น\n\n'
                '• การตัดสินใจรักษา: ข้อมูลและคำแนะนำจากระบบ AI ไม่มีผลต่อการวินิจฉัยทางการแพทย์ การปรับเปลี่ยนขนาด หรือการรักษาต้องอยู่ภายใต้ดุลยพินิจของแพทย์ผู้เชี่ยวชาญเท่านั้น\n\n'
                '• ภาวะฉุกเฉิน: หากมีอาการวิกฤต เจ็บแน่นหน้าอก หรือความดันโลหิตสูงรุนแรง กรุณาติดต่อสถานพยาบาลใกล้บ้านหรือโทร 1669 ทันที',
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
      'วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์', 'วันอาทิตย์'
    ];
    const thaiMonths = [
      '', 'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
      'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
    ];

    final weekday = thaiWeekdays[now.weekday - 1];
    final day = now.day;
    final month = thaiMonths[now.month];
    final year = now.year + 543;

    return '$weekdayที่ $day $month $year';
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
                ? const Center(child: CircularProgressIndicator(color: emeraldTheme))
                : RefreshIndicator(
                    onRefresh: _loadDashboardData,
                    color: emeraldTheme,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderSection(),
                          const SizedBox(height: 16),

                          // 📅 แบนเนอร์แสดงวันนัดหมายถัดไป (ถ้ามีนัดในระบบ)
                          if (_upcomingAppointment != null) ...[
                            _buildAppointmentBanner(),
                            const SizedBox(height: 14),
                          ],

                          // 🌱 แบนเนอร์ต้นไม้สุขภาพ
                          _buildHealthTreeBanner(),
                          const SizedBox(height: 18),


                          // 📊 การ์ดสรุปความดัน 7 วันล่าสุด
                          _buildHealthIndicatorCard(),
                          const SizedBox(height: 26),

                          // 🧱 เมนูบริการ 2 คอลัมน์
                          const Text(
                            'เมนูบริการสุขภาพ',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 14),

                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.96,
                            children: [
                              _buildMenuCard(
                                title: 'บันทึกความดัน',
                                subtitle: 'พิมพ์ค่าความดัน / ถ่ายรูปจอ LCD',
                                imagePath: 'assets/images/menu_bp.jpg',
                                icon: Icons.monitor_heart_rounded,
                                barColor: const Color(0xFF2F9E82),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const VitalSignRecordScreen(),
                                  ),
                                ),
                              ),
                              _buildMenuCard(
                                title: 'ห้องยาประจำตัว',
                                subtitle: 'สแกนฉลากยา & ตั้งเตือนทานยา',
                                imagePath: 'assets/images/menu_drug.jpg',
                                icon: Icons.medication_rounded,
                                barColor: const Color(0xFFE8A33D),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const MedicationHistoryScreen(),
                                  ),
                                ),
                              ),
                              _buildMenuCard(
                                title: 'อาหาร & กิจกรรม',
                                subtitle: 'พิมพ์บันทึกอาหาร / ถ่ายรูปมื้ออาหาร',
                                imagePath: 'assets/images/menu_fd.jpg',
                                icon: Icons.restaurant_menu_rounded,
                                barColor: const Color(0xFFD97B4F),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const NutritionScreen(),
                                  ),
                                ),
                              ),
                              _buildMenuCard(
                                title: 'ปรึกษาหมอ AI',
                                subtitle: 'ถามตอบอิง HT Guideline 2567',
                                imagePath: 'assets/images/menu_ai.jpg',
                                icon: Icons.chat_bubble_rounded,
                                barColor: const Color(0xFF4C8FA6),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HtConsultScreen(),
                                  ),
                                ),
                              ),
                              _buildMenuCard(
                                title: 'สมุดสุขภาพ',
                                subtitle: 'ดูกราฟ 7 วัน & ประวัติความเสี่ยง',
                                imagePath: 'assets/images/menu_graph.jpg',
                                icon: Icons.bar_chart_rounded,
                                barColor: const Color(0xFF6B9E5C),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HealthHistoryScreen(),
                                  ),
                                ),
                              ),
                              _buildMenuCard(
                                title: 'ข้อมูลของฉัน',
                                subtitle: 'คำนวณ TDEE & คัดกรองโรค',
                                imagePath: 'assets/images/menu_risk.jpg',
                                icon: Icons.person_pin_rounded,
                                barColor: const Color(0xFFB37B57),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PatientProfileScreen(),
                                  ),
                                ),
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

  // 📅 Widget การ์ดวันนัดหมายถัดไป (Appointment Banner)
  Widget _buildAppointmentBanner() {
    // 🟢 กรณีที่ 1: ยังไม่มีนัดหมายในระบบ (แสดงแถบสแตนด์บายรอ ไม่ซ่อน UI)
    if (_upcomingAppointment == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFF0E5D8),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: softCardBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: secondaryTextColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'นัดหมายแพทย์ครั้งถัดไป',
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'ยังไม่มีนัดหมายในระบบ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: mutedTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 🔵 กรณีที่ 2: มีนัดหมายจริง (ทำงานตามโค้ดเดิมของคุณทั้งหมด)
    final rawDate = _upcomingAppointment!['appointment_date']?.toString() ?? '';
    final timeStr = _upcomingAppointment!['appointment_time']?.toString().substring(0, 5) ?? '09:00';
    final clinic = _upcomingAppointment!['clinic_name']?.toString() ?? 'คลินิก NCDs';
    final reason = _upcomingAppointment!['reason']?.toString() ?? 'ตรวจติดตามอาการ';
    final bool needFasting = _upcomingAppointment!['need_fasting'] == true;

    // คำนวณจำนวนวันที่เหลือนับถอยหลัง
    int daysLeft = 0;
    try {
      final apptDate = DateTime.parse(rawDate);
      final today = DateTime.now();
      final cleanToday = DateTime(today.year, today.month, today.day);
      final cleanAppt = DateTime(apptDate.year, apptDate.month, apptDate.day);
      daysLeft = cleanAppt.difference(cleanToday).inDays;
    } catch (_) {}

    String daysBadgeText = daysLeft == 0
        ? 'นัดหมายวันนี้!'
        : daysLeft == 1
            ? 'พรุ่งนี้'
            : 'อีก $daysLeft วัน';

    Color badgeColor = daysLeft <= 1 ? const Color(0xFFDC2626) : const Color(0xFF2563EB);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.calendar_month_rounded, color: badgeColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'นัดหมายแพทย์ครั้งถัดไป',
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$rawDate (เวลา $timeStr น.)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  daysBadgeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: softCardBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🏥 $clinic • นัดเพื่อ: $reason',
                  style: const TextStyle(fontSize: 12, color: primaryTextColor),
                ),
                if (needFasting) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '⚠️ ต้องงดน้ำและอาหารหลัง 20:00 น. ก่อนมาตรวจเลือด',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🕒 Widget ส่วน Header + Badge เครดิตชื่อผู้พัฒนาที่มุมบนขวา
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
                  Icon(Icons.verified_user_rounded, color: emeraldTheme, size: 14),
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
          ],
        ),
      ],
    );
  }

  // 🌱 Widget แบนเนอร์ต้นไม้สุขภาพ
  Widget _buildHealthTreeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF4C7A3F).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFD9EBCF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.park_rounded,
              color: Color(0xFF4C7A3F),
              size: 26,
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
                      ? 'บันทึกต่อเนื่อง $_streakDays วันแล้ว ต้นไม้กำลังเติบโตแข็งแรงค่ะ 🌱'
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

  // 📊 Widget การ์ดสรุปความดัน 7 วัน
  Widget _buildHealthIndicatorCard() {
    final int sys = _avgSys7Days.round();
    final int dia = _avgDia7Days.round();

    final feedback = HealthFeedbackEvaluator.evaluate(
      systolicAvg: sys,
      diastolicAvg: dia,
      hasData: _hasVitalData,
      todayFoodLogs: _todayFoodLogs,
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: feedback.themeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  feedback.iconData,
                  size: 34,
                  color: feedback.themeColor,
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
                  Icons.lightbulb_circle_rounded,
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

  // 🖼️ Widget การ์ดเมนู
  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required IconData icon,
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
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

// ==========================================
// 🚀 Top-level Evaluator Classes
// ==========================================

class HealthFeedbackModel {
  final String statusTitle;
  final String adviceText;
  final IconData iconData;
  final Color themeColor;
  final Color bgColor;

  HealthFeedbackModel({
    required this.statusTitle,
    required this.adviceText,
    required this.iconData,
    required this.themeColor,
    required this.bgColor,
  });
}

class HealthFeedbackEvaluator {
  static HealthFeedbackModel evaluate({
    required int systolicAvg,
    required int diastolicAvg,
    required bool hasData,
    required List<Map<String, dynamic>> todayFoodLogs,
    required Map<String, dynamic>? profile,
  }) {
    if (!hasData) {
      return HealthFeedbackModel(
        statusTitle: 'ยังไม่มีข้อมูลความดัน',
        adviceText: 'แนะนำวัดความดันช่วงเช้า (หลังตื่นนอน) อย่างน้อยวันละ 1 ครั้งค่ะ',
        iconData: Icons.add_chart_rounded,
        themeColor: const Color(0xFF2F9E82),
        bgColor: const Color(0xFFECFDF5),
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

    final String diseases =
        (profile?['underlying_diseases'] ?? '').toString().toLowerCase();
    final bool hasDM = diseases.contains('เบาหวาน');
    final bool hasCKD = diseases.contains('ไต');
    final bool isSmoker = profile?['smokes'] == true;
    final double bmi = (profile?['bmi'] as num?)?.toDouble() ?? 0.0;

    String actionAdvice = '';

    if (tier == 1) {
      actionAdvice =
          '🚨 อันตราย! ความดันสูงวิกฤติ งดกิจกรรมหนัก สังเกตอาการหน้ามืด/เจ็บอก และรีบพบแพทย์ด่วน';
    } else if (todayFoodLogs.isNotEmpty && _hasWarningInFoods(todayFoodLogs)) {
      actionAdvice =
          '⚠️ อาหารวันนี้โซเดียม/น้ำตาลสูง: ระวังบวมน้ำและความดันพุ่ง พรุ่งนี้เน้นทานจืดและผักให้มากขึ้น';
    } else if (tier == 2) {
      actionAdvice =
          '💊 ความดันยังสูง: ทานยาให้ตรงเวลาอย่างเคร่งครัด และงดปรุงรส/น้ำปลา/ซีอิ๊ว (ลดเค็มลดความดันได้ 5 mmHg)';
    } else {
      if (isSmoker) {
        actionAdvice =
            '🚬 งดสูบบุหรี่: ช่วยลดความเสี่ยงโรคหัวใจและหลอดเลือดสมองตีบเฉียบพลันได้เห็นผลที่สุด';
      } else if (hasCKD) {
        actionAdvice =
            '💧 ถนอมไต: หลีกเลี่ยงยาแก้ปวดกลุ่ม NSAIDs (เช่น ไอบูโพรเฟน) และงดอาหารหมักดองเด็ดขาด';
      } else if (hasDM) {
        actionAdvice =
            '🥗 คุมน้ำตาล: เน้นทานอาหารสูตร 2:1:1 (ผักครึ่งจาน ข้าว 1 ส่วน เนื้อ 1 ส่วน) ป้องกันหลอดเลือดอักเสบ';
      } else if (bmi >= 25.0) {
        actionAdvice =
            '🏃‍♂️ ระวังอ้วนลงพุง: การลดน้ำหนัก 1 กก. ช่วยลดความดันโลหิตได้ถึง 1 mmHg พยายามขยับร่างกายบ่อยๆ';
      } else {
        actionAdvice =
            '✨ สุขภาพอยู่ในเกณฑ์ดี: ดื่มน้ำเปล่าให้เพียงพอ และเดินแกว่งแขน 30 นาที/วัน เพื่อหลอดเลือดที่แข็งแรง';
      }
    }

    switch (tier) {
      case 1:
        return HealthFeedbackModel(
          statusTitle: 'วิกฤติ! ต้องพบแพทย์',
          adviceText: actionAdvice,
          iconData: Icons.warning_amber_rounded,
          themeColor: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEF2F2),
        );
      case 2:
        return HealthFeedbackModel(
          statusTitle: 'ความดันระดับสูง',
          adviceText: actionAdvice,
          iconData: Icons.sentiment_dissatisfied_rounded,
          themeColor: const Color(0xFFF97316),
          bgColor: const Color(0xFFFFF7ED),
        );
      case 3:
        return HealthFeedbackModel(
          statusTitle: 'เฝ้าระวัง (ค่อนข้างสูง)',
          adviceText: actionAdvice,
          iconData: Icons.sentiment_neutral_rounded,
          themeColor: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEFCE8),
        );
      case 4:
      default:
        return HealthFeedbackModel(
          statusTitle: 'ความดันปกติ (ดีเยี่ยม)',
          adviceText: actionAdvice,
          iconData: Icons.sentiment_very_satisfied_rounded,
          themeColor: const Color(0xFF2F9E82),
          bgColor: const Color(0xFFECFDF5),
        );
    }
  }

  static bool _hasWarningInFoods(List<Map<String, dynamic>> logs) {
    for (var log in logs) {
      if (log['warning_flags'] != null &&
          (log['warning_flags'] as List).isNotEmpty) {
        return true;
      }
    }
    return false;
  }
}
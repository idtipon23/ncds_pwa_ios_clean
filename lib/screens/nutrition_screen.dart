import 'package:flutter/material.dart';
import '../services/patient_profile_service.dart';
import '../services/nutrition_service.dart';
import '../services/vital_repository.dart';
import '../services/patient_database_service.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  Map<String, dynamic>? _weeklySummary;

  final _profileService = PatientProfileService();
  final _nutritionService = NutritionService();
  final _vitalRepository = VitalRepository();
  final _foodInputController = TextEditingController();
  final _databaseService = PatientDatabaseService();

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color terracottaTheme = Color(0xFFD97B4F);
  static const Color softCardBg = Color(0xFFFBF6EE);

  bool _isLoading = true;
  bool _isAnalyzing = false;

  String? _patientId;
  String _underlyingDiseases = '';
  double _tdee = 2000.0;
  double _weightKg = 60.0; 
  int _latestSystolic = 120;

  List<Map<String, dynamic>> _todayFoods = [];
  List<Map<String, dynamic>> _todayExercises = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _foodInputController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      final profile = await _profileService.getProfile();

      if (patientId != null) {
        _patientId = patientId;
        _tdee = (profile?['tdee'] as num?)?.toDouble() ?? 2000.0;
        _weightKg = (profile?['weight_kg'] as num?)?.toDouble() ?? 60.0;
        _underlyingDiseases = profile?['underlying_diseases'] ?? '';

        final vitals = await _vitalRepository.getLast7Days(patientId);
        if (vitals.isNotEmpty) {
          _latestSystolic = (vitals.first['systolic'] as num?)?.toInt() ?? 120;
        }

        _todayFoods = await _nutritionService.getTodayFoodLogs(patientId);
        _todayExercises = await _nutritionService.getTodayExerciseLogs(patientId);
        _weeklySummary = await _nutritionService.getLast7DaysSummary(patientId);
      }
    } catch (e) {
      debugPrint('Error loading nutrition dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _analyzeAndLogFoodFromText() async {
    final text = _foodInputController.text.trim();
    if (text.isEmpty || _patientId == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final result = await _nutritionService.analyzeFoodInput(
        textInput: text,
        underlyingDiseases: _underlyingDiseases,
      );

      if (result != null && mounted) {
        _showFoodConfirmDialog(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถวิเคราะห์ข้อมูลอาหารได้ กรุณาลองใหม่อีกครั้ง'),
              backgroundColor: terracottaTheme,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showFoodConfirmDialog(Map<String, dynamic> foodData) {
    final warnings = List<String>.from(foodData['warning_flags'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEADBCE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.restaurant_menu, color: terracottaTheme, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      foodData['food_name'] ?? 'อาหาร',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: softCardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF2C879).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_fire_department, color: terracottaTheme, size: 36),
                    const SizedBox(width: 8),
                    Text(
                      '${foodData['calories']} kcal',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: terracottaTheme,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNutrientBadge('โปรตีน', '${foodData['protein_g']}g', Colors.blue),
                  _buildNutrientBadge('คาร์บ', '${foodData['carbs_g']}g', Colors.orange),
                  _buildNutrientBadge('ไขมัน', '${foodData['fat_g']}g', Colors.redAccent),
                  _buildNutrientBadge('น้ำตาล', '${foodData['sugar_g']}g', Colors.purple),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'โซเดียม: ${foodData['sodium_mg']} mg',
                  style: const TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                ),
              ),

              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'ข้อควรระวังสำหรับผู้ป่วย',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...warnings.map(
                        (w) => Text(
                          '• $w',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emeraldTheme,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    _foodInputController.clear();
                    await _nutritionService.saveFoodLog(
                      patientId: _patientId!,
                      foodData: foodData,
                    );
                    await _loadDashboardData();
                  },
                  child: const Text(
                    'บันทึกมื้อนี้',
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNutrientBadge(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: secondaryTextColor)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  double _calculateExerciseCalories(String exercise, int minutes, int zone, double weightKg) {
    final Map<String, double> baseMets = {
      'วิ่ง': 7.0, 'เดินเร็ว': 4.3, 'เวท': 3.5,
      'เต้นแอโรบิก': 6.5, 'ปั่นจักรยาน': 7.0, 'บอดี้เวท': 4.5,
      'ว่ายน้ำ': 6.0, 'เตะบอล': 7.0, 'วอลเลย์': 4.0, 'แบดมินตัน': 5.5,
    };
    
    double met = baseMets[exercise] ?? 5.0;
    double multiplier = 1.0;
    if (zone == 3) multiplier = 1.3;
    if (zone == 4) multiplier = 1.6;
    if (zone == 5) multiplier = 2.0;

    return (met * multiplier) * weightKg * (minutes / 60.0);
  }

  void _deleteLog(bool isFood, int index) async {
    final list = isFood ? _todayFoods : _todayExercises;
    final item = list[index];
    
    if (item['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถลบได้: กำลังซิงค์ข้อมูลกับเซิร์ฟเวอร์'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final String id = item['id'].toString();
    
    setState(() {
      if (isFood) {
        _todayFoods.removeAt(index);
      } else {
        _todayExercises.removeAt(index);
      }
    });

    try {
      if (isFood) {
        await _databaseService.deleteFoodLog(id);
      } else {
        await _databaseService.deleteExerciseLog(id);
      }
      _loadDashboardData();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isFood) {
            _todayFoods.insert(index, item);
          } else {
            _todayExercises.insert(index, item);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showQuickExerciseModal() {
    String selectedExercise = 'วิ่ง';
    int selectedZone = 2;
    final customExerciseCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '30');

    final exercises = [
      'วิ่ง', 'เดินเร็ว', 'เวท', 'เต้นแอโรบิก', 'ปั่นจักรยาน',
      'บอดี้เวท', 'ว่ายน้ำ', 'เตะบอล', 'วอลเลย์', 'แบดมินตัน', 'อื่นๆ'
    ];
    final zones = [
      {'zone': 2, 'title': 'พูดเป็นประโยคได้สบาย', 'subtitle': 'Zone 2 (เบา-ปานกลาง)', 'color': const Color(0xFF2F9E82)},
      {'zone': 3, 'title': 'เริ่มหอบ พูดเป็นประโยคสั้นๆ', 'subtitle': 'Zone 3 (ปานกลาง-หนัก)', 'color': const Color(0xFFE8A33D)},
      {'zone': 4, 'title': 'หอบมาก พูดได้เป็นคำๆ', 'subtitle': 'Zone 4 (หนักมาก)', 'color': const Color(0xFFD97B4F)},
      {'zone': 5, 'title': 'หอบจนพูดไม่ได้เลย', 'subtitle': 'Zone 5 (วิกฤต/อันตราย)', 'color': const Color(0xFFEF4444)},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เพิ่มการออกกำลังกายด่วน',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 16),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: exercises.map((ex) {
                        final isSelected = selectedExercise == ex;
                        return ChoiceChip(
                          label: Text(ex),
                          selected: isSelected,
                          selectedColor: emeraldTheme.withValues(alpha: 0.15),
                          backgroundColor: softCardBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: isSelected ? emeraldTheme : const Color(0xFFEADBCE)),
                          ),
                          labelStyle: TextStyle(
                            color: isSelected ? emeraldTheme : primaryTextColor,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (bool selected) {
                            setModalState(() => selectedExercise = ex);
                          },
                        );
                      }).toList(),
                    ),
                    
                    if (selectedExercise == 'อื่นๆ') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: customExerciseCtrl,
                        decoration: InputDecoration(
                          hintText: 'พิมพ์ชื่อการออกกำลังกาย...',
                          filled: true,
                          fillColor: const Color(0xFFFAFAFA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEADBCE))),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    const Text('วัดความเหนื่อย (Talk Test)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    const SizedBox(height: 8),

                    ...zones.map((z) => RadioListTile<int>(
                      value: z['zone'] as int,
                      groupValue: selectedZone,
                      activeColor: z['color'] as Color,
                      title: Text(z['title'] as String, style: const TextStyle(fontSize: 14, color: primaryTextColor)),
                      subtitle: Text(
                        z['subtitle'] as String,
                        style: TextStyle(fontSize: 12, color: (z['color'] as Color).withValues(alpha: 0.85)),
                      ),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setModalState(() => selectedZone = val!),
                    )),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('เวลาที่ใช้: ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: durationCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              suffixText: 'นาที',
                              filled: true,
                              fillColor: const Color(0xFFFAFAFA),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEADBCE))),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emeraldTheme,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final duration = int.tryParse(durationCtrl.text) ?? 30;
                          final finalExercise = selectedExercise == 'อื่นๆ' ? customExerciseCtrl.text.trim() : selectedExercise;
                          
                          if (finalExercise.isEmpty) return;

                          final burned = _calculateExerciseCalories(finalExercise, duration, selectedZone, _weightKg);
                          Navigator.pop(ctx);
                          
                          try {
                            await _databaseService.saveQuickExercise(
                              patientId: _patientId!,
                              exerciseName: finalExercise,
                              durationMinutes: duration,
                              intensityZone: selectedZone,
                              caloriesBurned: burned,
                            );
                            _loadDashboardData();
                          } catch (e) {
                            debugPrint('Save Exercise Error: $e');
                          }
                        },
                        child: const Text('บันทึกข้อมูล', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showResetWeeklyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('ยืนยันรีเซ็ตข้อมูล 7 วัน', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
          ],
        ),
        content: const Text(
          'การกระทำนี้จะลบประวัติการบันทึกอาหารและการออกกำลังกายในช่วง 7 วันย้อนหลังทั้งหมด เพื่อให้คุณเริ่มต้นทดลองกรอกใหม่ได้ทันที ต้องการดำเนินการต่อหรือไม่?',
          style: TextStyle(fontSize: 14, color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: mutedTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _executeResetWeeklyData();
            },
            child: const Text('ยืนยันรีเซ็ต', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeResetWeeklyData() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null && patientId.isNotEmpty) {
        await _nutritionService.resetWeeklyLogs(patientId);
        await _loadDashboardData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ รีเซ็ตข้อมูล 7 วันเรียบร้อยแล้ว'),
              backgroundColor: emeraldTheme,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error resetting weekly logs: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถรีเซ็ตข้อมูลได้: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalFoodCals = _todayFoods.fold<double>(
      0.0,
      (sum, item) => sum + ((item['calories'] as num?)?.toDouble() ?? 0.0),
    );

    final totalBurnedCals = _todayExercises.fold<double>(
      0.0,
      (sum, item) => sum + ((item['calories_burned'] as num?)?.toDouble() ?? 0.0),
    );

    final targetDeficit = (_tdee - 400).clamp(1200.0, 9999.0);

    return Scaffold(
      backgroundColor: creamBgColor,
      appBar: AppBar(
        title: const Text(
          'อาหาร & กิจกรรมสุขภาพ',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldTheme))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCalorieBalanceCard(totalFoodCals, totalBurnedCals, targetDeficit),
                  const SizedBox(height: 16),

                  _buildExerciseClinicalGuardCard(),
                  const SizedBox(height: 16),

                  _buildVoiceAndTextFoodLoggerCard(),
                  const SizedBox(height: 20),

                  _buildSectionHeader(
                    'รายการอาหารวันนี้ (${_todayFoods.length})',
                    Icons.fastfood_outlined,
                  ),
                  const SizedBox(height: 8),
                  if (_todayFoods.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('ยังไม่มีการบันทึกอาหารวันนี้', style: TextStyle(color: mutedTextColor)),
                    )
                  else
                    ..._todayFoods.asMap().entries.map((entry) {
                      final index = entry.key;
                      final f = entry.value;
                      return Dismissible(
                        key: Key('food_${f['id'] ?? index}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) => _deleteLog(true, index),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF0E5D8)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: terracottaTheme.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.lunch_dining, color: terracottaTheme, size: 22),
                            ),
                            title: Text(
                              f['food_name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            subtitle: Text(
                              'โซเดียม: ${f['sodium_mg'] ?? 0} mg | น้ำตาล: ${f['sugar_g'] ?? 0}g',
                              style: const TextStyle(color: secondaryTextColor, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${f['calories'] ?? 0} kcal',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: terracottaTheme,
                                    fontSize: 15,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                                  onPressed: () => _deleteLog(true, index),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader(
                        'การออกกำลังกาย (${_todayExercises.length})',
                        Icons.directions_run,
                      ),
                      TextButton.icon(
                        onPressed: _showQuickExerciseModal,
                        icon: const Icon(Icons.add, color: emeraldTheme, size: 18),
                        label: const Text(
                          'เพิ่มกิจกรรม',
                          style: TextStyle(color: emeraldTheme, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_todayExercises.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('ยังไม่มีการบันทึกกิจกรรมวันนี้', style: TextStyle(color: mutedTextColor)),
                    )
                  else
                    ..._todayExercises.asMap().entries.map((entry) {
                      final index = entry.key;
                      final ex = entry.value;
                      final exName = ex['exercise_type'] ?? ex['exercise_name'] ?? '';
                      final zone = ex['intensity_zone'];
                      final zoneText = zone != null ? ' (Zone $zone)' : '';

                      return Dismissible(
                        key: Key('ex_${ex['id'] ?? index}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) => _deleteLog(false, index),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF0E5D8)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.fitness_center, color: Colors.blue, size: 22),
                            ),
                            title: Text(
                              '$exName$zoneText',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            subtitle: Text(
                              '${ex['duration_minutes'] ?? 0} นาที',
                              style: const TextStyle(color: secondaryTextColor, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '-${ex['calories_burned'] ?? 0} kcal',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: emeraldTheme,
                                    fontSize: 15,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                                  onPressed: () => _deleteLog(false, index),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),

                  _buildWeeklySummaryCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildVoiceAndTextFoodLoggerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'บันทึกอาหาร & AI วิเคราะห์',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
              Icon(Icons.auto_awesome, color: terracottaTheme),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _foodInputController,
            maxLines: 2,
            style: const TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              hintText: 'พิมพ์ชื่ออาหาร เช่น: สลัดอกไก่ 7-11, เกาเหลาเลือดหมู, ข้าวสวย 1 ชาม',
              hintStyle: const TextStyle(color: mutedTextColor, fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFEADBCE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFEADBCE)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: terracottaTheme, width: 1.5),
              ),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              prefixIcon: const Icon(Icons.restaurant, color: terracottaTheme),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _analyzeAndLogFoodFromText,
              style: ElevatedButton.styleFrom(
                backgroundColor: terracottaTheme,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _isAnalyzing ? 'AI กำลังวิเคราะห์...' : 'วิเคราะห์สารอาหาร',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalorieBalanceCard(double food, double burned, double target) {
    final net = food - burned;
    final diff = target - net;
    
    String emoji = '😊';
    String message = 'ยอดเยี่ยม! พลังงานสุทธิอยู่ในเกณฑ์ดี';
    Color statusColor = emeraldTheme;

    if (diff < -200) {
      emoji = '😱';
      message = 'ระวัง! วันนี้กินเกินเป้าไป ${diff.abs().toStringAsFixed(0)} kcal แล้ว';
      statusColor = const Color(0xFFDC2626);
    } else if (diff > 500) {
      emoji = '🤔';
      message = 'พลังงานยังขาดอีก ${diff.toStringAsFixed(0)} kcal ควรทานเพิ่มอีกนิดนะคะ';
      statusColor = const Color(0xFFE8A33D);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('พลังงานสุทธิวันนี้ (Net Calories)', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      '${net.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                    const SizedBox(height: 2),
                    Text(message, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF5ECE1)),
          const SizedBox(height: 14),
          _buildMacroTracker(),
        ],
      ),
    );
  }

  Widget _buildMacroTracker() {
    double totalProtein = _todayFoods.fold(0, (sum, item) => sum + ((item['protein_g'] as num?)?.toDouble() ?? 0.0));
    double totalCarbs = _todayFoods.fold(0, (sum, item) => sum + ((item['carbs_g'] as num?)?.toDouble() ?? 0.0));
    double totalSodium = _todayFoods.fold(0, (sum, item) => sum + ((item['sodium_mg'] as num?)?.toDouble() ?? 0.0));

    double targetProtein = _weightKg * 0.8;
    double targetCarbs = 150.0;
    double targetSodium = 2000.0;

    return Column(
      children: [
        _buildProgressBar('โปรตีน (g)', totalProtein, targetProtein, Colors.blue),
        const SizedBox(height: 10),
        _buildProgressBar('คาร์โบไฮเดรต (g)', totalCarbs, targetCarbs, Colors.orange),
        const SizedBox(height: 10),
        _buildProgressBar('โซเดียม (mg)', totalSodium, targetSodium, const Color(0xFFDC2626), isLimitCheck: true),
      ],
    );
  }

  Widget _buildProgressBar(String label, double current, double target, Color color, {bool isLimitCheck = false}) {
    double progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    bool isDanger = isLimitCheck && current > target;

    return Row(
      children: [
        SizedBox(width: 95, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: const Color(0xFFF0E5D8),
              valueColor: AlwaysStoppedAnimation<Color>(isDanger ? const Color(0xFFDC2626) : color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            '${current.toStringAsFixed(0)}/${target.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDanger ? const Color(0xFFDC2626) : secondaryTextColor,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  } 

  Widget _buildExerciseClinicalGuardCard() {
    final isHighBp = _latestSystolic >= 160;
    final isLowBp = _latestSystolic <= 90;

    Color cardBg = isHighBp
        ? const Color(0xFFFEF2F2)
        : (isLowBp ? const Color(0xFFFFF7ED) : const Color(0xFFEAF3E4));
    Color borderColor = isHighBp
        ? const Color(0xFFFCA5A5)
        : (isLowBp ? const Color(0xFFFCD34D) : const Color(0xFFBCE3AA));
    IconData icon = isHighBp
        ? Icons.warning_rounded
        : (isLowBp ? Icons.info_outline : Icons.check_circle_outline);
    Color iconColor =
        isHighBp ? const Color(0xFFDC2626) : (isLowBp ? const Color(0xFFD97706) : emeraldTheme);

    String title = isHighBp
        ? '⚠️ ความดันตัวบนวันนี้สูง ($_latestSystolic mmHg) - งดออกแรงหนัก'
        : (isLowBp
            ? '⚠️ ความดันตัวบนค่อนข้างต่ำ ($_latestSystolic mmHg) - ระวังหน้ามืด'
            : '✅ ความดันปกติ ($_latestSystolic mmHg) - ออกกำลังกายได้ปลอดภัย');

    String desc = isHighBp
        ? 'งดการวิ่งหรือยกน้ำหนักหนักในวันนี้ แนะนำฝึกสมาธิ กำหนดลมหายใจ และพักผ่อน'
        : (isLowBp
            ? 'ควรจิบน้ำบ่อยๆ หลีกเลี่ยงการเปลี่ยนท่าทางกะทันหัน เน้นการยืดเหยียดเบาๆ'
            : 'แนะนำออกกำลังกายแบบแอโรบิกปานกลาง เช่น เดินเร็ว 20-30 นาที/วัน');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: iconColor)),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(fontSize: 12, color: primaryTextColor, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: terracottaTheme, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
        ),
      ],
    );
  }

  Widget _buildWeeklySummaryCard() {
    if (_weeklySummary == null) return const SizedBox.shrink();

    final avgFood = (_weeklySummary!['avgDailyFoodCals'] as double?) ?? 0.0;
    final avgBurn = (_weeklySummary!['avgDailyBurnedCals'] as double?) ?? 0.0;
    final protein = (_weeklySummary!['totalProtein'] as double?) ?? 0.0;
    final carbs = (_weeklySummary!['totalCarbs'] as double?) ?? 0.0;
    final fat = (_weeklySummary!['totalFat'] as double?) ?? 0.0;
    final totalMacro = protein + carbs + fat;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.donut_large, color: terracottaTheme, size: 22),
              SizedBox(width: 8),
              Text(
                'สัดส่วนสารอาหารและภาพรวม 7 วัน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: CustomPaint(
                painter: _DonutChartPainter(
                  protein: protein,
                  carbs: carbs,
                  fat: fat,
                  total: totalMacro,
                  strokeWidth: 20.0,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        avgFood.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
                      ),
                      const Text('kcal/วัน', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegendItem('โปรตีน', Colors.blue, protein, totalMacro),
              _buildLegendItem('คาร์บ', Colors.orange, carbs, totalMacro),
              _buildLegendItem('ไขมัน', Colors.redAccent, fat, totalMacro),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF5ECE1)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatMiniItem('กินเฉลี่ย/วัน', '${avgFood.toStringAsFixed(0)} kcal', terracottaTheme),
              Container(width: 1, height: 28, color: const Color(0xFFEADBCE)),
              _buildStatMiniItem('เผาผลาญเฉลี่ย/วัน', '${avgBurn.toStringAsFixed(0)} kcal', emeraldTheme),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showResetWeeklyDialog(context),
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFFDC2626), size: 18),
              label: const Text(
                'รีเซ็ตข้อมูลทดลอง 7 วัน',
                style: TextStyle(color: Color(0xFFDC2626), fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, double val, double total) {
    final pct = total > 0 ? (val / total * 100).toStringAsFixed(0) : '0';
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: secondaryTextColor)),
        const SizedBox(width: 4),
        Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
      ],
    );
  }

  Widget _buildStatMiniItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: secondaryTextColor)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double protein;
  final double carbs;
  final double fat;
  final double total;
  final double strokeWidth;

  _DonutChartPainter({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.total,
    this.strokeWidth = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (total <= 0) {
      paint.color = const Color(0xFFEADBCE);
      canvas.drawCircle(center, radius - strokeWidth / 2, paint);
      return;
    }

    double startAngle = -3.141592653589793 / 2;

    final sweepProtein = (protein / total) * 2 * 3.141592653589793;
    paint.color = Colors.blue;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweepProtein, false, paint);
    startAngle += sweepProtein;

    final sweepCarbs = (carbs / total) * 2 * 3.141592653589793;
    paint.color = Colors.orange;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweepCarbs, false, paint);
    startAngle += sweepCarbs;

    final sweepFat = (fat / total) * 2 * 3.141592653589793;
    paint.color = Colors.redAccent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweepFat, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
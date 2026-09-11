import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/patient_profile_service.dart';
import '../services/nutrition_service.dart';
import '../services/vital_repository.dart';
import '../services/patient_database_service.dart';
import 'package:image_picker/image_picker.dart';

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
  double _bmr = 0.0;
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

  double _profileNumber(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      final profile = await _profileService.validateAndLoadProfile() ??
          await _profileService.getProfile();

      if (patientId != null) {
        _patientId = patientId;
        _bmr = _profileNumber(profile?['bmr']);
        _tdee = _profileNumber(profile?['tdee'], 2000.0);
        _weightKg = _profileNumber(profile?['weight_kg'], 60.0);
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
                  CustomPaint(
                    size: const Size(28, 28),
                    painter: _ForkSpoonVectorPainter(color: terracottaTheme),
                  ),
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
                    CustomPaint(
                      size: const Size(36, 36),
                      painter: _FlameVectorPainter(color: terracottaTheme),
                    ),
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
                      Row(
                        children: [
                          CustomPaint(
                            size: const Size(22, 22),
                            painter: _WarningVectorPainter(color: const Color(0xFFDC2626)),
                          ),
                          const SizedBox(width: 8),
                          const Text(
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

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickAndAnalyzeFoodImage(ImageSource source) async {
    if (_patientId == null) return;

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );

      if (pickedFile == null) return;

      setState(() => _isAnalyzing = true);

      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';

      final result = await _nutritionService.analyzeFoodFromImage(
        imageBytes: bytes,
        mimeType: mimeType,
        underlyingDiseases: _underlyingDiseases,
      );

      if (result != null && mounted) {
        _showFoodConfirmDialog(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถวิเคราะห์ภาพถ่ายอาหารได้ กรุณาลองใหม่อีกครั้ง'),
              backgroundColor: terracottaTheme,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking/analyzing food image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเปิดกล้อง/รูปภาพ: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
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

                    RadioGroup<int>(
                      groupValue: selectedZone,
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedZone = val);
                        }
                      },
                      child: Column(
                        children: zones
                            .map((z) => RadioListTile<int>(
                                  value: z['zone'] as int,
                                  activeColor: z['color'] as Color,
                                  title: Text(
                                    z['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
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
        title: Row(
          children: [
            CustomPaint(
              size: const Size(22, 22),
              painter: _WarningVectorPainter(color: const Color(0xFFDC2626)),
            ),
            const SizedBox(width: 8),
            const Text('ยืนยันรีเซ็ตข้อมูล 7 วัน', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
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

    final double targetEnergy = _tdee > 0 ? _tdee : (_bmr > 0 ? _bmr : 1500.0);

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
          icon: CustomPaint(
            size: const Size(18, 18),
            painter: _ArrowBackVectorPainter(color: primaryTextColor),
          ),
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
                  _buildCalorieBalanceCard(totalFoodCals, totalBurnedCals, targetEnergy),
                  const SizedBox(height: 16),

                  _buildExerciseClinicalGuardCard(),
                  const SizedBox(height: 16),

                  _buildVoiceAndTextFoodLoggerCard(),
                  const SizedBox(height: 20),

                  _buildSectionHeader(
                    'รายการอาหารวันนี้ (${_todayFoods.length})',
                    NutritionHeaderIconType.food,
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
                          child: CustomPaint(
                            size: const Size(22, 22),
                            painter: _TrashVectorPainter(color: Colors.white),
                          ),
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
                              child: CustomPaint(
                                size: const Size(22, 22),
                                painter: _ForkSpoonVectorPainter(color: terracottaTheme),
                              ),
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
                                  icon: CustomPaint(
                                    size: const Size(18, 18),
                                    painter: _TrashVectorPainter(color: const Color(0xFFDC2626)),
                                  ),
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
                        NutritionHeaderIconType.exercise,
                      ),
                      TextButton(
                        onPressed: _showQuickExerciseModal,
                        child: Row(
                          children: [
                            CustomPaint(
                              size: const Size(14, 14),
                              painter: _PlusVectorPainter(color: emeraldTheme),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'เพิ่มกิจกรรม',
                              style: TextStyle(color: emeraldTheme, fontWeight: FontWeight.bold),
                            ),
                          ],
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
                          child: CustomPaint(
                            size: const Size(22, 22),
                            painter: _TrashVectorPainter(color: Colors.white),
                          ),
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
                              child: CustomPaint(
                                size: const Size(22, 22),
                                painter: _DumbbellVectorPainter(color: Colors.blue),
                              ),
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
                                  icon: CustomPaint(
                                    size: const Size(18, 18),
                                    painter: _TrashVectorPainter(color: const Color(0xFFDC2626)),
                                  ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'บันทึกอาหาร & AI วิเคราะห์',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
              CustomPaint(
                size: const Size(20, 20),
                painter: _SparkleVectorPainter(color: terracottaTheme),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _pickAndAnalyzeFoodImage(ImageSource.camera),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: terracottaTheme, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: terracottaTheme.withValues(alpha: 0.05),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(18, 18),
                        painter: _CameraVectorPainter(color: terracottaTheme),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'ถ่ายรูปอาหาร',
                        style: TextStyle(color: terracottaTheme, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _pickAndAnalyzeFoodImage(ImageSource.gallery),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEADBCE), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: softCardBg,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(18, 18),
                        painter: _GalleryVectorPainter(color: secondaryTextColor),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'เลือกจากคลัง',
                        style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _foodInputController,
            maxLines: 2,
            style: const TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              hintText: 'หรือพิมพ์ชื่ออาหาร เช่น: สลัดอกไก่ 7-11, เกาเหลาเลือดหมู',
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
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: CustomPaint(
                  size: const Size(18, 18),
                  painter: _ForkSpoonVectorPainter(color: terracottaTheme),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isAnalyzing ? null : _analyzeAndLogFoodFromText,
              style: ElevatedButton.styleFrom(
                backgroundColor: terracottaTheme,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isAnalyzing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  else
                    CustomPaint(
                      size: const Size(18, 18),
                      painter: _SendVectorPainter(color: Colors.white),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _isAnalyzing ? 'AI กำลังวิเคราะห์ภาพ/ข้อความ...' : 'วิเคราะห์จากข้อความ',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
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

    GuardIconType guardType = isHighBp
        ? GuardIconType.warning
        : (isLowBp ? GuardIconType.info : GuardIconType.check);

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
          CustomPaint(
            size: const Size(24, 24),
            painter: _GuardStatusVectorPainter(type: guardType, color: iconColor),
          ),
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

  Widget _buildSectionHeader(String title, NutritionHeaderIconType iconType) {
    return Row(
      children: [
        CustomPaint(
          size: const Size(20, 20),
          painter: _SectionHeaderVectorPainter(type: iconType, color: terracottaTheme),
        ),
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
          Row(
            children: [
              CustomPaint(
                size: const Size(22, 22),
                painter: _DonutMiniIconPainter(color: terracottaTheme),
              ),
              const SizedBox(width: 8),
              const Text(
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
            child: OutlinedButton(
              onPressed: () => _showResetWeeklyDialog(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomPaint(
                    size: const Size(18, 18),
                    painter: _ResetVectorPainter(color: const Color(0xFFDC2626)),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'รีเซ็ตข้อมูลทดลอง 7 วัน',
                    style: TextStyle(color: Color(0xFFDC2626), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
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

// =========================================================================
// 🎨 Pure Canvas Vector Painters (100% Canvas Vector - No Icon Font Needed)
// =========================================================================

enum NutritionHeaderIconType {
  food,
  exercise,
}

enum GuardIconType {
  warning,
  info,
  check,
}

class _ArrowBackVectorPainter extends CustomPainter {
  final Color color;
  _ArrowBackVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(w * 0.65, h * 0.15)
      ..lineTo(w * 0.30, h * 0.50)
      ..lineTo(w * 0.65, h * 0.85);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowBackVectorPainter old) => old.color != color;
}

class _ForkSpoonVectorPainter extends CustomPainter {
  final Color color;
  _ForkSpoonVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // ส้อม (ซ้าย)
    final fork = Path()
      ..moveTo(w * 0.22, h * 0.15)
      ..lineTo(w * 0.22, h * 0.45)
      ..cubicTo(w * 0.22, h * 0.55, w * 0.38, h * 0.55, w * 0.38, h * 0.45)
      ..lineTo(w * 0.38, h * 0.15)
      ..moveTo(w * 0.30, h * 0.15)
      ..lineTo(w * 0.30, h * 0.48)
      ..moveTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.30, h * 0.88);
    canvas.drawPath(fork, stroke);

    // ช้อน (ขวา)
    final spoon = Path()
      ..addOval(Rect.fromLTWH(w * 0.58, h * 0.15, w * 0.24, h * 0.38))
      ..moveTo(w * 0.70, h * 0.53)
      ..lineTo(w * 0.70, h * 0.88);
    canvas.drawPath(spoon, stroke);
  }

  @override
  bool shouldRepaint(covariant _ForkSpoonVectorPainter old) => old.color != color;
}

class _FlameVectorPainter extends CustomPainter {
  final Color color;
  _FlameVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.05)
      ..cubicTo(w * 0.65, h * 0.25, w * 0.85, h * 0.45, w * 0.85, h * 0.68)
      ..cubicTo(w * 0.85, h * 0.88, w * 0.70, h * 0.95, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.30, h * 0.95, w * 0.15, h * 0.88, w * 0.15, h * 0.68)
      ..cubicTo(w * 0.15, h * 0.48, w * 0.32, h * 0.30, w * 0.42, h * 0.20)
      ..cubicTo(w * 0.40, h * 0.38, w * 0.52, h * 0.48, w * 0.58, h * 0.38)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _FlameVectorPainter old) => old.color != color;
}

class _WarningVectorPainter extends CustomPainter {
  final Color color;
  _WarningVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.12)
      ..lineTo(w * 0.88, h * 0.82)
      ..lineTo(w * 0.12, h * 0.82)
      ..close();
    canvas.drawPath(path, stroke);

    final fill = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(w * 0.46, h * 0.38, w * 0.08, h * 0.22), fill);
    canvas.drawCircle(Offset(w * 0.50, h * 0.70), w * 0.04, fill);
  }

  @override
  bool shouldRepaint(covariant _WarningVectorPainter old) => old.color != color;
}

class _TrashVectorPainter extends CustomPainter {
  final Color color;
  _TrashVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // ฝาถัง
    canvas.drawLine(Offset(w * 0.18, h * 0.28), Offset(w * 0.82, h * 0.28), stroke);
    final handle = Path()
      ..moveTo(w * 0.38, h * 0.28)
      ..lineTo(w * 0.38, h * 0.16)
      ..lineTo(w * 0.62, h * 0.16)
      ..lineTo(w * 0.62, h * 0.28);
    canvas.drawPath(handle, stroke);

    // ตัวถัง
    final body = Path()
      ..moveTo(w * 0.25, h * 0.28)
      ..lineTo(w * 0.30, h * 0.86)
      ..lineTo(w * 0.70, h * 0.86)
      ..lineTo(w * 0.75, h * 0.28);
    canvas.drawPath(body, stroke);

    // ขีดแนวตั้ง 2 ขีด
    canvas.drawLine(Offset(w * 0.42, h * 0.40), Offset(w * 0.42, h * 0.74), stroke);
    canvas.drawLine(Offset(w * 0.58, h * 0.40), Offset(w * 0.58, h * 0.74), stroke);
  }

  @override
  bool shouldRepaint(covariant _TrashVectorPainter old) => old.color != color;
}

class _PlusVectorPainter extends CustomPainter {
  final Color color;
  _PlusVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(w / 2, h * 0.15), Offset(w / 2, h * 0.85), paint);
    canvas.drawLine(Offset(w * 0.15, h / 2), Offset(w * 0.85, h / 2), paint);
  }

  @override
  bool shouldRepaint(covariant _PlusVectorPainter old) => old.color != color;
}

class _DumbbellVectorPainter extends CustomPainter {
  final Color color;
  _DumbbellVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // แกนจับ
    canvas.drawLine(Offset(w * 0.30, h * 0.50), Offset(w * 0.70, h * 0.50), stroke);

    // ตุ้มซ้าย
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.25, w * 0.10, h * 0.50), const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.12, h * 0.32, w * 0.08, h * 0.36), const Radius.circular(2)),
      paint,
    );

    // ตุ้มขวา
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.70, h * 0.25, w * 0.10, h * 0.50), const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.80, h * 0.32, w * 0.08, h * 0.36), const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DumbbellVectorPainter old) => old.color != color;
}

class _SparkleVectorPainter extends CustomPainter {
  final Color color;
  _SparkleVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.10)
      ..cubicTo(w * 0.50, h * 0.35, w * 0.65, h * 0.50, w * 0.90, h * 0.50)
      ..cubicTo(w * 0.65, h * 0.50, w * 0.50, h * 0.65, w * 0.50, h * 0.90)
      ..cubicTo(w * 0.50, h * 0.65, w * 0.35, h * 0.50, w * 0.10, h * 0.50)
      ..cubicTo(w * 0.35, h * 0.50, w * 0.50, h * 0.35, w * 0.50, h * 0.10)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _SparkleVectorPainter old) => old.color != color;
}

class _CameraVectorPainter extends CustomPainter {
  final Color color;
  _CameraVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.28, w * 0.76, h * 0.58),
      const Radius.circular(4),
    );
    canvas.drawRRect(body, stroke);

    final topPart = Path()
      ..moveTo(w * 0.34, h * 0.28)
      ..lineTo(w * 0.40, h * 0.16)
      ..lineTo(w * 0.60, h * 0.16)
      ..lineTo(w * 0.66, h * 0.28);
    canvas.drawPath(topPart, stroke);

    canvas.drawCircle(Offset(w * 0.50, h * 0.57), w * 0.18, stroke);
  }

  @override
  bool shouldRepaint(covariant _CameraVectorPainter old) => old.color != color;
}

class _GalleryVectorPainter extends CustomPainter {
  final Color color;
  _GalleryVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.16, w * 0.76, h * 0.68),
      const Radius.circular(4),
    );
    canvas.drawRRect(frame, stroke);

    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.32, h * 0.36), w * 0.08, fill);

    final mountain = Path()
      ..moveTo(w * 0.18, h * 0.76)
      ..lineTo(w * 0.42, h * 0.52)
      ..lineTo(w * 0.58, h * 0.66)
      ..lineTo(w * 0.72, h * 0.48)
      ..lineTo(w * 0.82, h * 0.76);
    canvas.drawPath(mountain, stroke);
  }

  @override
  bool shouldRepaint(covariant _GalleryVectorPainter old) => old.color != color;
}

class _SendVectorPainter extends CustomPainter {
  final Color color;
  _SendVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;

    final path = Path()
      ..moveTo(w * 0.12, h * 0.15)
      ..lineTo(w * 0.90, h * 0.50)
      ..lineTo(w * 0.12, h * 0.85)
      ..lineTo(w * 0.28, h * 0.50)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _SendVectorPainter old) => old.color != color;
}

class _GuardStatusVectorPainter extends CustomPainter {
  final GuardIconType type;
  final Color color;

  _GuardStatusVectorPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final fill = Paint()..color = color;

    switch (type) {
      case GuardIconType.warning:
        final path = Path()
          ..moveTo(w * 0.50, h * 0.12)
          ..lineTo(w * 0.90, h * 0.85)
          ..lineTo(w * 0.10, h * 0.85)
          ..close();
        canvas.drawPath(path, stroke);
        canvas.drawRect(Rect.fromLTWH(w * 0.46, h * 0.38, w * 0.08, h * 0.24), fill);
        canvas.drawCircle(Offset(w * 0.50, h * 0.72), w * 0.045, fill);
        break;

      case GuardIconType.info:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.42, stroke);
        canvas.drawCircle(Offset(w * 0.50, h * 0.32), w * 0.06, fill);
        canvas.drawRect(Rect.fromLTWH(w * 0.44, h * 0.45, w * 0.12, h * 0.28), fill);
        break;

      case GuardIconType.check:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.42, stroke);
        final check = Path()
          ..moveTo(w * 0.30, h * 0.50)
          ..lineTo(w * 0.45, h * 0.66)
          ..lineTo(w * 0.72, h * 0.36);
        canvas.drawPath(check, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _GuardStatusVectorPainter old) =>
      old.type != type || old.color != color;
}

class _SectionHeaderVectorPainter extends CustomPainter {
  final NutritionHeaderIconType type;
  final Color color;

  _SectionHeaderVectorPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    if (type == NutritionHeaderIconType.food) {
      // แฮมเบอร์เกอร์ / จานอาหาร
      canvas.drawArc(Rect.fromLTWH(w * 0.15, h * 0.20, w * 0.70, h * 0.35), math.pi, math.pi, false, stroke);
      canvas.drawLine(Offset(w * 0.15, h * 0.55), Offset(w * 0.85, h * 0.55), stroke);
      canvas.drawLine(Offset(w * 0.20, h * 0.68), Offset(w * 0.80, h * 0.68), stroke);
      final bottomBun = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.72, w * 0.64, h * 0.16),
        const Radius.circular(3),
      );
      canvas.drawRRect(bottomBun, stroke);
    } else {
      // คนวิ่ง
      canvas.drawCircle(Offset(w * 0.62, h * 0.20), w * 0.12, stroke);
      final runner = Path()
        ..moveTo(w * 0.55, h * 0.35)
        ..lineTo(w * 0.45, h * 0.52)
        ..lineTo(w * 0.65, h * 0.65)
        ..lineTo(w * 0.75, h * 0.85)
        ..moveTo(w * 0.45, h * 0.52)
        ..lineTo(w * 0.30, h * 0.68)
        ..lineTo(w * 0.22, h * 0.85)
        ..moveTo(w * 0.52, h * 0.40)
        ..lineTo(w * 0.35, h * 0.36)
        ..moveTo(w * 0.52, h * 0.40)
        ..lineTo(w * 0.68, h * 0.48);
      canvas.drawPath(runner, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SectionHeaderVectorPainter old) =>
      old.type != type || old.color != color;
}

class _DonutMiniIconPainter extends CustomPainter {
  final Color color;
  _DonutMiniIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.36, stroke);
  }

  @override
  bool shouldRepaint(covariant _DonutMiniIconPainter old) => old.color != color;
}

class _ResetVectorPainter extends CustomPainter {
  final Color color;
  _ResetVectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCenter(center: Offset(w / 2, h / 2), width: w * 0.70, height: h * 0.70),
      -math.pi / 2,
      1.6 * math.pi,
      false,
      stroke,
    );

    final arrow = Path()
      ..moveTo(w * 0.40, h * 0.05)
      ..lineTo(w * 0.55, h * 0.15)
      ..lineTo(w * 0.40, h * 0.25);
    canvas.drawPath(arrow, stroke);
  }

  @override
  bool shouldRepaint(covariant _ResetVectorPainter old) => old.color != color;
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

    double startAngle = -math.pi / 2;

    final sweepProtein = (protein / total) * 2 * math.pi;
    paint.color = Colors.blue;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweepProtein, false, paint);
    startAngle += sweepProtein;

    final sweepCarbs = (carbs / total) * 2 * math.pi;
    paint.color = Colors.orange;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweepCarbs, false, paint);
    startAngle += sweepCarbs;

    final sweepFat = (fat / total) * 2 * math.pi;
    paint.color = Colors.redAccent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweepFat, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
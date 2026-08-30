import 'package:flutter/material.dart';
import '../services/patient_database_service.dart';
import '../services/patient_profile_service.dart';
import 'home_screen.dart';

enum OnboardingStep {
  firstName,
  lastName,
  age,
  gender,
  diseases,
  medication,
  weight,
  height,
  confirmation,
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final PatientDatabaseService _dbService = PatientDatabaseService();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _diseasesController = TextEditingController();
  final TextEditingController _medicationController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  // 🎨 Palette สีหลักตาม Design System
  static const Color creamBgColor = Color(0xFFFFF8F0);
  static const Color primaryTextColor = Color(0xFF4A3833);
  static const Color secondaryTextColor = Color(0xFF8A7568);
  static const Color mutedTextColor = Color(0xFFB3A69B);
  static const Color emeraldTheme = Color(0xFF2F9E82);
  static const Color softCardBg = Color(0xFFFBF6EE);

  final List<String> _genderOptions = ['ชาย', 'หญิง', 'ไม่ระบุ'];
  String _selectedGender = 'ไม่ระบุ';
  OnboardingStep _currentStep = OnboardingStep.firstName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    _diseasesController.dispose();
    _medicationController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProfile() async {
    final profile = await _profileService.getProfile();
    if (!mounted) return;

    setState(() {
      _firstNameController.text = (profile?['first_name'] ?? '').toString();
      _lastNameController.text = (profile?['last_name'] ?? '').toString();
      _ageController.text = (profile?['age'] ?? '').toString();
      final storedGender = (profile?['gender'] ?? 'ไม่ระบุ').toString();
      if (_genderOptions.contains(storedGender)) {
        _selectedGender = storedGender;
      }
      _diseasesController.text = (profile?['underlying_diseases'] ?? '').toString();
      _weightController.text = (profile?['weight_kg'] ?? '').toString();
      _heightController.text = (profile?['height_cm'] ?? '').toString();
    });
  }

  String _questionTextForStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.firstName:
        return 'กรุณากรอกชื่อของคุณ';
      case OnboardingStep.lastName:
        return 'กรุณากรอกนามสกุลของคุณ';
      case OnboardingStep.age:
        return 'อายุของคุณคือเท่าไหร่';
      case OnboardingStep.gender:
        return 'เพศกำเนิดของคุณคือ';
      case OnboardingStep.diseases:
        return 'โรคประจำตัวของคุณคืออะไร';
      case OnboardingStep.medication:
        return 'ยาที่ทานประจำอยู่มีอะไรบ้าง';
      case OnboardingStep.weight:
        return 'น้ำหนักปัจจุบันของคุณ (กก.)';
      case OnboardingStep.height:
        return 'ส่วนสูงปัจจุบันของคุณ (ซม.)';
      case OnboardingStep.confirmation:
        return 'ตรวจสอบข้อมูลก่อนบันทึก';
    }
  }

  String? _validateCurrentStep() {
    switch (_currentStep) {
      case OnboardingStep.firstName:
        if (_firstNameController.text.trim().isEmpty) {
          return 'กรุณากรอกชื่อให้ครบถ้วน';
        }
        return null;
      case OnboardingStep.lastName:
        if (_lastNameController.text.trim().isEmpty) {
          return 'กรุณากรอกนามสกุลให้ครบถ้วน';
        }
        return null;
      case OnboardingStep.age:
        if (_ageController.text.trim().isEmpty) {
          return 'กรุณากรอกอายุ';
        }
        final age = int.tryParse(_ageController.text.trim());
        if (age == null || age <= 0) {
          return 'อายุต้องเป็นตัวเลขที่มากกว่า 0';
        }
        return null;
      case OnboardingStep.gender:
        if (_selectedGender.isEmpty) {
          return 'กรุณาเลือกเพศ';
        }
        return null;
      case OnboardingStep.diseases:
        return null;
      case OnboardingStep.medication:
        return null;
      case OnboardingStep.weight:
        if (_weightController.text.trim().isEmpty) {
          return 'กรุณากรอกน้ำหนัก';
        }
        final weight = double.tryParse(_weightController.text.trim());
        if (weight == null || weight <= 0) {
          return 'น้ำหนักต้องเป็นตัวเลขที่มากกว่า 0';
        }
        return null;
      case OnboardingStep.height:
        if (_heightController.text.trim().isEmpty) {
          return 'กรุณากรอกส่วนสูง';
        }
        final height = double.tryParse(_heightController.text.trim());
        if (height == null || height <= 0) {
          return 'ส่วนสูงต้องเป็นตัวเลขที่มากกว่า 0';
        }
        return null;
      case OnboardingStep.confirmation:
        return null;
    }
  }

  void _goToNextStep() {
    if (_currentStep == OnboardingStep.confirmation) {
      return;
    }

    final validationMessage = _validateCurrentStep();
    if (validationMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationMessage),
          backgroundColor: const Color(0xFFD97B4F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() {
      switch (_currentStep) {
        case OnboardingStep.firstName:
          _currentStep = OnboardingStep.lastName;
          break;
        case OnboardingStep.lastName:
          _currentStep = OnboardingStep.age;
          break;
        case OnboardingStep.age:
          _currentStep = OnboardingStep.gender;
          break;
        case OnboardingStep.gender:
          _currentStep = OnboardingStep.diseases;
          break;
        case OnboardingStep.diseases:
          _currentStep = OnboardingStep.medication;
          break;
        case OnboardingStep.medication:
          _currentStep = OnboardingStep.weight;
          break;
        case OnboardingStep.weight:
          _currentStep = OnboardingStep.height;
          break;
        case OnboardingStep.height:
          _currentStep = OnboardingStep.confirmation;
          _showConfirmationDialog();
          break;
        case OnboardingStep.confirmation:
          break;
      }
    });
  }

  void _skipToReview() {
    setState(() => _currentStep = OnboardingStep.confirmation);
    _showConfirmationDialog();
  }

  void _showConfirmationDialog() {
    final firstNameController =
        TextEditingController(text: _firstNameController.text.trim());
    final lastNameController =
        TextEditingController(text: _lastNameController.text.trim());
    final ageController = TextEditingController(text: _ageController.text.trim());
    final diseaseController =
        TextEditingController(text: _diseasesController.text.trim());
    final medicationController =
        TextEditingController(text: _medicationController.text.trim());
    final weightController = TextEditingController(text: _weightController.text.trim());
    final heightController = TextEditingController(text: _heightController.text.trim());

    String currentGender = _selectedGender;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Row(
              children: [
                Icon(Icons.fact_check_rounded, color: emeraldTheme, size: 26),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ตรวจสอบข้อมูลก่อนบันทึก',
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
                  const Text(
                    'กรุณาตรวจทานข้อมูลให้ถูกต้องก่อนกดบันทึก',
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                  const SizedBox(height: 16),
                  _confirmationField('ชื่อ', firstNameController),
                  const SizedBox(height: 12),
                  _confirmationField('นามสกุล', lastNameController),
                  const SizedBox(height: 12),
                  _confirmationField(
                    'อายุ',
                    ageController,
                    inputType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'เพศกำเนิด',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _genderOptions.map((gender) {
                      final selected = currentGender == gender;
                      return ChoiceChip(
                        label: Text(gender),
                        selected: selected,
                        selectedColor: emeraldTheme.withValues(alpha: 0.15),
                        backgroundColor: softCardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected ? emeraldTheme : const Color(0xFFEADBCE),
                          ),
                        ),
                        labelStyle: TextStyle(
                          color: selected ? emeraldTheme : primaryTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setDialogState(() => currentGender = gender);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _confirmationField('โรคประจำตัว', diseaseController, maxLines: 2),
                  const SizedBox(height: 12),
                  _confirmationField('ยาที่ทานประจำ', medicationController, maxLines: 2),
                  const SizedBox(height: 12),
                  _confirmationField(
                    'น้ำหนัก (กก.)',
                    weightController,
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  _confirmationField(
                    'ส่วนสูง (ซม.)',
                    heightController,
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _currentStep = OnboardingStep.firstName);
                },
                child: const Text('กลับไปแก้ไข', style: TextStyle(color: mutedTextColor)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: emeraldTheme,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: () async {
                  final trimmedFirstName = firstNameController.text.trim();
                  final trimmedLastName = lastNameController.text.trim();
                  final trimmedDiseases = diseaseController.text.trim();
                  final trimmedMedication = medicationController.text.trim();

                  if (trimmedFirstName.isEmpty || trimmedLastName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('กรุณากรอกชื่อและนามสกุลให้ครบถ้วน'),
                        backgroundColor: Color(0xFFD97B4F),
                      ),
                    );
                    return;
                  }

                  setState(() {
                    _firstNameController.text = trimmedFirstName;
                    _lastNameController.text = trimmedLastName;
                    _diseasesController.text = trimmedDiseases;
                    _medicationController.text = trimmedMedication;
                    _selectedGender = currentGender;
                    _ageController.text = ageController.text.trim();
                    _weightController.text = weightController.text.trim();
                    _heightController.text = heightController.text.trim();
                  });

                  Navigator.pop(ctx);
                  await _saveAndPushToSupabase();
                },
                child: const Text(
                  'ยืนยันและบันทึก',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _confirmationField(
    String label,
    TextEditingController controller, {
    TextInputType? inputType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: inputType,
          maxLines: maxLines,
          style: const TextStyle(color: primaryTextColor, fontSize: 14),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEADBCE)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEADBCE)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: emeraldTheme, width: 1.5),
            ),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAndPushToSupabase() async {
    setState(() => _isSaving = true);

    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null || patientId.isEmpty) {
        throw Exception('ไม่พบรหัสผู้ป่วย');
      }

      final age = int.tryParse(_ageController.text.trim()) ?? 0;
      final weight = double.tryParse(_weightController.text.trim()) ?? 0.0;
      final height = double.tryParse(_heightController.text.trim()) ?? 0.0;
      final heightInMeters = height > 0 ? height / 100.0 : 0.0;
      final bmi =
          heightInMeters > 0 ? weight / (heightInMeters * heightInMeters) : 0.0;
      final trimmedDiseases = _diseasesController.text.trim();
      final trimmedMedication = _medicationController.text.trim();

      await _dbService.updatePatientOnboardingData(
        patientId: patientId,
        age: age,
        gender: _selectedGender,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        weight: weight,
        height: height,
        bmi: double.parse(bmi.toStringAsFixed(1)),
        underlyingDiseases: trimmedDiseases.isEmpty
            ? 'ไม่มีโรคประจำตัว'
            : trimmedDiseases,
        lifestyleNotes: 'ข้อมูลจาก onboarding',
        medicationsText: trimmedMedication,
      );

      await _profileService.updateLocalProfile({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'name': '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim(),
        'age': age,
        'gender': _selectedGender,
        'weight_kg': weight,
        'height_cm': height,
        'bmi': double.parse(bmi.toStringAsFixed(1)),
        'underlying_diseases': trimmedDiseases.isEmpty ? 'ไม่มีโรคประจำตัว' : trimmedDiseases,
        'current_medications': trimmedMedication,
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      debugPrint('Error saving onboarding data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการบันทึก: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStepIndex =
        _currentStep == OnboardingStep.confirmation ? 8 : _currentStep.index + 1;

    return Scaffold(
      backgroundColor: creamBgColor,
      appBar: AppBar(
        title: const Text(
          'เก็บข้อมูลสุขภาพเบื้องต้น',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isSaving
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: emeraldTheme),
                  SizedBox(height: 16),
                  Text(
                    'กำลังบันทึกข้อมูลลงฐานข้อมูล...',
                    style: TextStyle(fontSize: 16, color: secondaryTextColor),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  children: [
                    Text(
                      'ขั้นตอนที่ $currentStepIndex / 8',
                      style: const TextStyle(
                        fontSize: 16,
                        color: secondaryTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: currentStepIndex / 8,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF0E5D8),
                        valueColor: const AlwaysStoppedAnimation<Color>(emeraldTheme),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFF0E5D8), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _currentStep == OnboardingStep.confirmation
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 64,
                                    color: emeraldTheme,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'ข้อมูลทั้งหมดพร้อมบันทึกแล้ว',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'โปรดตรวจสอบอีกครั้ง ก่อนกด "ยืนยันและบันทึก"',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                ],
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _questionTextForStep(_currentStep),
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    if (_currentStep == OnboardingStep.gender)
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: _genderOptions.map((gender) {
                                          final selected = _selectedGender == gender;
                                          return ChoiceChip(
                                            label: Text(
                                              gender,
                                              style: const TextStyle(fontSize: 17),
                                            ),
                                            selected: selected,
                                            selectedColor: emeraldTheme.withValues(alpha: 0.15),
                                            backgroundColor: softCardBg,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                              side: BorderSide(
                                                color: selected ? emeraldTheme : const Color(0xFFEADBCE),
                                              ),
                                            ),
                                            labelStyle: TextStyle(
                                              color: selected ? emeraldTheme : primaryTextColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            onSelected: (_) {
                                              setState(() => _selectedGender = gender);
                                            },
                                          );
                                        }).toList(),
                                      )
                                    else
                                      TextFormField(
                                        controller: _currentStep == OnboardingStep.firstName
                                            ? _firstNameController
                                            : _currentStep == OnboardingStep.lastName
                                                ? _lastNameController
                                                : _currentStep == OnboardingStep.age
                                                    ? _ageController
                                                    : _currentStep == OnboardingStep.diseases
                                                        ? _diseasesController
                                                        : _currentStep == OnboardingStep.medication
                                                            ? _medicationController
                                                            : _currentStep == OnboardingStep.weight
                                                                ? _weightController
                                                                : _heightController,
                                        keyboardType: _currentStep == OnboardingStep.age
                                            ? TextInputType.number
                                            : _currentStep == OnboardingStep.weight
                                                ? const TextInputType.numberWithOptions(decimal: true)
                                                : _currentStep == OnboardingStep.height
                                                    ? const TextInputType.numberWithOptions(decimal: true)
                                                    : TextInputType.text,
                                        maxLines: _currentStep == OnboardingStep.diseases ||
                                                _currentStep == OnboardingStep.medication
                                            ? 3
                                            : 1,
                                        style: const TextStyle(fontSize: 18, color: primaryTextColor),
                                        decoration: InputDecoration(
                                          hintText: _currentStep == OnboardingStep.firstName
                                              ? 'กรอกชื่อของคุณ'
                                              : _currentStep == OnboardingStep.lastName
                                                  ? 'กรอกนามสกุลของคุณ'
                                                  : _currentStep == OnboardingStep.age
                                                      ? 'เช่น 68'
                                                      : _currentStep == OnboardingStep.diseases
                                                          ? 'ระบุโรคประจำตัว หรือพิมพ์ ไม่มีโรคประจำตัว'
                                                          : _currentStep == OnboardingStep.medication
                                                              ? 'เช่น ยาลดความดัน, วิตามิน'
                                                              : _currentStep == OnboardingStep.weight
                                                                  ? 'เช่น 68.5'
                                                                  : 'เช่น 168.5',
                                          hintStyle: const TextStyle(color: mutedTextColor),
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
                                            borderSide: const BorderSide(color: emeraldTheme, width: 1.5),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFFAFAFA),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_currentStep != OnboardingStep.confirmation)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: emeraldTheme),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _skipToReview,
                              child: const Text(
                                'ข้ามไปตรวจสอบข้อมูล',
                                style: TextStyle(color: emeraldTheme, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emeraldTheme,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 1,
                              ),
                              onPressed: _goToNextStep,
                              child: const Text(
                                'ถัดไป',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                  ],
                ),
              ),
            ),
    );
  }
}
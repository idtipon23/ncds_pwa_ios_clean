class HealthEvaluationModel {
  final int? systolic;
  final int? diastolic;
  final int? fbs;
  final int? pulse;
  final double? weightKg;
  final double? heightCm;
  final double? waistCm;
  final bool? isSmoker;
  final bool? isAlcoholDrinker;
  final bool hasWarningSign;
  final String? warningDetails;
  final String urgencyLevel; // 'NORMAL', 'ELEVATED', 'CRITICAL'
  final String spokenFeedback;
  final bool isMissingData;
  final bool isValidHealthData;

  HealthEvaluationModel({
    this.systolic,
    this.diastolic,
    this.fbs,
    this.pulse,
    this.weightKg,
    this.heightCm,
    this.waistCm,
    this.isSmoker,
    this.isAlcoholDrinker,
    required this.hasWarningSign,
    this.warningDetails,
    required this.urgencyLevel,
    required this.spokenFeedback,
    required this.isMissingData,
    required this.isValidHealthData,
  });

  factory HealthEvaluationModel.fromJson(Map<String, dynamic> json) {
    return HealthEvaluationModel(
      systolic: json['systolic'] as int?,
      diastolic: json['diastolic'] as int?,
      fbs: json['fbs'] as int?,
      pulse: json['pulse'] as int?,
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      waistCm: (json['waist_cm'] as num?)?.toDouble(),
      isSmoker: json['is_smoker'] as bool?,
      isAlcoholDrinker: json['is_alcohol_drinker'] as bool?,
      hasWarningSign: json['has_warning_sign'] ?? false,
      warningDetails: json['warning_details'] as String?,
      urgencyLevel: json['urgency_level'] ?? 'NORMAL',
      spokenFeedback: json['spoken_feedback'] ?? '',
      isMissingData: json['is_missing_data'] ?? false,
      isValidHealthData: json['is_valid_health_data'] ?? true,
    );
  }
}

/// 身体数据记录
class BodyMetric {
  BodyMetric({
    required this.id,
    DateTime? date,
    this.weightKg,
    this.bodyFatPercentage,
    this.chestCm,
    this.waistCm,
    this.hipsCm,
    this.armCm,
    this.thighCm,
  }) : date = date ?? DateTime.now();

  factory BodyMetric.fromJson(Map<String, dynamic> json) => BodyMetric(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    bodyFatPercentage: (json['bodyFatPercentage'] as num?)?.toDouble(),
    chestCm: (json['chestCm'] as num?)?.toDouble(),
    waistCm: (json['waistCm'] as num?)?.toDouble(),
    hipsCm: (json['hipsCm'] as num?)?.toDouble(),
    armCm: (json['armCm'] as num?)?.toDouble(),
    thighCm: (json['thighCm'] as num?)?.toDouble(),
  );
  final String id;
  final DateTime date;
  double? weightKg;
  double? bodyFatPercentage;
  double? chestCm;
  double? waistCm;
  double? hipsCm;
  double? armCm;
  double? thighCm;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'weightKg': weightKg,
    'bodyFatPercentage': bodyFatPercentage,
    'chestCm': chestCm,
    'waistCm': waistCm,
    'hipsCm': hipsCm,
    'armCm': armCm,
    'thighCm': thighCm,
  };
}

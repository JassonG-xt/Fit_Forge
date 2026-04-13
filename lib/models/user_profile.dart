import 'enums.dart';

/// 用户画像
class UserProfile {
  double heightCm;
  double weightKg;
  int age;
  Gender gender;
  FitnessGoal goal;
  int weeklyFrequency;
  ExperienceLevel experienceLevel;
  List<Equipment> availableEquipment;
  DateTime createdAt;

  UserProfile({
    this.heightCm = 170,
    this.weightKg = 70,
    this.age = 25,
    this.gender = Gender.male,
    this.goal = FitnessGoal.buildMuscle,
    this.weeklyFrequency = 4,
    this.experienceLevel = ExperienceLevel.beginner,
    List<Equipment>? availableEquipment,
    DateTime? createdAt,
  })  : availableEquipment = availableEquipment ?? [Equipment.bodyweight, Equipment.dumbbell],
        createdAt = createdAt ?? DateTime.now();

  /// 活动系数
  double get activityMultiplier {
    if (weeklyFrequency <= 2) return 1.375;
    if (weeklyFrequency <= 4) return 1.55;
    return 1.725;
  }

  /// BMR (Mifflin-St Jeor)
  double get bmr {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    switch (gender) {
      case Gender.male:
        return base + 5;
      case Gender.female:
        return base - 161;
      case Gender.other:
        return base - 78;
    }
  }

  /// TDEE
  double get tdee => bmr * activityMultiplier;

  Map<String, dynamic> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'age': age,
        'gender': gender.name,
        'goal': goal.name,
        'weeklyFrequency': weeklyFrequency,
        'experienceLevel': experienceLevel.name,
        'availableEquipment': availableEquipment.map((e) => e.name).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        heightCm: (json['heightCm'] as num).toDouble(),
        weightKg: (json['weightKg'] as num).toDouble(),
        age: json['age'] as int,
        gender: Gender.values.byName(json['gender'] as String),
        goal: FitnessGoal.values.byName(json['goal'] as String),
        weeklyFrequency: json['weeklyFrequency'] as int,
        experienceLevel: ExperienceLevel.values.byName(json['experienceLevel'] as String),
        availableEquipment: (json['availableEquipment'] as List)
            .map((e) => Equipment.values.byName(e as String))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

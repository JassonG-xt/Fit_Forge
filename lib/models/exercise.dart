import 'enums.dart';

/// 动作定义
class Exercise {
  final String id;
  final String name;
  final BodyPart bodyPart;
  final List<String> muscleGroups;
  final Equipment equipment;
  final ExperienceLevel difficulty;
  final bool isCompound;
  final List<String> formCues;
  final List<String> commonMistakes;
  final String instructions;
  final List<String> antiCheatTips;
  final String lottieAnimationName;
  final List<String> alternativeIds;
  final int recommendedSetsMin;
  final int recommendedSetsMax;
  final int recommendedRepsMin;
  final int recommendedRepsMax;

  const Exercise({
    required this.id,
    required this.name,
    required this.bodyPart,
    required this.muscleGroups,
    required this.equipment,
    this.difficulty = ExperienceLevel.beginner,
    this.isCompound = false,
    this.formCues = const [],
    this.commonMistakes = const [],
    this.instructions = '',
    this.antiCheatTips = const [],
    this.lottieAnimationName = '',
    this.alternativeIds = const [],
    this.recommendedSetsMin = 3,
    this.recommendedSetsMax = 4,
    this.recommendedRepsMin = 8,
    this.recommendedRepsMax = 12,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String,
      bodyPart: BodyPart.values.byName(json['bodyPart'] as String),
      muscleGroups: List<String>.from(json['muscleGroups'] as List),
      equipment: Equipment.values.byName(json['equipment'] as String),
      difficulty: ExperienceLevel.values.byName(json['difficulty'] as String),
      isCompound: json['isCompound'] as bool? ?? false,
      formCues: List<String>.from(json['formCues'] as List? ?? []),
      commonMistakes: List<String>.from(json['commonMistakes'] as List? ?? []),
      instructions: json['instructions'] as String? ?? '',
      antiCheatTips: List<String>.from(json['antiCheatTips'] as List? ?? []),
      lottieAnimationName: json['lottieAnimationName'] as String? ?? '',
      alternativeIds: List<String>.from(json['alternativeIds'] as List? ?? []),
      recommendedSetsMin: json['recommendedSetsMin'] as int? ?? 3,
      recommendedSetsMax: json['recommendedSetsMax'] as int? ?? 4,
      recommendedRepsMin: json['recommendedRepsMin'] as int? ?? 8,
      recommendedRepsMax: json['recommendedRepsMax'] as int? ?? 12,
    );
  }
}

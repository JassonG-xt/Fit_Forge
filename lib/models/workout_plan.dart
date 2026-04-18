import 'enums.dart';

/// 训练计划（一周）
class WorkoutPlan {

  WorkoutPlan({
    required this.id,
    required this.name,
    required this.goal,
    required this.split,
    required this.weeklyFrequency,
    DateTime? createdAt,
    this.isActive = true,
    List<WorkoutDay>? days,
  })  : createdAt = createdAt ?? DateTime.now(),
        days = days ?? [];

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        goal: FitnessGoal.values.byName(json['goal'] as String),
        split: TrainingSplit.values.byName(json['split'] as String),
        weeklyFrequency: json['weeklyFrequency'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isActive: json['isActive'] as bool? ?? true,
        days: (json['days'] as List)
            .map((d) => WorkoutDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
  final String id;
  final String name;
  final FitnessGoal goal;
  final TrainingSplit split;
  final int weeklyFrequency;
  final DateTime createdAt;
  bool isActive;
  final List<WorkoutDay> days;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goal': goal.name,
        'split': split.name,
        'weeklyFrequency': weeklyFrequency,
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
        'days': days.map((d) => d.toJson()).toList(),
      };
}

/// 计划中的某一天
class WorkoutDay {

  WorkoutDay({
    required this.dayOfWeek,
    required this.dayType,
    List<PlannedExercise>? exercises,
  }) : exercises = exercises ?? [];

  factory WorkoutDay.fromJson(Map<String, dynamic> json) => WorkoutDay(
        dayOfWeek: json['dayOfWeek'] as int,
        dayType: WorkoutDayType.values.byName(json['dayType'] as String),
        exercises: (json['exercises'] as List)
            .map((e) => PlannedExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
  final int dayOfWeek; // 1=周一 ... 7=周日
  final WorkoutDayType dayType;
  final List<PlannedExercise> exercises;

  Map<String, dynamic> toJson() => {
        'dayOfWeek': dayOfWeek,
        'dayType': dayType.name,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}

/// 计划中的单个动作
class PlannedExercise {

  PlannedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.targetSets,
    required this.targetReps,
    required this.restSeconds,
  });

  factory PlannedExercise.fromJson(Map<String, dynamic> json) => PlannedExercise(
        exerciseId: json['exerciseId'] as String,
        exerciseName: json['exerciseName'] as String,
        targetSets: json['targetSets'] as int,
        targetReps: json['targetReps'] as int,
        restSeconds: json['restSeconds'] as int,
      );
  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final int targetReps;
  final int restSeconds;

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'targetSets': targetSets,
        'targetReps': targetReps,
        'restSeconds': restSeconds,
      };
}

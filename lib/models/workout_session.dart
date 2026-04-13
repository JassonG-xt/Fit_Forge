import 'enums.dart';

/// 单次训练记录
class WorkoutSession {
  final String id;
  final DateTime date;
  final WorkoutDayType dayType;
  int durationMinutes;
  bool isCompleted;
  final List<ExerciseRecord> exerciseRecords;

  WorkoutSession({
    required this.id,
    DateTime? date,
    required this.dayType,
    this.durationMinutes = 0,
    this.isCompleted = false,
    List<ExerciseRecord>? exerciseRecords,
  })  : date = date ?? DateTime.now(),
        exerciseRecords = exerciseRecords ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'dayType': dayType.name,
        'durationMinutes': durationMinutes,
        'isCompleted': isCompleted,
        'exerciseRecords': exerciseRecords.map((r) => r.toJson()).toList(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        dayType: WorkoutDayType.values.byName(json['dayType'] as String),
        durationMinutes: json['durationMinutes'] as int,
        isCompleted: json['isCompleted'] as bool,
        exerciseRecords: (json['exerciseRecords'] as List)
            .map((r) => ExerciseRecord.fromJson(r))
            .toList(),
      );
}

/// 单个动作的训练记录
class ExerciseRecord {
  final String exerciseId;
  final String exerciseName;
  final List<SetRecord> sets;

  ExerciseRecord({
    required this.exerciseId,
    required this.exerciseName,
    List<SetRecord>? sets,
  }) : sets = sets ?? [];

  double get totalVolume =>
      sets.fold(0, (sum, s) => sum + s.weightKg * s.reps);

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'sets': sets.map((s) => s.toJson()).toList(),
      };

  factory ExerciseRecord.fromJson(Map<String, dynamic> json) => ExerciseRecord(
        exerciseId: json['exerciseId'] as String,
        exerciseName: json['exerciseName'] as String,
        sets: (json['sets'] as List).map((s) => SetRecord.fromJson(s)).toList(),
      );
}

/// 单组记录
class SetRecord {
  final int setNumber;
  double weightKg;
  int reps;
  bool isCompleted;

  SetRecord({
    required this.setNumber,
    this.weightKg = 0,
    this.reps = 0,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'setNumber': setNumber,
        'weightKg': weightKg,
        'reps': reps,
        'isCompleted': isCompleted,
      };

  factory SetRecord.fromJson(Map<String, dynamic> json) => SetRecord(
        setNumber: json['setNumber'] as int,
        weightKg: (json['weightKg'] as num).toDouble(),
        reps: json['reps'] as int,
        isCompleted: json['isCompleted'] as bool,
      );
}

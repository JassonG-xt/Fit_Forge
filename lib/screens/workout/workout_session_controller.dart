import '../../models/models.dart';

/// UI-independent state machine for an active workout session.
///
/// The screen owns rendering and navigation; this controller owns exercise
/// progress, set records, recovery serialization, and final session creation.
class WorkoutSessionController {
  WorkoutSessionController({
    required this.workoutDay,
    DateTime? startTime,
    this.currentIndex = 0,
    this.showWarmup = true,
    this.isCompleted = false,
    Map<String, ExerciseRecord>? records,
  }) : startTime = startTime ?? DateTime.now(),
       records = records ?? {};

  factory WorkoutSessionController.fromRecovery({
    required WorkoutDay workoutDay,
    required Map<String, dynamic> data,
  }) {
    final records = <String, ExerciseRecord>{};
    final savedRecords = data['records'];
    if (savedRecords is Map<String, dynamic>) {
      for (final entry in savedRecords.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        try {
          records[entry.key] = ExerciseRecord.fromJson(value);
        } catch (_) {
          continue;
        }
      }
    }

    final savedStart = data['startTime'];
    final startTime = savedStart is String
        ? DateTime.tryParse(savedStart)
        : null;
    final rawIndex = data['currentIndex'];
    final maxIndex = workoutDay.exercises.isEmpty
        ? 0
        : workoutDay.exercises.length - 1;
    final currentIndex = rawIndex is int
        ? rawIndex.clamp(0, maxIndex).toInt()
        : 0;

    return WorkoutSessionController(
      workoutDay: workoutDay,
      startTime: startTime,
      currentIndex: currentIndex,
      showWarmup: false,
      records: records,
    );
  }

  final WorkoutDay workoutDay;
  DateTime startTime;
  int currentIndex;
  bool showWarmup;
  bool isCompleted;
  final Map<String, ExerciseRecord> records;

  List<PlannedExercise> get exercises => workoutDay.exercises;

  PlannedExercise? get current =>
      currentIndex < exercises.length ? exercises[currentIndex] : null;

  int get completedSetsCount =>
      records.values.expand((r) => r.sets).where((s) => s.isCompleted).length;

  ExerciseRecord getRecord(
    PlannedExercise planned, {
    required double lastWeight,
    required int lastReps,
  }) {
    return records.putIfAbsent(planned.exerciseId, () {
      final record = ExerciseRecord(
        exerciseId: planned.exerciseId,
        exerciseName: planned.exerciseName,
      );
      for (var i = 1; i <= planned.targetSets; i++) {
        record.sets.add(
          SetRecord(
            setNumber: i,
            weightKg: lastWeight,
            reps: lastReps > 0 ? lastReps : planned.targetReps,
          ),
        );
      }
      return record;
    });
  }

  void startWorkout() {
    showWarmup = false;
  }

  void nextExercise() {
    if (currentIndex < exercises.length - 1) {
      currentIndex++;
    } else {
      isCompleted = true;
    }
  }

  Map<String, dynamic> toRecoveryJson() {
    return {
      'dayType': workoutDay.dayType.name,
      'currentIndex': currentIndex,
      'startTime': startTime.toIso8601String(),
      'records': records.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  WorkoutSession buildSession({required String id, required DateTime endedAt}) {
    return WorkoutSession(
      id: id,
      dayType: workoutDay.dayType,
      durationMinutes: endedAt.difference(startTime).inMinutes,
      isCompleted: completedSetsCount > 0,
      exerciseRecords: records.values.toList(),
    );
  }
}

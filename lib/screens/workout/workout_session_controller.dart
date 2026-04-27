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
    final draft = WorkoutSessionDraft.fromJson(data);
    final maxIndex = workoutDay.exercises.isEmpty
        ? 0
        : workoutDay.exercises.length - 1;
    final currentIndex = draft.currentIndex.clamp(0, maxIndex).toInt();
    final allowedExerciseIds = workoutDay.exercises
        .map((exercise) => exercise.exerciseId)
        .toSet();
    final records = Map<String, ExerciseRecord>.fromEntries(
      draft.records.entries.where(
        (entry) =>
            allowedExerciseIds.contains(entry.key) &&
            allowedExerciseIds.contains(entry.value.exerciseId),
      ),
    );

    return WorkoutSessionController(
      workoutDay: workoutDay,
      startTime: draft.startedAt,
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
    return WorkoutSessionDraft(
      dayType: workoutDay.dayType,
      startedAt: startTime,
      currentIndex: currentIndex,
      records: records,
    ).toJson();
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

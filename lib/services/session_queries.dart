import '../models/models.dart';

/// Pure query helpers for workout session-derived state.
///
/// Keeping these calculations outside AppState makes them testable and prevents
/// UI screens from duplicating date/window logic.
class SessionQueries {
  const SessionQueries._();

  static List<WorkoutSession> completedSessions(
    Iterable<WorkoutSession> sessions,
  ) {
    return sessions.where((s) => s.isCompleted).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static int streakDays(
    Iterable<WorkoutSession> completedSessions, {
    DateTime? now,
  }) {
    var streak = 0;
    final today = now ?? DateTime.now();
    var checkDate = DateTime(today.year, today.month, today.day);
    final completed = completedSessions.toList();

    final hasTodayWorkout = completed.any((s) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      return d == checkDate;
    });
    if (!hasTodayWorkout) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    for (final session in completed) {
      final sessionDay = DateTime(
        session.date.year,
        session.date.month,
        session.date.day,
      );
      if (sessionDay == checkDate) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (sessionDay.isBefore(checkDate)) {
        break;
      }
    }
    return streak;
  }

  static int totalWorkoutsThisWeek(
    Iterable<WorkoutSession> completedSessions, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final startOfWeek = current.subtract(Duration(days: current.weekday - 1));
    final start = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );
    return completedSessions.where((s) => s.date.isAfter(start)).length;
  }

  static double lastWeightForExercise(
    Iterable<WorkoutSession> completedSessions,
    String exerciseId,
  ) {
    for (final session in completedSessions) {
      for (final record in session.exerciseRecords) {
        if (record.exerciseId == exerciseId) {
          final completedSets = record.sets.where(
            (s) => s.isCompleted && s.weightKg > 0,
          );
          if (completedSets.isNotEmpty) return completedSets.first.weightKg;
        }
      }
    }
    return 0;
  }

  static int lastRepsForExercise(
    Iterable<WorkoutSession> completedSessions,
    String exerciseId,
  ) {
    for (final session in completedSessions) {
      for (final record in session.exerciseRecords) {
        if (record.exerciseId == exerciseId) {
          final completedSets = record.sets.where(
            (s) => s.isCompleted && s.reps > 0,
          );
          if (completedSets.isNotEmpty) return completedSets.first.reps;
        }
      }
    }
    return 0;
  }

  static List<double> weekActivity(
    Iterable<WorkoutSession> completedSessions, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final startOfWeek = current.subtract(Duration(days: current.weekday - 1));
    return List.generate(7, (i) {
      final day = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day + i,
      );
      final hasWorkout = completedSessions.any(
        (s) =>
            s.date.year == day.year &&
            s.date.month == day.month &&
            s.date.day == day.day,
      );
      return hasWorkout ? 1.0 : 0.0;
    });
  }
}

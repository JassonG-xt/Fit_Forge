import '../models/models.dart';

class TrainingLoadSummary {
  const TrainingLoadSummary({
    required this.plannedTrainingDays,
    required this.restDays,
    required this.totalPlannedSets,
    required this.maxDailySets,
    required this.longestConsecutiveTrainingDays,
    required this.weeklySetsByBodyPart,
    required this.flags,
    required this.loadLevel,
  });

  final int plannedTrainingDays;
  final int restDays;
  final int totalPlannedSets;
  final int maxDailySets;
  final int longestConsecutiveTrainingDays;
  final Map<String, int> weeklySetsByBodyPart;
  final List<String> flags;
  final String loadLevel;

  Map<String, dynamic> toJson() => {
    'plannedTrainingDays': plannedTrainingDays,
    'restDays': restDays,
    'totalPlannedSets': totalPlannedSets,
    'maxDailySets': maxDailySets,
    'longestConsecutiveTrainingDays': longestConsecutiveTrainingDays,
    'weeklySetsByBodyPart': weeklySetsByBodyPart,
    'flags': flags,
    'loadLevel': loadLevel,
  };
}

class TrainingLoadAnalyzer {
  const TrainingLoadAnalyzer();

  TrainingLoadSummary analyze({
    required WorkoutPlan? activePlan,
    required UserProfile? profile,
    Map<String, dynamic>? todayWorkout,
  }) {
    if (activePlan == null) {
      return const TrainingLoadSummary(
        plannedTrainingDays: 0,
        restDays: 0,
        totalPlannedSets: 0,
        maxDailySets: 0,
        longestConsecutiveTrainingDays: 0,
        weeklySetsByBodyPart: {},
        flags: ['no_active_plan'],
        loadLevel: 'unknown',
      );
    }

    final trainingDays = activePlan.days
        .where((day) => day.dayType != WorkoutDayType.rest)
        .toList();
    final plannedTrainingDays = trainingDays.length;
    final restDays = activePlan.days
        .where((day) => day.dayType == WorkoutDayType.rest)
        .length;
    var totalPlannedSets = 0;
    var maxDailySets = 0;
    final weeklySetsByBodyPart = <String, int>{};

    for (final day in trainingDays) {
      final dailySets = _dailySets(day);
      totalPlannedSets += dailySets;
      if (dailySets > maxDailySets) maxDailySets = dailySets;

      // Conservative Coach Agent estimate based on day type, not
      // exercise-level muscle accounting. This is not medical advice or a
      // professional training prescription.
      for (final bodyPart in day.dayType.targetBodyParts) {
        weeklySetsByBodyPart.update(
          bodyPart.name,
          (sets) => sets + dailySets,
          ifAbsent: () => dailySets,
        );
      }
    }

    final longestConsecutiveTrainingDays = _longestConsecutiveTrainingDays(
      activePlan.days,
    );
    final flags = _flags(
      plannedTrainingDays: plannedTrainingDays,
      totalPlannedSets: totalPlannedSets,
      maxDailySets: maxDailySets,
      longestConsecutiveTrainingDays: longestConsecutiveTrainingDays,
      profile: profile,
    );

    return TrainingLoadSummary(
      plannedTrainingDays: plannedTrainingDays,
      restDays: restDays,
      totalPlannedSets: totalPlannedSets,
      maxDailySets: maxDailySets,
      longestConsecutiveTrainingDays: longestConsecutiveTrainingDays,
      weeklySetsByBodyPart: weeklySetsByBodyPart,
      flags: flags,
      loadLevel: _loadLevel(
        plannedTrainingDays: plannedTrainingDays,
        totalPlannedSets: totalPlannedSets,
        flags: flags,
      ),
    );
  }

  int _dailySets(WorkoutDay day) =>
      day.exercises.fold<int>(0, (sum, exercise) => sum + exercise.targetSets);

  int _longestConsecutiveTrainingDays(List<WorkoutDay> days) {
    final sortedDays = [...days]..sort((a, b) => a.dayOfWeek - b.dayOfWeek);
    var current = 0;
    var longest = 0;

    for (final day in sortedDays) {
      if (day.dayType == WorkoutDayType.rest) {
        current = 0;
        continue;
      }
      current += 1;
      if (current > longest) longest = current;
    }

    return longest;
  }

  List<String> _flags({
    required int plannedTrainingDays,
    required int totalPlannedSets,
    required int maxDailySets,
    required int longestConsecutiveTrainingDays,
    required UserProfile? profile,
  }) {
    final flags = <String>[];

    if (plannedTrainingDays <= 1) {
      flags.add('very_low_training_frequency');
    }
    if (plannedTrainingDays >= 6) {
      flags.add('high_training_frequency');
    }
    if (totalPlannedSets >= 80) {
      flags.add('high_weekly_set_volume');
    }
    if (maxDailySets >= 25) {
      flags.add('high_daily_set_volume');
    }
    if (longestConsecutiveTrainingDays >= 4) {
      flags.add('long_consecutive_training_streak');
    }
    if (profile?.experienceLevel == ExperienceLevel.beginner) {
      if (plannedTrainingDays >= 5) {
        flags.add('beginner_high_frequency');
      }
      if (totalPlannedSets >= 60) {
        flags.add('beginner_high_volume');
      }
    }

    return flags;
  }

  String _loadLevel({
    required int plannedTrainingDays,
    required int totalPlannedSets,
    required List<String> flags,
  }) {
    const highLoadFlags = {
      'high_training_frequency',
      'high_weekly_set_volume',
      'high_daily_set_volume',
      'long_consecutive_training_streak',
      'beginner_high_frequency',
      'beginner_high_volume',
    };

    if (flags.any(highLoadFlags.contains)) return 'high';
    if (plannedTrainingDays <= 1 || totalPlannedSets < 20) return 'low';
    return 'moderate';
  }
}

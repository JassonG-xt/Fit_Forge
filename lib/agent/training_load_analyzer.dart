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

    final daysByWeekday = {
      for (final day in activePlan.days) day.dayOfWeek: day,
    };
    final orderedDays = [
      for (var weekday = 1; weekday <= 7; weekday++)
        daysByWeekday[weekday] ??
            WorkoutDay(dayOfWeek: weekday, dayType: WorkoutDayType.rest),
    ];

    final plannedTrainingDays = orderedDays
        .where((day) => day.dayType != WorkoutDayType.rest)
        .length;
    final restDays = orderedDays
        .where((day) => day.dayType == WorkoutDayType.rest)
        .length;
    var totalPlannedSets = 0;
    var maxDailySets = 0;
    final weeklySetsByBodyPart = <String, int>{};

    for (final day in orderedDays) {
      if (day.dayType == WorkoutDayType.rest) continue;

      final dailySets = day.exercises.fold<int>(
        0,
        (sum, exercise) => sum + exercise.targetSets,
      );
      totalPlannedSets += dailySets;
      if (dailySets > maxDailySets) maxDailySets = dailySets;

      // Coarse estimate: day type contributes its whole volume to each target
      // body part. This is not exercise-level muscle-group accounting.
      for (final bodyPart in day.dayType.targetBodyParts) {
        weeklySetsByBodyPart.update(
          bodyPart.name,
          (sets) => sets + dailySets,
          ifAbsent: () => dailySets,
        );
      }
    }

    final longestConsecutiveTrainingDays = _longestInWeekTrainingStreak(
      orderedDays,
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
      weeklySetsByBodyPart: Map.unmodifiable(weeklySetsByBodyPart),
      flags: List.unmodifiable(flags),
      loadLevel: _loadLevel(
        plannedTrainingDays: plannedTrainingDays,
        totalPlannedSets: totalPlannedSets,
        flags: flags,
      ),
    );
  }

  int _longestInWeekTrainingStreak(List<WorkoutDay> orderedDays) {
    // P0-A intentionally measures only Monday-Sunday in-week streaks. It does
    // not wrap Sunday into the following Monday.
    var current = 0;
    var longest = 0;
    for (final day in orderedDays) {
      if (day.dayType == WorkoutDayType.rest) {
        current = 0;
      } else {
        current += 1;
        if (current > longest) longest = current;
      }
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
    if (profile?.experienceLevel == ExperienceLevel.beginner &&
        plannedTrainingDays >= 5) {
      flags.add('beginner_high_frequency');
    }
    if (profile?.experienceLevel == ExperienceLevel.beginner &&
        totalPlannedSets >= 60) {
      flags.add('beginner_high_volume');
    }
    return flags;
  }

  String _loadLevel({
    required int plannedTrainingDays,
    required int totalPlannedSets,
    required List<String> flags,
  }) {
    const highFlags = {
      'high_training_frequency',
      'high_weekly_set_volume',
      'high_daily_set_volume',
      'long_consecutive_training_streak',
      'beginner_high_frequency',
      'beginner_high_volume',
    };
    if (flags.any(highFlags.contains)) return 'high';
    if (plannedTrainingDays <= 1 || totalPlannedSets < 20) return 'low';
    return 'moderate';
  }
}

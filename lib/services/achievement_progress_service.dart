import '../models/models.dart';
import 'session_queries.dart';

class AchievementProgressService {
  const AchievementProgressService();

  List<Achievement> migrateAchievements(List<Achievement> achievements) {
    final defaults = defaultAchievements();
    if (achievements.isEmpty) return defaults;

    final existingById = {for (final a in achievements) a.id: a};
    final defaultIds = defaults.map((a) => a.id).toSet();

    return [
      for (final fallback in defaults)
        _mergeAchievement(existingById[fallback.id], fallback),
      ...achievements.where((a) => !defaultIds.contains(a.id)),
    ];
  }

  Map<String, double> rebuildPrCache(List<WorkoutSession> sessions) {
    final prCache = <String, double>{};
    for (final session in sessions) {
      _updatePrCache(prCache, session);
    }
    return prCache;
  }

  PrUpdateResult updatePrCacheForSession({
    required Map<String, double> currentPrCache,
    required WorkoutSession session,
  }) {
    final prCache = Map<String, double>.from(currentPrCache);
    final newPRCount = _countNewPRs(session, currentPrCache);
    _updatePrCache(prCache, session);
    return PrUpdateResult(prCache: prCache, newPRCount: newPRCount);
  }

  List<Achievement> updateAchievementsAfterSession({
    required List<Achievement> achievements,
    required List<WorkoutSession> completedSessions,
    required int newPRCount,
  }) {
    final totalCompleted = completedSessions.length;
    final streak = SessionQueries.streakDays(completedSessions);

    for (final a in achievements) {
      if (a.isUnlocked) continue;
      switch (a.type) {
        case AchievementType.streak:
          a.currentProgress = streak;
          if (streak >= a.threshold) a.unlock();
        case AchievementType.totalWorkouts:
          a.currentProgress = totalCompleted;
          if (totalCompleted >= a.threshold) a.unlock();
        case AchievementType.personalRecord:
          if (newPRCount > 0) {
            a.currentProgress += newPRCount;
            if (a.currentProgress >= a.threshold) a.unlock();
          }
        case AchievementType.bodyPartMastery:
          final targetBodyPart = a.targetBodyPart;
          if (targetBodyPart == null) break;
          final bodyPartSessions = completedSessions
              .where((s) => s.dayType.targetBodyParts.contains(targetBodyPart))
              .length;
          a.currentProgress = bodyPartSessions;
          if (bodyPartSessions >= a.threshold) a.unlock();
        case AchievementType.nutritionStreak:
          break;
      }
    }

    return achievements;
  }

  Achievement _mergeAchievement(Achievement? existing, Achievement fallback) {
    if (existing == null) return fallback;
    return Achievement(
      id: fallback.id,
      type: fallback.type,
      title: fallback.title,
      description: fallback.description,
      icon: fallback.icon,
      threshold: fallback.threshold,
      targetBodyPart: existing.targetBodyPart ?? fallback.targetBodyPart,
      currentProgress: existing.currentProgress,
      isUnlocked: existing.isUnlocked,
      unlockedAt: existing.unlockedAt,
    );
  }

  void _updatePrCache(Map<String, double> prCache, WorkoutSession session) {
    for (final record in session.exerciseRecords) {
      for (final s in record.sets) {
        if (!s.isCompleted || s.weightKg <= 0) continue;
        final current = prCache[record.exerciseId] ?? 0;
        if (s.weightKg > current) {
          prCache[record.exerciseId] = s.weightKg;
        }
      }
    }
  }

  int _countNewPRs(WorkoutSession session, Map<String, double> prSnapshot) {
    var count = 0;
    for (final record in session.exerciseRecords) {
      final sessionMax = record.sets
          .where((s) => s.isCompleted && s.weightKg > 0)
          .fold<double>(0, (max, s) => s.weightKg > max ? s.weightKg : max);
      if (sessionMax <= 0) continue;
      final oldMax = prSnapshot[record.exerciseId] ?? 0;
      if (oldMax > 0 && sessionMax > oldMax) count++;
    }
    return count;
  }
}

class PrUpdateResult {
  const PrUpdateResult({required this.prCache, required this.newPRCount});

  final Map<String, double> prCache;
  final int newPRCount;
}

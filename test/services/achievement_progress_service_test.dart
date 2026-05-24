import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/services/achievement_progress_service.dart';

void main() {
  const service = AchievementProgressService();

  group('AchievementProgressService', () {
    test(
      'rebuildPrCache keeps highest completed positive weight per exercise',
      () {
        final cache = service.rebuildPrCache([
          _session(
            id: 's1',
            records: [
              _record('bench', [
                _set(60),
                _set(80),
                _set(90, completed: false),
              ]),
              _record('squat', [_set(0), _set(100)]),
            ],
          ),
          _session(
            id: 's2',
            records: [
              _record('bench', [_set(75), _set(85)]),
              _record('deadlift', [_set(-10), _set(120)]),
            ],
          ),
        ]);

        expect(cache, {'bench': 85.0, 'squat': 100.0, 'deadlift': 120.0});
      },
    );

    test('updatePrCacheForSession counts only real new PRs', () {
      final result = service.updatePrCacheForSession(
        currentPrCache: {'bench': 80},
        session: _session(
          id: 's1',
          records: [
            _record('bench', [_set(85), _set(70)]),
            _record('squat', [_set(100)]),
            _record('row', [_set(90, completed: false)]),
          ],
        ),
      );

      expect(result.prCache, {'bench': 85.0, 'squat': 100.0});
      expect(result.newPRCount, 1);
    });

    test(
      'migrateAchievements preserves existing progress and unlock state',
      () {
        final existing = Achievement(
          id: 'a05',
          type: AchievementType.totalWorkouts,
          title: 'Old title',
          description: 'Old description',
          icon: 'old',
          threshold: 99,
          currentProgress: 7,
          isUnlocked: true,
          unlockedAt: DateTime(2026, 5, 1),
        );

        final migrated = service.migrateAchievements([existing]);
        final migratedById = {
          for (final achievement in migrated) achievement.id: achievement,
        };

        expect(migrated.length, defaultAchievements().length);
        expect(
          migratedById.keys,
          containsAll(defaultAchievements().map((a) => a.id)),
        );
        expect(migratedById['a05']!.currentProgress, 7);
        expect(migratedById['a05']!.isUnlocked, isTrue);
        expect(migratedById['a05']!.unlockedAt, DateTime(2026, 5, 1));
        expect(
          migratedById['a05']!.threshold,
          defaultAchievements().firstWhere((a) => a.id == 'a05').threshold,
        );
      },
    );

    test(
      'updateAchievementsAfterSession updates and unlocks total workouts',
      () {
        final achievement = Achievement(
          id: 'total',
          type: AchievementType.totalWorkouts,
          title: 'Total',
          description: 'Complete workouts',
          icon: 'T',
          threshold: 2,
        );

        final updated = service.updateAchievementsAfterSession(
          achievements: [achievement],
          completedSessions: [
            _session(id: 's1'),
            _session(id: 's2'),
          ],
          newPRCount: 0,
        );

        expect(updated.single.currentProgress, 2);
        expect(updated.single.isUnlocked, isTrue);
      },
    );
  });
}

WorkoutSession _session({
  required String id,
  List<ExerciseRecord> records = const [],
}) {
  return WorkoutSession(
    id: id,
    date: DateTime(2026, 5, 1),
    dayType: WorkoutDayType.push,
    isCompleted: true,
    exerciseRecords: records,
  );
}

ExerciseRecord _record(String exerciseId, List<SetRecord> sets) {
  return ExerciseRecord(
    exerciseId: exerciseId,
    exerciseName: exerciseId,
    sets: sets,
  );
}

SetRecord _set(double weightKg, {bool completed = true}) {
  return SetRecord(
    setNumber: 1,
    weightKg: weightKg,
    reps: 5,
    isCompleted: completed,
  );
}

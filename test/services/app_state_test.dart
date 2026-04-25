import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_forge/services/app_state.dart';
import 'package:fit_forge/models/models.dart';

/// Creates an AppState ready for testing (no init() — that needs rootBundle).
/// Achievements are seeded via resetAllData which calls defaultAchievements().
Future<AppState> createTestState() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  // resetAllData seeds default achievements without needing rootBundle
  await state.resetAllData();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    state = await createTestState();
  });

  group('completedSessions', () {
    test('returns only completed sessions sorted descending', () {
      final s1 = WorkoutSession(
        id: '1',
        dayType: WorkoutDayType.push,
        isCompleted: true,
        date: DateTime(2026, 4, 10),
      );
      final s2 = WorkoutSession(
        id: '2',
        dayType: WorkoutDayType.pull,
        isCompleted: false,
        date: DateTime(2026, 4, 11),
      );
      final s3 = WorkoutSession(
        id: '3',
        dayType: WorkoutDayType.legs,
        isCompleted: true,
        date: DateTime(2026, 4, 12),
      );
      state.saveSession(s1);
      state.saveSession(s2);
      state.saveSession(s3);

      final completed = state.completedSessions;
      expect(completed.length, 2);
      expect(completed.first.id, '3'); // most recent first
      expect(completed.last.id, '1');
    });
  });

  group('lastWeightForExercise', () {
    test('returns 0 when no history', () {
      expect(state.lastWeightForExercise('ex001'), 0);
    });

    test('returns weight from most recent session', () {
      final s1 = WorkoutSession(
        id: '1',
        dayType: WorkoutDayType.push,
        isCompleted: true,
        date: DateTime(2026, 4, 10),
        exerciseRecords: [
          ExerciseRecord(
            exerciseId: 'ex001',
            exerciseName: 'Bench',
            sets: [
              SetRecord(
                setNumber: 1,
                weightKg: 60,
                reps: 10,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );
      final s2 = WorkoutSession(
        id: '2',
        dayType: WorkoutDayType.push,
        isCompleted: true,
        date: DateTime(2026, 4, 12),
        exerciseRecords: [
          ExerciseRecord(
            exerciseId: 'ex001',
            exerciseName: 'Bench',
            sets: [
              SetRecord(setNumber: 1, weightKg: 65, reps: 8, isCompleted: true),
            ],
          ),
        ],
      );
      state.saveSession(s1);
      state.saveSession(s2);

      expect(state.lastWeightForExercise('ex001'), 65); // most recent
    });
  });

  group('lastRepsForExercise', () {
    test('returns reps from most recent session', () {
      final s1 = WorkoutSession(
        id: '1',
        dayType: WorkoutDayType.push,
        isCompleted: true,
        date: DateTime(2026, 4, 10),
        exerciseRecords: [
          ExerciseRecord(
            exerciseId: 'ex001',
            exerciseName: 'Bench',
            sets: [
              SetRecord(
                setNumber: 1,
                weightKg: 60,
                reps: 12,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );
      state.saveSession(s1);
      expect(state.lastRepsForExercise('ex001'), 12);
    });
  });

  group('saveSession + achievements', () {
    test('totalWorkouts achievement progresses', () {
      state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));

      for (var i = 0; i < 3; i++) {
        state.saveSession(
          WorkoutSession(
            id: 'w$i',
            dayType: WorkoutDayType.push,
            isCompleted: true,
            date: DateTime(2026, 4, 1 + i),
          ),
        );
      }

      final totalWorkoutsAch = state.achievements
          .where((a) => a.type == AchievementType.totalWorkouts)
          .first;
      expect(totalWorkoutsAch.currentProgress, 3);
    });

    test('body part mastery progresses only for its target body part', () {
      state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));

      state.saveSession(
        WorkoutSession(
          id: 'legs-1',
          dayType: WorkoutDayType.legs,
          isCompleted: true,
          date: DateTime(2026, 4, 20),
        ),
      );

      final chestMastery = state.achievements.firstWhere((a) => a.id == 'a10');
      final backMastery = state.achievements.firstWhere((a) => a.id == 'a11');
      final legMastery = state.achievements.firstWhere((a) => a.id == 'a12');

      expect(chestMastery.currentProgress, 0);
      expect(backMastery.currentProgress, 0);
      expect(legMastery.currentProgress, 1);
    });
  });

  group('collection safety', () {
    test('public list getters cannot mutate AppState directly', () {
      expect(
        () => state.sessions.add(
          WorkoutSession(id: 'direct', dayType: WorkoutDayType.push),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('persistence debounce', () {
    test(
      'flushPendingPersistence writes debounced saveProfile immediately',
      () async {
        SharedPreferences.setMockInitialValues({});
        final state = AppState();

        state.saveProfile(UserProfile(goal: FitnessGoal.loseFat));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('profile'), isNull);

        await state.flushPendingPersistence();

        expect(prefs.getBool('hasCompletedOnboarding'), isTrue);
        expect(prefs.getString('profile'), isNotNull);
      },
    );
  });

  group('setThemeMode', () {
    test('changes theme and notifies', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.setThemeMode(ThemeMode.light);
      expect(state.themeMode, ThemeMode.light);
      expect(notified, true);
    });
  });

  group('resetAllData', () {
    test('clears all state', () async {
      state.saveProfile(UserProfile(goal: FitnessGoal.loseFat));
      state.saveSession(
        WorkoutSession(
          id: 'w1',
          dayType: WorkoutDayType.push,
          isCompleted: true,
        ),
      );

      expect(state.hasCompletedOnboarding, true);
      expect(state.sessions.isNotEmpty, true);

      await state.resetAllData();

      expect(state.hasCompletedOnboarding, false);
      expect(state.sessions.isEmpty, true);
      expect(state.profile, null);
      expect(state.activePlan, null);
      expect(state.themeMode, ThemeMode.light);
    });
  });

  group('restartOnboarding', () {
    test('clears onboarding flag but keeps data', () {
      state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));
      state.saveSession(
        WorkoutSession(
          id: 'w1',
          dayType: WorkoutDayType.push,
          isCompleted: true,
        ),
      );

      state.restartOnboarding();

      expect(state.hasCompletedOnboarding, false);
      expect(state.sessions.length, 1); // data preserved
      expect(state.profile, isNotNull); // profile preserved
    });
  });

  group('importFromJson', () {
    test('does not mutate state when import fails part way through', () {
      state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));

      final error = state.importFromJson(
        json.encode({
          'version': 1,
          'profile': UserProfile(goal: FitnessGoal.loseFat).toJson(),
          'sessions': ['not a session object'],
        }),
      );

      expect(error, isNotNull);
      expect(state.profile!.goal, FitnessGoal.buildMuscle);
    });

    test('migrates old body-part achievements missing targetBodyPart', () {
      final legacyAchievement = Achievement(
        id: 'a10',
        type: AchievementType.bodyPartMastery,
        title: '胸肌专家',
        description: '完成 20 次含胸部训练',
        icon: 'target',
        threshold: 20,
      );

      final error = state.importFromJson(
        json.encode({
          'version': 1,
          'achievements': [legacyAchievement.toJson()],
        }),
      );

      expect(error, isNull);
      expect(
        state.achievements.firstWhere((a) => a.id == 'a10').targetBodyPart,
        BodyPart.chest,
      );
    });
  });

  group('profile and plan consistency', () {
    test('clears active plan when plan-driving profile fields change', () {
      final profile = UserProfile(
        goal: FitnessGoal.buildMuscle,
        weeklyFrequency: 3,
      );
      state.saveProfile(profile);
      state.adoptPlan(
        WorkoutPlan(
          id: 'plan-1',
          name: 'Initial',
          goal: FitnessGoal.buildMuscle,
          split: TrainingSplit.pushPullLegs,
          weeklyFrequency: 3,
        ),
      );

      state.updateProfile(profile.copyWith(goal: FitnessGoal.loseFat));

      expect(state.activePlan, isNull);
    });
  });
}

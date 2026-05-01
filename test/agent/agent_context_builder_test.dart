import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/agent_context_builder.dart';
import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/services/app_state.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentContextBuilder', () {
    test('handles fresh state without profile', () async {
      final state = await freshAppState();
      const builder = AgentContextBuilder();
      final snapshot = builder.build(state);

      expect(snapshot.locale, 'zh-CN');
      expect(snapshot.profile, isNull);
      expect(snapshot.activePlan, isNull);
      expect(snapshot.todayWorkout, isNull);
      expect(snapshot.recentSessions, isEmpty);
      expect(snapshot.bodyMetrics, isEmpty);
      expect(snapshot.progressSummary['streakDays'], 0);
      expect(snapshot.progressSummary['totalWorkoutsThisWeek'], 0);
    });

    test('includes profile json when profile is set', () async {
      final state = await primedAppStateWithProfile();
      const builder = AgentContextBuilder();
      final snapshot = builder.build(state);

      expect(snapshot.profile, isNotNull);
      expect(snapshot.profile!['goal'], state.profile!.goal.name);
      expect(
        snapshot.progressSummary['goal'],
        state.profile!.goal.name,
      );
      expect(
        snapshot.progressSummary['weeklyFrequency'],
        state.profile!.weeklyFrequency,
      );
    });

    test('includes activePlan and today workout when present', () async {
      final state = await primedAppStateWithProfile();
      // Build a deterministic plan with a workout day for today's weekday.
      final today = DateTime.now().weekday;
      final restDays = <WorkoutDay>[];
      for (var d = 1; d <= 7; d++) {
        if (d == today) {
          restDays.add(
            WorkoutDay(
              dayOfWeek: d,
              dayType: WorkoutDayType.push,
              exercises: [
                PlannedExercise(
                  exerciseId: 'bench_press',
                  exerciseName: 'Bench Press',
                  targetSets: 4,
                  targetReps: 8,
                  restSeconds: 90,
                ),
              ],
            ),
          );
        } else {
          restDays.add(WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest));
        }
      }
      final plan = WorkoutPlan(
        id: 'plan_test',
        name: 'Test Plan',
        goal: state.profile!.goal,
        split: TrainingSplit.upperLower,
        weeklyFrequency: 1,
        days: restDays,
      );
      state.adoptPlan(plan);
      await state.flushPendingPersistence();

      const builder = AgentContextBuilder();
      final snapshot = builder.build(state);

      expect(snapshot.activePlan, isNotNull);
      expect(snapshot.activePlan!['id'], 'plan_test');
      expect(snapshot.todayWorkout, isNotNull);
      expect(snapshot.todayWorkout!['dayOfWeek'], today);
      expect(snapshot.todayWorkout!['dayType'], 'push');
      final exercises = snapshot.todayWorkout!['exercises'] as List;
      expect(exercises, hasLength(1));
      expect(
        (exercises.first as Map<String, dynamic>)['exerciseId'],
        'bench_press',
      );
    });

    test('today workout is null when today is rest day', () async {
      final state = await primedAppStateWithProfile();
      final allRest = [
        for (var d = 1; d <= 7; d++)
          WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
      ];
      state.adoptPlan(
        WorkoutPlan(
          id: 'rest_only',
          name: 'Rest week',
          goal: state.profile!.goal,
          split: TrainingSplit.fullBody,
          weeklyFrequency: 0,
          days: allRest,
        ),
      );
      await state.flushPendingPersistence();

      const builder = AgentContextBuilder();
      final snapshot = builder.build(state);
      expect(snapshot.activePlan, isNotNull);
      expect(snapshot.todayWorkout, isNull);
    });

    test('caps recentSessions at the configured limit', () async {
      final state = await primedAppStateWithProfile();
      for (var i = 0; i < 15; i++) {
        state.saveSession(
          WorkoutSession(
            id: 'session_$i',
            dayType: WorkoutDayType.push,
            date: DateTime.now().subtract(Duration(days: i)),
            durationMinutes: 30,
            isCompleted: true,
          ),
        );
      }
      await state.flushPendingPersistence();

      final snapshot = const AgentContextBuilder(
        recentSessionLimit: 5,
      ).build(state);
      expect(snapshot.recentSessions, hasLength(5));
    });

    test('recentSessions are the latest by date even when saved out of order', () async {
      final state = await primedAppStateWithProfile();
      // Insert sessions in deliberately scrambled date order.
      final dates = [3, 10, 1, 7, 2, 14, 5];
      for (var i = 0; i < dates.length; i++) {
        state.saveSession(
          WorkoutSession(
            id: 'session_${dates[i]}',
            dayType: WorkoutDayType.push,
            date: DateTime.now().subtract(Duration(days: dates[i])),
            durationMinutes: 30,
            isCompleted: true,
          ),
        );
      }
      await state.flushPendingPersistence();

      final snapshot = const AgentContextBuilder(
        recentSessionLimit: 3,
      ).build(state);
      expect(snapshot.recentSessions, hasLength(3));
      // 最近 3 条应为 days-ago = 1, 2, 3（按 date desc 取前 3 条）。
      final ids = snapshot.recentSessions
          .map((s) => s['id'] as String)
          .toList();
      expect(ids, ['session_1', 'session_2', 'session_3']);
    });

    test('availableExerciseSummary strips heavy fields', () async {
      final state = AppState();
      await state.init();

      const builder = AgentContextBuilder();
      final snapshot = builder.build(state);

      expect(snapshot.availableExerciseSummary, isNotEmpty);
      final keys = snapshot.availableExerciseSummary.first.keys.toSet();
      expect(keys, contains('id'));
      expect(keys, contains('name'));
      expect(keys, contains('bodyPart'));
      expect(keys, contains('equipment'));
      expect(keys, contains('requiredEquipment'));
      expect(keys, contains('difficulty'));
      expect(keys, contains('isCompound'));
      // Heavy fields should NOT be present in the summary.
      expect(keys, isNot(contains('formCues')));
      expect(keys, isNot(contains('commonMistakes')));
      expect(keys, isNot(contains('instructions')));
      expect(keys, isNot(contains('antiCheatTips')));
    });

    test('toJson serializes the snapshot to a Map', () async {
      final state = await primedAppStateWithProfile();
      final snapshot = const AgentContextBuilder().build(state);
      final json = snapshot.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json.containsKey('locale'), true);
      expect(json.containsKey('progressSummary'), true);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/services/app_state.dart';

Future<AppState> _createState() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.resetAllData();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('previews valid import without mutating current state', () async {
    final state = await _createState();
    state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));

    final preview = state.previewImportJson(
      json.encode({
        'version': 1,
        'profile': UserProfile(goal: FitnessGoal.loseFat).toJson(),
        'sessions': [
          WorkoutSession(
            id: 'session-1',
            dayType: WorkoutDayType.push,
            isCompleted: true,
          ).toJson(),
        ],
      }),
    );

    expect(preview.isValid, isTrue);
    expect(preview.error, isNull);
    expect(preview.snapshot!.profile!.goal, FitnessGoal.loseFat);
    expect(preview.snapshot!.sessions.single.id, 'session-1');
    expect(state.profile!.goal, FitnessGoal.buildMuscle);
  });

  test(
    'rejects unsupported import versions without mutating current state',
    () async {
      final state = await _createState();
      state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));

      final preview = state.previewImportJson(
        json.encode({
          'version': AppState.currentExportVersion + 1,
          'profile': UserProfile(goal: FitnessGoal.loseFat).toJson(),
        }),
      );
      final error = state.importFromJson(
        json.encode({
          'version': AppState.currentExportVersion + 1,
          'profile': UserProfile(goal: FitnessGoal.loseFat).toJson(),
        }),
      );

      expect(preview.isValid, isFalse);
      expect(preview.error, contains('不支持'));
      expect(error, contains('不支持'));
      expect(state.profile!.goal, FitnessGoal.buildMuscle);
    },
  );

  test('preview import does not expose current mutable session list', () async {
    final state = await _createState();
    state.saveSession(
      WorkoutSession(
        id: 'current-session',
        dayType: WorkoutDayType.push,
        isCompleted: true,
      ),
    );

    final preview = state.previewImportJson(json.encode({'version': 1}));

    preview.snapshot!.sessions.clear();

    expect(state.sessions.single.id, 'current-session');
  });

  test('rejects_import_json_over_size_limit', () async {
    final state = await _createState();
    state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));
    final huge = json.encode({
      'version': 1,
      'padding': List.filled(1000001, 'x').join(),
    });

    final preview = state.previewImportJson(huge);
    final error = state.importFromJson(huge);

    expect(preview.isValid, isFalse);
    expect(preview.error, contains('过大'));
    expect(error, contains('过大'));
    expect(state.profile!.goal, FitnessGoal.buildMuscle);
  });

  test('rejects_out_of_range_profile_values', () async {
    final state = await _createState();
    state.saveProfile(UserProfile(goal: FitnessGoal.buildMuscle));
    final profile = UserProfile(goal: FitnessGoal.loseFat).toJson()
      ..['weightKg'] = -1
      ..['weeklyFrequency'] = 999
      ..['age'] = 3;

    final preview = state.previewImportJson(
      json.encode({'version': 1, 'profile': profile}),
    );
    final error = state.importFromJson(
      json.encode({'version': 1, 'profile': profile}),
    );

    expect(preview.isValid, isFalse);
    expect(error, isNotNull);
    expect(state.profile!.goal, FitnessGoal.buildMuscle);
  });

  test('rejects_plan_with_too_many_days_or_exercises', () async {
    final state = await _createState();
    final plan = _validPlanJson()
      ..['days'] = [
        for (var i = 0; i < 15; i++)
          {
            'dayOfWeek': (i % 7) + 1,
            'dayType': WorkoutDayType.upper.name,
            'exercises': const <Map<String, dynamic>>[],
          },
      ];

    final preview = state.previewImportJson(
      json.encode({'version': 1, 'activePlan': plan}),
    );

    expect(preview.isValid, isFalse);
    expect(preview.error, contains('训练计划'));
  });

  test('rejects_import_with_absurd_body_metric_values', () async {
    final state = await _createState();

    final preview = state.previewImportJson(
      json.encode({
        'version': 1,
        'bodyMetrics': [
          {
            'id': 'metric-1',
            'date': DateTime.now().toIso8601String(),
            'weightKg': 999999,
          },
        ],
      }),
    );

    expect(preview.isValid, isFalse);
    expect(preview.error, contains('身体数据'));
  });

  test('export does not include AgentEventLog', () async {
    final state = await _createState();
    final exported = json.decode(state.exportToJson()) as Map<String, dynamic>;

    expect(exported.containsKey('agentEventLog'), false);
    expect(exported.containsKey('agentEvents'), false);
  });
}

Map<String, dynamic> _validPlanJson() => WorkoutPlan(
  id: 'plan-1',
  name: 'Plan',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.upperLower,
  weeklyFrequency: 4,
  days: [
    WorkoutDay(
      dayOfWeek: 1,
      dayType: WorkoutDayType.upper,
      exercises: [
        PlannedExercise(
          exerciseId: 'bench_press',
          exerciseName: 'Bench Press',
          targetSets: 3,
          targetReps: 10,
          restSeconds: 90,
        ),
      ],
    ),
  ],
).toJson();

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
}

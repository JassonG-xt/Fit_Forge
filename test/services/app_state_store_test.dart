import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/services/app_state_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('writes and loads app state snapshot', () async {
    const store = AppStateStore();
    final profile = UserProfile(goal: FitnessGoal.loseFat);
    final session = WorkoutSession(
      id: 's1',
      dayType: WorkoutDayType.push,
      isCompleted: true,
      date: DateTime(2026, 4, 21),
    );

    await store.write(
      AppStateSnapshot(
        profile: profile,
        sessions: [session],
        achievements: defaultAchievements(),
        hasCompletedOnboarding: true,
        themeMode: ThemeMode.light,
      ),
    );

    final loaded = await store.load();

    expect(loaded.profile!.goal, FitnessGoal.loseFat);
    expect(loaded.sessions.single.id, 's1');
    expect(loaded.hasCompletedOnboarding, isTrue);
    expect(loaded.themeMode, ThemeMode.light);
    expect(loaded.version, AppStateSnapshot.currentVersion);
  });

  test('loads legacy snapshots as version 1', () async {
    SharedPreferences.setMockInitialValues({
      'hasCompletedOnboarding': true,
      'themeMode': ThemeMode.light.name,
    });

    const store = AppStateStore();
    final loaded = await store.load();

    expect(loaded.version, 1);
    expect(loaded.hasCompletedOnboarding, isTrue);
  });

  test('keeps valid persisted fields when one field is corrupt', () async {
    final profile = UserProfile(goal: FitnessGoal.loseFat);
    SharedPreferences.setMockInitialValues({
      'profile': json.encode(profile.toJson()),
      'sessions': 'not-json',
      'hasCompletedOnboarding': true,
      'themeMode': ThemeMode.light.name,
    });

    const store = AppStateStore();
    final loaded = await store.load();

    expect(loaded.profile!.goal, FitnessGoal.loseFat);
    expect(loaded.sessions, isEmpty);
    expect(loaded.hasCompletedOnboarding, isTrue);
    expect(loaded.themeMode, ThemeMode.light);
  });

  test('migrates old default dark theme to light once', () async {
    SharedPreferences.setMockInitialValues({'themeMode': ThemeMode.dark.name});

    const store = AppStateStore();
    final firstLoad = await store.load();
    final secondLoad = await store.load();

    expect(firstLoad.themeMode, ThemeMode.light);
    expect(secondLoad.themeMode, ThemeMode.light);
  });

  test('stores and clears in-progress workout recovery payload', () async {
    const store = AppStateStore();
    final payload = {
      'dayType': WorkoutDayType.push.name,
      'currentIndex': 1,
      'records': <String, dynamic>{},
    };

    await store.saveInProgressSession(payload);
    expect(await store.loadInProgressSession(), payload);

    await store.clearInProgressSession();
    expect(await store.loadInProgressSession(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/main.dart';
import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/services/app_state.dart';

/// ════════════════════════════════════════════════════════════════════
///  Shared test fixtures for screen widget tests.
/// ════════════════════════════════════════════════════════════════════
///  Rationale: every screen test needs (a) mocked SharedPreferences,
///  (b) an initialized AppState, (c) optional preset state (profile /
///  active plan / etc). Centralizing these here keeps each test file
///  focused on the assertions that matter for *that* screen.
///
///  Usage pattern:
///  ```dart
///  late AppState appState;
///  setUp(() async {
///    appState = await primedAppStateWithProfile();
///  });
///  ```
/// ════════════════════════════════════════════════════════════════════

/// Returns a fresh AppState backed by empty SharedPreferences.
/// `hasCompletedOnboarding` is false — simulates a brand-new user.
///
/// Screen tests do not need the full asset-backed exercise/food libraries, and
/// repeatedly calling AppState.init() from widget fake-async tests can leave
/// rootBundle asset loads unresolved. resetAllData() seeds the user-owned state
/// these tests assert without touching assets.
Future<AppState> freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.resetAllData();
  return state;
}

/// Returns an AppState with a default UserProfile saved.
/// `hasCompletedOnboarding` is true — simulates a returning user
/// who finished onboarding but has no active plan or sessions yet.
Future<AppState> primedAppStateWithProfile({UserProfile? profile}) async {
  final state = await freshAppState();
  state.saveProfile(profile ?? UserProfile());
  await state.flushPendingPersistence();
  return state;
}

/// Pumps the full FitForgeApp widget tree with the given AppState.
///
/// Uses single-frame `pump()` instead of a fixed duration. Rationale:
/// Material 3 components like SegmentedButton run a continuous entry
/// animation; `pump(Duration)` advances fake time and processes every
/// frame within it, so 500ms → ~30 frames × full layout/paint per frame
/// → many seconds of real time on slower machines. A single `pump()`
/// processes the initial Provider rebuild + post-frame callbacks, which
/// is all widget tests need to assert tree contents. If a specific test
/// needs to exercise a tap or animation, the test itself adds its own
/// `pump(Duration)` — keep this helper minimal.
Future<void> pumpFitForgeApp(WidgetTester tester, AppState appState) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const FitForgeApp(),
    ),
  );
  await tester.pump();
}

/// Pumps a specific screen widget in isolation (without the top-level
/// MaterialApp routing). Use when a test cares about one screen's
/// behavior and wants to avoid triggering the onboarding/main routing.
///
/// See `pumpFitForgeApp` for the single-frame pump rationale.
Future<void> pumpIsolated(
  WidgetTester tester, {
  required AppState appState,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
}

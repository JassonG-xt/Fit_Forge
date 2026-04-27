import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/plan/plan_generator_screen.dart';
import 'package:fit_forge/screens/progress/achievements_screen.dart';
import 'package:fit_forge/screens/progress/body_metrics_screen.dart';
import 'package:fit_forge/screens/progress/calendar_screen.dart';
import 'package:fit_forge/screens/workout/rest_timer_screen.dart';
import 'package:fit_forge/services/app_state.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plan generator previews and adopts a generated plan', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.init();
    appState.saveProfile(
      UserProfile(
        weeklyFrequency: 3,
        availableEquipment: const [Equipment.bodyweight, Equipment.dumbbell],
      ),
    );
    await appState.flushPendingPersistence();

    await pumpIsolated(
      tester,
      appState: appState,
      child: const PlanGeneratorScreen(),
    );

    await tester.tap(find.text('生成计划'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('采用此计划'), findsOneWidget);

    await tester.ensureVisible(find.text('采用此计划'));
    await tester.pump();
    await tester.tap(find.text('采用此计划'));
    await tester.pump();
    await appState.flushPendingPersistence();

    expect(appState.activePlan, isNotNull);
  });

  testWidgets('body metrics screen adds and renders a metric', (tester) async {
    final appState = await primedAppStateWithProfile();

    await pumpIsolated(
      tester,
      appState: appState,
      child: const BodyMetricsScreen(),
    );

    expect(find.text('暂无数据，请先记录'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '体重 (kg)'),
      '72.5',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '腰围 (cm)'), '82');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(appState.bodyMetrics.single.weightKg, 72.5);
    expect(find.text('72.5kg'), findsOneWidget);
  });

  testWidgets('calendar screen opens a completed workout day summary', (
    tester,
  ) async {
    final appState = await primedAppStateWithProfile();
    final now = DateTime.now();
    appState.saveSession(
      WorkoutSession(
        id: 'calendar-session',
        dayType: WorkoutDayType.push,
        date: now,
        durationMinutes: 42,
        isCompleted: true,
        exerciseRecords: [
          ExerciseRecord(
            exerciseId: 'bench',
            exerciseName: 'Bench Press',
            sets: [
              SetRecord(setNumber: 1, weightKg: 80, reps: 8, isCompleted: true),
            ],
          ),
        ],
      ),
    );
    await appState.flushPendingPersistence();

    await pumpIsolated(
      tester,
      appState: appState,
      child: const CalendarScreen(),
    );

    await tester.tap(find.text('${now.day}').first);
    await tester.pumpAndSettle();

    expect(find.text('${now.month}/${now.day} 训练记录'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('42 分钟'), findsOneWidget);
  });

  testWidgets('achievements screen renders locked and unlocked states', (
    tester,
  ) async {
    final appState = await primedAppStateWithProfile();
    appState.saveSession(
      WorkoutSession(
        id: 'workout-1',
        dayType: WorkoutDayType.push,
        isCompleted: true,
      ),
    );
    await appState.flushPendingPersistence();

    await pumpIsolated(
      tester,
      appState: appState,
      child: const AchievementsScreen(),
    );

    expect(find.text('成就'), findsOneWidget);
    expect(find.textContaining('/'), findsWidgets);
  });

  testWidgets('rest timer supports pause, adjust, preset, and skip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RestTimerScreen(seconds: 30)),
    );

    expect(find.text('30'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('29'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.text('+15s'));
    await tester.pump();
    expect(find.text('44'), findsOneWidget);

    await tester.tap(find.text('60s'));
    await tester.pump();
    expect(find.text('1:00'), findsOneWidget);

    await tester.tap(find.text('跳过休息'));
    await tester.pumpAndSettle();
    expect(find.byType(RestTimerScreen), findsNothing);
  });
}

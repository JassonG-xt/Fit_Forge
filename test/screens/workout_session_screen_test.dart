import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/workout/workout_session_screen.dart';

import '../helpers/app_state_fixtures.dart';

// ════════════════════════════════════════════════════════════════════
//  WorkoutSessionScreen 测试 ── 训练会话的三阶段机制
// ════════════════════════════════════════════════════════════════════
//  训练会话有三个阶段（在一个 Scaffold 里切换 body）：
//   1. 热身页 `_warmupView`（默认进入）
//   2. 训练页 `_exerciseView`（跳过热身后）
//   3. 完成页 `_completedView`（全部组数打勾后）
//
//  这批测试守护前两阶段的关键跃迁（完成页需要构造更复杂的
//  ExerciseRecord 状态，放到 Sprint 2 单元测 state machine）：
//   - 默认进热身页
//   - AppBar 显示 dayType displayName
//   - "热身完成，开始训练"按钮存在
//   - tap 后进入训练页，第一个动作名可见
// ════════════════════════════════════════════════════════════════════

WorkoutDay _singleExerciseDay() => WorkoutDay(
      dayOfWeek: 1,
      dayType: WorkoutDayType.push,
      exercises: [
        PlannedExercise(
          exerciseId: 'ex001',
          exerciseName: 'Bench Press',
          targetSets: 3,
          targetReps: 10,
          restSeconds: 90,
        ),
      ],
    );

void main() {
  testWidgets(
    '打开训练会话默认进入热身页（AppBar 显示 dayType displayName）',
    (tester) async {
      final appState = await primedAppStateWithProfile();
      await pumpIsolated(
        tester,
        appState: appState,
        child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
      );

      expect(find.text('热身建议'), findsOneWidget);
      expect(find.text('热身完成，开始训练'), findsOneWidget);
      // AppBar 标题 = dayType displayName
      expect(find.text('推 (胸/肩/三头)'), findsOneWidget);
    },
  );

  testWidgets(
    '热身页可以选择跳过热身直接进入训练',
    (tester) async {
      final appState = await primedAppStateWithProfile();
      await pumpIsolated(
        tester,
        appState: appState,
        child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
      );

      expect(find.text('跳过热身'), findsOneWidget);
    },
  );

  testWidgets(
    'tap "热身完成" 进入训练页，第一个动作名可见',
    (tester) async {
      final appState = await primedAppStateWithProfile();
      await pumpIsolated(
        tester,
        appState: appState,
        child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
      );

      await tester.tap(find.text('热身完成，开始训练'));
      await tester.pump(const Duration(milliseconds: 500));

      // 离开热身页
      expect(find.text('热身建议'), findsNothing);
      // 进入训练页：第一个动作名应可见
      expect(find.text('Bench Press'), findsOneWidget);
    },
  );

  testWidgets(
    '训练页显示"完成这组"CTA（用户主要交互入口）',
    (tester) async {
      final appState = await primedAppStateWithProfile();
      await pumpIsolated(
        tester,
        appState: appState,
        child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
      );

      // 跳过热身进入训练页
      await tester.tap(find.text('跳过热身'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('完成这组'), findsOneWidget);
    },
  );

  testWidgets(
    'AppBar 有关闭按钮（用于中途退出）',
    (tester) async {
      final appState = await primedAppStateWithProfile();
      await pumpIsolated(
        tester,
        appState: appState,
        child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );
}

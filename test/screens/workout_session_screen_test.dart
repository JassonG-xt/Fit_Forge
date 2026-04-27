import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/workout/workout_session_screen.dart';
import 'package:fit_forge/services/app_state.dart';
import 'package:fit_forge/services/app_state_store.dart';

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

class _SlowRecoveryStore extends AppStateStore {
  final saveStarted = Completer<void>();
  final allowSave = Completer<void>();
  final events = <String>[];

  @override
  Future<void> clear() async {}

  @override
  Future<void> write(AppStateSnapshot snapshot) async {}

  @override
  Future<void> saveInProgressSession(Map<String, dynamic> sessionData) async {
    events.add('save-start');
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowSave.future;
    events.add('save-end');
  }

  @override
  Future<void> clearInProgressSession() async {
    events.add('clear');
  }
}

class _SessionFlushStore extends AppStateStore {
  final events = <String>[];

  @override
  Future<void> clear() async {}

  @override
  Future<void> write(AppStateSnapshot snapshot) async {
    events.add('write:${snapshot.sessions.length}');
  }

  @override
  Future<void> saveInProgressSession(Map<String, dynamic> sessionData) async {
    events.add('save');
  }

  @override
  Future<void> clearInProgressSession() async {
    events.add('clear');
  }
}

class _QueuedRecoveryStore extends AppStateStore {
  final events = <String>[];
  final _saveCompleters = <Completer<void>>[];
  final _saveCountWaiters = <int, Completer<void>>{};

  int get saveCount => _saveCompleters.length;

  @override
  Future<void> clear() async {}

  @override
  Future<void> write(AppStateSnapshot snapshot) async {}

  @override
  Future<void> saveInProgressSession(Map<String, dynamic> sessionData) async {
    final index = _saveCompleters.length;
    final allowSave = Completer<void>();
    _saveCompleters.add(allowSave);
    events.add('save-$index-start');
    _notifySaveCountWaiters();

    await allowSave.future;
    events.add('save-$index-end');
  }

  @override
  Future<void> clearInProgressSession() async {
    events.add('clear');
  }

  Future<void> waitForSaveCount(int count) {
    if (saveCount >= count) return Future.value();
    return (_saveCountWaiters[count] ??= Completer<void>()).future;
  }

  void completeLatestStartedSave() {
    for (var i = _saveCompleters.length - 1; i >= 0; i--) {
      final completer = _saveCompleters[i];
      if (!completer.isCompleted) {
        completer.complete();
        return;
      }
    }
    throw StateError('No pending save to complete');
  }

  void _notifySaveCountWaiters() {
    for (final entry in _saveCountWaiters.entries.toList()) {
      if (saveCount >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
  }
}

void main() {
  testWidgets('打开训练会话默认进入热身页（AppBar 显示 dayType displayName）', (tester) async {
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
  });

  testWidgets('热身页可以选择跳过热身直接进入训练', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
    );

    expect(find.text('跳过热身'), findsOneWidget);
  });

  testWidgets('tap "热身完成" 进入训练页，第一个动作名可见', (tester) async {
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
  });

  testWidgets('训练页显示"完成这组"CTA（用户主要交互入口）', (tester) async {
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
  });

  testWidgets('AppBar 有关闭按钮（用于中途退出）', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('退出训练前等待 pending autosave，避免恢复记录被旧写入覆盖', (tester) async {
    final store = _SlowRecoveryStore();
    final appState = AppState(store: store);
    await appState.resetAllData();
    appState.saveProfile(UserProfile());
    await appState.flushPendingPersistence();
    await pumpIsolated(
      tester,
      appState: appState,
      child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
    );

    await tester.tap(find.text('跳过热身'));
    await tester.pump();
    await store.saveStarted.future;

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pump();

    expect(store.events, ['save-start']);

    store.allowSave.complete();
    await tester.pumpAndSettle();
    await appState.flushPendingPersistence();

    expect(store.events, ['save-start', 'save-end', 'clear']);
  });

  testWidgets('保存训练时先落盘正式记录，再清除恢复草稿', (tester) async {
    final store = _SessionFlushStore();
    final appState = AppState(store: store);
    await appState.resetAllData();
    appState.saveProfile(UserProfile());
    await appState.flushPendingPersistence();
    store.events.clear();

    await pumpIsolated(
      tester,
      appState: appState,
      child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
    );

    await tester.tap(find.text('跳过热身'));
    await tester.pump();
    await tester.tap(find.text('完成这组'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    final clearIndex = store.events.indexOf('clear');
    expect(clearIndex, isNonNegative);
    expect(store.events.take(clearIndex), contains('write:1'));
  });

  testWidgets('退出训练前等待所有排队的 autosave，避免旧草稿复活', (tester) async {
    final store = _QueuedRecoveryStore();
    final appState = AppState(store: store);
    await appState.resetAllData();
    appState.saveProfile(UserProfile());
    await appState.flushPendingPersistence();

    await pumpIsolated(
      tester,
      appState: appState,
      child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
    );

    await tester.tap(find.text('跳过热身'));
    await tester.pump();
    await store.waitForSaveCount(1);

    await tester.tap(find.text('完成这组'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    store.completeLatestStartedSave();
    await tester.pump();
    expect(store.events, isNot(contains('clear')));

    await store.waitForSaveCount(2);
    store.completeLatestStartedSave();
    await tester.pumpAndSettle();
    await appState.flushPendingPersistence();

    expect(store.events.last, 'clear');
  });

  testWidgets('完成页支持复制训练总结到剪贴板', (tester) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = call.arguments as Map<Object?, Object?>;
              clipboardText = args['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: WorkoutSessionScreen(workoutDay: _singleExerciseDay()),
    );

    await tester.tap(find.text('跳过热身'));
    await tester.pump(const Duration(milliseconds: 500));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('完成这组'));
      await tester.pump();
    }

    await tester.tap(find.text('完成训练'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('训练完成!'), findsOneWidget);
    expect(find.text('复制训练总结'), findsOneWidget);

    await tester.tap(find.text('复制训练总结'));
    await tester.pump();

    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clip?.text, isNotNull);
    expect(clip!.text, contains('我刚完成了 FitForge 的推 (胸/肩/三头)训练'));
    expect(clip.text, contains('✅ 3 组'));
    expect(clip.text, contains('动作：Bench Press 3组'));
  });
}

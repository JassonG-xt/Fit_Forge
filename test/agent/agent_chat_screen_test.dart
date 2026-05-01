import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fit_forge/agent/agent_runtime.dart';
import 'package:fit_forge/agent/agent_service.dart';
import 'package:fit_forge/agent/local_agent_action_executor.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/agent/agent_chat_screen.dart';
import 'package:fit_forge/services/app_state.dart';

import '../helpers/app_state_fixtures.dart';

class _ChatHarness {
  _ChatHarness({required this.service, required this.state});
  final AgentService service;
  final AppState state;
}

void main() {
  Future<_ChatHarness> pumpChat(
    WidgetTester tester, {
    bool withPlan = false,
    AgentMode mode = AgentMode.mock,
    String baseUrl = '',
  }) async {
    final state = await primedAppStateWithProfile();
    if (withPlan) {
      state.adoptPlan(_seedPlan());
    }
    final service = AgentService(
      appState: state,
      client: MockAgentClient(delay: Duration.zero),
      executor: LocalAgentActionExecutor(state),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: service),
          Provider<AgentRuntime>.value(
            value: AgentRuntime(mode: mode, baseUrl: baseUrl),
          ),
        ],
        child: const MaterialApp(home: AgentChatScreen()),
      ),
    );
    await tester.pump();
    return _ChatHarness(service: service, state: state);
  }

  testWidgets('shows empty state and suggested prompts', (tester) async {
    await pumpChat(tester);
    expect(find.text('和你的 FitForge Coach 聊聊'), findsOneWidget);
    expect(find.text('帮我总结这周训练'), findsOneWidget);
  });

  testWidgets('tapping a suggested prompt sends a user message', (
    tester,
  ) async {
    await pumpChat(tester);
    await tester.tap(find.text('帮我总结这周训练'));
    await tester.pumpAndSettle();
    // The prompt chip persists and the user bubble adds another copy.
    expect(find.text('帮我总结这周训练'), findsNWidgets(2));
    expect(find.textContaining('本周训练'), findsWidgets);
    // weeklyReview is requiresConfirmation=false so no "应用修改" button.
    expect(find.text('应用修改'), findsNothing);
  });

  testWidgets('compress request renders an action card with confirm button', (
    tester,
  ) async {
    await pumpChat(tester);
    await tester.tap(find.text('今天只有 30 分钟，帮我压缩训练'));
    await tester.pumpAndSettle();
    expect(find.text('压缩今日训练'), findsOneWidget);
    expect(find.text('应用修改'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('cancelling an action disables the buttons', (tester) async {
    await pumpChat(tester);
    await tester.tap(find.text('今天只有 30 分钟，帮我压缩训练'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final applyButton = find.text('已处理');
    expect(applyButton, findsOneWidget);
  });

  testWidgets('confirming reschedule mutates the active plan', (tester) async {
    final harness = await pumpChat(tester, withPlan: true);
    final state = harness.state;
    expect(state.activePlan, isNotNull);

    final input = find.byType(TextField);
    await tester.enterText(input, '我这周只能周二、周四、周日练');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('应用修改'), findsOneWidget);
    await tester.tap(find.text('应用修改'));
    await tester.pumpAndSettle();

    final plan = state.activePlan!;
    expect(
      plan.days.firstWhere((d) => d.dayOfWeek == 2).dayType,
      WorkoutDayType.upper,
    );
    expect(
      plan.days.firstWhere((d) => d.dayOfWeek == 1).dayType,
      WorkoutDayType.rest,
    );
  });

  testWidgets('mock mode shows local-only privacy line', (tester) async {
    await pumpChat(tester);
    expect(find.textContaining('本地 Mock 模式：不会向任何后端发送数据'), findsOneWidget);
  });

  testWidgets('http mode shows remote host in privacy banner', (tester) async {
    await pumpChat(
      tester,
      mode: AgentMode.http,
      baseUrl: 'http://example.com:8000',
    );
    expect(find.textContaining('在线模式'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
  });

  testWidgets('privacy banner is dismissable', (tester) async {
    await pumpChat(tester);
    expect(find.text('我知道了'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.text('我知道了'), findsNothing);
  });
}

WorkoutPlan _seedPlan() => WorkoutPlan(
  id: 'seed',
  name: 'Seed',
  goal: FitnessGoal.buildMuscle,
  split: TrainingSplit.upperLower,
  weeklyFrequency: 2,
  days: [
    WorkoutDay(
      dayOfWeek: 1,
      dayType: WorkoutDayType.upper,
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
    for (var d = 2; d <= 6; d++)
      WorkoutDay(dayOfWeek: d, dayType: WorkoutDayType.rest),
    WorkoutDay(
      dayOfWeek: 7,
      dayType: WorkoutDayType.lower,
      exercises: [
        PlannedExercise(
          exerciseId: 'squat',
          exerciseName: 'Squat',
          targetSets: 4,
          targetReps: 8,
          restSeconds: 120,
        ),
      ],
    ),
  ],
);

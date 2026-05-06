import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/screens/agent/agent_weekly_review_panel.dart';

void main() {
  AgentAction makeWeeklyReview(Map<String, dynamic> payload) => AgentAction(
    id: 'r1',
    type: AgentActionType.weeklyReview,
    title: '本周训练复盘',
    summary: '近期 3 次训练。',
    requiresConfirmation: false,
    payload: payload,
  );

  Future<void> pumpPanel(WidgetTester tester, AgentAction action) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentWeeklyReviewPanel(action: action)),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders all sections with full payload', (tester) async {
    await pumpPanel(
      tester,
      makeWeeklyReview(const {
        'completedSessions': 3,
        'focusAreas': ['推（胸 / 肩 / 三头）', '腿'],
        'observations': ['训练间隔均匀。', '腿部恢复充足。'],
        'nextWeekSuggestions': ['保持每周 3 次训练。', '注意休息。'],
        'riskNotes': ['连续训练超过 7 天，建议休息一天。'],
      }),
    );
    expect(find.text('完成训练'), findsOneWidget);
    expect(find.text('3 次'), findsOneWidget);
    expect(find.text('重点部位'), findsOneWidget);
    expect(find.text('推（胸 / 肩 / 三头）、腿'), findsOneWidget);
    expect(find.text('观察'), findsOneWidget);
    expect(find.text('训练间隔均匀。'), findsOneWidget);
    expect(find.text('下周建议'), findsOneWidget);
    expect(find.text('保持每周 3 次训练。'), findsOneWidget);
    expect(find.text('风险提示'), findsOneWidget);
    expect(find.text('连续训练超过 7 天，建议休息一天。'), findsOneWidget);
  });

  testWidgets('omits sections when fields empty or absent', (tester) async {
    await pumpPanel(
      tester,
      makeWeeklyReview(const {
        'completedSessions': 0,
        'observations': ['最近没有训练记录。'],
      }),
    );
    expect(find.text('完成训练'), findsOneWidget);
    expect(find.text('0 次'), findsOneWidget);
    expect(find.text('观察'), findsOneWidget);
    // Sections that have no data must not render their headers.
    expect(find.text('重点部位'), findsNothing);
    expect(find.text('下周建议'), findsNothing);
    expect(find.text('风险提示'), findsNothing);
  });

  testWidgets('risk notes section only renders when riskNotes is non-empty', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      makeWeeklyReview(const {
        'completedSessions': 2,
        'nextWeekSuggestions': ['保持节奏。'],
        'riskNotes': <String>[],
      }),
    );
    expect(find.text('下周建议'), findsOneWidget);
    expect(find.text('风险提示'), findsNothing);
  });

  testWidgets('renders nothing when payload is empty', (tester) async {
    await pumpPanel(tester, makeWeeklyReview(const {}));
    expect(find.text('完成训练'), findsNothing);
    expect(find.text('观察'), findsNothing);
    expect(find.text('重点部位'), findsNothing);
  });

  testWidgets('renders nothing when payload is malformed', (tester) async {
    // observations contains a non-string element → parser fails → panel skips.
    await pumpPanel(
      tester,
      makeWeeklyReview(const {
        'observations': ['ok', 42],
      }),
    );
    expect(find.text('观察'), findsNothing);
    expect(find.text('完成训练'), findsNothing);
  });

  testWidgets('panel never renders apply / confirm / cancel mutation buttons', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      makeWeeklyReview(const {
        'completedSessions': 3,
        'observations': ['训练间隔均匀。'],
        'riskNotes': ['注意恢复。'],
      }),
    );
    // Panel itself shows insights only — no mutation buttons here.
    expect(find.text('应用修改'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('已处理'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/screens/home/home_screen.dart';

import '../helpers/app_state_fixtures.dart';

// ════════════════════════════════════════════════════════════════════
//  HomeScreen 测试 ── 首页空态与交互入口
// ════════════════════════════════════════════════════════════════════
//  HomeScreen 是用户完成 onboarding 后看到的第一页。根据是否
//  `activePlan` 存在，今日训练卡片有两种渲染：
//    - 空态：显示"还没有训练计划" + 引导生成计划
//    - 有计划态：显示"今日训练" + 动作列表 + "开始训练" CTA
//
//  这批测试先守护空态，因为：
//   1. fixtures 最小（只需 profile，无需 plan）
//   2. 新用户首次 login 就是这个场景
//   3. 有计划态需要 PlanEngine 生成 WorkoutPlan，复杂度大，
//      放到 Sprint 1.8 的后续增量（或 Sprint 2 freezed 重构后）。
// ════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('已 onboard 但无计划 → 显示"还没有训练计划"空态', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('还没有训练计划'), findsOneWidget);
    expect(find.text('点击生成个性化训练计划'), findsOneWidget);
    // 今日训练 CTA 不该出现（没有计划无法开始训练）
    expect(find.text('开始训练'), findsNothing);
  });

  testWidgets('AppBar 显示 FitForge 标题和 settings 入口', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    expect(find.text('FitForge'), findsOneWidget);
    // IndexedStack 挂载了 MoreScreen，里面也有 Icons.settings_outlined 入口；
    // 用 descendant 把查找范围收到 HomeScreen 子树，避免 2 个匹配。
    expect(
      find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('快捷入口区域存在', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    expect(find.text('快捷入口'), findsOneWidget);
  });

  testWidgets('首页默认不显示崩溃恢复提示（无未完成训练）', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    expect(appState.hasRecoverableSession, isFalse);
    expect(find.byIcon(Icons.restore), findsNothing);
  });
}

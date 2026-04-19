import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/screens/home/home_screen.dart';
import 'package:fit_forge/screens/library/exercise_library_screen.dart';
import 'package:fit_forge/screens/main_tab_screen.dart';
import 'package:fit_forge/screens/more/more_screen.dart';
import 'package:fit_forge/screens/nutrition/meal_plan_screen.dart';
import 'package:fit_forge/screens/progress/progress_tab_screen.dart';

import '../helpers/app_state_fixtures.dart';

// ════════════════════════════════════════════════════════════════════
//  MainTabScreen 测试 ── 5 个 tab 的导航契约
// ════════════════════════════════════════════════════════════════════
//  MainTabScreen 使用 IndexedStack——5 个 page **同时挂载**，仅以
//  index 切换显示。这是"tab 切换保状态"的关键，但给 widget test
//  带来两条隐性约束：
//
//   1. `find.text('动作库')` 会同时命中 NavigationBar label 和
//      ExerciseLibraryScreen 的 AppBar title。要断言 tab label，
//      必须把查找范围 descend 到 NavigationBar 子树。
//
//   2. `find.byType(ExerciseLibraryScreen)` 始终为 1（IndexedStack
//      里本来就存在），不能证明"切到该 tab"。验证切换要看
//      `tester.widget<IndexedStack>(...).index`。
// ════════════════════════════════════════════════════════════════════

/// 限定查找范围到 NavigationBar 子树——绕过 IndexedStack 里
/// 其他 screen 内部的同名文字。
Finder _tabLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('已完成 onboarding 用户应看到 MainTabScreen + 5 个 tab label', (
    tester,
  ) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    expect(find.byType(MainTabScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // 5 个 tab label 必须都在 NavigationBar 子树下
    expect(_tabLabel('首页'), findsOneWidget);
    expect(_tabLabel('动作库'), findsOneWidget);
    expect(_tabLabel('饮食'), findsOneWidget);
    expect(_tabLabel('进度'), findsOneWidget);
    expect(_tabLabel('更多'), findsOneWidget);
  });

  testWidgets('默认 IndexedStack.index == 0（Home tab 激活）', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 0);
  });

  testWidgets('tap "动作库" tab → IndexedStack.index 切到 1', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    // 用 descendant 精确定位 NavigationBar 里的 "动作库"
    await tester.tap(_tabLabel('动作库'));
    await tester.pump(const Duration(milliseconds: 500));

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
  });

  testWidgets('IndexedStack 结构：所有 5 个 page 同时挂载（切换不重建）', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    // IndexedStack 的特点：所有 child 都在 widget tree 里，
    // 仅靠 index 控制显示。这是"切换 tab 不丢状态"的关键。
    expect(find.byType(IndexedStack), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      find.byType(ExerciseLibraryScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(MealPlanScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(ProgressTabScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(MoreScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('tap "更多" tab → IndexedStack.index 切到 4（列表最后一个 tab）', (
    tester,
  ) async {
    final appState = await primedAppStateWithProfile();
    await pumpFitForgeApp(tester, appState);

    await tester.tap(_tabLabel('更多'));
    await tester.pump(const Duration(milliseconds: 500));

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 4);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/screens/settings/settings_screen.dart';

import '../helpers/app_state_fixtures.dart';

// ════════════════════════════════════════════════════════════════════
//  SettingsScreen 测试 ── 个人信息 / 主题 / 数据管理
// ════════════════════════════════════════════════════════════════════
//  Settings 有两态：
//   - profile == null → 显示"请先完成个人资料设置"空态
//   - profile != null → 显示完整菜单（目标/频率/主题/导出/导入/重置）
//
//  守护重点：
//   1. 主题切换按钮 tap 后 AppState.themeMode 反映变化（持久化契约）
//   2. 危险操作（清除所有数据）入口存在且显示 danger 色
//   3. 导出/导入入口对称存在（数据迁移闭环）
// ════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('profile == null 时显示"请先完成个人资料设置"空态', (tester) async {
    final appState = await freshAppState();
    await pumpIsolated(
      tester,
      appState: appState,
      child: const SettingsScreen(),
    );

    expect(find.text('请先完成个人资料设置'), findsOneWidget);
    // 完整菜单项不应出现
    expect(find.text('清除所有数据'), findsNothing);
  });

  testWidgets('profile 已设置 → AppBar 标题和核心菜单项全部可见', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: const SettingsScreen(),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('目标'), findsOneWidget);
    expect(find.text('每周频率'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('导出数据'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('导出数据'), findsOneWidget);
    expect(find.text('导入数据'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('清除所有数据'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('重新设置个人信息'), findsOneWidget);
    expect(find.text('清除所有数据'), findsOneWidget);
  });

  testWidgets('默认 themeMode 是 dark（与 AppState 构造默认一致）', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: const SettingsScreen(),
    );

    expect(appState.themeMode, ThemeMode.dark);
  });

  testWidgets('tap light 主题图标 → AppState.themeMode 翻为 light', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: const SettingsScreen(),
    );

    // SegmentedButton 里有 3 个 icon：dark_mode / brightness_auto / light_mode
    final lightModeIcon = find.byIcon(Icons.light_mode);
    expect(lightModeIcon, findsOneWidget);

    await tester.tap(lightModeIcon);
    await tester.pump(const Duration(milliseconds: 500));

    expect(appState.themeMode, ThemeMode.light);
  });

  testWidgets('"清除所有数据"入口存在（danger 色 CTA）', (tester) async {
    final appState = await primedAppStateWithProfile();
    await pumpIsolated(
      tester,
      appState: appState,
      child: const SettingsScreen(),
    );

    // Danger 入口文案：红色"清除所有数据"
    // 仅测 Text 存在；不触发 tap，以免触发清除流程影响后续测试
    await tester.scrollUntilVisible(
      find.text('清除所有数据'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('清除所有数据'), findsOneWidget);
    expect(find.text('删除个人信息、训练记录、成就等所有数据'), findsOneWidget);
  });
}

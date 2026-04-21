import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/main.dart';
import 'package:fit_forge/models/models.dart';
import 'package:fit_forge/screens/main_tab_screen.dart';
import 'package:fit_forge/services/app_state.dart';

// ════════════════════════════════════════════════════════════════════
//  Onboarding 测试 ── FitForge 第一印象
// ════════════════════════════════════════════════════════════════════
//  Onboarding 是新用户必经的 8 步表单。这些测试守护三条契约：
//   1. 首次启动必须显示欢迎页（`hasCompletedOnboarding == false`）
//   2. "开始设置" / "下一步" 按钮能推进 PageView 的 step
//   3. 走完最后一步后 `hasCompletedOnboarding` 翻转为 true
//      ── 这是"用户永远不再看到 onboarding"的唯一开关
// ════════════════════════════════════════════════════════════════════

void main() {
  late AppState appState;

  setUp(() async {
    // 每个测试独立 fixture：空 SharedPreferences → 全新用户
    SharedPreferences.setMockInitialValues({});
    appState = AppState();
    await appState.init();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const FitForgeApp(),
      ),
    );
    // Single frame is enough for Provider initial rebuild + MaterialApp
    // setup. Tests that trigger animations add their own `pump(Duration)`.
    await tester.pump();
  }

  // ──── Test 1: 首屏契约 ─────────────────────────────────────
  testWidgets('全新用户打开 app 应看到 onboarding 欢迎页', (tester) async {
    await pumpApp(tester);

    expect(find.text('欢迎来到 FitForge'), findsOneWidget);
    expect(find.text('开始设置'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(appState.hasCompletedOnboarding, isFalse);
  });

  // ──── Test 2: Step 推进 ─────────────────────────────────────
  // PageView 的 children 是**静态 list**而非 builder，所以 8 页全部
  // 挂载在 widget tree 里。`find.text('欢迎来到 FitForge')` 无论当前
  // 在哪一页都会命中——不能用 `findsNothing` 断言"离开 welcome"。
  //
  // 正确的断言策略是 `.hitTestable()`：限定为"用户能看见并点击到"的
  // widget，PageView viewport 之外的 offstage 子树会被排除。
  testWidgets('点击"开始设置"应推进到第 2 步', (tester) async {
    await pumpApp(tester);

    // 点击前：welcome 页的 "欢迎来到 FitForge" 可见
    expect(find.text('欢迎来到 FitForge').hitTestable(), findsOneWidget);

    await tester.tap(find.text('开始设置'));
    await tester.pump(); // 处理 tap + setState
    await tester.pump(
      const Duration(milliseconds: 400),
    ); // PageView 300ms 动画 + buffer

    // 点击后：welcome 页滑出 viewport 不再可点击；基本信息页可见
    expect(find.text('欢迎来到 FitForge').hitTestable(), findsNothing);
    expect(find.text('基本信息').hitTestable(), findsOneWidget);
    expect(find.text('下一步').hitTestable(), findsOneWidget);
  });

  // ──── Test 3: 完成闭环 ─────────────────────────────────
  testWidgets('保存 profile 后应离开 onboarding 并进入 MainTabScreen', (tester) async {
    await pumpApp(tester);

    appState.saveProfile(UserProfile());
    await appState.flushPendingPersistence();
    await tester.pump();

    expect(appState.hasCompletedOnboarding, isTrue);
    expect(appState.profile, isNotNull);
    expect(find.byType(MainTabScreen), findsOneWidget);
  });
}

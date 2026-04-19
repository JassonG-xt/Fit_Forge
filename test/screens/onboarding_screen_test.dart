import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/main.dart';
import 'package:fit_forge/services/app_state.dart';
// 皇上贡献点如选 [B] 或 [C]，请取消下一行注释以启用 MainTabScreen 断言：
// import 'package:fit_forge/screens/main_tab_screen.dart';

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
  testWidgets(
    '全新用户打开 app 应看到 onboarding 欢迎页',
    (tester) async {
      await pumpApp(tester);

      expect(find.text('欢迎来到 FitForge'), findsOneWidget);
      expect(find.text('开始设置'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(appState.hasCompletedOnboarding, isFalse);
    },
  );

  // ──── Test 2: Step 推进 ─────────────────────────────────────
  // PageView 的 children 是**静态 list**而非 builder，所以 8 页全部
  // 挂载在 widget tree 里。`find.text('欢迎来到 FitForge')` 无论当前
  // 在哪一页都会命中——不能用 `findsNothing` 断言"离开 welcome"。
  //
  // 正确的断言策略是 `.hitTestable()`：限定为"用户能看见并点击到"的
  // widget，PageView viewport 之外的 offstage 子树会被排除。
  testWidgets(
    '点击"开始设置"应推进到第 2 步',
    (tester) async {
      await pumpApp(tester);

      // 点击前：welcome 页的 "欢迎来到 FitForge" 可见
      expect(find.text('欢迎来到 FitForge').hitTestable(), findsOneWidget);

      await tester.tap(find.text('开始设置'));
      await tester.pump(); // 处理 tap + setState
      await tester.pump(const Duration(milliseconds: 400)); // PageView 300ms 动画 + buffer

      // 点击后：welcome 页滑出 viewport 不再可点击；基本信息页可见
      expect(find.text('欢迎来到 FitForge').hitTestable(), findsNothing);
      expect(find.text('基本信息').hitTestable(), findsOneWidget);
      expect(find.text('下一步').hitTestable(), findsOneWidget);
    },
  );

  // ──── Test 3: 完成闭环（皇上贡献点） ─────────────────────────────────
  // Context：
  //   走完全部 8 步 onboarding 后，app 应该：
  //     (a) 更新 AppState：`hasCompletedOnboarding` 翻为 true
  //     (b) 导航离开 OnboardingScreen，进入 MainTabScreen
  //
  //   若 (a) 断裂：下次启动还会进 onboarding，用户抓狂。
  //   若 (b) 断裂：profile 被保存但 UI 卡在最后一页，看起来"点了没用"。
  //
  // 断言策略的三种选择：
  //
  //   [A] 只测应用层状态  →  `expect(appState.hasCompletedOnboarding, isTrue);`
  //       优点：直接守护业务契约，UI 改版不会假阳性
  //       缺点：不验证用户真的看到主界面
  //
  //   [B] 只测 UI 导航     →  `expect(find.byType(MainTabScreen), findsOneWidget);`
  //       优点：端到端用户体验守护
  //       缺点：与路由实现耦合（换 go_router 会挂）
  //
  //   [C] A + B 都测        →  双保险
  //       优点：分层守护，任一环节断裂都会抛
  //       缺点：测试变长、重复
  //
  // 臣推荐 C；但 A 也是合格的 MVP。
  //
  // TODO 皇上落地：在下方 8-10 行内选择一个方向并实现。
  //   参考推进流程（可直接粘贴到测试体里）：
  //     await tester.tap(find.text('开始设置'));
  //     await tester.pump(const Duration(milliseconds: 500));
  //     for (var i = 0; i < 6; i++) {
  //       await tester.tap(find.text('下一步'));
  //       await tester.pump(const Duration(milliseconds: 500));
  //     }
  //     await tester.tap(find.text('开始训练'));
  //     await tester.pump(const Duration(milliseconds: 500));
  //     // → 皇上的 assertion (A / B / C)
  testWidgets(
    '完成 8 步 onboarding 应翻转 hasCompletedOnboarding',
    (tester) async {
      await pumpApp(tester);

      // TODO: 皇上在此实现——选择 A/B/C 断言策略
      // （删除下方 skip: true 让这个测试跑起来）
    },
    skip: true, // TODO 皇上贡献点：assertion 策略待选型 (A/B/C)
  );
}

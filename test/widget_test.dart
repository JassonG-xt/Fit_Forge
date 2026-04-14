import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/main.dart';
import 'package:fit_forge/services/app_state.dart';

void main() {
  testWidgets('App should build and show onboarding', (WidgetTester tester) async {
    // Mock SharedPreferences — 必须在 getInstance() 之前调用，
    // 否则测试环境没有原生平台响应，会永远挂起。
    SharedPreferences.setMockInitialValues({});

    final appState = AppState();
    await appState.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const FitForgeApp(),
      ),
    );

    // 首次启动应显示 Onboarding（未完成过）
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('欢迎来到 FitForge'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fit_forge/main.dart';
import 'package:fit_forge/services/app_state.dart';

void main() {
  testWidgets('App should build without errors', (WidgetTester tester) async {
    final appState = AppState();
    await appState.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const FitForgeApp(),
      ),
    );

    // App 应正常构建并显示 MaterialApp
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

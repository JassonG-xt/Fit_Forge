import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/screens/workout/exercise_detail_screen.dart';
import 'package:fit_forge/services/app_state.dart';

import '../helpers/app_state_fixtures.dart';

Future<AppState> _assetBackedAppState() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState();
  await state.init();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unknown exercise id renders not-found state', (tester) async {
    final appState = await freshAppState();
    await pumpIsolated(
      tester,
      appState: appState,
      child: const ExerciseDetailScreen(exerciseId: 'missing-exercise'),
    );

    expect(find.text('动作未找到'), findsOneWidget);
  });

  testWidgets(
    'renders bundled exercise detail and opens alternative exercise',
    (tester) async {
      final appState = await _assetBackedAppState();
      await pumpIsolated(
        tester,
        appState: appState,
        child: const ExerciseDetailScreen(exerciseId: 'ex001'),
      );

      expect(find.text('杠铃平板卧推'), findsOneWidget);
      expect(find.text('胸部'), findsWidgets);
      expect(find.text('动作讲解'), findsOneWidget);
      expect(find.text('动作要点'), findsOneWidget);
      expect(find.text('避免借力'), findsOneWidget);
      expect(find.text('常见错误'), findsOneWidget);
      expect(find.text('推荐训练参数'), findsOneWidget);
      expect(find.text('替代动作'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('哑铃平板卧推'),
        300,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('哑铃平板卧推'));
      await tester.pumpAndSettle();

      expect(find.text('哑铃平板卧推'), findsWidgets);
      expect(find.text('哑铃'), findsWidgets);
    },
  );
}

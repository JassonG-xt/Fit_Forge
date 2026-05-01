import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'agent/agent_client.dart';
import 'agent/agent_service.dart';
import 'agent/http_agent_client.dart';
import 'agent/mocks/mock_agent_client.dart';
import 'services/app_state.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/main_tab_screen.dart';
import 'theme/app_theme.dart';

/// 后端 base URL。空字符串表示使用本地 Mock 客户端。
///
/// 启动时通过 `--dart-define=AGENT_BASE_URL=http://localhost:8000` 指定。
const _agentBaseUrl = String.fromEnvironment('AGENT_BASE_URL');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = AppState();
  await appState.init();

  final AgentClient agentClient = _agentBaseUrl.isEmpty
      ? MockAgentClient()
      : HttpAgentClient(baseUrl: _agentBaseUrl);

  final agentService = AgentService(
    appState: appState,
    client: agentClient,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<AgentService>.value(value: agentService),
      ],
      child: const FitForgeApp(),
    ),
  );
}

class FitForgeApp extends StatelessWidget {
  const FitForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return MaterialApp(
          title: 'FitForge',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: state.themeMode,
          home: state.hasCompletedOnboarding
              ? const MainTabScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'agent/agent_client.dart';
import 'agent/agent_event_log.dart';
import 'agent/agent_runtime.dart';
import 'agent/agent_service.dart';
import 'agent/http_agent_client.dart';
import 'agent/mocks/mock_agent_client.dart';
import 'services/app_state.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/main_tab_screen.dart';
import 'theme/app_theme.dart';

/// 显式 Agent 模式（`mock` / `http`）。
///
/// 通过 `--dart-define=FITFORGE_AGENT_MODE=...` 指定。空字符串时，
/// 若 [_agentBaseUrl] 非空则推断为 `http`（向后兼容旧文档），否则 `mock`。
const _agentMode = String.fromEnvironment('FITFORGE_AGENT_MODE');

/// HTTP 模式下的后端 base URL。
///
/// 通过 `--dart-define=AGENT_BASE_URL=http://localhost:8000` 指定。
const _agentBaseUrl = String.fromEnvironment('AGENT_BASE_URL');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = AppState();
  await appState.init();

  final mode = _resolveAgentMode();
  final AgentClient agentClient = _createAgentClient(mode);

  final eventLog = AgentEventLog();
  await eventLog.hydrate();

  final agentService = AgentService(
    appState: appState,
    client: agentClient,
    eventLog: eventLog,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<AgentService>.value(value: agentService),
        ChangeNotifierProvider<AgentEventLog>.value(value: eventLog),
        Provider<AgentRuntime>.value(
          value: AgentRuntime(mode: mode, baseUrl: _agentBaseUrl),
        ),
      ],
      child: const FitForgeApp(),
    ),
  );
}

AgentMode _resolveAgentMode() {
  final raw = _agentMode.isNotEmpty
      ? _agentMode
      : (_agentBaseUrl.isNotEmpty ? 'http' : 'mock');
  switch (raw) {
    case 'mock':
      return AgentMode.mock;
    case 'http':
      return AgentMode.http;
    default:
      throw StateError(
        'Unknown FITFORGE_AGENT_MODE="$raw" (expected "mock" or "http")',
      );
  }
}

AgentClient _createAgentClient(AgentMode mode) {
  switch (mode) {
    case AgentMode.mock:
      return MockAgentClient();
    case AgentMode.http:
      if (_agentBaseUrl.isEmpty) {
        throw StateError(
          'FITFORGE_AGENT_MODE=http 时必须同时提供 '
          '--dart-define=AGENT_BASE_URL=http://your-backend',
        );
      }
      return HttpAgentClient(baseUrl: _agentBaseUrl);
  }
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

/// Coach Agent 当前运行模式。
///
/// 用于 UI 在隐私说明里区分本地 mock 与 HTTP 后端。
enum AgentMode { mock, http }

/// 运行时元信息：当前 Agent 模式 + （http 模式下的）后端 base URL。
///
/// 通过 Provider 注入，UI 用它来渲染隐私横幅、调试栏等。
class AgentRuntime {
  const AgentRuntime({required this.mode, required this.baseUrl});

  final AgentMode mode;
  final String baseUrl;

  bool get isHttp => mode == AgentMode.http;
}

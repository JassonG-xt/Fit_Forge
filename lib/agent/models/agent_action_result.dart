/// LocalAgentActionExecutor 执行后的结果。
///
/// 由 UI 层用于显示成功/失败 SnackBar 或 Toast。
class AgentActionResult {
  const AgentActionResult({
    required this.success,
    required this.title,
    required this.message,
  });

  factory AgentActionResult.success({
    required String title,
    required String message,
  }) {
    return AgentActionResult(success: true, title: title, message: message);
  }

  factory AgentActionResult.failure(String message) {
    return AgentActionResult(success: false, title: '操作失败', message: message);
  }

  factory AgentActionResult.noop(String message) {
    return AgentActionResult(success: true, title: '无需修改', message: message);
  }

  final bool success;
  final String title;
  final String message;
}

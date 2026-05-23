import 'models/agent_context_snapshot.dart';
import 'models/agent_message.dart';
import 'models/agent_response.dart';
import 'intent/pending_clarification.dart';

/// Coach Agent 通信接口。
///
/// 抽象 mock 与 HTTP 两种实现，便于本地开发和后端切换。
abstract class AgentClient {
  Future<AgentResponse> sendMessage({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
    PendingClarification? pendingClarification,
  });
}

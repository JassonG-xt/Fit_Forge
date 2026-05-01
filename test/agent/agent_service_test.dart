import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/agent_client.dart';
import 'package:fit_forge/agent/agent_service.dart';
import 'package:fit_forge/agent/local_agent_action_executor.dart';
import 'package:fit_forge/agent/mocks/mock_agent_client.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_context_snapshot.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_message.dart';
import 'package:fit_forge/agent/models/agent_response.dart';

import '../helpers/app_state_fixtures.dart';

class _ThrowingAgentClient implements AgentClient {
  @override
  Future<AgentResponse> sendMessage({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
  }) async {
    throw Exception('connection refused');
  }
}

void main() {
  group('AgentService', () {
    test('sendUserMessage appends user + assistant messages', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('我这周只能周二、周四、周日练');

      expect(service.messages, hasLength(2));
      expect(service.messages.first.role, AgentMessageRole.user);
      expect(service.messages.last.role, AgentMessageRole.assistant);
      expect(
        service.messages.last.actions.first.type,
        AgentActionType.rescheduleWeek,
      );
      expect(service.isSending, false);
    });

    test('cancelAction does not modify AppState plan', () async {
      final state = await primedAppStateWithProfile();
      final planBefore = state.activePlan;
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('帮我生成一份新训练计划');
      final action = service.messages.last.actions.single;
      service.cancelAction(action);

      expect(state.activePlan, equals(planBefore));
      expect(service.isActionResolved(action.id), true);
    });

    test('confirmAction returns noop result for read-only actions', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('帮我总结这周训练');
      final action = service.messages.last.actions.single;
      expect(action.type, AgentActionType.weeklyReview);

      final result = await service.confirmAction(action);
      expect(result.success, true);
      expect(result.title, '无需修改');
      expect(service.isActionResolved(action.id), true);
    });

    test('blank input is ignored', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('   ');
      expect(service.messages, isEmpty);
    });

    test('safety prompt sets intent to safetyResponse', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: MockAgentClient(delay: Duration.zero),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('我胸口疼但想继续高强度训练');

      // The intent shows up via the assistant's action, not directly.
      final action = service.messages.last.actions.single;
      expect(action.type, AgentActionType.safetyResponse);
      expect(action.riskLevel, AgentActionRiskLevel.high);

      // confirm should be a noop for safety responses
      final result = await service.confirmAction(action);
      expect(result.success, true);
    });

    test('intent enum name matches expected values', () {
      // Sanity: ensure mapping aligns with backend strings.
      expect(AgentIntent.rescheduleWeek.name, 'rescheduleWeek');
      expect(AgentIntent.compressWorkout.name, 'compressWorkout');
      expect(AgentIntent.safetyResponse.name, 'safetyResponse');
    });

    test('client failure is surfaced as an error assistant bubble', () async {
      final state = await primedAppStateWithProfile();
      final service = AgentService(
        appState: state,
        client: _ThrowingAgentClient(),
        executor: LocalAgentActionExecutor(state),
      );

      await service.sendUserMessage('帮我调整训练');

      expect(service.messages, hasLength(2));
      expect(service.messages.last.role, AgentMessageRole.assistant);
      expect(service.messages.last.isError, true);
      expect(service.messages.last.content, contains('暂时无法连接'));
      expect(service.lastError, contains('connection refused'));
    });
  });
}

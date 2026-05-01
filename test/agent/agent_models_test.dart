import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_message.dart';
import 'package:fit_forge/agent/models/agent_response.dart';

void main() {
  group('AgentAction JSON', () {
    test('roundtrip preserves type, risk and payload', () {
      final action = AgentAction(
        id: 'a1',
        type: AgentActionType.rescheduleWeek,
        title: '调整',
        summary: '把周二、周四、周日定为训练日',
        requiresConfirmation: true,
        riskLevel: AgentActionRiskLevel.medium,
        payload: const {
          'availableWeekdays': [2, 4, 7],
        },
      );

      final restored = AgentAction.fromJson(action.toJson());

      expect(restored.id, action.id);
      expect(restored.type, AgentActionType.rescheduleWeek);
      expect(restored.riskLevel, AgentActionRiskLevel.medium);
      expect(restored.requiresConfirmation, true);
      expect(restored.payload['availableWeekdays'], [2, 4, 7]);
    });

    test('unknown type falls back to answerOnly', () {
      final action = AgentAction.fromJson(const {
        'id': 'a2',
        'type': 'thisDoesNotExist',
        'title': 't',
        'summary': 's',
        'requiresConfirmation': false,
      });
      expect(action.type, AgentActionType.answerOnly);
      expect(action.riskLevel, AgentActionRiskLevel.low);
    });
  });

  group('AgentMessage JSON', () {
    test('roundtrip preserves role, actions and isError', () {
      final original = AgentMessage(
        id: 'm1',
        role: AgentMessageRole.assistant,
        content: 'hello',
        createdAt: DateTime.utc(2026, 4, 30, 10, 0, 0),
        actions: [
          AgentAction(
            id: 'inner',
            type: AgentActionType.compressWorkout,
            title: '压缩',
            summary: '25 分钟',
            requiresConfirmation: true,
          ),
        ],
        isError: false,
      );
      final restored = AgentMessage.fromJson(original.toJson());
      expect(restored.role, AgentMessageRole.assistant);
      expect(restored.content, 'hello');
      expect(restored.actions.length, 1);
      expect(restored.actions.first.type, AgentActionType.compressWorkout);
      expect(restored.isError, false);
    });
  });

  group('AgentResponse JSON', () {
    test('parses safety block and confidence', () {
      final json = {
        'message': '建议停止训练',
        'intent': 'safetyResponse',
        'confidence': 0.92,
        'actions': [
          {
            'id': 'safe',
            'type': 'safetyResponse',
            'title': '风险',
            'summary': '请停止训练',
            'requiresConfirmation': false,
            'riskLevel': 'high',
            'payload': {'matchedRisks': ['chest_pain']},
          },
        ],
        'safety': {
          'hasMedicalConcern': true,
          'shouldStopWorkout': true,
          'disclaimer': 'no medical advice',
        },
      };
      final response = AgentResponse.fromJson(json);
      expect(response.intent, AgentIntent.safetyResponse);
      expect(response.confidence, closeTo(0.92, 1e-6));
      expect(response.safety.hasMedicalConcern, true);
      expect(response.safety.shouldStopWorkout, true);
      expect(response.actions.first.type, AgentActionType.safetyResponse);
      expect(response.actions.first.riskLevel, AgentActionRiskLevel.high);
    });
  });
}

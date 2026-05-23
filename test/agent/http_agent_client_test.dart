import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fit_forge/agent/agent_context_builder.dart';
import 'package:fit_forge/agent/http_agent_client.dart';
import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_intent.dart';
import 'package:fit_forge/agent/models/agent_message.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  group('HttpAgentClient', () {
    test(
      'POSTs to /v1/coach/message with message + context + history',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);

        late http.Request capturedRequest;
        final mockHttp = MockClient((http.Request request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'message': '已重新安排',
              'intent': 'rescheduleWeek',
              'confidence': 0.9,
              'actions': [
                {
                  'id': 'mocked',
                  'type': 'rescheduleWeek',
                  'title': '重新安排',
                  'summary': '周二、周四、周日',
                  'requiresConfirmation': true,
                  'riskLevel': 'low',
                  'payload': {
                    'availableWeekdays': [2, 4, 7],
                  },
                },
              ],
              'safety': {
                'hasMedicalConcern': false,
                'shouldStopWorkout': false,
                'disclaimer': 'no medical advice',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = HttpAgentClient(
          baseUrl: 'http://example.com',
          httpClient: mockHttp,
        );

        final response = await client.sendMessage(
          message: '帮我把训练改到周二、周四、周日',
          context: context,
          history: const [],
        );

        expect(capturedRequest.url.path, '/v1/coach/message');
        expect(capturedRequest.method, 'POST');
        expect(
          capturedRequest.headers['content-type'],
          contains('application/json'),
        );
        final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
        expect(body['message'], contains('训练'));
        expect(body['context'], isA<Map<String, dynamic>>());
        expect(body['history'], isA<List<dynamic>>());

        expect(response.intent, AgentIntent.rescheduleWeek);
        expect(response.actions.first.type, AgentActionType.rescheduleWeek);
        expect(response.actions.first.payload['availableWeekdays'], [2, 4, 7]);
      },
    );

    test('serializes assistant history actions as minimal metadata', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);

      late Map<String, dynamic> capturedBody;
      final mockHttp = MockClient((http.Request request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'message': 'ok',
            'intent': 'answerOnly',
            'confidence': 0.5,
            'actions': <Map<String, dynamic>>[],
            'safety': {
              'hasMedicalConcern': false,
              'shouldStopWorkout': false,
              'disclaimer': 'no medical advice',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HttpAgentClient(
        baseUrl: 'http://example.com',
        httpClient: mockHttp,
      );

      await client.sendMessage(
        message: '那今天轻一点',
        context: context,
        history: [
          AgentMessage(
            id: 'user-1',
            role: AgentMessageRole.user,
            content: '最近训练怎么样',
            createdAt: DateTime(2026, 1, 1, 10),
          ),
          AgentMessage(
            id: 'assistant-1',
            role: AgentMessageRole.assistant,
            content: '本周训练复盘',
            createdAt: DateTime(2026, 1, 1, 10, 1),
            actions: [
              AgentAction(
                id: 'review-1',
                type: AgentActionType.weeklyReview,
                title: '本周训练复盘',
                summary: '本周完成 3 次训练。',
                requiresConfirmation: false,
                payload: const {'summary': '本周完成 3 次训练。'},
                sourceContextHash: 'should_not_be_sent',
              ),
            ],
          ),
        ],
      );

      final history = capturedBody['history'] as List<dynamic>;
      expect(history.first, isNot(contains('actions')));

      final assistant = history.last as Map<String, dynamic>;
      final actions = assistant['actions'] as List<dynamic>;
      expect(actions, hasLength(1));
      expect(actions.single, {
        'id': 'review-1',
        'type': 'weeklyReview',
        'requiresConfirmation': false,
      });
      expect(actions.single, isNot(contains('payload')));
      expect(actions.single, isNot(contains('sourceContextHash')));
      expect(actions.single, isNot(contains('title')));
      expect(actions.single, isNot(contains('summary')));
    });

    test('non-2xx status throws HttpAgentException with status code', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final mockHttp = MockClient(
        (request) async => http.Response('upstream error', 502),
      );
      final client = HttpAgentClient(
        baseUrl: 'http://example.com',
        httpClient: mockHttp,
      );

      await expectLater(
        client.sendMessage(message: '你好', context: context, history: const []),
        throwsA(
          isA<HttpAgentException>().having(
            (e) => e.statusCode,
            'statusCode',
            502,
          ),
        ),
      );
    });

    test(
      'non-JSON body raises FormatException-derived HttpAgentException',
      () async {
        final state = await primedAppStateWithProfile();
        final context = const AgentContextBuilder().build(state);
        final mockHttp = MockClient(
          (request) async => http.Response('this is not json', 200),
        );
        final client = HttpAgentClient(
          baseUrl: 'http://example.com',
          httpClient: mockHttp,
        );

        await expectLater(
          client.sendMessage(
            message: '你好',
            context: context,
            history: const [],
          ),
          throwsA(isA<HttpAgentException>()),
        );
      },
    );

    test('respects custom path', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      late Uri capturedUrl;
      final mockHttp = MockClient((request) async {
        capturedUrl = request.url;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'message': '',
            'intent': 'answerOnly',
            'confidence': 0.0,
            'actions': <Map<String, dynamic>>[],
            'safety': <String, dynamic>{},
          }),
          200,
        );
      });

      final client = HttpAgentClient(
        baseUrl: 'http://example.com',
        path: '/custom/coach',
        httpClient: mockHttp,
      );

      await client.sendMessage(
        message: 'hi',
        context: context,
        history: const [],
      );
      expect(capturedUrl.path, '/custom/coach');
    });

    test('http.ClientException is wrapped in HttpAgentException', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final mockHttp = MockClient((request) async {
        throw http.ClientException('connection refused');
      });
      final client = HttpAgentClient(
        baseUrl: 'http://example.com',
        httpClient: mockHttp,
      );

      await expectLater(
        client.sendMessage(message: '你好', context: context, history: const []),
        throwsA(
          isA<HttpAgentException>().having(
            (e) => e.message,
            'message',
            contains('connection refused'),
          ),
        ),
      );
    });

    test('timeout is wrapped in HttpAgentException', () async {
      final state = await primedAppStateWithProfile();
      final context = const AgentContextBuilder().build(state);
      final mockHttp = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });
      final client = HttpAgentClient(
        baseUrl: 'http://example.com',
        httpClient: mockHttp,
        timeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        client.sendMessage(message: '你好', context: context, history: const []),
        throwsA(
          isA<HttpAgentException>().having(
            (e) => e.message,
            'message',
            contains('超时'),
          ),
        ),
      );
    });
  });
}

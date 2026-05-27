import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_forge/agent/agent_event_log.dart';
import 'package:fit_forge/agent/models/agent_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AgentAction makeAction(String id) => AgentAction(
    id: id,
    type: AgentActionType.compressWorkout,
    title: 't',
    summary: 's',
    requiresConfirmation: true,
  );

  AgentEventLog trackedLog({int maxEvents = 50}) {
    final log = AgentEventLog(maxEvents: maxEvents);
    addTearDown(log.dispose);
    return log;
  }

  Future<AgentEventLog> hydratedLog({int maxEvents = 50}) async {
    final log = trackedLog(maxEvents: maxEvents);
    await log.hydrate();
    return log;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AgentEventLog', () {
    test('record appends an event with default outcome flags', () async {
      final log = await hydratedLog();

      final event = log.record(
        id: 'event-1',
        userMessage: 'hi',
        agentMessage: 'hello',
        actions: [makeAction('a-1')],
      );

      expect(log.events, hasLength(1));
      expect(event.accepted, false);
      expect(event.executed, false);
      expect(event.failureReason, isNull);
    });

    test('updateOutcome rewrites flags on the matching event', () async {
      final log = await hydratedLog();
      log.record(
        id: 'e-1',
        userMessage: 'a',
        agentMessage: 'b',
        actions: [makeAction('a-1')],
      );

      log.updateOutcome(actionId: 'a-1', accepted: true, executed: true);

      expect(log.events.single.accepted, true);
      expect(log.events.single.executed, true);
      expect(log.events.single.failureReason, isNull);
    });

    test(
      'updateOutcome captures failure reason on execution failure',
      () async {
        final log = await hydratedLog();
        log.record(
          id: 'e-1',
          userMessage: 'a',
          agentMessage: 'b',
          actions: [makeAction('a-1')],
        );

        log.updateOutcome(
          actionId: 'a-1',
          accepted: true,
          executed: false,
          failureReason: 'plan missing',
        );

        expect(log.events.single.accepted, true);
        expect(log.events.single.executed, false);
        expect(log.events.single.failureReason, 'plan missing');
      },
    );

    test('updateOutcome is a no-op for unknown action ids', () async {
      final log = await hydratedLog();
      log.record(
        id: 'e-1',
        userMessage: 'a',
        agentMessage: 'b',
        actions: [makeAction('a-1')],
      );

      log.updateOutcome(
        actionId: 'never-presented',
        accepted: true,
        executed: true,
      );

      expect(log.events.single.accepted, false);
    });

    test('caps the buffer at maxEvents (FIFO)', () async {
      final log = await hydratedLog(maxEvents: 3);
      for (var i = 0; i < 5; i++) {
        log.record(id: 'e-$i', userMessage: 'm$i', agentMessage: 'r$i');
      }
      expect(log.events.map((e) => e.id), ['e-2', 'e-3', 'e-4']);
    });

    test('event_log_caps_retained_events', () async {
      final log = await hydratedLog(maxEvents: 3);

      for (var i = 0; i < 6; i++) {
        log.record(
          id: 'event-$i',
          userMessage: 'message $i',
          agentMessage: 'ok',
        );
      }

      expect(log.events, hasLength(3));
      expect(log.events.first.id, 'event-3');
      expect(log.events.last.id, 'event-5');
    });

    test('event_log_truncates_long_messages', () async {
      final log = await hydratedLog();

      log.record(id: 'long', userMessage: 'x' * 1000, agentMessage: 'y' * 1000);

      expect(log.events.single.userMessage.length, lessThanOrEqualTo(520));
      expect(log.events.single.agentMessage.length, lessThanOrEqualTo(520));
    });

    test('event_log_redacts_sensitive_health_text', () async {
      final log = await hydratedLog();

      log.record(
        id: 'sensitive',
        userMessage: '我的体重是72kg，胸痛但想继续训练',
        agentMessage: 'Your weight is 72kg and chest pain needs care.',
      );

      final stored =
          '${log.events.single.userMessage}\n'
          '${log.events.single.agentMessage}';
      expect(stored, contains('[redacted]'));
      expect(stored, isNot(contains('72kg')));
      expect(stored, isNot(contains('胸痛但想继续训练')));
      expect(stored, isNot(contains('chest pain needs care')));
    });

    test('persists events across instances', () async {
      final first = await hydratedLog();
      first.record(
        id: 'e-1',
        userMessage: 'hello',
        agentMessage: 'hi back',
        actions: [makeAction('a-1')],
      );
      first.updateOutcome(actionId: 'a-1', accepted: true, executed: true);
      await first.flushPending();

      final second = await hydratedLog();

      expect(second.events, hasLength(1));
      expect(second.events.single.id, 'e-1');
      expect(second.events.single.userMessage, 'hello');
      expect(second.events.single.accepted, true);
      expect(second.events.single.executed, true);
    });

    test('clear empties the buffer and removes the persisted blob', () async {
      final log = await hydratedLog();
      log.record(id: 'e-1', userMessage: 'a', agentMessage: 'b');
      await log.flushPending();

      await log.clear();

      expect(log.events, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitforge.agent_event_log.v1'), isNull);
    });

    test('hydrate recovers from corrupt persisted JSON', () async {
      SharedPreferences.setMockInitialValues({
        'fitforge.agent_event_log.v1': 'not json',
      });
      final log = trackedLog();

      await log.hydrate();

      expect(log.events, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fitforge.agent_event_log.v1'), isNull);
    });

    test('hydrate is idempotent', () async {
      SharedPreferences.setMockInitialValues({});
      final log = await hydratedLog();
      log.record(id: 'e-1', userMessage: 'a', agentMessage: 'b');

      await log.hydrate();

      expect(log.events, hasLength(1));
    });
  });
}

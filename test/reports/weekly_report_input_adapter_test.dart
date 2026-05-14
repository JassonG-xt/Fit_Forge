import 'package:fit_forge/agent/models/agent_action.dart';
import 'package:fit_forge/agent/models/agent_event.dart';
import 'package:fit_forge/reports/weekly_report_builder.dart';
import 'package:fit_forge/reports/weekly_report_input_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_state_fixtures.dart';

void main() {
  group('buildWeeklyReportInput', () {
    test(
      'includes latest structured weeklyReview inside the current report week',
      () async {
        final appState = await freshAppState();
        final input = buildWeeklyReportInput(
          appState: appState,
          now: DateTime(2026, 5, 14, 9),
          agentEvents: [
            _event(
              createdAt: DateTime(2026, 5, 12, 8),
              actions: [
                _weeklyReviewAction(
                  payload: const {'summary': 'Earlier in-week summary.'},
                ),
              ],
            ),
            _event(
              createdAt: DateTime(2026, 5, 14, 8),
              actions: [
                _weeklyReviewAction(
                  payload: const {
                    'summary': 'Structured weekly summary.',
                    'observations': ['Training density stayed moderate.'],
                    'nextWeekSuggestions': ['Keep three planned sessions.'],
                    'riskNotes': ['Watch total training volume.'],
                  },
                ),
              ],
            ),
          ],
        );

        final report = buildWeeklyReportMarkdown(input);

        expect(report, contains('Structured weekly summary.'));
        expect(report, isNot(contains('Earlier in-week summary.')));
        expect(report, contains('- Training density stayed moderate.'));
        expect(report, contains('- Keep three planned sessions.'));
        expect(report, contains('- Watch total training volume.'));
      },
    );

    test(
      'falls back deterministically when no in-week weeklyReview exists',
      () async {
        final appState = await freshAppState();
        final input = buildWeeklyReportInput(
          appState: appState,
          now: DateTime(2026, 5, 14, 9),
        );

        final report = buildWeeklyReportMarkdown(input);

        expect(report, contains('No coach review available for this period.'));
        expect(report, contains('Open the Coach Agent chat'));
      },
    );

    test('ignores structured weeklyReview from the previous week', () async {
      final appState = await freshAppState();
      final input = buildWeeklyReportInput(
        appState: appState,
        now: DateTime(2026, 5, 14, 9),
        agentEvents: [
          _event(
            createdAt: DateTime(2026, 5, 10, 23, 59),
            actions: [
              _weeklyReviewAction(
                payload: const {'summary': 'Previous-week review.'},
              ),
            ],
          ),
        ],
      );

      final report = buildWeeklyReportMarkdown(input);

      expect(report, isNot(contains('Previous-week review.')));
      expect(report, contains('No coach review available for this period.'));
    });

    test(
      'uses current-week latest when previous and current reviews exist',
      () async {
        final appState = await freshAppState();
        final input = buildWeeklyReportInput(
          appState: appState,
          now: DateTime(2026, 5, 14, 9),
          agentEvents: [
            _event(
              createdAt: DateTime(2026, 5, 7, 8),
              actions: [
                _weeklyReviewAction(
                  payload: const {'summary': 'Older out-of-week review.'},
                ),
              ],
            ),
            _event(
              createdAt: DateTime(2026, 5, 13, 8),
              actions: [
                _weeklyReviewAction(
                  payload: const {'summary': 'Earlier in-week review.'},
                ),
              ],
            ),
            _event(
              createdAt: DateTime(2026, 5, 14, 8),
              actions: [
                _weeklyReviewAction(
                  payload: const {'summary': 'Latest in-week review.'},
                ),
              ],
            ),
          ],
        );

        final report = buildWeeklyReportMarkdown(input);

        expect(report, contains('Latest in-week review.'));
        expect(report, isNot(contains('Earlier in-week review.')));
        expect(report, isNot(contains('Older out-of-week review.')));
      },
    );

    test('includes reviews at ISO week start and end boundaries only', () {
      final weekStart = DateTime(2026, 5, 11);
      final weekEnd = DateTime(2026, 5, 17);

      final startBoundaryReview = latestWeeklyReviewReportDataFromEvents(
        [
          _event(
            createdAt: DateTime(2026, 5, 10, 23, 59, 59),
            actions: [
              _weeklyReviewAction(
                payload: const {'summary': 'Before Monday review.'},
              ),
            ],
          ),
          _event(
            createdAt: DateTime(2026, 5, 11),
            actions: [
              _weeklyReviewAction(
                payload: const {'summary': 'Monday boundary review.'},
              ),
            ],
          ),
        ],
        weekStart: weekStart,
        weekEnd: weekEnd,
      );

      final endBoundaryReview = latestWeeklyReviewReportDataFromEvents(
        [
          _event(
            createdAt: DateTime(2026, 5, 17, 23, 59, 59),
            actions: [
              _weeklyReviewAction(
                payload: const {'summary': 'Sunday boundary review.'},
              ),
            ],
          ),
          _event(
            createdAt: DateTime(2026, 5, 18),
            actions: [
              _weeklyReviewAction(
                payload: const {'summary': 'Next Monday review.'},
              ),
            ],
          ),
        ],
        weekStart: weekStart,
        weekEnd: weekEnd,
      );

      expect(startBoundaryReview?.summary, 'Monday boundary review.');
      expect(endBoundaryReview?.summary, 'Sunday boundary review.');
    });

    test('does not include raw provider text from event or action', () async {
      final appState = await freshAppState();
      final input = buildWeeklyReportInput(
        appState: appState,
        now: DateTime(2026, 5, 14, 9),
        agentEvents: [
          _event(
            createdAt: DateTime(2026, 5, 14, 8),
            agentMessage: 'RAW_PROVIDER_OUTPUT_FROM_MESSAGE',
            actions: [
              _weeklyReviewAction(
                summary: 'RAW_PROVIDER_OUTPUT_FROM_ACTION_SUMMARY',
                payload: const {'summary': 'Verified structured summary.'},
              ),
            ],
          ),
        ],
      );

      final report = buildWeeklyReportMarkdown(input);

      expect(report, contains('Verified structured summary.'));
      expect(report, isNot(contains('RAW_PROVIDER_OUTPUT_FROM_MESSAGE')));
      expect(
        report,
        isNot(contains('RAW_PROVIDER_OUTPUT_FROM_ACTION_SUMMARY')),
      );
    });
  });

  group('latestWeeklyReviewReportDataFromEvents', () {
    test('skips malformed payloads instead of rendering them', () {
      final review = latestWeeklyReviewReportDataFromEvents([
        _event(
          createdAt: DateTime(2026, 5, 14, 9),
          actions: [
            _weeklyReviewAction(
              payload: const {
                'summary': 'Malformed review.',
                'observations': [42],
              },
            ),
          ],
        ),
      ]);

      expect(review, isNull);
    });
  });
}

AgentEvent _event({
  required DateTime createdAt,
  required List<AgentAction> actions,
  String agentMessage = '',
}) {
  return AgentEvent(
    id: 'event-${createdAt.microsecondsSinceEpoch}',
    userMessage: 'weekly review',
    agentMessage: agentMessage,
    actions: actions,
    accepted: false,
    executed: false,
    createdAt: createdAt,
  );
}

AgentAction _weeklyReviewAction({
  required Map<String, dynamic> payload,
  String summary = '',
}) {
  return AgentAction(
    id: 'review',
    type: AgentActionType.weeklyReview,
    title: 'Weekly Review',
    summary: summary,
    requiresConfirmation: false,
    payload: payload,
  );
}

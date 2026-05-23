import 'package:flutter_test/flutter_test.dart';

import 'package:fit_forge/agent/action_payload_parser.dart';

void main() {
  group('parseDayOfWeek', () {
    test('accepts valid int 1-7', () {
      for (var i = 1; i <= 7; i++) {
        final result = parseDayOfWeek(i);
        expect(result, isA<PayloadParseSuccess<int>>());
        expect((result as PayloadParseSuccess<int>).value, i);
      }
    });

    test('rejects null', () {
      final result = parseDayOfWeek(null);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('哪一天'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects double', () {
      final result = parseDayOfWeek(1.5);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects String', () {
      final result = parseDayOfWeek('1');
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects 0', () {
      final result = parseDayOfWeek(0);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects 8', () {
      final result = parseDayOfWeek(8);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects negative', () {
      final result = parseDayOfWeek(-1);
      expect(result, isA<PayloadParseFailure<int>>());
    });
  });

  group('parseAvailableWeekdays', () {
    test('accepts valid list', () {
      final result = parseAvailableWeekdays([1, 3, 5]);
      expect(result, isA<PayloadParseSuccess<List<int>>>());
      expect((result as PayloadParseSuccess<List<int>>).value, [1, 3, 5]);
    });

    test('rejects non-List', () {
      final result = parseAvailableWeekdays('not a list');
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('可训练的星期几'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects null', () {
      final result = parseAvailableWeekdays(null);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('可训练的星期几'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects empty list', () {
      final result = parseAvailableWeekdays(<int>[]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('不能为空'));
    });

    test('rejects list with double element', () {
      final result = parseAvailableWeekdays([1, 2.5, 3]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects list with String element', () {
      final result = parseAvailableWeekdays([2, 'bad', 5]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects list with 0', () {
      final result = parseAvailableWeekdays([0, 3]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects list with 8', () {
      final result = parseAvailableWeekdays([2, 8]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects duplicates', () {
      final result = parseAvailableWeekdays([2, 2, 4]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('重复'));
    });
  });

  group('parseReplaceExercisePayload', () {
    test('accepts valid payload', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1,
        'fromExerciseId': 'bench',
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseSuccess<ReplaceExercisePayload>>());
      final payload =
          (result as PayloadParseSuccess<ReplaceExercisePayload>).value;
      expect(payload.dayOfWeek, 1);
      expect(payload.fromExerciseId, 'bench');
      expect(payload.toExerciseId, 'incline');
    });

    test('rejects missing dayOfWeek', () {
      final result = parseReplaceExercisePayload({
        'fromExerciseId': 'bench',
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('哪一天'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects double dayOfWeek', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1.5,
        'fromExerciseId': 'bench',
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects missing fromExerciseId', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1,
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('原动作'));
      expect(result.message, isNot(contains('fromExerciseId')));
    });

    test('rejects empty fromExerciseId', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1,
        'fromExerciseId': '',
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
    });

    test('rejects missing toExerciseId', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1,
        'fromExerciseId': 'bench',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('替换后的动作'));
      expect(result.message, isNot(contains('toExerciseId')));
    });

    test('rejects same from and to', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1,
        'fromExerciseId': 'bench',
        'toExerciseId': 'bench',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('相同'));
    });
  });

  group('parseCompressWorkoutPayload', () {
    test('accepts valid payload', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 3,
        'targetMinutes': 20,
      });
      expect(result, isA<PayloadParseSuccess<CompressWorkoutPayload>>());
      final payload =
          (result as PayloadParseSuccess<CompressWorkoutPayload>).value;
      expect(payload.dayOfWeek, 3);
      expect(payload.targetMinutes, 20);
    });

    test('rejects missing dayOfWeek', () {
      final result = parseCompressWorkoutPayload({'targetMinutes': 20});
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('压缩哪一天'));
      expect(result.message, contains('周三'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects double dayOfWeek', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1.5,
        'targetMinutes': 20,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('dayOfWeek')));
    });

    test('rejects missing targetMinutes', () {
      final result = parseCompressWorkoutPayload({'dayOfWeek': 1});
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('目标训练时长'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects double targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': 15.5,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('整数分钟数'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects String targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': '20',
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('整数分钟数'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects zero targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': 0,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('大于 0 分钟'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects negative targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': -5,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('大于 0 分钟'));
      expect(result.message, isNot(contains('targetMinutes')));
    });
  });

  group('parseGeneratePlanPayload', () {
    test('accepts empty payload (no preferences)', () {
      final result = parseGeneratePlanPayload(const {});
      expect(result, isA<PayloadParseSuccess<GeneratePlanPayload>>());
      final value = (result as PayloadParseSuccess<GeneratePlanPayload>).value;
      expect(value.availableWeekdays, isNull);
      expect(value.targetMinutes, isNull);
    });

    test('accepts payload with usePreviewPlan only', () {
      final result = parseGeneratePlanPayload(const {'usePreviewPlan': true});
      expect(result, isA<PayloadParseSuccess<GeneratePlanPayload>>());
    });

    test('accepts both preferences', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': [1, 3, 5],
        'targetMinutes': 45,
      });
      expect(result, isA<PayloadParseSuccess<GeneratePlanPayload>>());
      final value = (result as PayloadParseSuccess<GeneratePlanPayload>).value;
      expect(value.availableWeekdays, [1, 3, 5]);
      expect(value.targetMinutes, 45);
    });

    test('accepts only availableWeekdays', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': [2, 4],
      });
      expect(result, isA<PayloadParseSuccess<GeneratePlanPayload>>());
      final value = (result as PayloadParseSuccess<GeneratePlanPayload>).value;
      expect(value.availableWeekdays, [2, 4]);
      expect(value.targetMinutes, isNull);
    });

    test('accepts only targetMinutes', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': 30});
      expect(result, isA<PayloadParseSuccess<GeneratePlanPayload>>());
      final value = (result as PayloadParseSuccess<GeneratePlanPayload>).value;
      expect(value.availableWeekdays, isNull);
      expect(value.targetMinutes, 30);
    });

    test('rejects availableWeekdays with String element', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': [1, 'bad', 5],
      });
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects availableWeekdays out of range', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': [0, 8],
      });
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('availableWeekdays')));
    });

    test('rejects duplicate availableWeekdays', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': [1, 1, 5],
      });
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('重复'));
    });

    test('rejects empty availableWeekdays list', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': <int>[],
      });
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('不能为空'));
    });

    test('rejects double targetMinutes', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': 45.5});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('整数分钟数'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects String targetMinutes', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': '45'});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('整数分钟数'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects targetMinutes below lower bound', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': 4});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('5 到 180 分钟'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('rejects targetMinutes above upper bound', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': 200});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('5 到 180 分钟'));
      expect(result.message, isNot(contains('targetMinutes')));
    });

    test('treats null preference fields as absent', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': null,
        'targetMinutes': null,
      });
      expect(result, isA<PayloadParseSuccess<GeneratePlanPayload>>());
      final value = (result as PayloadParseSuccess<GeneratePlanPayload>).value;
      expect(value.availableWeekdays, isNull);
      expect(value.targetMinutes, isNull);
    });
  });

  group('parseWeeklyReviewPayload', () {
    test('accepts empty payload', () {
      final result = parseWeeklyReviewPayload(const {});
      expect(result, isA<PayloadParseSuccess<WeeklyReviewPayload>>());
      final value = (result as PayloadParseSuccess<WeeklyReviewPayload>).value;
      expect(value.summary, isNull);
      expect(value.completedSessions, isNull);
      expect(value.focusAreas, isEmpty);
      expect(value.observations, isEmpty);
      expect(value.nextWeekSuggestions, isEmpty);
      expect(value.riskNotes, isEmpty);
    });

    test('accepts full payload', () {
      final result = parseWeeklyReviewPayload(const {
        'summary': '近期 3 次训练。',
        'completedSessions': 3,
        'focusAreas': ['推', '腿'],
        'observations': ['训练间隔均匀。'],
        'nextWeekSuggestions': ['保持每周 3 次。'],
        'riskNotes': <String>[],
      });
      expect(result, isA<PayloadParseSuccess<WeeklyReviewPayload>>());
      final value = (result as PayloadParseSuccess<WeeklyReviewPayload>).value;
      expect(value.summary, '近期 3 次训练。');
      expect(value.completedSessions, 3);
      expect(value.focusAreas, ['推', '腿']);
      expect(value.observations, ['训练间隔均匀。']);
      expect(value.nextWeekSuggestions, ['保持每周 3 次。']);
      expect(value.riskNotes, isEmpty);
    });

    test('rejects non-string summary', () {
      final result = parseWeeklyReviewPayload(const {'summary': 123});
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
      expect(result.message, contains('summary'));
    });

    test('rejects negative completedSessions', () {
      final result = parseWeeklyReviewPayload(const {'completedSessions': -1});
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
    });

    test('rejects non-int completedSessions', () {
      final result = parseWeeklyReviewPayload(const {'completedSessions': '3'});
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
    });

    test('rejects list element that is not a string', () {
      final result = parseWeeklyReviewPayload(const {
        'observations': ['ok', 42],
      });
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
      expect(result.message, contains('observations 第 2 项'));
    });

    test('rejects empty list element', () {
      final result = parseWeeklyReviewPayload(const {
        'focusAreas': [''],
      });
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
      expect(result.message, contains('为空字符串'));
    });

    test('rejects list with too many items', () {
      final result = parseWeeklyReviewPayload(const {
        'nextWeekSuggestions': [
          'a',
          'b',
          'c',
          'd',
          'e',
          'f',
          'g',
          'h',
          'i', // 9 items, exceeds 8
        ],
      });
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
      expect(result.message, contains('不能超过 8 项'));
    });

    test('rejects list element exceeding 200 chars', () {
      final result = parseWeeklyReviewPayload({
        'observations': ['x' * 201],
      });
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
      expect(result.message, contains('200'));
    });

    test('rejects non-list array fields', () {
      final result = parseWeeklyReviewPayload(const {
        'observations': 'not a list',
      });
      expect(result, isA<PayloadParseFailure<WeeklyReviewPayload>>());
      expect(result.message, contains('数组'));
    });
  });

  group('parseMoveWorkoutSessionPayload', () {
    test('accepts valid payload without reason', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': 2,
      });
      expect(result, isA<PayloadParseSuccess<MoveWorkoutSessionPayload>>());
      final value =
          (result as PayloadParseSuccess<MoveWorkoutSessionPayload>).value;
      expect(value.fromDayOfWeek, 1);
      expect(value.toDayOfWeek, 2);
      expect(value.reason, isNull);
    });

    test('accepts payload with reason', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 3,
        'toDayOfWeek': 5,
        'reason': '今天太累了',
      });
      expect(result, isA<PayloadParseSuccess<MoveWorkoutSessionPayload>>());
      final value =
          (result as PayloadParseSuccess<MoveWorkoutSessionPayload>).value;
      expect(value.fromDayOfWeek, 3);
      expect(value.toDayOfWeek, 5);
      expect(value.reason, '今天太累了');
    });

    test('treats null reason as absent', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': 4,
        'reason': null,
      });
      expect(result, isA<PayloadParseSuccess<MoveWorkoutSessionPayload>>());
      final value =
          (result as PayloadParseSuccess<MoveWorkoutSessionPayload>).value;
      expect(value.reason, isNull);
    });

    test('rejects missing fromDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {'toDayOfWeek': 2});
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('移动哪一天'));
      expect(result.message, isNot(contains('fromDayOfWeek')));
    });

    test('rejects missing toDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {'fromDayOfWeek': 1});
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('移动到哪一天'));
      expect(result.message, isNot(contains('toDayOfWeek')));
    });

    test('rejects double fromDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1.5,
        'toDayOfWeek': 2,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('fromDayOfWeek')));
    });

    test('rejects String fromDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': '1',
        'toDayOfWeek': 2,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('fromDayOfWeek')));
    });

    test('rejects double toDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': 2.5,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('toDayOfWeek')));
    });

    test('rejects String toDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': '2',
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('训练日期格式不正确'));
      expect(result.message, isNot(contains('toDayOfWeek')));
    });

    test('rejects fromDayOfWeek below range', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 0,
        'toDayOfWeek': 2,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('fromDayOfWeek')));
    });

    test('rejects fromDayOfWeek above range', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 8,
        'toDayOfWeek': 2,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('fromDayOfWeek')));
    });

    test('rejects toDayOfWeek below range', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': 0,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('toDayOfWeek')));
    });

    test('rejects toDayOfWeek above range', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': 9,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('周一到周日'));
      expect(result.message, isNot(contains('toDayOfWeek')));
    });

    test('rejects same fromDayOfWeek and toDayOfWeek', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 3,
        'toDayOfWeek': 3,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('不能相同'));
      expect(result.message, isNot(contains('fromDayOfWeek')));
      expect(result.message, isNot(contains('toDayOfWeek')));
    });

    test('rejects non-string reason', () {
      final result = parseMoveWorkoutSessionPayload(const {
        'fromDayOfWeek': 1,
        'toDayOfWeek': 2,
        'reason': 42,
      });
      expect(result, isA<PayloadParseFailure<MoveWorkoutSessionPayload>>());
      expect(result.message, contains('reason'));
      expect(result.message, contains('字符串'));
    });
  });
}

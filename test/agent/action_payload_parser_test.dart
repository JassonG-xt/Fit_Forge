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
      expect(result.message, contains('缺失'));
    });

    test('rejects double', () {
      final result = parseDayOfWeek(1.5);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('整数'));
    });

    test('rejects String', () {
      final result = parseDayOfWeek('1');
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('整数'));
    });

    test('rejects 0', () {
      final result = parseDayOfWeek(0);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('1-7'));
    });

    test('rejects 8', () {
      final result = parseDayOfWeek(8);
      expect(result, isA<PayloadParseFailure<int>>());
      expect(result.message, contains('1-7'));
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
    });

    test('rejects null', () {
      final result = parseAvailableWeekdays(null);
      expect(result, isA<PayloadParseFailure<List<int>>>());
    });

    test('rejects empty list', () {
      final result = parseAvailableWeekdays(<int>[]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('不能为空'));
    });

    test('rejects list with double element', () {
      final result = parseAvailableWeekdays([1, 2.5, 3]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('第 2 个'));
    });

    test('rejects list with String element', () {
      final result = parseAvailableWeekdays([2, 'bad', 5]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('第 2 个'));
    });

    test('rejects list with 0', () {
      final result = parseAvailableWeekdays([0, 3]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('第 1 个'));
    });

    test('rejects list with 8', () {
      final result = parseAvailableWeekdays([2, 8]);
      expect(result, isA<PayloadParseFailure<List<int>>>());
      expect(result.message, contains('第 2 个'));
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
    });

    test('rejects double dayOfWeek', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1.5,
        'fromExerciseId': 'bench',
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('整数'));
    });

    test('rejects missing fromExerciseId', () {
      final result = parseReplaceExercisePayload({
        'dayOfWeek': 1,
        'toExerciseId': 'incline',
      });
      expect(result, isA<PayloadParseFailure<ReplaceExercisePayload>>());
      expect(result.message, contains('fromExerciseId'));
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
      expect(result.message, contains('toExerciseId'));
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
      expect(result.message, contains('dayOfWeek'));
      expect(result.message, contains('缺失'));
    });

    test('rejects double dayOfWeek', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1.5,
        'targetMinutes': 20,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('整数'));
    });

    test('rejects missing targetMinutes', () {
      final result = parseCompressWorkoutPayload({'dayOfWeek': 1});
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('targetMinutes'));
    });

    test('rejects double targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': 15.5,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('正整数'));
    });

    test('rejects String targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': '20',
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('正整数'));
    });

    test('rejects zero targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': 0,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('正数'));
    });

    test('rejects negative targetMinutes', () {
      final result = parseCompressWorkoutPayload({
        'dayOfWeek': 1,
        'targetMinutes': -5,
      });
      expect(result, isA<PayloadParseFailure<CompressWorkoutPayload>>());
      expect(result.message, contains('正数'));
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
      expect(result.message, contains('不是整数'));
    });

    test('rejects availableWeekdays out of range', () {
      final result = parseGeneratePlanPayload(const {
        'availableWeekdays': [0, 8],
      });
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('1-7'));
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
      expect(result.message, contains('正整数'));
    });

    test('rejects String targetMinutes', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': '45'});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('正整数'));
    });

    test('rejects targetMinutes below lower bound', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': 4});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('5-180'));
    });

    test('rejects targetMinutes above upper bound', () {
      final result = parseGeneratePlanPayload(const {'targetMinutes': 200});
      expect(result, isA<PayloadParseFailure<GeneratePlanPayload>>());
      expect(result.message, contains('5-180'));
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
}

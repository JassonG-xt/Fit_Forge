/// 集中校验 AgentAction payload，返回类型安全的结果。
///
/// 所有 parser 都是纯逻辑，不依赖 AppState。
/// 校验失败时返回 [PayloadParseFailure]，附带用户可理解的中文消息。
sealed class PayloadParseResult<T> {
  const PayloadParseResult();

  /// 失败消息，成功时为 null。
  String? get message;
}

class PayloadParseSuccess<T> extends PayloadParseResult<T> {
  const PayloadParseSuccess(this.value);
  final T value;

  @override
  String? get message => null;
}

class PayloadParseFailure<T> extends PayloadParseResult<T> {
  const PayloadParseFailure(this.message);
  @override
  final String message;
}

// ─── typed payload data ──────────────────────────────────────────────

class GeneratePlanPayload {
  const GeneratePlanPayload({this.availableWeekdays, this.targetMinutes});

  /// 可选偏好：用户希望本周训练哪些天。
  /// 若提供，executor 会在生成基础计划后调用 [reschedulePlanToWeekdays] 应用。
  final List<int>? availableWeekdays;

  /// 可选偏好：用户希望每次训练时长（分钟）。
  /// 若提供，executor 会在生成基础计划后对每个训练日调用 [compressDayInPlan] 应用。
  final int? targetMinutes;
}

class RescheduleWeekPayload {
  const RescheduleWeekPayload(this.availableWeekdays);
  final List<int> availableWeekdays;
}

class ReplaceExercisePayload {
  const ReplaceExercisePayload({
    required this.dayOfWeek,
    required this.fromExerciseId,
    required this.toExerciseId,
  });
  final int dayOfWeek;
  final String fromExerciseId;
  final String toExerciseId;
}

class CompressWorkoutPayload {
  const CompressWorkoutPayload({
    required this.dayOfWeek,
    required this.targetMinutes,
  });
  final int dayOfWeek;
  final int targetMinutes;
}

// ─── parser functions ───────────────────────────────────────────────

/// 校验 dayOfWeek：必须是 int，值在 1-7。
/// 不接受 double / num 的 toInt() 截断，不接受 String。
PayloadParseResult<int> parseDayOfWeek(dynamic raw) {
  if (raw == null) {
    return const PayloadParseFailure('dayOfWeek 缺失。');
  }
  if (raw is! int) {
    // 拒绝 double、String、num 等非 int 类型
    return const PayloadParseFailure('dayOfWeek 必须是整数（1-7），不接受小数或文本。');
  }
  if (raw < 1 || raw > 7) {
    return PayloadParseFailure('dayOfWeek 必须在 1-7 之间，当前值为 $raw。');
  }
  return PayloadParseSuccess(raw);
}

/// 校验 availableWeekdays：必须是非空、无重复、元素全为 int 且在 1-7 的 List。
/// 不静默丢弃非法元素。
PayloadParseResult<List<int>> parseAvailableWeekdays(dynamic raw) {
  if (raw is! List) {
    return const PayloadParseFailure('availableWeekdays 字段缺失或格式不正确。');
  }
  if (raw.isEmpty) {
    return const PayloadParseFailure('训练日期不能为空。');
  }
  // 逐个检查元素类型，不静默丢弃
  for (var i = 0; i < raw.length; i++) {
    final element = raw[i];
    if (element is! int) {
      return PayloadParseFailure('训练日期列表中第 ${i + 1} 个值不是整数：$element');
    }
    if (element < 1 || element > 7) {
      return PayloadParseFailure('训练日期必须在 1-7 之间，第 ${i + 1} 个值为 $element。');
    }
  }
  final weekdays = List<int>.from(raw);
  if (weekdays.toSet().length != weekdays.length) {
    return const PayloadParseFailure('训练日期不能重复。');
  }
  return PayloadParseSuccess(weekdays);
}

/// 校验 replaceExercise payload。
PayloadParseResult<ReplaceExercisePayload> parseReplaceExercisePayload(
  Map<String, dynamic> payload,
) {
  final dayResult = parseDayOfWeek(payload['dayOfWeek']);
  if (dayResult is PayloadParseFailure) {
    return PayloadParseFailure(dayResult.message!);
  }

  final fromId = payload['fromExerciseId'];
  if (fromId is! String || fromId.isEmpty) {
    return const PayloadParseFailure('fromExerciseId 缺失。');
  }

  final toId = payload['toExerciseId'];
  if (toId is! String || toId.isEmpty) {
    return const PayloadParseFailure('toExerciseId 缺失。');
  }

  if (fromId == toId) {
    return const PayloadParseFailure('替代动作不能和原动作相同。');
  }

  return PayloadParseSuccess(
    ReplaceExercisePayload(
      dayOfWeek: (dayResult as PayloadParseSuccess<int>).value,
      fromExerciseId: fromId,
      toExerciseId: toId,
    ),
  );
}

/// 校验 compressWorkout payload。
/// dayOfWeek 必须显式提供，不允许静默 fallback 到今天。
PayloadParseResult<CompressWorkoutPayload> parseCompressWorkoutPayload(
  Map<String, dynamic> payload,
) {
  final dayOfWeekRaw = payload['dayOfWeek'];
  if (dayOfWeekRaw == null) {
    return const PayloadParseFailure('dayOfWeek 缺失，请明确指定要压缩哪天的训练。');
  }
  final dayResult = parseDayOfWeek(dayOfWeekRaw);
  if (dayResult is PayloadParseFailure) {
    return PayloadParseFailure(dayResult.message!);
  }

  final targetMinutesRaw = payload['targetMinutes'];
  if (targetMinutesRaw == null) {
    return const PayloadParseFailure('targetMinutes 缺失。');
  }
  if (targetMinutesRaw is! int) {
    return const PayloadParseFailure('targetMinutes 必须是正整数，不接受小数或文本。');
  }
  if (targetMinutesRaw <= 0) {
    return PayloadParseFailure('targetMinutes 必须为正数，当前值为 $targetMinutesRaw。');
  }

  return PayloadParseSuccess(
    CompressWorkoutPayload(
      dayOfWeek: (dayResult as PayloadParseSuccess<int>).value,
      targetMinutes: targetMinutesRaw,
    ),
  );
}

/// 校验 generatePlan payload。
///
/// generatePlan 历史上无 payload 字段。本 PR 引入可选偏好：
/// - `availableWeekdays`: 整数列表 1-7、不重复（语义同 [parseAvailableWeekdays]）
/// - `targetMinutes`: 正整数，建议在 [5, 180] 之间（与 backend strict 校验对齐）
///
/// 两个字段都可缺省；缺省时退化为不带偏好的纯 profile 计划生成。
/// 若字段存在但格式非法，必须返回 [PayloadParseFailure] —— 不允许静默丢弃。
PayloadParseResult<GeneratePlanPayload> parseGeneratePlanPayload(
  Map<String, dynamic> payload,
) {
  List<int>? weekdays;
  if (payload.containsKey('availableWeekdays') &&
      payload['availableWeekdays'] != null) {
    final parsed = parseAvailableWeekdays(payload['availableWeekdays']);
    if (parsed is PayloadParseFailure<List<int>>) {
      return PayloadParseFailure(parsed.message);
    }
    weekdays = (parsed as PayloadParseSuccess<List<int>>).value;
  }

  int? minutes;
  if (payload.containsKey('targetMinutes') &&
      payload['targetMinutes'] != null) {
    final raw = payload['targetMinutes'];
    if (raw is! int) {
      return const PayloadParseFailure('targetMinutes 必须是正整数，不接受小数或文本。');
    }
    if (raw < 5 || raw > 180) {
      return PayloadParseFailure('targetMinutes 必须在 5-180 之间，当前值为 $raw。');
    }
    minutes = raw;
  }

  return PayloadParseSuccess(
    GeneratePlanPayload(availableWeekdays: weekdays, targetMinutes: minutes),
  );
}

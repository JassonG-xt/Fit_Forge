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

/// `weeklyReview` 是非 mutating 的结构化复盘。所有字段都可选；
/// parser 用于校验后端 / mock 给出的复盘内容形状是否合规，
/// 不参与任何 AppState 写入。
///
/// 字段约束（与 backend `_WeeklyReviewPayload` 对齐）：
/// - 字符串类字段最大 500 字符，列表最多 8 项。
/// - 列表元素必须是非空字符串。
/// - 数值字段非负。
class WeeklyReviewPayload {
  const WeeklyReviewPayload({
    this.summary,
    this.completedSessions,
    this.focusAreas = const [],
    this.observations = const [],
    this.nextWeekSuggestions = const [],
    this.riskNotes = const [],
  });
  final String? summary;
  final int? completedSessions;
  final List<String> focusAreas;
  final List<String> observations;
  final List<String> nextWeekSuggestions;
  final List<String> riskNotes;
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

/// 校验 `weeklyReview` payload。所有字段都可选；缺省字段返回默认空值。
///
/// 不允许静默丢弃非法元素：列表中遇到非 String 或空 String 直接整体拒绝，
/// 让上游知道 payload 不合规，而不是悄悄把列表截断/忽略。
PayloadParseResult<WeeklyReviewPayload> parseWeeklyReviewPayload(
  Map<String, dynamic> payload,
) {
  String? summary;
  if (payload.containsKey('summary') && payload['summary'] != null) {
    final raw = payload['summary'];
    if (raw is! String) {
      return const PayloadParseFailure('summary 必须是字符串。');
    }
    if (raw.length > 500) {
      return const PayloadParseFailure('summary 长度超过 500 字符。');
    }
    summary = raw;
  }

  int? completedSessions;
  if (payload.containsKey('completedSessions') &&
      payload['completedSessions'] != null) {
    final raw = payload['completedSessions'];
    if (raw is! int) {
      return const PayloadParseFailure('completedSessions 必须是非负整数。');
    }
    if (raw < 0 || raw > 10000) {
      return PayloadParseFailure('completedSessions 越界（应在 0-10000），当前值为 $raw。');
    }
    completedSessions = raw;
  }

  final focusAreas = _parseStringList(payload, 'focusAreas');
  if (focusAreas is PayloadParseFailure<List<String>>) {
    return PayloadParseFailure(focusAreas.message);
  }

  final observations = _parseStringList(payload, 'observations');
  if (observations is PayloadParseFailure<List<String>>) {
    return PayloadParseFailure(observations.message);
  }

  final nextWeekSuggestions = _parseStringList(payload, 'nextWeekSuggestions');
  if (nextWeekSuggestions is PayloadParseFailure<List<String>>) {
    return PayloadParseFailure(nextWeekSuggestions.message);
  }

  final riskNotes = _parseStringList(payload, 'riskNotes');
  if (riskNotes is PayloadParseFailure<List<String>>) {
    return PayloadParseFailure(riskNotes.message);
  }

  return PayloadParseSuccess(
    WeeklyReviewPayload(
      summary: summary,
      completedSessions: completedSessions,
      focusAreas: (focusAreas as PayloadParseSuccess<List<String>>).value,
      observations: (observations as PayloadParseSuccess<List<String>>).value,
      nextWeekSuggestions:
          (nextWeekSuggestions as PayloadParseSuccess<List<String>>).value,
      riskNotes: (riskNotes as PayloadParseSuccess<List<String>>).value,
    ),
  );
}

/// 共享的小帮手：解析 weeklyReview 中的字符串列表字段。
/// 限制：最多 8 项，每项必须是非空 String 且长度 <= 200。
PayloadParseResult<List<String>> _parseStringList(
  Map<String, dynamic> payload,
  String key,
) {
  if (!payload.containsKey(key) || payload[key] == null) {
    return const PayloadParseSuccess(<String>[]);
  }
  final raw = payload[key];
  if (raw is! List) {
    return PayloadParseFailure('$key 必须是数组。');
  }
  if (raw.length > 8) {
    return PayloadParseFailure('$key 不能超过 8 项。');
  }
  final result = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final element = raw[i];
    if (element is! String) {
      return PayloadParseFailure('$key 第 ${i + 1} 项不是字符串。');
    }
    if (element.isEmpty) {
      return PayloadParseFailure('$key 第 ${i + 1} 项为空字符串。');
    }
    if (element.length > 200) {
      return PayloadParseFailure('$key 第 ${i + 1} 项超过 200 字符。');
    }
    result.add(element);
  }
  return PayloadParseSuccess(result);
}

// ─── moveWorkoutSession（前端契约阶段，runtime 尚未实现） ─────────────
//
// 仅校验 payload 形状，不进入 executor。详见 docs/move_workout_session_design.md。
// 复用 parseDayOfWeek 的范围/类型规则，但区分 fromDayOfWeek / toDayOfWeek
// 的错误消息以便用户定位字段。

class MoveWorkoutSessionPayload {
  const MoveWorkoutSessionPayload({
    required this.fromDayOfWeek,
    required this.toDayOfWeek,
    this.reason,
  });
  final int fromDayOfWeek;
  final int toDayOfWeek;
  final String? reason;
}

/// 校验 moveWorkoutSession payload。
///
/// 字段规则（与 design doc §5 对齐）：
/// - `fromDayOfWeek`: 必填 int，1-7。
/// - `toDayOfWeek`: 必填 int，1-7。
/// - `fromDayOfWeek` 与 `toDayOfWeek` 不能相同。
/// - `reason`: 可选 String（仅展示用）。
///
/// 不接受 double/num 截断，不接受 String。其他字段静默忽略，与现有 parser
/// 风格一致；strict extra-field 校验在 backend 层做。
PayloadParseResult<MoveWorkoutSessionPayload> parseMoveWorkoutSessionPayload(
  Map<String, dynamic> payload,
) {
  final fromRaw = payload['fromDayOfWeek'];
  if (fromRaw == null) {
    return const PayloadParseFailure('fromDayOfWeek 缺失。');
  }
  if (fromRaw is! int) {
    return const PayloadParseFailure('fromDayOfWeek 必须是整数（1-7），不接受小数或文本。');
  }
  if (fromRaw < 1 || fromRaw > 7) {
    return PayloadParseFailure('fromDayOfWeek 必须在 1-7 之间，当前值为 $fromRaw。');
  }

  final toRaw = payload['toDayOfWeek'];
  if (toRaw == null) {
    return const PayloadParseFailure('toDayOfWeek 缺失。');
  }
  if (toRaw is! int) {
    return const PayloadParseFailure('toDayOfWeek 必须是整数（1-7），不接受小数或文本。');
  }
  if (toRaw < 1 || toRaw > 7) {
    return PayloadParseFailure('toDayOfWeek 必须在 1-7 之间，当前值为 $toRaw。');
  }

  if (fromRaw == toRaw) {
    return const PayloadParseFailure('fromDayOfWeek 与 toDayOfWeek 必须不同。');
  }

  String? reason;
  if (payload.containsKey('reason') && payload['reason'] != null) {
    final raw = payload['reason'];
    if (raw is! String) {
      return const PayloadParseFailure('reason 必须是字符串。');
    }
    reason = raw;
  }

  return PayloadParseSuccess(
    MoveWorkoutSessionPayload(
      fromDayOfWeek: fromRaw,
      toDayOfWeek: toRaw,
      reason: reason,
    ),
  );
}

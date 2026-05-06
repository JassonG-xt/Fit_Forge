import '../models/enums.dart';
import '../models/workout_plan.dart';
import '../services/app_state.dart';
import 'action_helpers/workout_compressor.dart';
import 'action_helpers/workout_rescheduler.dart';
import 'action_payload_parser.dart';
import 'models/agent_action.dart';

/// 纯数据，描述一个 AgentAction 的 before/after 预览。
///
/// UI 层（AgentDiffView）只负责渲染，不负责计算。
/// executor 和 previewer 共享同一个 parser，消除漂移风险。
sealed class ActionPreview {
  const ActionPreview();
}

class CompressPreview extends ActionPreview {
  const CompressPreview({
    required this.original,
    required this.compressed,
    required this.dayOfWeek,
    required this.targetMinutes,
  });
  final WorkoutDay original;
  final WorkoutDay compressed;
  final int dayOfWeek;
  final int targetMinutes;
}

class ReplacePreview extends ActionPreview {
  const ReplacePreview({
    required this.dayOfWeek,
    required this.originalExercise,
    required this.toExerciseName,
    required this.toExerciseId,
  });
  final int dayOfWeek;
  final PlannedExercise originalExercise;
  final String toExerciseName;
  final String toExerciseId;
}

class ReschedulePreview extends ActionPreview {
  const ReschedulePreview({
    required this.originalPlan,
    required this.newPlan,
    required this.availableWeekdays,
  });
  final WorkoutPlan originalPlan;
  final WorkoutPlan newPlan;
  final List<int> availableWeekdays;
}

class GeneratePlanPreview extends ActionPreview {
  const GeneratePlanPreview({
    required this.originalPlan,
    required this.previewPlan,
  });
  final WorkoutPlan? originalPlan;
  final WorkoutPlan previewPlan;
}

/// 只读复盘视图。weeklyReview 不修改 AppState；这个 preview 类型只承载
/// 结构化文案，由 UI 渲染成 insight 面板。
class WeeklyReviewPreview extends ActionPreview {
  const WeeklyReviewPreview({
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

  /// 至少有一个结构化字段时返回 true。`summary` 不计入：card 顶部已经
  /// 显示 `action.summary`，重复显示就只是噪音。
  bool get hasContent =>
      completedSessions != null ||
      focusAreas.isNotEmpty ||
      observations.isNotEmpty ||
      nextWeekSuggestions.isNotEmpty ||
      riskNotes.isNotEmpty;
}

/// 校验失败时返回此类型，附带用户可理解的中文消息。
class PreviewFailure extends ActionPreview {
  const PreviewFailure(this.message);
  final String message;
}

/// 纯逻辑层：根据 [AgentAction] 和 [AppState] 计算预览数据。
///
/// 使用和 [action_payload_parser.dart] 相同的校验逻辑，
/// 确保 preview 和 execute 永远不会对同一个 payload 产生不同理解。
class AgentActionPreviewer {
  const AgentActionPreviewer();

  ActionPreview preview({
    required AgentAction action,
    required AppState appState,
  }) {
    switch (action.type) {
      case AgentActionType.compressWorkout:
        return _previewCompress(action, appState);
      case AgentActionType.replaceExercise:
        return _previewReplace(action, appState);
      case AgentActionType.rescheduleWeek:
        return _previewReschedule(action, appState);
      case AgentActionType.generatePlan:
        return _previewGeneratePlan(action, appState);
      case AgentActionType.weeklyReview:
        return previewWeeklyReview(action);
      case AgentActionType.answerOnly:
      case AgentActionType.nutritionAdvice:
      case AgentActionType.safetyResponse:
        return const PreviewFailure('此类型不需要预览。');
    }
  }

  ActionPreview _previewCompress(AgentAction action, AppState appState) {
    final plan = appState.activePlan;
    if (plan == null) {
      return const PreviewFailure('无法预览：当前没有训练计划。');
    }

    final parsed = parseCompressWorkoutPayload(action.payload);
    if (parsed is PayloadParseFailure<CompressWorkoutPayload>) {
      return PreviewFailure(parsed.message);
    }
    final payload =
        (parsed as PayloadParseSuccess<CompressWorkoutPayload>).value;

    final original = plan.days.firstWhere(
      (d) => d.dayOfWeek == payload.dayOfWeek,
      orElse: () => WorkoutDay(
        dayOfWeek: payload.dayOfWeek,
        dayType: WorkoutDayType.rest,
      ),
    );
    if (original.dayType == WorkoutDayType.rest || original.exercises.isEmpty) {
      return const PreviewFailure('当天没有训练内容可以压缩。');
    }

    final newPlan = compressDayInPlan(
      plan: plan,
      dayOfWeek: payload.dayOfWeek,
      targetMinutes: payload.targetMinutes,
    );
    if (newPlan == null) {
      return const PreviewFailure('压缩失败：无法找到对应的训练日。');
    }
    final compressed = newPlan.days.firstWhere(
      (d) => d.dayOfWeek == payload.dayOfWeek,
      orElse: () => original,
    );

    return CompressPreview(
      original: original,
      compressed: compressed,
      dayOfWeek: payload.dayOfWeek,
      targetMinutes: payload.targetMinutes,
    );
  }

  ActionPreview _previewReplace(AgentAction action, AppState appState) {
    final plan = appState.activePlan;
    if (plan == null) {
      return const PreviewFailure('无法预览：当前没有训练计划。');
    }

    final parsed = parseReplaceExercisePayload(action.payload);
    if (parsed is PayloadParseFailure<ReplaceExercisePayload>) {
      return PreviewFailure(parsed.message);
    }
    final payload =
        (parsed as PayloadParseSuccess<ReplaceExercisePayload>).value;

    final dayIndex = plan.days.indexWhere(
      (d) => d.dayOfWeek == payload.dayOfWeek,
    );
    if (dayIndex < 0) {
      return const PreviewFailure('无法预览：计划中没有该训练日。');
    }

    PlannedExercise? original;
    for (final ex in plan.days[dayIndex].exercises) {
      if (ex.exerciseId == payload.fromExerciseId) {
        original = ex;
        break;
      }
    }
    if (original == null) {
      return const PreviewFailure('无法预览：在该训练日中没有找到原动作。');
    }

    final toExercise = appState.exercises
        .where((e) => e.id == payload.toExerciseId)
        .firstOrNull;
    final toName = toExercise?.name ?? payload.toExerciseId;

    return ReplacePreview(
      dayOfWeek: payload.dayOfWeek,
      originalExercise: original,
      toExerciseName: toName,
      toExerciseId: payload.toExerciseId,
    );
  }

  ActionPreview _previewReschedule(AgentAction action, AppState appState) {
    final plan = appState.activePlan;
    if (plan == null) {
      return const PreviewFailure('无法预览：当前没有训练计划。');
    }

    final parsed = parseAvailableWeekdays(action.payload['availableWeekdays']);
    if (parsed is PayloadParseFailure<List<int>>) {
      return PreviewFailure(parsed.message);
    }
    final weekdays = (parsed as PayloadParseSuccess<List<int>>).value;

    final result = reschedulePlanToWeekdays(
      plan: plan,
      availableWeekdays: weekdays,
    );

    return ReschedulePreview(
      originalPlan: plan,
      newPlan: result.plan,
      availableWeekdays: weekdays,
    );
  }

  ActionPreview _previewGeneratePlan(AgentAction action, AppState appState) {
    if (appState.profile == null) {
      return const PreviewFailure('需要先完成个人信息设置才能预览计划。');
    }
    final parsed = parseGeneratePlanPayload(action.payload);
    if (parsed is PayloadParseFailure<GeneratePlanPayload>) {
      return PreviewFailure(parsed.message);
    }
    final preferences =
        (parsed as PayloadParseSuccess<GeneratePlanPayload>).value;
    try {
      var preview = appState.previewPlan();
      final weekdays = preferences.availableWeekdays;
      if (weekdays != null) {
        preview = reschedulePlanToWeekdays(
          plan: preview,
          availableWeekdays: weekdays,
        ).plan;
      }
      final minutes = preferences.targetMinutes;
      if (minutes != null) {
        for (final day in preview.days) {
          if (day.dayType == WorkoutDayType.rest || day.exercises.isEmpty) {
            continue;
          }
          final compressed = compressDayInPlan(
            plan: preview,
            dayOfWeek: day.dayOfWeek,
            targetMinutes: minutes,
          );
          if (compressed != null) {
            preview = compressed;
          }
        }
      }
      return GeneratePlanPreview(
        originalPlan: appState.activePlan,
        previewPlan: preview,
      );
    } catch (_) {
      return const PreviewFailure('预览计划生成失败。');
    }
  }

  /// 解析 weeklyReview payload。校验失败时返回 [PreviewFailure]，UI
  /// 会安全 fallback 到 `action.summary`，不会显示空 panel。
  ///
  /// 故意不需要 AppState：weeklyReview 是只读、non-mutating 的复盘卡片，
  /// 只读 payload 即可生成 preview，UI 层不必引入 Provider 依赖。
  ActionPreview previewWeeklyReview(AgentAction action) {
    final parsed = parseWeeklyReviewPayload(action.payload);
    if (parsed is PayloadParseFailure<WeeklyReviewPayload>) {
      return PreviewFailure(parsed.message);
    }
    final value = (parsed as PayloadParseSuccess<WeeklyReviewPayload>).value;
    return WeeklyReviewPreview(
      summary: value.summary,
      completedSessions: value.completedSessions,
      focusAreas: value.focusAreas,
      observations: value.observations,
      nextWeekSuggestions: value.nextWeekSuggestions,
      riskNotes: value.riskNotes,
    );
  }
}

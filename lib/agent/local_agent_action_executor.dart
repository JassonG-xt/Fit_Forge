import '../models/enums.dart';
import '../models/workout_plan.dart';
import '../services/app_state.dart';
import 'action_helpers/exercise_replacer.dart';
import 'action_helpers/workout_compressor.dart';
import 'action_helpers/workout_mover.dart';
import 'action_helpers/workout_rescheduler.dart';
import 'action_payload_parser.dart';
import 'models/agent_action.dart';
import 'models/agent_action_result.dart';
import 'plan_context_hash.dart';

/// 在用户确认后真正修改 AppState 的执行器。
///
/// 集中所有写操作，UI 不直接修改训练计划。各 action 类型的实现
/// 都会先做 payload 校验，校验失败时返回 [AgentActionResult.failure]
/// 而不抛异常给 UI。
class LocalAgentActionExecutor {
  LocalAgentActionExecutor(this.appState);

  final AppState appState;

  Future<AgentActionResult> execute(AgentAction action) async {
    final mutationGuard = _validateMutationBoundary(action);
    if (mutationGuard != null) return mutationGuard;

    switch (action.type) {
      case AgentActionType.generatePlan:
        return _generatePlan(action);
      case AgentActionType.rescheduleWeek:
        return _rescheduleWeek(action);
      case AgentActionType.replaceExercise:
        return _replaceExercise(action);
      case AgentActionType.compressWorkout:
        return _compressWorkout(action);
      case AgentActionType.moveWorkoutSession:
        return _moveWorkoutSession(action);
      case AgentActionType.answerOnly:
      case AgentActionType.nutritionAdvice:
      case AgentActionType.weeklyReview:
      case AgentActionType.safetyResponse:
        return AgentActionResult.noop('这个建议不需要修改本地数据。');
    }
  }

  // 共享 payload 校验：plan 必须存在。
  static AgentActionResult? _requireActivePlan(WorkoutPlan? plan) {
    if (plan == null) {
      return AgentActionResult.failure('当前没有可调整的训练计划。');
    }
    return null;
  }

  static bool _isMutation(AgentActionType type) {
    switch (type) {
      case AgentActionType.generatePlan:
      case AgentActionType.rescheduleWeek:
      case AgentActionType.replaceExercise:
      case AgentActionType.compressWorkout:
      case AgentActionType.moveWorkoutSession:
        // moveWorkoutSession 是 mutation（design §6），即使 runtime 尚未实现，
        // 也保留 mutation boundary 检查（requiresConfirmation + sourceContextHash），
        // 防止上游绕过用户确认。
        return true;
      case AgentActionType.answerOnly:
      case AgentActionType.nutritionAdvice:
      case AgentActionType.weeklyReview:
      case AgentActionType.safetyResponse:
        return false;
    }
  }

  AgentActionResult? _validateMutationBoundary(AgentAction action) {
    if (!_isMutation(action.type)) return null;
    if (!action.requiresConfirmation) {
      return AgentActionResult.failure('该修改建议缺少用户确认要求，已拒绝执行。');
    }

    final plan = appState.activePlan;
    if (plan == null) return null;

    final expected = action.sourceContextHash;
    if (expected == null || expected.isEmpty) {
      return AgentActionResult.failure('修改建议缺少训练计划校验信息，请重新让教练生成建议。');
    }

    final current = computePlanContextHash(plan);
    if (current != expected) {
      return AgentActionResult.failure('训练计划已经发生变化，请重新让教练生成建议。');
    }
    return null;
  }

  // stale action 检测：如果 action 创建后 plan 已变化，拒绝执行。
  AgentActionResult? _checkStale(AgentAction action) {
    final expected = action.sourceContextHash;
    if (expected == null) return null; // legacy action without hash — allow
    final plan = appState.activePlan;
    if (plan == null) return null; // plan 消失 → _requireActivePlan 会拦
    final current = computePlanContextHash(plan);
    if (current != expected) {
      return AgentActionResult.failure('训练计划已经发生变化，请重新让教练生成建议。');
    }
    return null;
  }

  // ─── generatePlan ───
  // 不做 stale guard：generatePlan 基于 profile 生成全新计划，
  // 不依赖当前 activePlan 内容（situation A）。
  //
  // 可选偏好（payload 字段，均可缺省）：
  // - availableWeekdays: 生成基础计划后用 reschedulePlanToWeekdays 应用
  // - targetMinutes: 生成基础计划后对每个训练日用 compressDayInPlan 应用
  //
  // 偏好仅作为 PlanEngine 输出的确定性后处理，不进入 PlanEngine 内部
  // 选动作 / 划分 split 的逻辑；这样无需扩 PlanEngine 接口即可支持基础偏好。
  Future<AgentActionResult> _generatePlan(AgentAction action) async {
    if (appState.profile == null) {
      return AgentActionResult.failure('需要先完成个人信息设置才能生成训练计划。');
    }

    final parsed = parseGeneratePlanPayload(action.payload);
    if (parsed is PayloadParseFailure<GeneratePlanPayload>) {
      return AgentActionResult.failure(parsed.message);
    }
    final preferences =
        (parsed as PayloadParseSuccess<GeneratePlanPayload>).value;

    try {
      var plan = appState.previewPlan();
      plan = _applyPreferences(plan, preferences);
      appState.adoptPlan(plan);
      return AgentActionResult.success(
        title: '已生成训练计划',
        message: _generatePlanSuccessMessage(plan, preferences),
      );
    } catch (e) {
      return AgentActionResult.failure('生成计划失败：$e');
    }
  }

  // 把可选偏好作用到 PlanEngine 输出上。
  // 仅使用现有的 reschedulePlanToWeekdays / compressDayInPlan 助手，
  // 不引入新 helper、不修改 PlanEngine 行为。
  WorkoutPlan _applyPreferences(
    WorkoutPlan plan,
    GeneratePlanPayload preferences,
  ) {
    var current = plan;
    final weekdays = preferences.availableWeekdays;
    if (weekdays != null) {
      current = reschedulePlanToWeekdays(
        plan: current,
        availableWeekdays: weekdays,
      ).plan;
    }
    final minutes = preferences.targetMinutes;
    if (minutes != null) {
      for (final day in current.days) {
        if (day.dayType == WorkoutDayType.rest || day.exercises.isEmpty) {
          continue;
        }
        final compressed = compressDayInPlan(
          plan: current,
          dayOfWeek: day.dayOfWeek,
          targetMinutes: minutes,
        );
        if (compressed != null) {
          current = compressed;
        }
      }
    }
    return current;
  }

  String _generatePlanSuccessMessage(
    WorkoutPlan plan,
    GeneratePlanPayload preferences,
  ) {
    final dayCount = _workoutDayCount(plan.days);
    final parts = <String>['新计划包含 $dayCount 个训练日'];
    final weekdays = preferences.availableWeekdays;
    if (weekdays != null && weekdays.isNotEmpty) {
      final sorted = (weekdays.toSet().toList()..sort());
      parts.add('安排在 ${sorted.map(_weekdayName).join('、')}');
    }
    final minutes = preferences.targetMinutes;
    if (minutes != null) {
      parts.add('每次约 $minutes 分钟');
    }
    return '${parts.join('，')}。';
  }

  // ─── rescheduleWeek ───
  Future<AgentActionResult> _rescheduleWeek(AgentAction action) async {
    final plan = appState.activePlan;
    final planErr = _requireActivePlan(plan);
    if (planErr != null) return planErr;
    final staleErr = _checkStale(action);
    if (staleErr != null) return staleErr;

    final parsed = parseAvailableWeekdays(action.payload['availableWeekdays']);
    if (parsed is PayloadParseFailure) {
      return AgentActionResult.failure(parsed.message!);
    }
    final weekdays = (parsed as PayloadParseSuccess<List<int>>).value;

    final result = reschedulePlanToWeekdays(
      plan: plan!,
      availableWeekdays: weekdays,
    );
    appState.adoptPlan(result.plan);
    final dayLabel = (weekdays..sort()).map(_weekdayName).join('、');
    final dropped = result.dropped > 0
        ? '（${result.dropped} 个原训练日被合并到休息日）'
        : '';
    return AgentActionResult.success(
      title: '已重新安排训练日',
      message: '本周训练改到 $dayLabel$dropped。',
    );
  }

  // ─── replaceExercise ───
  Future<AgentActionResult> _replaceExercise(AgentAction action) async {
    final plan = appState.activePlan;
    final planErr = _requireActivePlan(plan);
    if (planErr != null) return planErr;
    final staleErr = _checkStale(action);
    if (staleErr != null) return staleErr;

    final parsed = parseReplaceExercisePayload(action.payload);
    if (parsed is PayloadParseFailure) {
      return AgentActionResult.failure(parsed.message!);
    }
    final payload =
        (parsed as PayloadParseSuccess<ReplaceExercisePayload>).value;

    final target = appState.exercises
        .where((e) => e.id == payload.toExerciseId)
        .firstOrNull;
    if (target == null) {
      return AgentActionResult.failure('替代动作 ${payload.toExerciseId} 不在动作库中。');
    }

    final newPlan = replaceExerciseInPlan(
      plan: plan!,
      dayOfWeek: payload.dayOfWeek,
      fromExerciseId: payload.fromExerciseId,
      toExerciseId: payload.toExerciseId,
      toExerciseName: target.name,
    );
    if (newPlan == null) {
      return AgentActionResult.failure('在计划中没有找到对应的动作。');
    }
    appState.adoptPlan(newPlan);
    return AgentActionResult.success(
      title: '已替换动作',
      message: '已将原动作替换为 ${target.name}。',
    );
  }

  // ─── compressWorkout ───
  Future<AgentActionResult> _compressWorkout(AgentAction action) async {
    final plan = appState.activePlan;
    final planErr = _requireActivePlan(plan);
    if (planErr != null) return planErr;
    final staleErr = _checkStale(action);
    if (staleErr != null) return staleErr;

    final parsed = parseCompressWorkoutPayload(action.payload);
    if (parsed is PayloadParseFailure) {
      return AgentActionResult.failure(parsed.message!);
    }
    final payload =
        (parsed as PayloadParseSuccess<CompressWorkoutPayload>).value;

    final newPlan = compressDayInPlan(
      plan: plan!,
      dayOfWeek: payload.dayOfWeek,
      targetMinutes: payload.targetMinutes,
    );
    if (newPlan == null) {
      return AgentActionResult.failure('当天没有可以压缩的训练。');
    }
    appState.adoptPlan(newPlan);
    return AgentActionResult.success(
      title: '已压缩训练',
      message: '今日训练已压缩到约 ${payload.targetMinutes} 分钟。',
    );
  }

  // ─── moveWorkoutSession ───
  // 把一个已计划的训练从源日完整移到目标日。冲突规则：目标日已有训练时拒绝，
  // 不自动合并、不交换、不追加。源日转为 rest。详见
  // docs/move_workout_session_design.md。
  Future<AgentActionResult> _moveWorkoutSession(AgentAction action) async {
    final plan = appState.activePlan;
    final planErr = _requireActivePlan(plan);
    if (planErr != null) return planErr;
    final staleErr = _checkStale(action);
    if (staleErr != null) return staleErr;

    final parsed = parseMoveWorkoutSessionPayload(action.payload);
    if (parsed is PayloadParseFailure) {
      return AgentActionResult.failure(parsed.message!);
    }
    final payload =
        (parsed as PayloadParseSuccess<MoveWorkoutSessionPayload>).value;

    final source = plan!.days
        .where((d) => d.dayOfWeek == payload.fromDayOfWeek)
        .firstOrNull;
    final sourceHasWorkout =
        source != null &&
        source.dayType != WorkoutDayType.rest &&
        source.exercises.isNotEmpty;
    if (!sourceHasWorkout) {
      return AgentActionResult.failure(
        '${_weekdayName(payload.fromDayOfWeek)}没有训练，无法移动。',
      );
    }

    final target = plan.days
        .where((d) => d.dayOfWeek == payload.toDayOfWeek)
        .firstOrNull;
    final targetOccupied =
        target != null &&
        target.dayType != WorkoutDayType.rest &&
        target.exercises.isNotEmpty;
    if (targetOccupied) {
      return AgentActionResult.failure(
        '${_weekdayName(payload.toDayOfWeek)}已有训练，'
        '请先调整目标日；不会自动合并或交换。',
      );
    }

    final newPlan = moveWorkoutSessionInPlan(
      plan: plan,
      fromDayOfWeek: payload.fromDayOfWeek,
      toDayOfWeek: payload.toDayOfWeek,
    );
    appState.adoptPlan(newPlan);
    return AgentActionResult.success(
      title: '已移动训练',
      message:
          '已将${_weekdayName(payload.fromDayOfWeek)}的训练'
          '移到${_weekdayName(payload.toDayOfWeek)}。',
    );
  }

  int _workoutDayCount(Iterable<WorkoutDay> days) =>
      days.where((d) => d.dayType != WorkoutDayType.rest).length;

  String _weekdayName(int weekday) =>
      const {
        1: '周一',
        2: '周二',
        3: '周三',
        4: '周四',
        5: '周五',
        6: '周六',
        7: '周日',
      }[weekday] ??
      '周$weekday';
}

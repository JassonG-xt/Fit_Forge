import '../models/enums.dart';
import '../models/workout_plan.dart';
import '../services/app_state.dart';
import 'action_helpers/exercise_replacer.dart';
import 'action_helpers/workout_compressor.dart';
import 'action_helpers/workout_rescheduler.dart';
import 'models/agent_action.dart';
import 'models/agent_action_result.dart';

/// 在用户确认后真正修改 AppState 的执行器。
///
/// 集中所有写操作，UI 不直接修改训练计划。各 action 类型的实现
/// 都会先做 payload 校验，校验失败时返回 [AgentActionResult.failure]
/// 而不抛异常给 UI。
class LocalAgentActionExecutor {
  LocalAgentActionExecutor(this.appState);

  final AppState appState;

  Future<AgentActionResult> execute(AgentAction action) async {
    switch (action.type) {
      case AgentActionType.generatePlan:
        return _generatePlan(action);
      case AgentActionType.rescheduleWeek:
        return _rescheduleWeek(action);
      case AgentActionType.replaceExercise:
        return _replaceExercise(action);
      case AgentActionType.compressWorkout:
        return _compressWorkout(action);
      case AgentActionType.answerOnly:
      case AgentActionType.nutritionAdvice:
      case AgentActionType.weeklyReview:
      case AgentActionType.safetyResponse:
        return AgentActionResult.noop('这个建议不需要修改本地数据。');
    }
  }

  // ─── generatePlan ───
  Future<AgentActionResult> _generatePlan(AgentAction action) async {
    if (appState.profile == null) {
      return AgentActionResult.failure('需要先完成个人信息设置才能生成训练计划。');
    }
    try {
      final plan = appState.previewPlan();
      appState.adoptPlan(plan);
      return AgentActionResult.success(
        title: '已生成训练计划',
        message: '新计划包含 ${_workoutDayCount(plan.days)} 个训练日。',
      );
    } catch (e) {
      return AgentActionResult.failure('生成计划失败：$e');
    }
  }

  // ─── rescheduleWeek ───
  Future<AgentActionResult> _rescheduleWeek(AgentAction action) async {
    final plan = appState.activePlan;
    if (plan == null) {
      return AgentActionResult.failure('当前没有可调整的训练计划。');
    }
    final raw = action.payload['availableWeekdays'];
    if (raw is! List) {
      return AgentActionResult.failure('availableWeekdays 字段缺失或格式不正确。');
    }
    final weekdays = raw.whereType<num>().map((n) => n.toInt()).toList();
    if (weekdays.isEmpty) {
      return AgentActionResult.failure('训练日期不能为空。');
    }
    if (weekdays.any((d) => d < 1 || d > 7)) {
      return AgentActionResult.failure('训练日期必须在 1-7 之间（周一到周日）。');
    }

    final result = reschedulePlanToWeekdays(
      plan: plan,
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
    if (plan == null) {
      return AgentActionResult.failure('当前没有可调整的训练计划。');
    }
    final dayOfWeek = action.payload['dayOfWeek'];
    final fromId = action.payload['fromExerciseId'];
    final toId = action.payload['toExerciseId'];
    if (dayOfWeek is! num || dayOfWeek < 1 || dayOfWeek > 7) {
      return AgentActionResult.failure('dayOfWeek 缺失或不在 1-7 之间。');
    }
    if (fromId is! String || fromId.isEmpty) {
      return AgentActionResult.failure('fromExerciseId 缺失。');
    }
    if (toId is! String || toId.isEmpty) {
      return AgentActionResult.failure('toExerciseId 缺失。');
    }

    final target = appState.exercises.where((e) => e.id == toId).firstOrNull;
    if (target == null) {
      return AgentActionResult.failure('替代动作 $toId 不在动作库中。');
    }

    final newPlan = replaceExerciseInPlan(
      plan: plan,
      dayOfWeek: dayOfWeek.toInt(),
      fromExerciseId: fromId,
      toExerciseId: toId,
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
    if (plan == null) {
      return AgentActionResult.failure('当前没有可调整的训练计划。');
    }
    final dayOfWeekRaw = action.payload['dayOfWeek'] ?? DateTime.now().weekday;
    final targetMinutesRaw = action.payload['targetMinutes'];

    if (dayOfWeekRaw is! num ||
        dayOfWeekRaw.toInt() < 1 ||
        dayOfWeekRaw.toInt() > 7) {
      return AgentActionResult.failure('dayOfWeek 不在 1-7 之间。');
    }
    if (targetMinutesRaw is! num || targetMinutesRaw.toInt() <= 0) {
      return AgentActionResult.failure('targetMinutes 必须为正数。');
    }

    final newPlan = compressDayInPlan(
      plan: plan,
      dayOfWeek: dayOfWeekRaw.toInt(),
      targetMinutes: targetMinutesRaw.toInt(),
    );
    if (newPlan == null) {
      return AgentActionResult.failure('当天没有可以压缩的训练。');
    }
    appState.adoptPlan(newPlan);
    return AgentActionResult.success(
      title: '已压缩训练',
      message: '今日训练已压缩到约 ${targetMinutesRaw.toInt()} 分钟。',
    );
  }

  int _workoutDayCount(Iterable<WorkoutDay> days) =>
      days.where((d) => d.dayType != WorkoutDayType.rest).length;

  String _weekdayName(int weekday) =>
      const {1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日'}[weekday] ??
      '周$weekday';
}

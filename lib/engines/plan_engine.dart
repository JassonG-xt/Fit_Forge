import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// 训练计划生成引擎
/// 根据用户画像动态生成个性化训练计划
class PlanEngine {
  static const _uuid = Uuid();

  // ══════════ 主入口 ══════════

  static WorkoutPlan generatePlan(UserProfile profile, List<Exercise> exercises) {
    final split = determineSplit(profile.weeklyFrequency);
    final schedule = buildWeeklySchedule(split, profile.weeklyFrequency);
    final params = trainingParameters(profile.goal, profile.experienceLevel);

    final days = <WorkoutDay>[];
    for (var i = 0; i < schedule.length; i++) {
      final dayType = schedule[i];
      if (dayType == WorkoutDayType.rest) {
        days.add(WorkoutDay(dayOfWeek: i + 1, dayType: WorkoutDayType.rest));
        continue;
      }

      final selected = selectExercises(
        dayType.targetBodyParts,
        exercises,
        profile.availableEquipment,
        profile.experienceLevel,
        params,
      );

      final planned = selected.map((ex) => PlannedExercise(
            exerciseId: ex.id,
            exerciseName: ex.name,
            targetSets: params.sets,
            targetReps: params.reps,
            restSeconds: params.restSeconds,
          )).toList();

      days.add(WorkoutDay(dayOfWeek: i + 1, dayType: dayType, exercises: planned));
    }

    return WorkoutPlan(
      id: _uuid.v4(),
      name: '${profile.goal.displayName} - ${split.displayName}',
      goal: profile.goal,
      split: split,
      weeklyFrequency: profile.weeklyFrequency,
      days: days,
    );
  }

  // ══════════ Step 1: 确定分化模式 ══════════

  static TrainingSplit determineSplit(int frequency) {
    if (frequency <= 2) return TrainingSplit.fullBody;
    if (frequency == 3) return TrainingSplit.pushPullLegs;
    if (frequency == 4) return TrainingSplit.upperLower;
    return TrainingSplit.pushPullLegs;
  }

  // ══════════ Step 2: 构建一周日程 ══════════

  static List<WorkoutDayType> buildWeeklySchedule(TrainingSplit split, int frequency) {
    switch (split) {
      case TrainingSplit.fullBody:
        if (frequency == 1) {
          return [WorkoutDayType.fullBody, ...List.filled(6, WorkoutDayType.rest)];
        }
        return [WorkoutDayType.fullBody, WorkoutDayType.rest, WorkoutDayType.rest,
                WorkoutDayType.fullBody, WorkoutDayType.rest, WorkoutDayType.rest, WorkoutDayType.rest];

      case TrainingSplit.upperLower:
        return [WorkoutDayType.upper, WorkoutDayType.lower, WorkoutDayType.rest,
                WorkoutDayType.upper, WorkoutDayType.lower, WorkoutDayType.rest, WorkoutDayType.rest];

      case TrainingSplit.pushPullLegs:
        switch (frequency) {
          case 3:
            return [WorkoutDayType.push, WorkoutDayType.rest, WorkoutDayType.pull,
                    WorkoutDayType.rest, WorkoutDayType.legs, WorkoutDayType.rest, WorkoutDayType.rest];
          case 4:
            return [WorkoutDayType.push, WorkoutDayType.pull, WorkoutDayType.rest,
                    WorkoutDayType.legs, WorkoutDayType.push, WorkoutDayType.rest, WorkoutDayType.rest];
          case 5:
            return [WorkoutDayType.push, WorkoutDayType.pull, WorkoutDayType.legs,
                    WorkoutDayType.rest, WorkoutDayType.push, WorkoutDayType.pull, WorkoutDayType.rest];
          case 6:
            return [WorkoutDayType.push, WorkoutDayType.pull, WorkoutDayType.legs,
                    WorkoutDayType.push, WorkoutDayType.pull, WorkoutDayType.legs, WorkoutDayType.rest];
          default:
            return [WorkoutDayType.push, WorkoutDayType.rest, WorkoutDayType.pull,
                    WorkoutDayType.rest, WorkoutDayType.legs, WorkoutDayType.rest, WorkoutDayType.rest];
        }

      case TrainingSplit.custom:
        return [WorkoutDayType.fullBody, WorkoutDayType.rest, WorkoutDayType.fullBody,
                WorkoutDayType.rest, WorkoutDayType.fullBody, WorkoutDayType.rest, WorkoutDayType.rest];
    }
  }

  // ══════════ Step 3: 训练参数 ══════════

  static TrainingParams trainingParameters(FitnessGoal goal, ExperienceLevel level) {
    final baseEx = level == ExperienceLevel.beginner ? 4 : (level == ExperienceLevel.intermediate ? 5 : 6);

    switch (goal) {
      case FitnessGoal.buildMuscle:
        return TrainingParams(
          sets: level == ExperienceLevel.beginner ? 3 : 4,
          reps: 10, restSeconds: 75, exercisesPerSession: baseEx, compoundFirst: true,
        );
      case FitnessGoal.loseFat:
        return TrainingParams(
          sets: 3, reps: 14, restSeconds: 40, exercisesPerSession: baseEx + 1, compoundFirst: true,
        );
      case FitnessGoal.maintain:
        return TrainingParams(
          sets: 3, reps: 10, restSeconds: 60, exercisesPerSession: baseEx, compoundFirst: true,
        );
      case FitnessGoal.endurance:
        return TrainingParams(
          sets: 3, reps: 18, restSeconds: 30, exercisesPerSession: baseEx + 1, compoundFirst: false,
        );
    }
  }

  // ══════════ Step 4: 选择动作 ══════════

  static List<Exercise> selectExercises(
    List<BodyPart> bodyParts,
    List<Exercise> allExercises,
    List<Equipment> availableEquipment,
    ExperienceLevel level,
    TrainingParams params,
  ) {
    final selected = <Exercise>[];
    final pickedIds = <String>{}; // 去重：防止跨部位选到同一动作
    final levelIndex = ExperienceLevel.values.indexOf(level);

    for (final part in bodyParts) {
      final candidates = allExercises.where((e) =>
          e.bodyPart == part &&
          !pickedIds.contains(e.id) &&
          e.allRequiredEquipment.every((req) => availableEquipment.contains(req)) &&
          ExperienceLevel.values.indexOf(e.difficulty) <= levelIndex).toList();

      if (candidates.isEmpty) {
        // 兜底：同部位自重动作（也需去重）
        final fallback = allExercises.where((e) =>
            e.bodyPart == part &&
            !pickedIds.contains(e.id) &&
            e.equipment == Equipment.bodyweight).toList();
        if (fallback.isNotEmpty) {
          selected.add(fallback.first);
          pickedIds.add(fallback.first.id);
        }
        continue;
      }

      // 复合动作优先
      if (params.compoundFirst) {
        candidates.sort((a, b) => (b.isCompound ? 1 : 0) - (a.isCompound ? 1 : 0));
      }

      final count = bodyParts.length <= 3 ? 2 : 1;
      for (final ex in candidates.take(count)) {
        if (pickedIds.add(ex.id)) {
          selected.add(ex);
        }
      }
      if (selected.length >= params.exercisesPerSession) break;
    }

    return selected.take(params.exercisesPerSession).toList();
  }

  // ══════════ 热身推荐 ══════════

  static List<String> warmupRecommendation(WorkoutDayType dayType) {
    final general = ['5 分钟轻度有氧（快走/跳绳）', '关节绕环（肩/肘/膝/踝各 10 次）'];
    final Map<WorkoutDayType, List<String>> specific = {
      WorkoutDayType.push: ['肩部绕环 15 次', '弹力带肩外旋 12 次', '俯卧撑 10 次（热身）'],
      WorkoutDayType.pull: ['猫牛伸展 10 次', '弹力带拉伸 12 次', '悬挂 20 秒'],
      WorkoutDayType.legs: ['徒手深蹲 15 次', '弓步走 10 步', '臀桥 15 次'],
      WorkoutDayType.upper: ['肩部绕环 15 次', '俯卧撑 10 次', '弹力带面拉 12 次'],
      WorkoutDayType.lower: ['徒手深蹲 15 次', '弓步走 10 步', '小腿踮起 20 次'],
      WorkoutDayType.fullBody: ['开合跳 20 次', '徒手深蹲 10 次', '俯卧撑 10 次'],
    };
    return [...general, ...specific[dayType] ?? []];
  }

  /// 训练后拉伸推荐
  static List<String> cooldownRecommendation(WorkoutDayType dayType) {
    final general = ['5 分钟慢走放松', '深呼吸 5 次'];
    final Map<WorkoutDayType, List<String>> specific = {
      WorkoutDayType.push: ['胸部门框拉伸 30 秒', '三头肌过头拉伸 30 秒'],
      WorkoutDayType.pull: ['背阔肌侧拉 30 秒', '二头肌墙面拉伸 30 秒'],
      WorkoutDayType.legs: ['股四头肌拉伸 30 秒', '腘绳肌拉伸 30 秒', '臀部鸽子式 30 秒'],
      WorkoutDayType.upper: ['胸部拉伸 30 秒', '背部拉伸 30 秒'],
      WorkoutDayType.lower: ['股四头肌拉伸 30 秒', '腘绳肌拉伸 30 秒'],
      WorkoutDayType.fullBody: ['全身拉伸序列各 20 秒'],
    };
    return [...general, ...specific[dayType] ?? ['泡沫轴全身放松 5 分钟']];
  }
}

/// 训练参数
class TrainingParams {

  const TrainingParams({
    required this.sets,
    required this.reps,
    required this.restSeconds,
    required this.exercisesPerSession,
    required this.compoundFirst,
  });
  final int sets;
  final int reps;
  final int restSeconds;
  final int exercisesPerSession;
  final bool compoundFirst;
}

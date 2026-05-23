import 'coach_intent.dart';

class CoachClarificationPolicy {
  const CoachClarificationPolicy();

  String? messageFor(IntentCandidate candidate) {
    if (!candidate.hasMissingSlots) return null;
    return switch (candidate.type) {
      CoachIntentType.compressWorkout => compressTargetDuration,
      CoachIntentType.replaceExercise => replaceExerciseAndEquipment,
      CoachIntentType.rescheduleWeek ||
      CoachIntentType.moveWorkoutSession => scheduleScope,
      _ => null,
    };
  }

  static const compressTargetDuration =
      '可以帮你缩短今天的训练。为了不随便删动作，我需要知道目标时长，比如 20 分钟、30 分钟或半小时。';

  static const replaceExerciseAndEquipment =
      '可以帮你替换动作。请告诉我具体要替换哪个动作，以及你现在可用的器械；如果今天已有训练计划，我会优先找同部位替代动作。';

  static const scheduleScope =
      '可以帮你调整训练时间和训练安排。你是想调整整周可训练日，还是把某一天的训练移动到另一天下？例如“这周只能周二周四练”或“把周一训练挪到周三”。';
}

/// Coach Agent 解析出的用户意图。
///
/// 用于驱动 UI 上的 hint、suggested prompts 排序，以及在 mock 客户端中
/// 选择不同的响应分支。后端真实模型也会返回该枚举对应的字符串。
enum AgentIntent {
  answerOnly,
  generatePlan,
  rescheduleWeek,
  replaceExercise,
  compressWorkout,
  nutritionAdvice,
  weeklyReview,
  safetyResponse,
  unknown;

  static AgentIntent fromName(String? name) {
    if (name == null) return AgentIntent.unknown;
    for (final value in AgentIntent.values) {
      if (value.name == name) return value;
    }
    return AgentIntent.unknown;
  }
}

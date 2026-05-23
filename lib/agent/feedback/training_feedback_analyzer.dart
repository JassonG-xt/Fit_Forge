import '../models/agent_context_snapshot.dart';
import 'training_feedback_summary.dart';

class TrainingFeedbackAnalyzer {
  const TrainingFeedbackAnalyzer();

  TrainingFeedbackSummary analyze({
    required AgentContextSnapshot context,
    String? userMessage,
  }) {
    final progress = context.progressSummary;
    final completedThisWeek = _asInt(progress['totalWorkoutsThisWeek']) ?? 0;
    final streakDays = _asInt(progress['streakDays']) ?? 0;
    final weeklyFrequency = _asInt(progress['weeklyFrequency']);
    final recentSessions = context.recentSessions;
    final recentSessionCount = recentSessions.length;

    if (recentSessionCount == 0) {
      const observations = [
        '最近没有已完成的训练记录。',
        '目前没有睡眠、酸痛评分或主观疲劳数据，所以不能判断你的真实恢复状态。',
      ];
      const suggestions = [
        '目前缺少最近训练记录，恢复判断有限。先完成几次训练后，我可以根据训练频率、连续训练天数和训练部位分布给出更具体的复盘。',
        '我不会直接修改你的计划；如果之后想调整今天或下周的训练，需要你明确说一句，并经过确认。',
      ];
      return const TrainingFeedbackSummary(
        hasSufficientData: false,
        recentSessionCount: 0,
        completedThisWeek: 0,
        streakDays: 0,
        weeklyFrequency: null,
        focusAreas: [],
        observations: observations,
        riskNotes: [],
        suggestions: suggestions,
        summaryText: '暂无近期训练数据，无法判断真实恢复状态。',
        messageText:
            '最近还没有完成的训练记录，我现在不能判断你的真实恢复状态。先完成几次训练后，我可以根据训练频率、连续训练天数和训练部位分布给出更具体的复盘。',
      );
    }

    final focusAreas = _focusAreas(recentSessions);
    final observations = <String>[
      '近期已记录 $recentSessionCount 次训练。',
      if (weeklyFrequency != null)
        '本周完成 $completedThisWeek 次，计划频率为每周 $weeklyFrequency 次。',
      if (focusAreas.isNotEmpty) '最近主要训练：${focusAreas.join('、')}。',
      if (streakDays > 0) '当前连续训练 $streakDays 天。',
      '目前没有睡眠、酸痛评分或主观疲劳数据，所以恢复判断只能基于训练频率和连续训练天数。',
    ];

    final riskNotes = <String>[];
    if (weeklyFrequency != null && completedThisWeek > weeklyFrequency) {
      riskNotes.add(
        '本周已经超过计划频率：完成 $completedThisWeek 次，高于计划的 $weeklyFrequency 次，注意恢复。',
      );
    }
    if (streakDays >= 4) {
      riskNotes.add('连续训练天数较高，注意安排恢复日。');
    }

    final suggestions = <String>[];
    if (weeklyFrequency != null) {
      if (completedThisWeek < weeklyFrequency) {
        suggestions.add(
          '本周训练频率还没达到计划目标，可以优先补足训练次数到每周 $weeklyFrequency 次；如果疲劳明显，优先保证恢复。',
        );
        suggestions.add('不建议盲目加强度补偿，也不要为了追次数硬撑高强度训练。');
      } else if (completedThisWeek == weeklyFrequency) {
        suggestions.add('本周频率已经达标，接下来优先保证动作质量和恢复。');
        suggestions.add('不建议额外加练；如果今天状态一般，可以休息或做低强度活动。');
      } else {
        suggestions.add('下一次建议降低强度或做恢复训练，不建议继续加量。');
      }
    } else {
      suggestions.add('当前缺少计划频率，只能先根据近期训练次数和连续训练天数做保守判断。');
    }

    if (focusAreas.isNotEmpty) {
      suggestions.add('继续保证 ${focusAreas.first} 训练日的动作质量。');
    }
    if (streakDays >= 4) {
      suggestions.add('如果今天状态一般，建议休息或低强度活动，把恢复日安排进本周。');
    }
    if (_hasSoreLegs(userMessage) && _hasLowerBodyFocus(recentSessions)) {
      suggestions.add('近期下肢训练占比较高，今天腿还酸时不建议继续高强度腿部训练，可以选择休息、低强度活动或上肢训练。');
    }
    if (riskNotes.isNotEmpty || streakDays >= 4 || _hasSoreLegs(userMessage)) {
      suggestions.add('我不会直接修改你的计划；训练反馈会保持只读，需要调整计划时仍要你明确确认。');
    }

    final focusText = focusAreas.isEmpty
        ? ''
        : '最近主要训练 ${focusAreas.join('、')}。';
    final summaryText =
        '近期 $recentSessionCount 次训练，本周完成 $completedThisWeek 次，连续 $streakDays 天。$focusText';
    final messageText =
        '$summaryText${suggestions.isEmpty ? '' : suggestions.first}';

    return TrainingFeedbackSummary(
      hasSufficientData: true,
      recentSessionCount: recentSessionCount,
      completedThisWeek: completedThisWeek,
      streakDays: streakDays,
      weeklyFrequency: weeklyFrequency,
      focusAreas: focusAreas,
      observations: observations,
      riskNotes: riskNotes,
      suggestions: suggestions,
      summaryText: summaryText,
      messageText: messageText,
    );
  }

  int? _asInt(Object? raw) => raw is int ? raw : null;

  List<String> _focusAreas(List<Map<String, dynamic>> recentSessions) {
    final counts = <String, int>{};
    for (final session in recentSessions) {
      final dayType = session['dayType'];
      if (dayType is! String || dayType == 'rest') continue;
      counts[dayType] = (counts[dayType] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });
    return entries.take(3).map((entry) => _dayTypeLabel(entry.key)).toList();
  }

  bool _hasLowerBodyFocus(List<Map<String, dynamic>> recentSessions) {
    var lowerCount = 0;
    var total = 0;
    for (final session in recentSessions) {
      final dayType = session['dayType'];
      if (dayType is! String || dayType == 'rest') continue;
      total += 1;
      if (dayType == 'legs' || dayType == 'lower') lowerCount += 1;
    }
    return total > 0 && lowerCount / total >= 0.5;
  }

  bool _hasSoreLegs(String? message) {
    if (message == null) return false;
    return message.contains('腿酸') ||
        message.contains('腿还酸') ||
        message.contains('腿部酸') ||
        message.contains('下肢酸');
  }

  String _dayTypeLabel(String key) => switch (key) {
    'push' => '推（胸 / 肩 / 三头）',
    'pull' => '拉（背 / 二头）',
    'legs' => '腿',
    'upper' => '上肢',
    'lower' => '下肢',
    'fullBody' || 'full' => '全身',
    'cardio' => '有氧',
    _ => key,
  };
}

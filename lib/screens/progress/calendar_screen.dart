import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<AppState>().completedSessions;
    final workoutDates = sessions.map((s) =>
        DateTime(s.date.year, s.date.month, s.date.day)).toSet();
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('训练日历')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // 月份标题
          Text('${now.year} 年 ${now.month} 月',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // 星期标题
          Row(children: ['一', '二', '三', '四', '五', '六', '日']
              .map((d) => Expanded(child: Center(
                  child: Text(d, style: TextStyle(fontSize: 12, color: Colors.grey[600])))))
              .toList()),
          const SizedBox(height: 8),
          // 日期网格
          _monthGrid(now, workoutDates),
          const SizedBox(height: 20),
          // 本月统计
          _monthStats(sessions, now),
        ]),
      ),
    );
  }

  Widget _monthGrid(DateTime now, Set<DateTime> workoutDates) {
    final firstDay = DateTime(now.year, now.month, 1);
    int startWeekday = firstDay.weekday; // 1=Mon
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final today = DateTime(now.year, now.month, now.day);

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: [
        // 空白填充
        ...List.generate(startWeekday - 1, (_) => const SizedBox()),
        // 日期
        ...List.generate(daysInMonth, (i) {
          final day = i + 1;
          final date = DateTime(now.year, now.month, day);
          final isToday = date == today;
          final hasWorkout = workoutDates.contains(date);

          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isToday ? Colors.orange : null,
              shape: BoxShape.circle,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$day',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isToday ? FontWeight.bold : null,
                    color: isToday ? Colors.white : null,
                  )),
              if (hasWorkout)
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: isToday ? Colors.white : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          );
        }),
      ],
    );
  }

  Widget _monthStats(List<WorkoutSession> sessions, DateTime now) {
    final monthSessions = sessions.where((s) =>
        s.date.year == now.year && s.date.month == now.month).toList();
    final totalMin = monthSessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);

    return Card(
      elevation: 0, color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('${monthSessions.length}', '训练次数'),
          _stat('$totalMin', '总时长(分钟)'),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
  }
}

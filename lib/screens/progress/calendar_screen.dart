import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/stat_number.dart';
import '../../widgets/cards/section_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    // Don't navigate beyond current month
    if (nextMonth.isAfter(DateTime(now.year, now.month + 1))) return;
    setState(() => _selectedMonth = nextMonth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final sessions = state.completedSessions;
    final workoutDates = sessions.map((s) =>
        DateTime(s.date.year, s.date.month, s.date.day)).toSet();
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Scaffold(
      appBar: AppBar(title: const Text('训练日历')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        child: Column(children: [
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _prevMonth,
              ),
              Text(
                '${_selectedMonth.year} 年 ${_selectedMonth.month} 月',
                style: theme.textTheme.headlineSmall,
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth ? AppColors.textTertiary : null),
                onPressed: isCurrentMonth ? null : _nextMonth,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(children: ['一', '二', '三', '四', '五', '六', '日']
              .map((d) => Expanded(child: Center(
                  child: Text(d, style: theme.textTheme.labelSmall))))
              .toList()),
          const SizedBox(height: AppSpacing.sm),
          _monthGrid(theme, now, workoutDates, sessions),
          const SizedBox(height: AppSpacing.lg),
          _monthStats(theme, sessions),
        ]),
      ),
    );
  }

  Widget _monthGrid(ThemeData theme, DateTime now, Set<DateTime> workoutDates,
      List<WorkoutSession> sessions) {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final int startWeekday = firstDay.weekday;
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final today = DateTime(now.year, now.month, now.day);

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: [
        ...List.generate(startWeekday - 1, (_) => const SizedBox()),
        ...List.generate(daysInMonth, (i) {
          final day = i + 1;
          final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
          final isToday = date == today;
          final hasWorkout = workoutDates.contains(date);

          // Find sessions for this day (for tap handler)
          final daySessions = sessions.where((s) =>
              s.date.year == date.year &&
              s.date.month == date.month &&
              s.date.day == date.day).toList();

          return GestureDetector(
            onTap: daySessions.isNotEmpty ? () => _showDaySessions(daySessions, date) : null,
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isToday ? AppColors.primary : null,
                shape: BoxShape.circle,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$day',
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: isToday ? FontWeight.bold : null,
                      color: isToday ? Colors.white : null,
                    )),
                if (hasWorkout)
                  Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(
                      color: isToday ? Colors.white : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ]),
            ),
          );
        }),
      ],
    );
  }

  void _showDaySessions(List<WorkoutSession> sessions, DateTime date) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date.month}/${date.day} 训练记录',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            ...sessions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(s.dayType.displayName, style: theme.textTheme.titleSmall),
                      const Spacer(),
                      Text('${s.durationMinutes} 分钟',
                          style: theme.textTheme.labelSmall),
                    ]),
                    const SizedBox(height: AppSpacing.xs),
                    ...s.exerciseRecords.map((r) {
                      final completedSets = r.sets.where((set) => set.isCompleted).length;
                      final totalVolume = r.totalVolume;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Expanded(
                            child: Text(r.exerciseName,
                                style: theme.textTheme.bodySmall),
                          ),
                          Text(
                            '$completedSets 组 · ${totalVolume.toStringAsFixed(0)}kg',
                            style: theme.textTheme.labelSmall!.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ]),
                      );
                    }),
                  ],
                ),
              ),
            )),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _monthStats(ThemeData theme, List<WorkoutSession> sessions) {
    final monthSessions = sessions.where((s) =>
        s.date.year == _selectedMonth.year &&
        s.date.month == _selectedMonth.month).toList();
    final totalMin = monthSessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);

    return Row(
      children: [
        Expanded(child: SectionCard(
          child: StatNumber(value: '${monthSessions.length}', label: '训练次数', fontSize: 24),
        )),
        const SizedBox(width: AppSpacing.cardGap),
        Expanded(child: SectionCard(
          child: StatNumber(value: '$totalMin', label: '总时长(分)', fontSize: 24, valueColor: AppColors.accent),
        )),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/brand/heat_strip.dart';
import '../../widgets/brand/metric_tile.dart';
import '../../widgets/brand/nav_card.dart';
import '../../widgets/cards/section_card.dart';
import 'body_metrics_screen.dart';
import 'calendar_screen.dart';
import 'achievements_screen.dart';

class ProgressTabScreen extends StatelessWidget {
  const ProgressTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('进度追踪')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),

                // ─── 本月总览 ───
                _monthlySummary(context, state),
                const SizedBox(height: AppSpacing.lg),

                // ─── 体重趋势图 ───
                _weightTrendCard(context, state),
                const SizedBox(height: AppSpacing.lg),

                // ─── 本周热图 ───
                _weekHeatSection(context, state),
                const SizedBox(height: AppSpacing.lg),

                // ─── 最近训练 ───
                _recentWorkouts(context, state),
                const SizedBox(height: AppSpacing.lg),

                // ─── 成就精选 ───
                _achievementHighlights(context, state),
                const SizedBox(height: AppSpacing.lg),

                // ─── 导航入口 ───
                Text('详细数据', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                NavCard(
                  title: '身体数据',
                  subtitle: '记录体重、体脂、围度变化',
                  icon: Icons.show_chart,
                  color: AppColors.arms,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const BodyMetricsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.cardGap),
                NavCard(
                  title: '训练日历',
                  subtitle: '查看训练历史和安排',
                  icon: Icons.calendar_month,
                  color: AppColors.back,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const CalendarScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.cardGap),
                NavCard(
                  title: '全部成就',
                  subtitle: '你的健身里程碑',
                  icon: Icons.emoji_events,
                  color: AppColors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AchievementsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  本月总览 —— 复用 MetricTile，与首页 dashboard 视觉一致
  // ════════════════════════════════════════════
  Widget _monthlySummary(BuildContext context, AppState state) {
    final now = DateTime.now();
    final monthSessions = state.completedSessions
        .where((s) => s.date.year == now.year && s.date.month == now.month)
        .toList();
    final totalWorkouts = monthSessions.length;
    final totalVolume = monthSessions.fold<double>(
      0,
      (sum, s) =>
          sum +
          s.exerciseRecords.fold<double>(0, (rs, r) => rs + r.totalVolume),
    );

    final tiles = <Widget>[
      MetricTile(
        icon: Icons.fitness_center_rounded,
        value: '$totalWorkouts',
        label: '本月训练',
        unit: '次',
        accentColor: AppColors.primary,
      ),
      MetricTile(
        icon: Icons.scale_outlined,
        value: '${totalVolume ~/ 1000}',
        label: '总容量',
        unit: '吨',
        accentColor: AppColors.accent,
      ),
      MetricTile(
        icon: Icons.local_fire_department_outlined,
        value: '${state.streakDays}',
        label: '连续天数',
        unit: '天',
        accentColor: AppColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                SizedBox(width: double.infinity, child: tiles[i]),
                if (i != tiles.length - 1)
                  const SizedBox(height: AppSpacing.cardGap),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i != tiles.length - 1)
                const SizedBox(width: AppSpacing.cardGap),
            ],
          ],
        );
      },
    );
  }

  // ════════════════════════════════════════════
  //  体重趋势图
  // ════════════════════════════════════════════
  Widget _weightTrendCard(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final metrics = state.bodyMetrics;
    final points = metrics.reversed
        .where((m) => m.weightKg != null)
        .map(
          (m) => FlSpot(m.date.millisecondsSinceEpoch.toDouble(), m.weightKg!),
        )
        .toList();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('体重趋势', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (points.isNotEmpty)
                Text(
                  '${points.last.y.toStringAsFixed(1)} kg',
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: points.length < 2
                ? Center(
                    child: Text(
                      '记录 2 次以上体重后显示趋势图',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => AppColors.bgSurface,
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: points,
                          isCurved: true,
                          curveSmoothness: 0.3,
                          color: AppColors.primary,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) =>
                                FlDotCirclePainter(
                                  radius: 3,
                                  color: AppColors.primary,
                                  strokeColor: AppColors.bgElevated,
                                  strokeWidth: 2,
                                ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.primary.withValues(alpha: 0.2),
                                AppColors.primary.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  本周热图
  // ════════════════════════════════════════════
  Widget _weekHeatSection(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final weekActivity = state.weekActivityForCurrentWeek(now: now);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本周训练', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          HeatStrip(weekActivity: weekActivity, todayIndex: now.weekday - 1),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  最近训练
  // ════════════════════════════════════════════
  Widget _recentWorkouts(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final recent = state.completedSessions.take(5).toList();

    if (recent.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近训练', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        ...recent.map((s) {
          final totalVolume = s.exerciseRecords.fold<double>(
            0,
            (sum, r) => sum + r.totalVolume,
          );
          final exerciseNames = s.exerciseRecords
              .take(3)
              .map((r) => r.exerciseName)
              .join('、');
          final extra = s.exerciseRecords.length > 3
              ? ' 等${s.exerciseRecords.length}个动作'
              : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.dayType.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Text(
                        '${s.date.month}/${s.date.day}',
                        style: theme.textTheme.labelSmall!.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$exerciseNames$extra',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Text(
                        '${s.durationMinutes} 分钟',
                        style: theme.textTheme.labelSmall!.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        '${totalVolume.toStringAsFixed(0)} kg',
                        style: theme.textTheme.labelSmall!.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  成就精选（横向 carousel）
  // ════════════════════════════════════════════
  Widget _achievementHighlights(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final achievements = state.achievements;
    // 优先显示已解锁的，再显示进度最高的未解锁
    final sorted = [...achievements]
      ..sort((a, b) {
        if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
        return b.progressPercentage.compareTo(a.progressPercentage);
      });
    final highlights = sorted.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('成就', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AchievementsScreen(),
                ),
              ),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: highlights.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.cardGap),
            itemBuilder: (context, index) {
              final a = highlights[index];
              return Container(
                width: 100,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: AppRadius.brLg,
                  border: Border.all(
                    color: a.isUnlocked
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: a.isUnlocked ? 1.5 : 0.5,
                  ),
                  boxShadow: a.isUnlocked
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(a.icon, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      a.title,
                      style: theme.textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (a.isUnlocked)
                      Text(
                        '已解锁',
                        style: theme.textTheme.labelSmall!.copyWith(
                          color: AppColors.accent,
                          fontSize: 10,
                        ),
                      )
                    else
                      SizedBox(
                        width: 50,
                        child: LinearProgressIndicator(
                          value: a.progressPercentage,
                          backgroundColor: AppColors.border,
                          color: AppColors.primary,
                          borderRadius: AppRadius.brFull,
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

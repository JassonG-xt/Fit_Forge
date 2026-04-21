import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/brand/hero_card.dart';
import '../../widgets/brand/stat_number.dart';
import '../../widgets/brand/progress_ring.dart';
import '../../widgets/brand/glow_button.dart';
import '../../widgets/brand/heat_strip.dart';
import '../../widgets/cards/section_card.dart';
import '../plan/plan_generator_screen.dart';
import '../workout/workout_session_screen.dart';
import '../settings/settings_screen.dart';
import '../library/exercise_library_screen.dart';
import '../nutrition/meal_plan_screen.dart';
import '../progress/body_metrics_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      return Scaffold(
        appBar: AppBar(
          title: Text('FitForge', style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          )),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.sm),

              // ─── 崩溃恢复提示 ───
              if (state.hasRecoverableSession)
                _recoveryBanner(context, state),

              // ─── Hero 区：问候 + 连续天数 + 周进度环 ───
              _heroSection(context, state),
              const SizedBox(height: AppSpacing.lg),

              // ─── 今日训练大卡片 ───
              _todayWorkoutCard(context, state),
              const SizedBox(height: AppSpacing.lg),

              // ─── 本周热图 ───
              _weekHeatSection(context, state),
              const SizedBox(height: AppSpacing.lg),

              // ─── 快速统计 ───
              _statsRow(context, state),
              const SizedBox(height: AppSpacing.lg),

              // ─── 快捷入口 ───
              Text('快捷入口', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _quickAccessGrid(context),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      );
    });
  }

  // ════════════════════════════════════════════
  //  崩溃恢复提示
  // ════════════════════════════════════════════
  Widget _recoveryBanner(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SectionCard(
        borderColor: AppColors.warning.withValues(alpha: 0.5),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.restore, color: AppColors.warning, size: 28),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('有未完成的训练', style: theme.textTheme.titleSmall),
                  Text('上次训练未正常结束，是否恢复？',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(
              onPressed: () => state.dismissRecoverableSession(),
              child: const Text('放弃'),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: () {
                // Navigate to workout with the saved day type
                final data = state.recoverableSessionData;
                if (data == null) return;
                final dayTypeName = data['dayType'] as String?;
                if (dayTypeName == null) return;

                final dayType = WorkoutDayType.values
                    .where((d) => d.name == dayTypeName)
                    .firstOrNull;
                if (dayType == null) return;

                // Create a minimal WorkoutDay for recovery
                final workoutDay = WorkoutDay(
                  dayOfWeek: DateTime.now().weekday,
                  dayType: dayType,
                  exercises: state.activePlan?.days
                      .where((d) => d.dayType == dayType)
                      .firstOrNull
                      ?.exercises ?? [],
                );

                Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => WorkoutSessionScreen(workoutDay: workoutDay)));
              },
              child: const Text('恢复'),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Hero 区
  // ════════════════════════════════════════════
  Widget _heroSection(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final weekProgress = state.activePlan != null
        ? state.totalWorkoutsThisWeek / (state.profile?.weeklyFrequency ?? 4)
        : 0.0;

    return HeroCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          // 左侧：问候 + 目标
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: theme.textTheme.headlineMedium!.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                if (state.profile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '目标: ${state.profile!.goal.displayName}',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                // Streak 大数字
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${state.streakDays}',
                      style: theme.textTheme.displayLarge!.copyWith(
                        color: Colors.white,
                        fontSize: 48,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '天连续训练',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 右侧：周进度环
          ProgressRing(
            progress: weekProgress.clamp(0.0, 1.0),
            size: 80,
            strokeWidth: 6,
            gradientColors: const [Colors.white, Color(0xFFFFD12B)],
            trackColor: Colors.white.withValues(alpha: 0.2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${state.totalWorkoutsThisWeek}/${state.profile?.weeklyFrequency ?? '-'}',
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '本周',
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  今日训练卡片
  // ════════════════════════════════════════════
  Widget _todayWorkoutCard(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final today = state.todayWorkout;

    if (today != null) {
      final exerciseCount = today.exercises.length;
      final estMinutes = exerciseCount * 6; // 粗估每动作 6 分钟

      return SectionCard(
        borderColor: AppColors.primary.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: InkWell(
          borderRadius: AppRadius.brLg,
          onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => WorkoutSessionScreen(workoutDay: today))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      gradient: AppColors.heatGradient,
                      borderRadius: AppRadius.brSm,
                    ),
                    child: const Icon(Icons.local_fire_department, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('今日训练', style: theme.textTheme.titleSmall),
                        Text(
                          today.dayType.displayName,
                          style: theme.textTheme.bodySmall!.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  // 动作数 + 预估时长
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$exerciseCount 个动作', style: theme.textTheme.labelSmall),
                      Text('~$estMinutes min', style: theme.textTheme.labelSmall!
                          .copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),

              // 动作列表预览
              ...today.exercises.take(4).map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(e.exerciseName, style: theme.textTheme.bodyMedium),
                        ),
                        Text(
                          '${e.targetSets}×${e.targetReps}',
                          style: theme.textTheme.labelSmall!
                              .copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  )),
              if (today.exercises.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '还有 ${today.exercises.length - 4} 个动作...',
                    style: theme.textTheme.bodySmall!.copyWith(color: AppColors.textTertiary),
                  ),
                ),

              const SizedBox(height: AppSpacing.md),

              // CTA
              GlowButton(
                label: '开始训练',
                icon: Icons.play_arrow_rounded,
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => WorkoutSessionScreen(workoutDay: today))),
              ),
            ],
          ),
        ),
      );
    }

    // 有计划但今天是休息日：显示 rest day 卡片（不要误导成"没有计划"）
    if (state.activePlan != null) {
      return _restDayCard(context, state);
    }

    // 没有计划
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
      child: InkWell(
        borderRadius: AppRadius.brLg,
        onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const PlanGeneratorScreen())),
        child: Column(
          children: [
            Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(
                gradient: AppColors.heatGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('还没有训练计划', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '点击生成个性化训练计划',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  本周热图
  // ════════════════════════════════════════════
  Widget _weekHeatSection(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    // 构造 7 天活动数据
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final weekActivity = List.generate(7, (i) {
      final day = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + i);
      final hasWorkout = state.completedSessions.any((s) =>
          s.date.year == day.year &&
          s.date.month == day.month &&
          s.date.day == day.day);
      return hasWorkout ? 1.0 : 0.0;
    });
    final todayIndex = now.weekday - 1; // 0=周一

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本周训练', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          HeatStrip(
            weekActivity: weekActivity,
            todayIndex: todayIndex,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  快速统计
  // ════════════════════════════════════════════
  Widget _statsRow(BuildContext context, AppState state) {
    return Row(
      children: [
        Expanded(
          child: SectionCard(
            child: StatNumber(
              value: '${state.totalWorkoutsThisWeek}',
              label: '本周训练',
              fontSize: 24,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.cardGap),
        Expanded(
          child: SectionCard(
            child: StatNumber(
              value: state.profile != null ? '${state.profile!.weightKg}' : '--',
              label: '当前体重(kg)',
              fontSize: 24,
              valueColor: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.cardGap),
        Expanded(
          child: SectionCard(
            child: StatNumber(
              value: '${state.completedSessions.length}',
              label: '累计训练',
              fontSize: 24,
              valueColor: AppColors.warning,
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  快捷入口
  // ════════════════════════════════════════════
  Widget _quickAccessGrid(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      ('动作库', Icons.menu_book_outlined, AppColors.back, const ExerciseLibraryScreen()),
      ('饮食计划', Icons.restaurant_outlined, AppColors.accent, const MealPlanScreen()),
      ('训练计划', Icons.auto_awesome_outlined, AppColors.shoulders, const PlanGeneratorScreen()),
      ('数据追踪', Icons.show_chart_outlined, AppColors.arms, const BodyMetricsScreen()),
    ];

    return Row(
      children: items.map((item) {
        final (title, icon, color, screen) = item;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: item != items.last ? AppSpacing.sm : 0),
            child: InkWell(
              borderRadius: AppRadius.brMd,
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen)),
              child: SectionCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
                child: Column(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      title,
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ════════════════════════════════════════════
  //  休息日卡片
  // ════════════════════════════════════════════
  Widget _restDayCard(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final plan = state.activePlan!;
    final nextDay = _findNextTrainingDay(plan);

    return SectionCard(
      borderColor: AppColors.textTertiary.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.18),
                  borderRadius: AppRadius.brSm,
                ),
                child: const Icon(Icons.bedtime_outlined,
                    color: AppColors.textSecondary, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今日休息', style: theme.textTheme.titleSmall),
                    Text(
                      '恢复是进步的一部分',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nextDay != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '下一个训练日',
              style: theme.textTheme.labelSmall!
                  .copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  _weekdayLabel(nextDay.dayOfWeek),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '· ${nextDay.dayType.displayName}',
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: AppColors.primary),
                ),
                const Spacer(),
                Text(
                  '${nextDay.exercises.length} 个动作',
                  style: theme.textTheme.labelSmall!
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  WorkoutDay? _findNextTrainingDay(WorkoutPlan plan) {
    final today = DateTime.now().weekday; // 1..7 (Mon..Sun)
    for (var offset = 1; offset <= 7; offset++) {
      final target = ((today - 1 + offset) % 7) + 1;
      for (final d in plan.days) {
        if (d.dayOfWeek == target && d.dayType != WorkoutDayType.rest) {
          return d;
        }
      }
    }
    return null;
  }

  String _weekdayLabel(int dayOfWeek) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[(dayOfWeek - 1).clamp(0, 6).toInt()];
  }
}

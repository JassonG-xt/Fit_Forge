import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/coach_prompt_card.dart';
import '../../widgets/brand/glow_button.dart';
import '../../widgets/brand/heat_strip.dart';
import '../../widgets/brand/hero_card.dart';
import '../../widgets/brand/metric_tile.dart';
import '../../widgets/brand/progress_ring.dart';
import '../../widgets/brand/shortcut_tile.dart';
import '../../widgets/cards/section_card.dart';
import '../agent/agent_chat_screen.dart';
import '../library/exercise_library_screen.dart';
import '../nutrition/meal_plan_screen.dart';
import '../plan/plan_generator_screen.dart';
import '../progress/body_metrics_screen.dart';
import '../settings/settings_screen.dart';
import '../workout/workout_session_screen.dart';

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
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: AppSpacing.screenH,
            title: _BrandTitle(),
            actions: [
              IconButton(
                tooltip: '和 Coach 对话',
                icon: const Icon(Icons.auto_awesome_outlined),
                onPressed: () => _pushCoach(context),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.sm),

                    // 崩溃恢复提示（条件渲染）
                    if (state.hasRecoverableSession)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _RecoveryBanner(state: state),
                      ),

                    // ── Hero 区：问候 + streak + 周环 ──
                    _HeroSection(state: state, greeting: _greeting),
                    const SizedBox(height: AppSpacing.md),

                    // ── Coach 入口（醒目）──
                    CoachPromptCard(onTap: () => _pushCoach(context)),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 今日训练 ──
                    const _SectionLabel(text: '今日训练'),
                    const SizedBox(height: AppSpacing.sm),
                    _TodayWorkoutCard(state: state),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 本周节律 ──
                    const _SectionLabel(text: '本周节律'),
                    const SizedBox(height: AppSpacing.sm),
                    _WeekRhythmCard(state: state),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 仪表盘 ──
                    const _SectionLabel(text: '仪表盘'),
                    const SizedBox(height: AppSpacing.sm),
                    _StatsRow(state: state),
                    const SizedBox(height: AppSpacing.lg),

                    // ── 快捷入口 ──
                    const _SectionLabel(text: '快捷入口'),
                    const SizedBox(height: AppSpacing.sm),
                    const _QuickAccessGrid(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static void _pushCoach(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AgentChatScreen()),
    );
  }
}

// ════════════════════════════════════════════
//  Brand title — 把 "FitForge" 用 Manrope 渲染，作为整个 app 的字标。
//  保持纯 Text（而非 Text.rich 拆色）以便 `find.text('FitForge')` 命中测试。
// ════════════════════════════════════════════
class _BrandTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      'FitForge',
      style: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        letterSpacing: -0.3,
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Section label — 统一的小节标题（all-caps Manrope letter-spaced）。
//  这个排印手法是替代每节用 titleSmall 的视觉单调；
//  让"今日训练"/"本周节律" 看起来像章节标签而非段落标题。
// ════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            text,
            style: GoogleFonts.notoSansSc(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryLight,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Hero
// ════════════════════════════════════════════
class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.state, required this.greeting});

  final AppState state;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final weeklyTarget = state.profile?.weeklyFrequency ?? 4;
    final weekDone = state.totalWorkoutsThisWeek;
    final weekProgress = state.activePlan != null && weeklyTarget > 0
        ? weekDone / weeklyTarget
        : 0.0;

    final baseColor = isDark
        ? AppColors.textPrimary
        : AppColors.textPrimaryLight;
    final mutedColor = isDark
        ? AppColors.textSecondary
        : AppColors.textSecondaryLight;

    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // greeting + 目标
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: AppRadius.brFull,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  state.profile == null
                      ? '欢迎'
                      : '目标 · ${state.profile!.goal.displayName}',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            greeting,
            style: GoogleFonts.notoSansSc(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: baseColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 主数据行：左 streak（大），右 周完成度环
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 大数字 streak
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${state.streakDays}',
                          style: GoogleFonts.manrope(
                            fontSize: 64,
                            fontWeight: FontWeight.w800,
                            color: baseColor,
                            height: 0.95,
                            letterSpacing: -2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'DAY',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              letterSpacing: 2.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '连续训练',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              // 周完成环
              ProgressRing(
                progress: weekProgress.clamp(0.0, 1.0),
                size: 96,
                strokeWidth: 8,
                trackColor: isDark
                    ? AppColors.bgSurface
                    : Colors.white.withValues(alpha: 0.65),
                gradientColors: const [
                  AppColors.primary,
                  AppColors.primaryGlow,
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$weekDone/$weeklyTarget',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: baseColor,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '本周',
                      style: GoogleFonts.notoSansSc(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Today workout card —— missionGradient header + content body
// ════════════════════════════════════════════
class _TodayWorkoutCard extends StatelessWidget {
  const _TodayWorkoutCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final today = state.todayWorkout;
    if (today != null) {
      return _TodayActiveCard(today: today);
    }
    if (state.activePlan != null) {
      return _RestDayCard(state: state);
    }
    return const _NoPlanCard();
  }
}

class _TodayActiveCard extends StatelessWidget {
  const _TodayActiveCard({required this.today});
  final WorkoutDay today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final exerciseCount = today.exercises.length;
    final estMinutes = exerciseCount * 6;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.brXl,
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.borderLight,
          width: 0.5,
        ),
        color: isDark ? AppColors.bgElevated : AppColors.bgElevatedLight,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.brXl,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => WorkoutSessionScreen(workoutDay: today),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── gradient header strip ──
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  decoration: const BoxDecoration(
                    gradient: AppColors.missionGradient,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: AppRadius.brSm,
                        ),
                        child: Text(
                          'TODAY',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          today.dayType.displayName,
                          style: GoogleFonts.notoSansSc(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$exerciseCount 动作 · ~$estMinutes 分钟',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── body ──
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...today.exercises.take(4).map((e) => _ExerciseRow(e: e)),
                      if (today.exercises.length > 4)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            '还有 ${today.exercises.length - 4} 个动作…',
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      GlowButton(
                        label: '开始训练',
                        icon: Icons.play_arrow_rounded,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                WorkoutSessionScreen(workoutDay: today),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.e});
  final PlannedExercise e;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              e.exerciseName,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${e.targetSets} × ${e.targetReps}',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.brightness == Brightness.dark
                  ? AppColors.textSecondary
                  : AppColors.textSecondaryLight,
              letterSpacing: 0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestDayCard extends StatelessWidget {
  const _RestDayCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.18),
                  borderRadius: AppRadius.brSm,
                ),
                child: const Icon(
                  Icons.bedtime_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今日休息', style: theme.textTheme.titleSmall),
                    Text(
                      '恢复是进步的一部分',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: AppColors.textTertiary,
                      ),
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
              style: theme.textTheme.labelSmall!.copyWith(
                color: AppColors.textTertiary,
              ),
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
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${nextDay.exercises.length} 个动作',
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static WorkoutDay? _findNextTrainingDay(WorkoutPlan plan) {
    final today = DateTime.now().weekday;
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

  static String _weekdayLabel(int dayOfWeek) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[(dayOfWeek - 1).clamp(0, 6).toInt()];
  }
}

class _NoPlanCard extends StatelessWidget {
  const _NoPlanCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.lg,
      ),
      child: InkWell(
        borderRadius: AppRadius.brLg,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PlanGeneratorScreen()),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('还没有训练计划', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text('点击生成个性化训练计划', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  本周节律 card
// ════════════════════════════════════════════
class _WeekRhythmCard extends StatelessWidget {
  const _WeekRhythmCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final weekActivity = state.weekActivityForCurrentWeek(now: now);
    final todayIndex = now.weekday - 1;
    final done = state.totalWorkoutsThisWeek;
    final target = state.profile?.weeklyFrequency ?? 4;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$done',
                style: GoogleFonts.manrope(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ $target',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textTertiaryLight,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('次 · 目标', style: theme.textTheme.bodySmall),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brFull,
                ),
                child: Text(
                  _weekHint(done, target),
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          HeatStrip(weekActivity: weekActivity, todayIndex: todayIndex),
        ],
      ),
    );
  }

  static String _weekHint(int done, int target) {
    if (target <= 0) return 'KEEP GOING';
    if (done >= target) return 'GOAL HIT';
    final remain = target - done;
    return '还差 $remain 次';
  }
}

// ════════════════════════════════════════════
//  Stats row —— 三张 MetricTile
// ════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final tiles = <Widget>[
      MetricTile(
        icon: Icons.fitness_center_rounded,
        value: '${state.totalWorkoutsThisWeek}',
        label: '本周训练',
        unit: '次',
        accentColor: AppColors.primary,
      ),
      MetricTile(
        icon: Icons.monitor_weight_outlined,
        value: profile != null ? '${profile.weightKg}' : '--',
        label: '当前体重',
        unit: 'kg',
        accentColor: AppColors.accent,
      ),
      MetricTile(
        icon: Icons.local_fire_department_outlined,
        value: '${state.completedSessions.length}',
        label: '累计训练',
        unit: '次',
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
}

// ════════════════════════════════════════════
//  Quick access grid —— ShortcutTile
// ════════════════════════════════════════════
class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid();

  @override
  Widget build(BuildContext context) {
    final items = <_ShortcutItem>[
      _ShortcutItem(
        title: '动作库',
        icon: Icons.menu_book_rounded,
        color: AppColors.back,
        builder: (_) => const ExerciseLibraryScreen(),
      ),
      _ShortcutItem(
        title: '饮食计划',
        icon: Icons.restaurant_rounded,
        color: AppColors.accent,
        builder: (_) => const MealPlanScreen(),
      ),
      _ShortcutItem(
        title: '训练计划',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.shoulders,
        builder: (_) => const PlanGeneratorScreen(),
      ),
      _ShortcutItem(
        title: '数据追踪',
        icon: Icons.show_chart_rounded,
        color: AppColors.arms,
        builder: (_) => const BodyMetricsScreen(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        const gap = AppSpacing.cardGap;
        final cols = isNarrow ? 2 : 4;
        final itemWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: ShortcutTile(
                    icon: item.icon,
                    label: item.title,
                    accentColor: item.color,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: item.builder),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ShortcutItem {
  const _ShortcutItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}

// ════════════════════════════════════════════
//  Recovery banner
// ════════════════════════════════════════════
class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
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
                Text('上次训练未正常结束，是否恢复？', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () => state.dismissRecoverableSession(),
            child: const Text('放弃'),
          ),
          const SizedBox(width: AppSpacing.xs),
          FilledButton(
            onPressed: () => _resumeRecoverable(context),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }

  void _resumeRecoverable(BuildContext context) {
    final data = state.recoverableSessionData;
    if (data == null) return;
    final dayTypeName = data['dayType'] as String?;
    if (dayTypeName == null) return;

    final dayType = WorkoutDayType.values
        .where((d) => d.name == dayTypeName)
        .firstOrNull;
    if (dayType == null) return;

    final workoutDay = WorkoutDay(
      dayOfWeek: DateTime.now().weekday,
      dayType: dayType,
      exercises:
          state.activePlan?.days
              .where((d) => d.dayType == dayType)
              .firstOrNull
              ?.exercises ??
          [],
    );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSessionScreen(workoutDay: workoutDay),
      ),
    );
  }
}

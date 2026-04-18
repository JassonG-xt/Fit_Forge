import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../engines/plan_engine.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/brand/glow_button.dart';
import '../../widgets/brand/progress_ring.dart';
import '../../widgets/brand/stat_number.dart';
import '../../widgets/cards/section_card.dart';
import '../../widgets/cards/chip_tag.dart';
import 'exercise_detail_screen.dart';
import 'rest_timer_screen.dart';

class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key, required this.workoutDay});
  final WorkoutDay workoutDay;

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  static const _uuid = Uuid();
  int _currentIndex = 0;
  bool _showWarmup = true;
  bool _isCompleted = false;
  late DateTime _startTime;
  final Map<String, ExerciseRecord> _records = {};

  List<PlannedExercise> get _exercises => widget.workoutDay.exercises;
  PlannedExercise? get _current => _currentIndex < _exercises.length ? _exercises[_currentIndex] : null;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    // If recovering, restore records from saved data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryRestoreFromRecovery();
    });
  }

  void _tryRestoreFromRecovery() {
    final state = context.read<AppState>();
    final data = state.recoverableSessionData;
    if (data == null) return;

    // Only restore if it matches this workout day type
    final savedDayType = data['dayType'] as String?;
    if (savedDayType != widget.workoutDay.dayType.name) return;

    final savedRecords = data['records'] as Map<String, dynamic>?;
    if (savedRecords == null) return;

    setState(() {
      _currentIndex = (data['currentIndex'] as int?) ?? 0;
      _showWarmup = false;
      final savedStart = data['startTime'] as String?;
      if (savedStart != null) _startTime = DateTime.parse(savedStart);

      for (final entry in savedRecords.entries) {
        final record = ExerciseRecord.fromJson(entry.value as Map<String, dynamic>);
        _records[entry.key] = record;
      }
    });

    state.dismissRecoverableSession();
  }

  ExerciseRecord _getRecord(PlannedExercise planned) {
    return _records.putIfAbsent(planned.exerciseId, () {
      final state = context.read<AppState>();
      final lastWeight = state.lastWeightForExercise(planned.exerciseId);
      final lastReps = state.lastRepsForExercise(planned.exerciseId);
      final record = ExerciseRecord(exerciseId: planned.exerciseId, exerciseName: planned.exerciseName);
      for (var i = 1; i <= planned.targetSets; i++) {
        record.sets.add(SetRecord(
          setNumber: i,
          weightKg: lastWeight,
          reps: lastReps > 0 ? lastReps : planned.targetReps,
        ));
      }
      return record;
    });
  }

  void _nextExercise() {
    if (_currentIndex < _exercises.length - 1) {
      setState(() => _currentIndex++);
    } else {
      setState(() => _isCompleted = true);
    }
  }

  int get _completedSetsCount =>
      _records.values.expand((r) => r.sets).where((s) => s.isCompleted).length;

  void _autoSave() {
    final data = {
      'dayType': widget.workoutDay.dayType.name,
      'currentIndex': _currentIndex,
      'startTime': _startTime.toIso8601String(),
      'records': _records.map((k, v) => MapEntry(k, v.toJson())),
    };
    context.read<AppState>().saveInProgressSession(data);
  }

  Future<void> _saveAndExit() async {
    final hasCompletedSets = _completedSetsCount > 0;

    if (!hasCompletedSets) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未完成训练'),
          content: const Text('你还没有完成任何一组，确定要结束吗？\n本次训练将记录为未完成。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续训练')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('结束')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    final duration = DateTime.now().difference(_startTime).inMinutes;
    final session = WorkoutSession(
      id: _uuid.v4(),
      dayType: widget.workoutDay.dayType,
      durationMinutes: duration,
      isCompleted: hasCompletedSets,
      exerciseRecords: _records.values.toList(),
    );
    context.read<AppState>().saveSession(session);
    await context.read<AppState>().clearInProgressSession();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workoutDay.dayType.displayName),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saveAndExit,
        ),
      ),
      body: _showWarmup ? _warmupView() : (_isCompleted ? _completedView() : _exerciseView()),
    );
  }

  // ════════════════════════════════════════════
  //  热身
  // ════════════════════════════════════════════
  Widget _warmupView() {
    final theme = Theme.of(context);
    final warmups = PlanEngine.warmupRecommendation(widget.workoutDay.dayType);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(
              gradient: AppColors.coolGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.self_improvement, color: Colors.white, size: 36),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('热身建议', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),

          SectionCard(
            child: Column(
              children: warmups.map((w) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.accent, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(w, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )).toList(),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          GlowButton(
            label: '热身完成，开始训练',
            icon: Icons.play_arrow_rounded,
            onPressed: () => setState(() => _showWarmup = false),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => setState(() => _showWarmup = false),
            child: Text('跳过热身', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  训练中 — 沉浸式界面
  // ════════════════════════════════════════════
  Widget _exerciseView() {
    final theme = Theme.of(context);
    final planned = _current;
    if (planned == null) return const SizedBox();
    final record = _getRecord(planned);
    final progress = (_currentIndex + 1) / _exercises.length;

    return Column(
      children: [
        // 细进度条
        LinearProgressIndicator(
          value: progress,
          minHeight: 3,
          backgroundColor: AppColors.border,
          color: AppColors.primary,
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 当前动作 Hero ───
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '动作 ${_currentIndex + 1}/${_exercises.length}',
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            planned.exerciseName,
                            style: theme.textTheme.headlineMedium!.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                          builder: (_) => ExerciseDetailScreen(exerciseId: planned.exerciseId))),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.sm),

                // 目标 chips
                Row(
                  children: [
                    ChipTag(label: '${planned.targetSets} 组'),
                    const SizedBox(width: AppSpacing.sm),
                    ChipTag(label: '${planned.targetReps} 次'),
                    const SizedBox(width: AppSpacing.sm),
                    ChipTag(label: '${planned.restSeconds}s 休息'),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // ─── 组记录卡片 ───
                ...record.sets.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                    child: _setRecordCard(s, idx, record),
                  );
                }),
              ],
            ),
          ),
        ),

        // ─── 底部 Sticky Bar ───
        Container(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            MediaQuery.of(context).padding.bottom + AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: AppColors.bgSurface,
            border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('休息计时'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                      builder: (_) => RestTimerScreen(seconds: planned.restSeconds))),
                ),
              ),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(
                child: GlowButton(
                  label: _currentIndex < _exercises.length - 1 ? '下一动作' : '完成训练',
                  icon: _currentIndex < _exercises.length - 1 ? Icons.skip_next : Icons.check,
                  onPressed: _nextExercise,
                  fullWidth: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  组记录卡片 — 三态：完成 / 当前 / 等待
  // ════════════════════════════════════════════
  Widget _setRecordCard(SetRecord s, int index, ExerciseRecord record) {
    final theme = Theme.of(context);
    // 当前组 = 第一个未完成的组
    final currentSetIndex = record.sets.indexWhere((ss) => !ss.isCompleted);
    final isCurrent = index == currentSetIndex;
    final isCompleted = s.isCompleted;

    Color bg;
    Color borderColor;
    if (isCompleted) {
      bg = AppColors.accent.withValues(alpha: 0.08);
      borderColor = AppColors.accent.withValues(alpha: 0.3);
    } else if (isCurrent) {
      bg = AppColors.primary.withValues(alpha: 0.06);
      borderColor = AppColors.primary.withValues(alpha: 0.5);
    } else {
      bg = AppColors.bgElevated;
      borderColor = AppColors.border;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: borderColor, width: isCurrent ? 1.5 : 0.5),
        boxShadow: isCurrent
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 12)]
            : null,
      ),
      child: Column(
        children: [
          // 标题行
          Row(
            children: [
              Text(
                '第 ${s.setNumber} 组',
                style: theme.textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isCompleted) ...[
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.check_circle, color: AppColors.accent, size: 18),
              ],
              const Spacer(),
              if (isCompleted)
                Text(
                  '${s.weightKg}kg × ${s.reps}',
                  style: theme.textTheme.labelLarge!.copyWith(color: AppColors.accent),
                ),
            ],
          ),

          // 输入区（仅当前组 + 未完成组展开）
          if (!isCompleted) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                // 重量步进器
                Expanded(
                  child: _numberStepper(
                    label: '重量 (kg)',
                    value: s.weightKg,
                    step: 2.5,
                    onChanged: (v) => setState(() => s.weightKg = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 次数步进器
                Expanded(
                  child: _numberStepper(
                    label: '次数',
                    value: s.reps.toDouble(),
                    step: 1,
                    onChanged: (v) => setState(() => s.reps = v.round()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // 完成这组按钮
            if (isCurrent)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('完成这组'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => setState(() {
                    s.isCompleted = true;
                    _autoSave();
                  }),
                ),
              )
            else
              // 非当前组 toggle
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.circle_outlined, size: 24),
                  color: AppColors.textTertiary,
                  onPressed: () => setState(() {
                    s.isCompleted = !s.isCompleted;
                    _autoSave();
                  }),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  数字步进器（替代 TextField）
  // ════════════════════════════════════════════
  Widget _numberStepper({
    required String label,
    required double value,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final displayValue = step >= 1
        ? value.round().toString()
        : value.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.brMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // 减
              InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                onTap: () {
                  final newVal = value - step;
                  if (newVal >= 0) onChanged(newVal);
                },
                child: Container(
                  width: 40, height: 44,
                  alignment: Alignment.center,
                  child: const Icon(Icons.remove, size: 18, color: AppColors.textSecondary),
                ),
              ),
              // 值
              Expanded(
                child: Text(
                  displayValue,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // 加
              InkWell(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                onTap: () => onChanged(value + step),
                child: Container(
                  width: 40, height: 44,
                  alignment: Alignment.center,
                  child: const Icon(Icons.add, size: 18, color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  完成页
  // ════════════════════════════════════════════
  Widget _completedView() {
    final theme = Theme.of(context);
    final duration = DateTime.now().difference(_startTime).inMinutes;
    final totalSets = _completedSetsCount;
    final totalVolume = _records.values.fold<double>(0, (sum, r) => sum + r.totalVolume);
    final cooldowns = PlanEngine.cooldownRecommendation(widget.workoutDay.dayType);
    final hasWork = totalSets > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),

          // 完成图标
          ProgressRing(
            progress: hasWork ? 1.0 : 0.0,
            size: 90,
            strokeWidth: 6,
            gradientColors: hasWork
                ? const [AppColors.accent, AppColors.primary]
                : [AppColors.border, AppColors.border],
            child: Icon(
              hasWork ? Icons.emoji_events : Icons.info_outline,
              size: 36,
              color: hasWork ? AppColors.accent : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hasWork ? '训练完成!' : '训练未完成',
            style: theme.textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!hasWork)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('你还没有完成任何一组', style: theme.textTheme.bodySmall),
            ),

          const SizedBox(height: AppSpacing.lg),

          // 数据汇总
          Row(
            children: [
              Expanded(child: SectionCard(
                child: StatNumber(value: '$duration', label: '分钟', fontSize: 24),
              )),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: SectionCard(
                child: StatNumber(
                  value: '$totalSets', label: '组', fontSize: 24,
                  valueColor: AppColors.accent,
                ),
              )),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: SectionCard(
                child: StatNumber(
                  value: totalVolume >= 1000
                      ? '${(totalVolume / 1000).toStringAsFixed(1)}t'
                      : '${totalVolume.toStringAsFixed(0)}kg',
                  label: '总容量', fontSize: 24,
                  valueColor: AppColors.warning,
                ),
              )),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // 拉伸建议
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('拉伸建议', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                ...cooldowns.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.spa_outlined, color: AppColors.accent, size: 16),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(c, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          GlowButton(
            label: hasWork ? '保存并返回' : '结束训练',
            icon: Icons.check_rounded,
            onPressed: _saveAndExit,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

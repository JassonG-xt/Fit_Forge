import 'package:flutter/material.dart';

import '../../agent/action_preview.dart';
import '../../agent/models/agent_action.dart';
import '../../models/enums.dart';
import '../../models/workout_plan.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Before/after preview that turns an [AgentAction] payload into a concrete
/// view of "what your plan looks like now" vs. "what it'll look like after".
///
/// Read-only action types (answerOnly, nutritionAdvice, weeklyReview,
/// safetyResponse) render nothing — they don't mutate the plan.
///
/// All computation is delegated to [AgentActionPreviewer]; this widget
/// only handles rendering.
class AgentDiffView extends StatelessWidget {
  const AgentDiffView({
    super.key,
    required this.action,
    required this.appState,
  });

  final AgentAction action;
  final AppState appState;

  static const _previewer = AgentActionPreviewer();

  @override
  Widget build(BuildContext context) {
    final preview = _previewer.preview(action: action, appState: appState);
    final inner = _buildFromPreview(preview);
    if (inner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: inner,
    );
  }

  Widget? _buildFromPreview(ActionPreview preview) {
    if (preview is PreviewFailure) {
      // 此类型不需要预览 → 静默不渲染
      if (preview.message == '此类型不需要预览。') return null;
      return _Hint(preview.message);
    }
    if (preview is CompressPreview) {
      return _CompressDiff(preview: preview);
    }
    if (preview is ReplacePreview) {
      return _ReplaceDiff(preview: preview);
    }
    if (preview is ReschedulePreview) {
      return _RescheduleDiff(preview: preview);
    }
    if (preview is GeneratePlanPreview) {
      return _GeneratePlanDiff(preview: preview);
    }
    return null;
  }
}

// ─── shared layout primitives ─────────────────────────────────────────

class _BeforeAfterRow extends StatelessWidget {
  const _BeforeAfterRow({required this.before, required this.after});

  final Widget before;
  final Widget after;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _DiffSide(
              label: '修改前',
              tint: AppColors.danger,
              child: before,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _DiffSide(
              label: '修改后',
              tint: AppColors.primary,
              child: after,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffSide extends StatelessWidget {
  const _DiffSide({
    required this.label,
    required this.tint,
    required this.child,
  });

  final String label;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: AppRadius.brSm,
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodySmall ?? const TextStyle(),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: AppRadius.brSm,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

// ─── compressWorkout ─────────────────────────────────────────────────

class _CompressDiff extends StatelessWidget {
  const _CompressDiff({required this.preview});

  final CompressPreview preview;

  @override
  Widget build(BuildContext context) {
    final beforeSets = preview.original.exercises.fold<int>(
      0,
      (s, e) => s + e.targetSets,
    );
    final afterSets = preview.compressed.exercises.fold<int>(
      0,
      (s, e) => s + e.targetSets,
    );
    final keptIds = preview.compressed.exercises
        .map((e) => e.exerciseId)
        .toSet();
    final removedNames = preview.original.exercises
        .where((e) => !keptIds.contains(e.exerciseId))
        .map((e) => e.exerciseName)
        .toList();

    return _BeforeAfterRow(
      before: _CompressSummary(
        exerciseCount: preview.original.exercises.length,
        totalSets: beforeSets,
      ),
      after: _CompressSummary(
        exerciseCount: preview.compressed.exercises.length,
        totalSets: afterSets,
        targetMinutes: preview.targetMinutes,
        keptNames: preview.compressed.exercises
            .map((e) => e.exerciseName)
            .toList(),
        removedNames: removedNames,
      ),
    );
  }
}

class _CompressSummary extends StatelessWidget {
  const _CompressSummary({
    required this.exerciseCount,
    required this.totalSets,
    this.targetMinutes,
    this.keptNames = const [],
    this.removedNames = const [],
  });

  final int exerciseCount;
  final int totalSets;
  final int? targetMinutes;
  final List<String> keptNames;
  final List<String> removedNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$exerciseCount 个动作 · $totalSets 组'),
        if (targetMinutes != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text('约 $targetMinutes 分钟'),
        ],
        if (keptNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('保留：${keptNames.join("、")}'),
        ],
        if (removedNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '减少：${removedNames.join("、")}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── replaceExercise ─────────────────────────────────────────────────

class _ReplaceDiff extends StatelessWidget {
  const _ReplaceDiff({required this.preview});

  final ReplacePreview preview;

  @override
  Widget build(BuildContext context) {
    return _BeforeAfterRow(
      before: _ExerciseSpec(
        name: preview.originalExercise.exerciseName,
        sets: preview.originalExercise.targetSets,
        reps: preview.originalExercise.targetReps,
        rest: preview.originalExercise.restSeconds,
      ),
      after: _ExerciseSpec(
        name: preview.toExerciseName,
        sets: preview.originalExercise.targetSets,
        reps: preview.originalExercise.targetReps,
        rest: preview.originalExercise.restSeconds,
      ),
    );
  }
}

class _ExerciseSpec extends StatelessWidget {
  const _ExerciseSpec({
    required this.name,
    required this.sets,
    required this.reps,
    required this.rest,
  });

  final String name;
  final int sets;
  final int reps;
  final int rest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text('$sets 组 × $reps 次'),
        Text('组间休息 ${rest}s'),
      ],
    );
  }
}

// ─── rescheduleWeek ──────────────────────────────────────────────────

class _RescheduleDiff extends StatelessWidget {
  const _RescheduleDiff({required this.preview});

  final ReschedulePreview preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var d = 1; d <= 7; d++)
          _RescheduleRow(
            dayOfWeek: d,
            before: _dayTypeOf(preview.originalPlan, d),
            after: _dayTypeOf(preview.newPlan, d),
          ),
      ],
    );
  }

  WorkoutDayType _dayTypeOf(WorkoutPlan p, int dayOfWeek) {
    return p.days
        .firstWhere(
          (d) => d.dayOfWeek == dayOfWeek,
          orElse: () =>
              WorkoutDay(dayOfWeek: dayOfWeek, dayType: WorkoutDayType.rest),
        )
        .dayType;
  }
}

class _RescheduleRow extends StatelessWidget {
  const _RescheduleRow({
    required this.dayOfWeek,
    required this.before,
    required this.after,
  });

  final int dayOfWeek;
  final WorkoutDayType before;
  final WorkoutDayType after;

  static const _names = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = before != after;
    final accent = changed
        ? AppColors.primary
        : theme.textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              _names[dayOfWeek],
              style: theme.textTheme.bodySmall?.copyWith(color: accent),
            ),
          ),
          Expanded(
            child: Text(before.displayName, style: theme.textTheme.bodySmall),
          ),
          Icon(Icons.arrow_forward, size: 14, color: accent),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              after.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: changed ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── generatePlan ────────────────────────────────────────────────────

class _GeneratePlanDiff extends StatelessWidget {
  const _GeneratePlanDiff({required this.preview});

  final GeneratePlanPreview preview;

  @override
  Widget build(BuildContext context) {
    return _BeforeAfterRow(
      before: _PlanSummary(plan: preview.originalPlan),
      after: _PlanSummary(plan: preview.previewPlan),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final WorkoutPlan? plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (plan == null) {
      return Text(
        '尚无计划',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final workoutDayCount = plan!.days
        .where((d) => d.dayType != WorkoutDayType.rest)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan!.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(plan!.split.displayName),
        Text('每周 $workoutDayCount 训练日'),
      ],
    );
  }
}

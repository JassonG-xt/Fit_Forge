import 'package:flutter/material.dart';

import '../../agent/action_preview.dart';
import '../../agent/models/agent_action.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Read-only insight panel for `weeklyReview` actions.
///
/// Renders structured fields (`completedSessions`, `focusAreas`, `observations`,
/// `nextWeekSuggestions`, `riskNotes`) as labelled sections. The action's
/// `summary` is intentionally NOT shown here — `AgentActionCard` already
/// renders it above the panel, and duplicating it adds visual noise.
///
/// This panel is strictly read-only: no apply / confirm / mutation behavior.
/// When the payload is missing or invalid the panel renders nothing, so the
/// card falls back to just `action.summary`.
class AgentWeeklyReviewPanel extends StatelessWidget {
  const AgentWeeklyReviewPanel({super.key, required this.action});

  final AgentAction action;

  static const _previewer = AgentActionPreviewer();

  @override
  Widget build(BuildContext context) {
    final preview = _previewer.previewWeeklyReview(action);
    if (preview is! WeeklyReviewPreview) return const SizedBox.shrink();
    if (!preview.hasContent) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final sections = <Widget>[];

    if (preview.completedSessions != null) {
      sections.add(
        _LabelledSection(
          label: '完成训练',
          child: Text(
            '${preview.completedSessions} 次',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    if (preview.focusAreas.isNotEmpty) {
      sections.add(
        _LabelledSection(
          label: '重点部位',
          child: Text(
            preview.focusAreas.join('、'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    if (preview.observations.isNotEmpty) {
      sections.add(
        _LabelledSection(
          label: '观察',
          child: _BulletList(items: preview.observations),
        ),
      );
    }

    if (preview.nextWeekSuggestions.isNotEmpty) {
      sections.add(
        _LabelledSection(
          label: '下周建议',
          child: _BulletList(items: preview.nextWeekSuggestions),
        ),
      );
    }

    if (preview.riskNotes.isNotEmpty) {
      sections.add(
        _LabelledSection(
          label: '风险提示',
          tint: AppColors.warning,
          child: _BulletList(items: preview.riskNotes, tint: AppColors.warning),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.brSm,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            sections[i],
          ],
        ],
      ),
    );
  }
}

class _LabelledSection extends StatelessWidget {
  const _LabelledSection({required this.label, required this.child, this.tint});

  final String label;
  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tint ?? AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall ?? const TextStyle(),
          child: child,
        ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, this.tint});

  final List<String> items;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bulletColor = tint ?? theme.textTheme.bodySmall?.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: AppSpacing.xs),
                  child: Text(
                    '•',
                    style: TextStyle(color: bulletColor, height: 1.2),
                  ),
                ),
                Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../agent/models/agent_action.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/glow_button.dart';
import '../../widgets/cards/section_card.dart';
import 'agent_diff_view.dart';
import 'agent_weekly_review_panel.dart';

/// Coach Agent 建议的结构化动作卡片。
///
/// 显示 title / summary / risk badge；
/// 若 `requiresConfirmation` 为 true 则提供"应用修改"和"取消"按钮，
/// 否则显示纯信息状态（已被自动处理）。
///
/// 已处理（确认或取消过）时整体置灰并禁用按钮。
class AgentActionCard extends StatelessWidget {
  const AgentActionCard({
    super.key,
    required this.action,
    required this.isResolved,
    this.onConfirm,
    this.onCancel,
  });

  final AgentAction action;
  final bool isResolved;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xs,
      ),
      child: Opacity(
        opacity: isResolved ? 0.55 : 1.0,
        child: SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      action.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  _RiskBadge(riskLevel: action.riskLevel),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(action.summary, style: theme.textTheme.bodyMedium),
              if (action.requiresConfirmation && !isResolved)
                AgentDiffView(
                  action: action,
                  appState: Provider.of<AppState>(context, listen: false),
                ),
              if (action.type == AgentActionType.weeklyReview)
                AgentWeeklyReviewPanel(action: action),
              if (action.requiresConfirmation) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: GlowButton(
                        label: isResolved ? '已处理' : '应用修改',
                        onPressed: isResolved ? null : onConfirm,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: isResolved ? null : onCancel,
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.riskLevel});

  final AgentActionRiskLevel riskLevel;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (riskLevel) {
      AgentActionRiskLevel.low => ('低风险', AppColors.primary),
      AgentActionRiskLevel.medium => ('中风险', AppColors.warning),
      AgentActionRiskLevel.high => ('高风险', AppColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.brSm,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

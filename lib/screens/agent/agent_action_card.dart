import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../agent/models/agent_action.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/glow_button.dart';
import 'agent_diff_view.dart';
import 'agent_weekly_review_panel.dart';

/// Coach Agent 建议的结构化动作卡片。
///
/// 视觉职责（颗粒度对齐 PRD）：
///   1. 顶部"action type 标识带"——type icon + 中文类型名 + 风险徽章 +
///      "需要你确认 / 无需确认" 状态徽章，一行说清"这是什么 action / 风险 / 流程位置"。
///   2. 标题 + summary 主体。
///   3. （仅 requiresConfirmation）before/after diff 区。
///   4. （仅 weeklyReview）insights panel。
///   5. 底部 CTA：主按钮 GlowButton "应用修改"（resolved 后变 "已处理"），
///      次按钮 TextButton "取消"，建立明确视觉层级。
///   6. resolved 状态：左侧加一条灰色状态带 + 顶部贴 "已处理" 角章，
///      整张卡 opacity 降到 0.55，按钮 disabled。
///
/// **不改任何执行逻辑**：`onConfirm`/`onCancel`/`requiresConfirmation` 行为完全保留。
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
    final isDark = theme.brightness == Brightness.dark;
    final visuals = _ActionVisuals.forType(action.type);
    final willMutate = action.requiresConfirmation;
    final accent = isResolved ? AppColors.textTertiary : visuals.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.sm,
      ),
      child: Opacity(
        opacity: isResolved ? 0.55 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgElevated : AppColors.bgElevatedLight,
            borderRadius: AppRadius.brLg,
            border: Border.all(
              color: isResolved
                  ? (isDark ? AppColors.border : AppColors.borderLight)
                  : accent.withValues(alpha: 0.30),
              width: 0.6,
            ),
            boxShadow: isResolved || isDark ? null : AppShadows.cardElevation,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.brLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActionHeader(
                  visuals: visuals,
                  accent: accent,
                  action: action,
                  isResolved: isResolved,
                  willMutate: willMutate,
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        action.summary,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          height: 1.5,
                        ),
                      ),
                      if (willMutate && !isResolved)
                        AgentDiffView(
                          action: action,
                          appState: Provider.of<AppState>(
                            context,
                            listen: false,
                          ),
                        ),
                      if (action.type == AgentActionType.weeklyReview)
                        AgentWeeklyReviewPanel(action: action),
                      if (willMutate) ...[
                        const SizedBox(height: AppSpacing.md),
                        _ConfirmationFooter(
                          isResolved: isResolved,
                          onConfirm: onConfirm,
                          onCancel: onCancel,
                        ),
                      ],
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

// ════════════════════════════════════════════
//  Header band —— type icon + 类型名 + 风险徽章 + 流程徽章
// ════════════════════════════════════════════
class _ActionHeader extends StatelessWidget {
  const _ActionHeader({
    required this.visuals,
    required this.accent,
    required this.action,
    required this.isResolved,
    required this.willMutate,
  });

  final _ActionVisuals visuals;
  final Color accent;
  final AgentAction action;
  final bool isResolved;
  final bool willMutate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = accent.withValues(alpha: isDark ? 0.12 : 0.08);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + 2,
        AppSpacing.md,
        AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.18), width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.20),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(visuals.icon, color: accent, size: 17),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              visuals.label,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (isResolved)
            _Badge(
              label: '已结束',
              fg: AppColors.textTertiary,
              bg: AppColors.textTertiary.withValues(alpha: 0.14),
              icon: Icons.check_rounded,
            )
          else ...[
            _ConfirmationBadge(willMutate: willMutate),
            const SizedBox(width: AppSpacing.xs),
            _RiskBadge(riskLevel: action.riskLevel),
          ],
        ],
      ),
    );
  }
}

class _ConfirmationBadge extends StatelessWidget {
  const _ConfirmationBadge({required this.willMutate});
  final bool willMutate;

  @override
  Widget build(BuildContext context) {
    if (willMutate) {
      return _Badge(
        label: '需要你确认',
        fg: AppColors.primary,
        bg: AppColors.primary.withValues(alpha: 0.14),
        icon: Icons.lock_outline_rounded,
      );
    }
    return _Badge(
      label: '无需确认',
      fg: AppColors.textTertiary,
      bg: AppColors.textTertiary.withValues(alpha: 0.12),
      icon: Icons.visibility_outlined,
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.riskLevel});

  final AgentActionRiskLevel riskLevel;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (riskLevel) {
      AgentActionRiskLevel.low => (
        '低风险',
        AppColors.primary,
        Icons.check_circle_outline_rounded,
      ),
      AgentActionRiskLevel.medium => (
        '中风险',
        AppColors.warning,
        Icons.error_outline_rounded,
      ),
      AgentActionRiskLevel.high => (
        '高风险',
        AppColors.danger,
        Icons.warning_amber_rounded,
      ),
    };
    return _Badge(
      label: label,
      fg: color,
      bg: color.withValues(alpha: 0.15),
      icon: icon,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.fg,
    required this.bg,
    this.icon,
  });

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brFull),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Footer —— 应用修改 / 取消 / 已处理
//  保留测试断言：'应用修改' / '取消' / '已处理'。
// ════════════════════════════════════════════
class _ConfirmationFooter extends StatelessWidget {
  const _ConfirmationFooter({
    required this.isResolved,
    required this.onConfirm,
    required this.onCancel,
  });

  final bool isResolved;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GlowButton(
            label: isResolved ? '已处理' : '应用修改',
            icon: isResolved ? Icons.check_rounded : Icons.bolt_rounded,
            onPressed: isResolved ? null : onConfirm,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton(
          onPressed: isResolved ? null : onCancel,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════
//  类型 → 图标 + 中文类别名 + accent 色 映射
// ════════════════════════════════════════════
class _ActionVisuals {
  const _ActionVisuals({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  static _ActionVisuals forType(AgentActionType type) {
    return switch (type) {
      AgentActionType.answerOnly => const _ActionVisuals(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'COACH 回答',
        accent: AppColors.accent,
      ),
      AgentActionType.generatePlan => const _ActionVisuals(
        icon: Icons.auto_awesome_rounded,
        label: '生成训练计划',
        accent: AppColors.primary,
      ),
      AgentActionType.rescheduleWeek => const _ActionVisuals(
        icon: Icons.calendar_month_rounded,
        label: '重排本周',
        accent: AppColors.accent,
      ),
      AgentActionType.replaceExercise => const _ActionVisuals(
        icon: Icons.swap_horiz_rounded,
        label: '替换动作',
        accent: AppColors.shoulders,
      ),
      AgentActionType.compressWorkout => const _ActionVisuals(
        icon: Icons.compress_rounded,
        label: '压缩训练',
        accent: AppColors.cardio,
      ),
      AgentActionType.nutritionAdvice => const _ActionVisuals(
        icon: Icons.restaurant_rounded,
        label: '饮食建议',
        accent: AppColors.accent,
      ),
      AgentActionType.weeklyReview => const _ActionVisuals(
        icon: Icons.insights_rounded,
        label: '周复盘',
        accent: AppColors.primary,
      ),
      AgentActionType.moveWorkoutSession => const _ActionVisuals(
        icon: Icons.event_repeat_rounded,
        label: '调整训练日',
        accent: AppColors.accent,
      ),
      AgentActionType.safetyResponse => const _ActionVisuals(
        icon: Icons.health_and_safety_rounded,
        label: '安全提醒',
        accent: AppColors.danger,
      ),
    };
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../cards/section_card.dart';

/// 统一的"空态"卡片 —— icon orb + 标题 + 描述 + 可选 CTA。
///
/// 之前各个屏幕（body metrics / 周报 / 历史）各自用 `Center(child: Text)` 处理空态，
/// 视觉重量不足、不引导用户下一步。统一成本组件后：
///   - icon orb 用 [accent]（默认 primary）染色，与 MetricTile / ShortcutTile 视觉一致。
///   - title 用 Manrope 中粗，description 用 bodySmall 1.5 行距。
///   - 可选 cta：当传入 [actionLabel] + [onAction] 时显示一个 OutlinedButton。
///   - 整张包在 [SectionCard] 里，与正常内容卡同节奏。
class BrandEmptyState extends StatelessWidget {
  const BrandEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.accent,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color? accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = accent ?? AppColors.primary;
    final hasCta = actionLabel != null && onAction != null;

    return SectionCard(
      padding:
          padding ??
          const EdgeInsets.symmetric(
            vertical: AppSpacing.xl,
            horizontal: AppSpacing.lg,
          ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.08),
                ],
              ),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: GoogleFonts.notoSansSc(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textPrimary
                  : AppColors.textPrimaryLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (hasCta) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.brFull),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm + 2,
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

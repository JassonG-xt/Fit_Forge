import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';

/// 仪表盘单元 —— 替代散落在首页的 `SectionCard + StatNumber` 组合。
///
/// 视觉职责：
///   1. 左上一个小图标圆盘（accentColor 染色），帮助快速扫读类别。
///   2. 中间放主数值（Manrope w800，tabular digits 让多位数字对齐）。
///   3. 主数值后跟一个小单位（如 "kg" / "min"），不和主数字同字号竞争。
///   4. 底部 label，弱化但可读。
///   5. 可选 [trend] 文本（"+2 本周" / "PR"），用 accentColor 染色作为强调。
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.unit,
    this.trend,
    this.accentColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final String? unit;
  final String? trend;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentColor ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgElevated : AppColors.bgElevatedLight,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.borderLight,
          width: 0.5,
        ),
        boxShadow: isDark ? null : AppShadows.cardElevation,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: AppRadius.brSm,
                ),
                child: Icon(icon, color: accent, size: 16),
              ),
              if (trend != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: AppRadius.brFull,
                  ),
                  child: Text(
                    trend!,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.manrope(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppColors.textPrimary
                      : AppColors.textPrimaryLight,
                  height: 1.0,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textTertiaryLight,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

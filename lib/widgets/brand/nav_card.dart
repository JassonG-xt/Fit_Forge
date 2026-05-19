import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';

/// 标准导航条目 —— "更多"/"进度"/"设置" 等 Tab 顶级入口共用。
///
/// 之前 `MoreScreen._navTile` 与 `ProgressTabScreen._navCard` 两份 byte-identical
/// 副本散落在不同文件，导致颗粒度（圆角/orb 尺寸/padding）容易漂移。
/// 本组件把这一抓手沉到 brand 层，复用 [SectionCard] 的边框/阴影 token。
class NavCard extends StatelessWidget {
  const NavCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// orb 染色（同时用作 icon 颜色）。建议从 AppColors 取语义色。
  final Color color;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgElevated : AppColors.bgElevatedLight;
    final border = isDark ? AppColors.border : AppColors.borderLight;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        boxShadow: isDark ? null : AppShadows.cardElevation,
      ),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: AppRadius.brLg,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: AppRadius.brMd,
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        Text(subtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';

/// 快捷入口 —— 首页底部 4 个跳转入口。
///
/// 视觉职责：
///   1. 顶部一个圆形"色彩 orb"——用 [accentColor] 做柔光底，icon 居中。
///   2. orb 后面有一圈极淡的同色辉光（`RadialGradient`），让 tile 有"灯"的感觉。
///   3. 下方标题用 titleSmall，居中。
///   4. 整张卡 [SectionCard] 风格的轻边框 + 浅阴影，与 MetricTile 节奏一致。
///   5. 点击有 Material InkWell ripple，圆角与卡片一致。
class ShortcutTile extends StatelessWidget {
  const ShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
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
            mainAxisSize: MainAxisSize.min,
            children: [
              _Orb(icon: icon, color: accentColor),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外层光晕：极淡同色辉光
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.20),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // 内层圆盘：实色 tint
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ],
      ),
    );
  }
}

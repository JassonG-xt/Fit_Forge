import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';

/// 标准内容卡片壳：浅色主门面使用白底轻阴影，深色模式使用细描边。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        backgroundColor ??
        (isDark ? AppColors.bgElevated : AppColors.bgElevatedLight);
    final border =
        borderColor ?? (isDark ? AppColors.border : AppColors.borderLight);

    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius ?? AppRadius.brLg,
        border: Border.all(color: border, width: 0.5),
        boxShadow: isDark ? null : AppShadows.cardElevation,
      ),
      child: child,
    );
  }
}

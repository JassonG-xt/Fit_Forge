import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// 品牌标签 chip —— 替换散落在各屏幕的 `Container(decoration: ...)` chip。
///
/// [selected] 为 true 时使用 primary 色，否则使用 bgSurface。
class ChipTag extends StatelessWidget {
  const ChipTag({
    super.key,
    required this.label,
    this.selected = false,
    this.color,
    this.onTap,
    this.textStyle,
  });

  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback? onTap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = selected
        ? (color ?? AppColors.primary)
        : (isDark ? AppColors.bgSurface : AppColors.bgBaseLight);
    final fg = selected
        ? Colors.white
        : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.brFull,
        border: selected
            ? null
            : Border.all(
                color: isDark ? AppColors.border : AppColors.borderLight,
                width: 0.5,
              ),
      ),
      child: Text(
        label,
        style: textStyle ?? theme.textTheme.labelMedium!.copyWith(color: fg),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }
}

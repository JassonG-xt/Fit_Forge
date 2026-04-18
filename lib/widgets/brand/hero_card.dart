import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// 渐变 Hero 容器 —— 首页顶部 / 完成页 / 各种"高能"卡片。
///
/// 内置 `AppColors.heatGradient` 为默认渐变，可通过 [gradient] 覆写。
/// [child] 放在带内边距的 ClipRRect 内。
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.gradient,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius,
  });

  final Widget child;
  final Gradient? gradient;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? AppRadius.brXl;

    return Container(
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.heatGradient,
        borderRadius: br,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

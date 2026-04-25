import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Hero 容器 —— 首页顶部 / 完成页 / 各种重点卡片。
///
/// 默认使用清爽绿色渐变，可通过 [gradient] 覆写。
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
        gradient: gradient ?? AppColors.freshGradient,
        borderRadius: br,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

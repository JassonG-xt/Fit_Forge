import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';

/// Hero 容器 —— 首页顶部 / 完成页 / 各种重点卡片。
///
/// 视觉职责：
///   1. 自动选浅 / 深主题对应的 [AppColors.heroWashLight] / `heroWashDark`。
///   2. 浅色加 [AppShadows.heroElevation] 浮起感；深色靠渐变本身的亮暗对比撑出层次。
///   3. 右上角可选 [ambientGlow]：一抹品牌色光晕，作为 Hero 区的氛围装饰。
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.gradient,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius,
    this.ambientGlow = true,
  });

  final Widget child;
  final Gradient? gradient;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  /// 是否绘制右上角品牌色光晕装饰。Hero 区开，其它复用场景可关。
  final bool ambientGlow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final br = borderRadius ?? AppRadius.brXxl;
    final wash =
        gradient ?? (isDark ? AppColors.heroWashDark : AppColors.heroWashLight);

    final glow = ambientGlow
        ? Positioned(
            top: -60,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: isDark ? 0.28 : 0.22),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          )
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: isDark ? null : AppShadows.heroElevation,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: wash),
          child: Stack(
            children: [
              ?glow,
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

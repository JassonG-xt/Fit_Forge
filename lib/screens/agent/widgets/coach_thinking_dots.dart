import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// "Coach 正在思考…" 的细腻指示器。
///
/// 三个圆点轮流呼吸，比 [CircularProgressIndicator] 更像"AI 在打字"。
/// 使用 [SingleTickerProviderStateMixin] 自管控生命周期；
/// 父级 unmount 时 controller 会被 dispose，不会在 widget tester 里
/// 留下未完成的 Timer。
class CoachThinkingDots extends StatefulWidget {
  const CoachThinkingDots({
    super.key,
    this.label = 'Coach 正在思考…',
    this.dotColor,
  });

  final String label;
  final Color? dotColor;

  @override
  State<CoachThinkingDots> createState() => _CoachThinkingDotsState();
}

class _CoachThinkingDotsState extends State<CoachThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dotColor = widget.dotColor ?? AppColors.primary;
    final bg = isDark
        ? AppColors.bgSurface.withValues(alpha: 0.5)
        : AppColors.bgSurfaceLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _Dot(controller: _controller, index: i, color: dotColor),
                ],
                const SizedBox(width: AppSpacing.sm),
                Text(
                  widget.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.controller,
    required this.index,
    required this.color,
  });

  final AnimationController controller;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // 每个点错开 1/3 周期；用 sin-like 波形让 opacity 0.3↔1.0 平滑过渡
        final t = (controller.value + index / 3) % 1.0;
        // 三角波转 0..1..0
        final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
        final opacity = 0.3 + 0.7 * wave;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

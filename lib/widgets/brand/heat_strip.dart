import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'progress_ring.dart';

/// 7 日训练热图条 —— 首页 / 进度页。
///
/// 显示一周 7 天，每天一个小环形进度，当日用 primary 高亮描边。
class HeatStrip extends StatelessWidget {
  const HeatStrip({
    super.key,
    required this.weekActivity,
    this.todayIndex,
  });

  /// 7 个元素，每个 0.0~1.0 表示当日训练完成度。
  final List<double> weekActivity;

  /// 当前是第几天（0=周一），会高亮描边。null 表示不高亮。
  final int? todayIndex;

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final activity = i < weekActivity.length ? weekActivity[i] : 0.0;
        final isToday = i == todayIndex;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: isToday
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    )
                  : null,
              child: ProgressRing(
                progress: activity,
                size: 36,
                strokeWidth: 3,
                gradientColors: activity > 0
                    ? const [AppColors.primary, AppColors.primaryGlow]
                    : [AppColors.border, AppColors.border],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _dayLabels[i],
              style: theme.textTheme.labelSmall!.copyWith(
                color: isToday ? AppColors.primary : AppColors.textTertiary,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        );
      }),
    );
  }
}

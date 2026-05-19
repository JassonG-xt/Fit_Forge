import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// 7 日训练节律条 —— 首页 / 进度页。
///
/// 与旧 `HeatStrip` 的差异：
///   1. 每天一根**纵向条**而非环；条高 = 完成度，更像运动 App 的"节拍"。
///   2. 当日加 primary 描边 + 顶部小圆点高亮。
///   3. 已完成的日子条体染品牌绿渐变，未训练日染浅灰，让强弱节奏一眼可读。
///   4. 顶部一行小字"本周 N 次"放在 [WeekRhythm] 外层的 SectionCard 标题处即可；
///      本控件只渲染条体与日标签，专注一件事。
class HeatStrip extends StatelessWidget {
  const HeatStrip({super.key, required this.weekActivity, this.todayIndex});

  /// 7 个元素，每个 0.0~1.0 表示当日训练完成度。
  final List<double> weekActivity;

  /// 当前是第几天（0=周一），会高亮描边。null 表示不高亮。
  final int? todayIndex;

  static const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedTrack = isDark ? AppColors.bgSurface : AppColors.bgSurfaceLight;

    return SizedBox(
      height: 86,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final activity = (i < weekActivity.length ? weekActivity[i] : 0.0)
              .clamp(0.0, 1.0);
          final isToday = i == todayIndex;
          final done = activity > 0;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isToday)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 10),
                  // 节拍条本身
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final maxH = c.maxHeight;
                        // 至少给个最小高度，让"空"也能被看到（4px 底坑）
                        final h = (maxH * activity).clamp(4.0, maxH);
                        return Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // 底坑
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: mutedTrack,
                                borderRadius: AppRadius.brSm,
                                border: isToday
                                    ? Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 1.2,
                                      )
                                    : null,
                              ),
                            ),
                            // 完成填充
                            if (done)
                              Container(
                                width: double.infinity,
                                height: h,
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.brSm,
                                  gradient: const LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primaryGlow,
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _dayLabels[i],
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.textTertiary
                                : AppColors.textTertiaryLight),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

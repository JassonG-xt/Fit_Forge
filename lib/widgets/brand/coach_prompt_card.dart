import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';

/// 首页"和 Coach 对话"入口 —— 醒目的渐变行动卡。
///
/// 视觉职责：
///   1. 使用 [AppColors.missionGradient]（绿→湖蓝），明确区别于 Hero / SectionCard。
///   2. 左侧一个深底圆 + 机器人 icon，作为"虚拟教练"的代号。
///   3. 中间标题强 + 副标题弱；标题用纯白，副标题降透明度，深浅主题都看得清。
///   4. 右侧 chevron 暗示可点。整张卡 [InkWell] 点击 → 跳转 Coach 聊天页。
class CoachPromptCard extends StatelessWidget {
  const CoachPromptCard({
    super.key,
    required this.onTap,
    this.title = 'FitForge Coach',
    this.subtitle = '问 AI 教练：调整训练 · 替换动作 · 复盘表现',
    this.badge = 'AI',
  });

  final VoidCallback onTap;
  final String title;
  final String subtitle;

  /// 右上角小角标，默认 "AI"；可传 "BETA" / 任意短文本。
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brXl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            gradient: AppColors.missionGradient,
            borderRadius: AppRadius.brXl,
            boxShadow: AppShadows.missionElevation,
          ),
          child: Row(
            children: [
              // ── 左圆 ──
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // ── 中间文本 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: AppRadius.brSm,
                            ),
                            child: Text(
                              badge!,
                              style: GoogleFonts.manrope(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // ── 右 chevron ──
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

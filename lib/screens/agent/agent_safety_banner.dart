import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// 提示用户存在医疗/安全风险的横幅。
///
/// 当 AgentResponse.safety.shouldStopWorkout 为 true 时显示在聊天最上方。
/// 视觉职责：必须**最高紧迫感**——danger 渐变背景 + 大警告 icon +
/// "立即停止训练" 措辞强化，比之前轻量的 12% danger 染色更难被忽略。
/// 文案保留原意：不弱化高风险健康提醒。
class AgentSafetyBanner extends StatelessWidget {
  const AgentSafetyBanner({super.key, required this.disclaimer});

  final String disclaimer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.6),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.danger.withValues(alpha: 0.18),
            AppColors.danger.withValues(alpha: 0.08),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: AppRadius.brSm,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.health_and_safety_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SAFETY ALERT',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    disclaimer,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: AppColors.danger,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

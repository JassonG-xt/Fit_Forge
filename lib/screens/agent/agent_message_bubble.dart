import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../agent/models/agent_message.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'widgets/coach_avatar.dart';

/// 单条聊天消息气泡。
///
/// 视觉规则：
///   - user：右对齐、品牌绿气泡、白字。右下角微圆，左下角更圆，形成"指向我"。
///   - Coach（assistant）：左对齐 + 头像 + "FitForge Coach" sender label +
///     soft surface 卡片。左下角微圆。长文本走 bodyMedium，行距 1.5 保证可读。
///   - error：消息背景换 danger 染色、保留头像但 icon 改为 warning。
///
/// **不改 [AgentMessage] 数据结构，只换渲染**。
class AgentMessageBubble extends StatelessWidget {
  const AgentMessageBubble({super.key, required this.message});

  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AgentMessageRole.user;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xs,
      ),
      child: isUser
          ? _UserBubble(message: message)
          : _CoachBubble(message: message),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDim],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.lg),
                  topRight: Radius.circular(AppRadius.lg),
                  bottomLeft: Radius.circular(AppRadius.lg),
                  bottomRight: Radius.circular(AppRadius.xs),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message.content,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: AppColors.textInverse,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoachBubble extends StatelessWidget {
  const _CoachBubble({required this.message});
  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isError = message.isError;

    final bg = isError
        ? AppColors.danger.withValues(alpha: 0.10)
        : (isDark ? AppColors.bgElevated : AppColors.bgElevatedLight);
    final border = isError
        ? AppColors.danger.withValues(alpha: 0.35)
        : (isDark ? AppColors.border : AppColors.borderLight);
    final fg = isError
        ? AppColors.danger
        : (isDark ? AppColors.textPrimary : AppColors.textPrimaryLight);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: CoachAvatar(
            size: 32,
            haloOpacity: 0,
            icon: isError
                ? Icons.error_outline_rounded
                : Icons.auto_awesome_rounded,
            gradient: isError
                ? const LinearGradient(
                    colors: [AppColors.danger, AppColors.danger],
                  )
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    'FitForge Coach',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textTertiaryLight,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: border, width: 0.6),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.xs),
                      topRight: Radius.circular(AppRadius.lg),
                      bottomLeft: Radius.circular(AppRadius.lg),
                      bottomRight: Radius.circular(AppRadius.lg),
                    ),
                  ),
                  child: SelectableText(
                    message.content,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: fg,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

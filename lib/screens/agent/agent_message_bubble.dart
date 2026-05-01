import 'package:flutter/material.dart';

import '../../agent/models/agent_message.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// 单条聊天消息气泡。
///
/// 用户消息靠右、绿色；assistant 消息靠左、灰色卡片。
/// `isError=true` 时使用 danger 色提示。
class AgentMessageBubble extends StatelessWidget {
  const AgentMessageBubble({super.key, required this.message});

  final AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AgentMessageRole.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = message.isError
        ? AppColors.danger.withValues(alpha: 0.12)
        : isUser
        ? AppColors.primary
        : (isDark ? AppColors.bgSurface : AppColors.bgSurfaceLight);

    final fg = message.isError
        ? AppColors.danger
        : isUser
        ? AppColors.textInverse
        : (isDark ? AppColors.textPrimary : AppColors.textPrimaryLight);

    final align = isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.md),
          topRight: const Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(isUser ? AppRadius.md : AppRadius.xs),
          bottomRight: Radius.circular(isUser ? AppRadius.xs : AppRadius.md),
        ),
      ),
      child: Text(
        message.content,
        style: theme.textTheme.bodyMedium!.copyWith(color: fg),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [Flexible(child: bubble)],
          ),
        ],
      ),
    );
  }
}

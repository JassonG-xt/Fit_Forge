import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// 输入框上方的预设 prompt 横向滚动栏。
///
/// 帮助新用户快速触发核心场景。
class SuggestedPromptBar extends StatelessWidget {
  const SuggestedPromptBar({
    super.key,
    required this.prompts,
    required this.onTapPrompt,
    this.enabled = true,
  });

  final List<String> prompts;
  final ValueChanged<String> onTapPrompt;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        itemCount: prompts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final prompt = prompts[index];
          return ActionChip(
            label: Text(
              prompt,
              style: theme.textTheme.bodySmall!.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.brFull),
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
            onPressed: enabled ? () => onTapPrompt(prompt) : null,
          );
        },
      ),
    );
  }
}

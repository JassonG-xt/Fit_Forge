import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// 输入框上方的预设 prompt 横向滚动栏。
///
/// 帮助新用户快速触发核心场景。每个 chip 比默认 [ActionChip] 更扁、更"按钮感"，
/// 边框去掉、改用浅底 + brand color text 的"软按钮"风。
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
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        itemCount: prompts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final prompt = prompts[index];
          return _PromptChip(
            label: prompt,
            onTap: enabled ? () => onTapPrompt(prompt) : null,
          );
        },
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disabled = onTap == null;

    final bg = disabled
        ? (isDark
              ? AppColors.bgSurface.withValues(alpha: 0.4)
              : AppColors.bgSurfaceLight)
        : (isDark
              ? AppColors.bgSurface
              : AppColors.primary.withValues(alpha: 0.08));
    final fg = disabled
        ? (isDark ? AppColors.textTertiary : AppColors.textTertiaryLight)
        : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brFull,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.brFull,
            border: Border.all(
              color: disabled
                  ? (isDark
                        ? AppColors.border.withValues(alpha: 0.4)
                        : AppColors.borderLight)
                  : AppColors.primary.withValues(alpha: 0.30),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 12,
                color: fg.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

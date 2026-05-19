import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/progress_ring.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final achievements = context.watch<AppState>().achievements;
    return Scaffold(
      appBar: AppBar(title: const Text('成就')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(AppSpacing.screenH),
            mainAxisSpacing: AppSpacing.cardGap,
            crossAxisSpacing: AppSpacing.cardGap,
            childAspectRatio: 0.85,
            children: achievements.map((a) => _Card(achievement: a)).toList(),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.achievement});
  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUnlocked = achievement.isUnlocked;

    // Unlocked 用 accent 强调（accent + accent glow）；
    // Locked 走 SectionCard 同款边框/阴影，让两态在视觉重量上有差异但不脱节。
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgElevated : AppColors.bgElevatedLight,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: isUnlocked
              ? AppColors.accent.withValues(alpha: 0.5)
              : (isDark ? AppColors.border : AppColors.borderLight),
          width: isUnlocked ? 1.5 : 0.5,
        ),
        boxShadow: isUnlocked
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : (isDark ? null : AppShadows.cardElevation),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ProgressRing(
            progress: isUnlocked ? 1.0 : achievement.progressPercentage,
            size: 54,
            strokeWidth: 4,
            gradientColors: isUnlocked
                ? const [AppColors.accent, AppColors.accent]
                : const [AppColors.primary, AppColors.primaryGlow],
            child: Text(achievement.icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            achievement.title,
            style: theme.textTheme.labelMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            achievement.description,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (isUnlocked)
            Text(
              '已解锁',
              style: theme.textTheme.labelSmall!.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              '${achievement.currentProgress}/${achievement.threshold}',
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

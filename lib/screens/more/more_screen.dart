import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/cards/section_card.dart';
import '../settings/settings_screen.dart';
import '../progress/calendar_screen.dart';
import '../progress/achievements_screen.dart';
import '../plan/plan_generator_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          _sectionHeader(theme, '训练工具'),
          _navTile(
            context,
            '训练计划',
            '生成或更换个性化训练计划',
            Icons.auto_awesome,
            AppColors.primary,
            const PlanGeneratorScreen(),
          ),
          _navTile(
            context,
            '训练日历',
            '查看训练历史和安排',
            Icons.calendar_month,
            AppColors.back,
            const CalendarScreen(),
          ),
          _navTile(
            context,
            '成就',
            '你的健身里程碑',
            Icons.emoji_events,
            AppColors.warning,
            const AchievementsScreen(),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionHeader(theme, '应用'),
          _navTile(
            context,
            '设置',
            '个人信息和应用配置',
            Icons.settings_outlined,
            AppColors.textSecondary,
            const SettingsScreen(),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: theme.textTheme.labelMedium!.copyWith(
        color: AppColors.textTertiary,
      ),
    ),
  );

  Widget _navTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    Widget screen,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: AppRadius.brMd,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title, style: theme.textTheme.titleSmall),
          subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.textTertiary,
            size: 20,
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => screen),
          ),
        ),
      ),
    );
  }
}

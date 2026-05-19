import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/nav_card.dart';
import '../agent/agent_chat_screen.dart';
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenH),
            children: [
              _sectionHeader(theme, 'AI 教练'),
              _gap,
              NavCard(
                title: 'FitForge Coach',
                subtitle: '让 AI 教练帮你调整训练、替换动作、复盘表现',
                icon: Icons.smart_toy_outlined,
                color: AppColors.accent,
                onTap: () => _push(context, const AgentChatScreen()),
              ),
              const SizedBox(height: AppSpacing.lg),
              _sectionHeader(theme, '训练工具'),
              _gap,
              NavCard(
                title: '训练计划',
                subtitle: '生成或更换个性化训练计划',
                icon: Icons.auto_awesome,
                color: AppColors.primary,
                onTap: () => _push(context, const PlanGeneratorScreen()),
              ),
              _gap,
              NavCard(
                title: '训练日历',
                subtitle: '查看训练历史和安排',
                icon: Icons.calendar_month,
                color: AppColors.back,
                onTap: () => _push(context, const CalendarScreen()),
              ),
              _gap,
              NavCard(
                title: '成就',
                subtitle: '你的健身里程碑',
                icon: Icons.emoji_events,
                color: AppColors.warning,
                onTap: () => _push(context, const AchievementsScreen()),
              ),
              const SizedBox(height: AppSpacing.lg),
              _sectionHeader(theme, '应用'),
              _gap,
              NavCard(
                title: '设置',
                subtitle: '个人信息和应用配置',
                icon: Icons.settings_outlined,
                color: AppColors.textSecondary,
                onTap: () => _push(context, const SettingsScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: AppSpacing.cardGap);

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  Widget _sectionHeader(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text(
      text,
      style: theme.textTheme.labelMedium!.copyWith(
        color: AppColors.textTertiary,
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/glow_button.dart';
import '../../widgets/cards/section_card.dart';
import '../../widgets/cards/chip_tag.dart';

class PlanGeneratorScreen extends StatefulWidget {
  const PlanGeneratorScreen({super.key});

  @override
  State<PlanGeneratorScreen> createState() => _PlanGeneratorScreenState();
}

class _PlanGeneratorScreenState extends State<PlanGeneratorScreen> {
  WorkoutPlan? _plan;
  bool _isGenerating = false;

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  void _generate() {
    setState(() => _isGenerating = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final plan = context.read<AppState>().previewPlan();
      setState(() {
        _plan = plan;
        _isGenerating = false;
      });
    });
  }

  void _adopt() {
    if (_plan != null) {
      context.read<AppState>().adoptPlan(_plan!);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('训练计划')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        child: _plan != null
            ? _planPreview()
            : (_isGenerating ? _loadingView() : _preView(state)),
      ),
    );
  }

  Widget _preView(AppState state) {
    final theme = Theme.of(context);
    final profile = state.profile;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            gradient: AppColors.heatGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('智能生成训练计划', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),
        if (profile != null) ...[
          _infoRow(theme, '目标', profile.goal.displayName),
          _infoRow(theme, '频率', '每周 ${profile.weeklyFrequency} 次'),
          _infoRow(theme, '经验', profile.experienceLevel.displayName),
          _infoRow(theme, '器械', '${profile.availableEquipment.length} 种可用'),
        ],
        const SizedBox(height: AppSpacing.xl),
        GlowButton(
          label: '生成计划',
          icon: Icons.auto_awesome,
          onPressed: _generate,
        ),
      ],
    );
  }

  Widget _loadingView() => SizedBox(
    height: 300,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text('正在生成训练计划...', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );

  Widget _planPreview() {
    final theme = Theme.of(context);
    final plan = _plan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.name, style: theme.textTheme.headlineSmall),
        Text(
          '${plan.split.displayName} | 每周 ${plan.weeklyFrequency} 天',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        ...plan.days.map((day) {
          final dayName = (day.dayOfWeek >= 1 && day.dayOfWeek <= 7)
              ? _weekdays[day.dayOfWeek - 1]
              : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(dayName, style: theme.textTheme.titleSmall),
                      const Spacer(),
                      ChipTag(
                        label: day.dayType.displayName,
                        selected: day.dayType != WorkoutDayType.rest,
                        color: day.dayType == WorkoutDayType.rest
                            ? AppColors.textTertiary
                            : AppColors.primary,
                      ),
                    ],
                  ),
                  if (day.dayType != WorkoutDayType.rest)
                    ...day.exercises.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Row(
                          children: [
                            Text(
                              '  ${e.exerciseName}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const Spacer(),
                            Text(
                              '${e.targetSets}组×${e.targetReps}次',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _plan = null),
                child: const Text('重新生成'),
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: GlowButton(label: '采用此计划', onPressed: _adopt),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    ),
  );
}

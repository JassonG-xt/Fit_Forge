import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/cards/section_card.dart';
import '../../widgets/cards/chip_tag.dart';
import '../../widgets/brand/stat_number.dart';

class ExerciseDetailScreen extends StatelessWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises = context.read<AppState>().exercises;
    final exercise = exercises.where((e) => e.id == exerciseId).firstOrNull;

    if (exercise == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text('动作未找到', style: theme.textTheme.bodyMedium)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 动作示意图
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _bodyPartColor(exercise.bodyPart).withValues(alpha: 0.15),
                  _bodyPartColor(exercise.bodyPart).withValues(alpha: 0.05),
                ],
              ),
              borderRadius: AppRadius.brXl,
              border: Border.all(color: _bodyPartColor(exercise.bodyPart).withValues(alpha: 0.3), width: 0.5),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_bodyPartIcon(exercise.bodyPart), size: 56,
                  color: _bodyPartColor(exercise.bodyPart)),
              const SizedBox(height: AppSpacing.sm),
              Text(exercise.bodyPart.displayName,
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: _bodyPartColor(exercise.bodyPart),
                  )),
              Text(exercise.isCompound ? '复合动作' : '孤立动作',
                  style: theme.textTheme.labelSmall),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),

          // 标签
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
            ChipTag(label: exercise.bodyPart.displayName, selected: true, color: AppColors.primary),
            ChipTag(label: exercise.equipment.displayName, selected: true, color: AppColors.back),
            ChipTag(label: exercise.difficulty.displayName, selected: true, color: AppColors.accent),
            if (exercise.isCompound) const ChipTag(label: '复合动作', selected: true, color: AppColors.shoulders),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // 动作讲解
          _section(theme, '动作讲解', Icons.description),
          Text(exercise.instructions, style: theme.textTheme.bodyMedium!.copyWith(height: 1.6)),
          const SizedBox(height: AppSpacing.md),

          // 动作要点
          _section(theme, '动作要点', Icons.check_circle),
          ...exercise.formCues.map((c) => _tipRow(theme, c, Icons.check_circle, AppColors.accent)),
          const SizedBox(height: AppSpacing.md),

          // 避免借力
          _section(theme, '避免借力', Icons.warning_amber),
          ...exercise.antiCheatTips.map((t) => _tipRow(theme, t, Icons.warning_amber, AppColors.warning)),
          const SizedBox(height: AppSpacing.md),

          // 常见错误
          _section(theme, '常见错误', Icons.cancel),
          ...exercise.commonMistakes.map((m) => _tipRow(theme, m, Icons.cancel, AppColors.danger)),
          const SizedBox(height: AppSpacing.md),

          // 推荐参数
          _section(theme, '推荐训练参数', Icons.tune),
          Row(children: [
            Expanded(child: SectionCard(
              child: StatNumber(
                value: '${exercise.recommendedSetsMin}-${exercise.recommendedSetsMax}',
                label: '组数', fontSize: 20,
              ),
            )),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(child: SectionCard(
              child: StatNumber(
                value: '${exercise.recommendedRepsMin}-${exercise.recommendedRepsMax}',
                label: '次数', fontSize: 20, valueColor: AppColors.accent,
              ),
            )),
          ]),
          const SizedBox(height: AppSpacing.md),

          // 替代动作
          if (exercise.alternativeIds.isNotEmpty) ...[
            _section(theme, '替代动作', Icons.swap_horiz),
            ...exercise.alternativeIds.map((altId) {
              final alt = exercises.where((e) => e.id == altId).firstOrNull;
              if (alt == null) return const SizedBox();
              return ListTile(
                leading: const Icon(Icons.fitness_center, color: AppColors.primary),
                title: Text(alt.name),
                subtitle: Text(alt.equipment.displayName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => ExerciseDetailScreen(exerciseId: alt.id))),
                dense: true,
              );
            }),
          ],
        ]),
      ),
    );
  }

  Widget _section(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: theme.textTheme.titleSmall),
      ]),
    );
  }

  Widget _tipRow(ThemeData theme, String text, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }

  static IconData _bodyPartIcon(BodyPart part) => switch (part) {
        BodyPart.chest => Icons.fitbit_outlined,
        BodyPart.back => Icons.airline_seat_flat,
        BodyPart.shoulders => Icons.accessibility_new,
        BodyPart.biceps || BodyPart.triceps || BodyPart.forearms => Icons.front_hand,
        BodyPart.legs || BodyPart.calves => Icons.directions_walk,
        BodyPart.glutes => Icons.chair,
        BodyPart.abs => Icons.view_column_outlined,
        BodyPart.fullBody => Icons.sports_gymnastics,
        BodyPart.cardio => Icons.favorite,
      };

  static Color _bodyPartColor(BodyPart part) => switch (part) {
        BodyPart.chest => AppColors.chest,
        BodyPart.back => AppColors.back,
        BodyPart.shoulders => AppColors.shoulders,
        BodyPart.biceps || BodyPart.triceps || BodyPart.forearms => AppColors.arms,
        BodyPart.legs || BodyPart.calves || BodyPart.glutes => AppColors.legs,
        BodyPart.abs => AppColors.core,
        BodyPart.fullBody => AppColors.primary,
        BodyPart.cardio => AppColors.cardio,
      };
}

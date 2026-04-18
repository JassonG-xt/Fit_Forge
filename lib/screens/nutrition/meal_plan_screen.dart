import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../engines/nutrition_engine.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/hero_card.dart';
import '../../widgets/cards/section_card.dart';

class MealPlanScreen extends StatelessWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final profile = state.profile;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('饮食计划')),
        body: Center(child: Text('请先完成个人资料设置', style: theme.textTheme.bodyMedium)),
      );
    }

    final macros = NutritionEngine.calculateMacros(profile);
    final meals = NutritionEngine.generateMealPlan(macros, profile.goal, state.foods);
    final water = NutritionEngine.dailyWaterIntake(profile.weightKg, profile.weeklyFrequency);

    return Scaffold(
      appBar: AppBar(title: const Text('饮食计划')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 宏量总览
          HeroCard(
            gradient: AppColors.heatGradient,
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('每日营养目标',
                    style: theme.textTheme.titleSmall!.copyWith(color: Colors.white)),
                Text(profile.goal.displayName,
                    style: theme.textTheme.labelMedium!.copyWith(color: Colors.white.withValues(alpha: 0.8))),
              ]),
              const SizedBox(height: AppSpacing.md),
              Text('${macros.calories}',
                  style: theme.textTheme.displayLarge!.copyWith(color: Colors.white, fontSize: 40)),
              Text('千卡/天', style: theme.textTheme.bodySmall!.copyWith(color: Colors.white.withValues(alpha: 0.7))),
              const SizedBox(height: AppSpacing.md),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _macroColumn(theme, '蛋白质', '${macros.proteinGrams}g', AppColors.danger),
                _macroColumn(theme, '碳水', '${macros.carbGrams}g', AppColors.back),
                _macroColumn(theme, '脂肪', '${macros.fatGrams}g', AppColors.warning),
              ]),
            ]),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 饮水
          SectionCard(
            borderColor: AppColors.accent.withValues(alpha: 0.3),
            child: Row(children: [
              const Icon(Icons.water_drop, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('每日饮水建议', style: theme.textTheme.titleSmall),
                  Text('$water ml（约 ${water ~/ 250} 杯）', style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 三餐
          Text('每日饮食建议', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          ...meals.map((meal) => _mealCard(theme, meal)),
        ]),
      ),
    );
  }

  Widget _macroColumn(ThemeData theme, String label, String value, Color color) {
    return Column(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(height: AppSpacing.xs),
      Text(value, style: theme.textTheme.labelLarge!.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
      Text(label, style: theme.textTheme.labelSmall!.copyWith(color: Colors.white.withValues(alpha: 0.7))),
    ]);
  }

  Widget _mealCard(ThemeData theme, MealSuggestion meal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(meal.name, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text('${meal.calories} kcal',
                style: theme.textTheme.labelLarge!.copyWith(color: AppColors.primary)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Row(children: [
            Text('蛋白 ${meal.proteinGrams}g', style: theme.textTheme.labelSmall!.copyWith(color: AppColors.danger)),
            const SizedBox(width: AppSpacing.sm),
            Text('碳水 ${meal.carbGrams}g', style: theme.textTheme.labelSmall!.copyWith(color: AppColors.back)),
            const SizedBox(width: AppSpacing.sm),
            Text('脂肪 ${meal.fatGrams}g', style: theme.textTheme.labelSmall!.copyWith(color: AppColors.warning)),
          ]),
          const Divider(height: AppSpacing.lg),
          ...meal.foods.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text(f.name, style: theme.textTheme.bodyMedium)),
                  Text(f.portion, style: theme.textTheme.bodySmall),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${f.calories}kcal', style: theme.textTheme.labelSmall),
                ]),
              )),
        ]),
      ),
    );
  }
}

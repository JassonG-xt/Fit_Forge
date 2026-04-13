import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../engines/nutrition_engine.dart';

class MealPlanScreen extends StatelessWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('饮食计划')),
        body: const Center(child: Text('请先完成个人资料设置')),
      );
    }

    final macros = NutritionEngine.calculateMacros(profile);
    final meals = NutritionEngine.generateMealPlan(macros, profile.goal);
    final water = NutritionEngine.dailyWaterIntake(profile.weightKg, profile.weeklyFrequency);

    return Scaffold(
      appBar: AppBar(title: const Text('饮食计划')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 宏量总览
          Card(
            elevation: 0, color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('每日营养目标', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(profile.goal.displayName, style: const TextStyle(color: Colors.orange)),
                ]),
                const SizedBox(height: 12),
                Text('${macros.calories}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.orange)),
                Text('千卡/天', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _macroColumn('蛋白质', '${macros.proteinGrams}g', Colors.red),
                  _macroColumn('碳水', '${macros.carbGrams}g', Colors.blue),
                  _macroColumn('脂肪', '${macros.fatGrams}g', Colors.amber),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // 饮水
          Card(
            elevation: 0, color: Colors.cyan.shade50,
            child: ListTile(
              leading: const Icon(Icons.water_drop, color: Colors.cyan),
              title: const Text('每日饮水建议', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text('$water ml（约 ${water ~/ 250} 杯）'),
            ),
          ),
          const SizedBox(height: 16),

          // 三餐
          const Text('每日饮食建议', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...meals.map(_mealCard),
        ]),
      ),
    );
  }

  Widget _macroColumn(String label, String value, Color color) {
    return Column(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }

  Widget _mealCard(MealSuggestion meal) {
    return Card(
      elevation: 0, color: Colors.grey[100],
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(meal.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${meal.calories} kcal', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('蛋白 ${meal.proteinGrams}g', style: const TextStyle(fontSize: 11, color: Colors.red)),
            const SizedBox(width: 8),
            Text('碳水 ${meal.carbGrams}g', style: const TextStyle(fontSize: 11, color: Colors.blue)),
            const SizedBox(width: 8),
            Text('脂肪 ${meal.fatGrams}g', style: const TextStyle(fontSize: 11, color: Colors.amber)),
          ]),
          const Divider(height: 16),
          ...meal.foods.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(children: [
                  Text(f.name, style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text(f.portion, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(width: 8),
                  Text('${f.calories}kcal', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ]),
              )),
        ]),
      ),
    );
  }
}

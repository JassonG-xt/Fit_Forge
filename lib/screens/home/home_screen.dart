import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../plan/plan_generator_screen.dart';
import '../workout/workout_session_screen.dart';
import '../settings/settings_screen.dart';
import '../library/exercise_library_screen.dart';
import '../nutrition/meal_plan_screen.dart';
import '../music/music_hub_screen.dart';
import '../progress/body_metrics_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('FitForge', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 问候
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_greeting, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (state.profile != null)
                      Text('目标: ${state.profile!.goal.displayName}',
                          style: TextStyle(color: Colors.grey[600])),
                  ]),
                  Column(children: [
                    Text('${state.streakDays}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
                    Text('连续天数', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]),
                ],
              ),
              const SizedBox(height: 20),

              // 今日训练卡片
              _todayWorkoutCard(context, state),
              const SizedBox(height: 16),

              // 快速统计
              Row(children: [
                _statCard('本周训练', '${state.totalWorkoutsThisWeek}', Icons.fitness_center),
                const SizedBox(width: 8),
                _statCard('当前体重', state.profile != null ? '${state.profile!.weightKg}kg' : '--', Icons.monitor_weight),
                const SizedBox(width: 8),
                _statCard('累计训练', '${state.completedSessions.length}', Icons.trending_up),
              ]),
              const SizedBox(height: 20),

              // 快捷入口
              const Text('快捷入口', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _quickAccessGrid(context),
            ],
          ),
        ),
      );
    });
  }

  Widget _todayWorkoutCard(BuildContext context, AppState state) {
    final today = state.todayWorkout;
    if (today != null) {
      return Card(
        elevation: 0,
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => WorkoutSessionScreen(workoutDay: today))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.local_fire_department, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('今日训练', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                  child: Text(today.dayType.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ]),
              const Divider(),
              ...today.exercises.take(4).map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(
                          color: Colors.orange.shade300, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(e.exerciseName, style: const TextStyle(fontSize: 14)),
                      const Spacer(),
                      Text('${e.targetSets}×${e.targetReps}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ]),
                  )),
              if (today.exercises.length > 4)
                Text('还有 ${today.exercises.length - 4} 个动作...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ]),
          ),
        ),
      );
    }

    // 没有计划
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PlanGeneratorScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(children: [
            Icon(Icons.add_circle, size: 48, color: Colors.orange),
            const SizedBox(height: 8),
            const Text('还没有训练计划', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('点击生成个性化训练计划', style: TextStyle(color: Colors.grey[600])),
          ]),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, color: Colors.orange),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _quickAccessGrid(BuildContext context) {
    final items = [
      ('动作库', Icons.menu_book, Colors.blue, const ExerciseLibraryScreen()),
      ('饮食计划', Icons.restaurant, Colors.green, const MealPlanScreen()),
      ('训练音乐', Icons.music_note, Colors.purple, const MusicHubScreen()),
      ('数据追踪', Icons.show_chart, Colors.cyan, const BodyMetricsScreen()),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.8,
      children: items.map((item) {
        final (title, icon, color, screen) = item;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

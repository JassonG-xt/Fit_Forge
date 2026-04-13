import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';

class ExerciseDetailScreen extends StatelessWidget {
  final String exerciseId;
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  @override
  Widget build(BuildContext context) {
    final exercises = context.read<AppState>().exercises;
    final exercise = exercises.where((e) => e.id == exerciseId).firstOrNull;

    if (exercise == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('动作未找到')));
    }

    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 动画占位
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.fitness_center, size: 60, color: Colors.orange),
              const SizedBox(height: 8),
              Text('动画: ${exercise.lottieAnimationName}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 16),

          // 标签
          Wrap(spacing: 6, children: [
            _chip(exercise.bodyPart.displayName, Colors.orange),
            _chip(exercise.equipment.displayName, Colors.blue),
            _chip(exercise.difficulty.displayName, Colors.green),
            if (exercise.isCompound) _chip('复合动作', Colors.purple),
          ]),
          const SizedBox(height: 20),

          // 动作讲解
          _section('动作讲解', Icons.description),
          Text(exercise.instructions, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 16),

          // 动作要点
          _section('动作要点', Icons.check_circle),
          ...exercise.formCues.map((c) => _tipRow(c, Icons.check_circle, Colors.green)),
          const SizedBox(height: 16),

          // 避免借力
          _section('避免借力', Icons.warning_amber),
          ...exercise.antiCheatTips.map((t) => _tipRow(t, Icons.warning_amber, Colors.orange)),
          const SizedBox(height: 16),

          // 常见错误
          _section('常见错误', Icons.cancel),
          ...exercise.commonMistakes.map((m) => _tipRow(m, Icons.cancel, Colors.red)),
          const SizedBox(height: 16),

          // 推荐参数
          _section('推荐训练参数', Icons.tune),
          Row(children: [
            _paramBox('组数', '${exercise.recommendedSetsMin}-${exercise.recommendedSetsMax}'),
            const SizedBox(width: 12),
            _paramBox('次数', '${exercise.recommendedRepsMin}-${exercise.recommendedRepsMax}'),
          ]),
          const SizedBox(height: 16),

          // 替代动作
          if (exercise.alternativeIds.isNotEmpty) ...[
            _section('替代动作', Icons.swap_horiz),
            ...exercise.alternativeIds.map((altId) {
              final alt = exercises.where((e) => e.id == altId).firstOrNull;
              if (alt == null) return const SizedBox();
              return ListTile(
                leading: const Icon(Icons.fitness_center, color: Colors.orange),
                title: Text(alt.name),
                subtitle: Text(alt.equipment.displayName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ExerciseDetailScreen(exerciseId: alt.id))),
                dense: true,
              );
            }),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Chip(
      label: Text(text, style: TextStyle(fontSize: 12, color: color.shade700)),
      backgroundColor: color.shade50,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.orange),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _tipRow(String text, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }

  Widget _paramBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
      ),
    );
  }
}

extension on Color {
  Color get shade50 => withOpacity(0.1);
  Color get shade700 => this;
}

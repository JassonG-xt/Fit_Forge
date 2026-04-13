import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../models/models.dart';

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
      final plan = context.read<AppState>().generatePlan();
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
        padding: const EdgeInsets.all(16),
        child: _plan != null ? _planPreview() : (_isGenerating ? _loadingView() : _preView(state)),
      ),
    );
  }

  Widget _preView(AppState state) {
    final profile = state.profile;
    return Column(children: [
      const Icon(Icons.auto_awesome, size: 60, color: Colors.orange),
      const SizedBox(height: 16),
      const Text('智能生成训练计划', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      if (profile != null) ...[
        _infoRow('目标', profile.goal.displayName),
        _infoRow('频率', '每周 ${profile.weeklyFrequency} 次'),
        _infoRow('经验', profile.experienceLevel.displayName),
        _infoRow('器械', '${profile.availableEquipment.length} 种可用'),
      ],
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('生成计划'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  Widget _loadingView() => const SizedBox(
        height: 300,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.orange),
          SizedBox(height: 16),
          Text('正在生成训练计划...'),
        ])),
      );

  Widget _planPreview() {
    final plan = _plan!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(plan.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Text('${plan.split.displayName} | 每周 ${plan.weeklyFrequency} 天',
          style: TextStyle(color: Colors.grey[600])),
      const SizedBox(height: 16),
      ...plan.days.map((day) {
        final dayName = (day.dayOfWeek >= 1 && day.dayOfWeek <= 7) ? _weekdays[day.dayOfWeek - 1] : '';
        return Card(
          elevation: 0, color: Colors.grey[100],
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(dayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: day.dayType == WorkoutDayType.rest ? Colors.grey : Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(day.dayType.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ]),
              if (day.dayType != WorkoutDayType.rest)
                ...day.exercises.map((e) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Text('  ${e.exerciseName}', style: const TextStyle(fontSize: 13)),
                        const Spacer(),
                        Text('${e.targetSets}组×${e.targetReps}次',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ]),
                    )),
            ]),
          ),
        );
      }),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => _plan = null), child: const Text('重新生成'))),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _adopt,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('采用此计划'),
          ),
        ),
      ]),
    ]);
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      );
}

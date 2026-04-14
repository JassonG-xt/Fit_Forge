import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../engines/plan_engine.dart';
import 'exercise_detail_screen.dart';
import 'rest_timer_screen.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final WorkoutDay workoutDay;
  const WorkoutSessionScreen({super.key, required this.workoutDay});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  static const _uuid = Uuid();
  int _currentIndex = 0;
  bool _showWarmup = true;
  bool _isCompleted = false;
  late DateTime _startTime;
  final Map<String, ExerciseRecord> _records = {};

  List<PlannedExercise> get _exercises => widget.workoutDay.exercises;
  PlannedExercise? get _current => _currentIndex < _exercises.length ? _exercises[_currentIndex] : null;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
  }

  ExerciseRecord _getRecord(PlannedExercise planned) {
    return _records.putIfAbsent(planned.exerciseId, () {
      final record = ExerciseRecord(exerciseId: planned.exerciseId, exerciseName: planned.exerciseName);
      for (var i = 1; i <= planned.targetSets; i++) {
        record.sets.add(SetRecord(setNumber: i));
      }
      return record;
    });
  }

  void _nextExercise() {
    if (_currentIndex < _exercises.length - 1) {
      setState(() => _currentIndex++);
    } else {
      setState(() => _isCompleted = true);
    }
  }

  int get _completedSetsCount =>
      _records.values.expand((r) => r.sets).where((s) => s.isCompleted).length;

  void _saveAndExit() async {
    final hasCompletedSets = _completedSetsCount > 0;

    if (!hasCompletedSets) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未完成训练'),
          content: const Text('你还没有完成任何一组，确定要结束吗？\n本次训练将记录为未完成。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续训练')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('结束')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    final duration = DateTime.now().difference(_startTime).inMinutes;
    final session = WorkoutSession(
      id: _uuid.v4(),
      dayType: widget.workoutDay.dayType,
      durationMinutes: duration,
      isCompleted: hasCompletedSets,
      exerciseRecords: _records.values.toList(),
    );
    context.read<AppState>().saveSession(session);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.workoutDay.dayType.displayName)),
      body: _showWarmup ? _warmupView() : (_isCompleted ? _completedView() : _exerciseView()),
    );
  }

  // ──── 热身 ────
  Widget _warmupView() {
    final warmups = PlanEngine.warmupRecommendation(widget.workoutDay.dayType);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const Icon(Icons.self_improvement, size: 50, color: Colors.orange),
        const SizedBox(height: 8),
        const Text('热身建议', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...warmups.map((w) => ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text(w, style: const TextStyle(fontSize: 14)),
              dense: true,
            )),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _showWarmup = false),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('热身完成，开始训练'),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _showWarmup = false),
          child: const Text('跳过热身', style: TextStyle(color: Colors.grey)),
        ),
      ]),
    );
  }

  // ──── 训练中 ────
  Widget _exerciseView() {
    final planned = _current;
    if (planned == null) return const SizedBox();
    final record = _getRecord(planned);

    return Column(children: [
      LinearProgressIndicator(
        value: (_currentIndex + 1) / _exercises.length,
        backgroundColor: Colors.grey[200], color: Colors.orange,
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('动作 ${_currentIndex + 1}/${_exercises.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(planned.exerciseName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ExerciseDetailScreen(exerciseId: planned.exerciseId))),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _tag('${planned.targetSets} 组', Icons.layers),
              _tag('${planned.targetReps} 次', Icons.repeat),
              _tag('${planned.restSeconds}s 休息', Icons.timer),
            ]),
            const SizedBox(height: 16),
            ...record.sets.map((s) => _setRow(s)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.timer),
                  label: const Text('休息计时'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => RestTimerScreen(seconds: planned.restSeconds))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(_currentIndex < _exercises.length - 1 ? Icons.skip_next : Icons.check),
                  label: Text(_currentIndex < _exercises.length - 1 ? '下一动作' : '完成训练'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: _nextExercise,
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _setRow(SetRecord s) {
    return Card(
      elevation: 0,
      color: s.isCompleted ? Colors.green.shade50 : Colors.grey[100],
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          SizedBox(width: 50, child: Text('第 ${s.setNumber} 组', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          const SizedBox(width: 8),
          _numberInput('重量(kg)', s.weightKg.toString(), (v) => s.weightKg = double.tryParse(v) ?? 0),
          const SizedBox(width: 8),
          _numberInput('次数', s.reps.toString(), (v) => s.reps = int.tryParse(v) ?? 0),
          const Spacer(),
          IconButton(
            icon: Icon(s.isCompleted ? Icons.check_circle : Icons.circle_outlined,
                color: s.isCompleted ? Colors.green : Colors.grey),
            onPressed: () => setState(() => s.isCompleted = !s.isCompleted),
          ),
        ]),
      ),
    );
  }

  Widget _numberInput(String label, String initial, ValueChanged<String> onChanged) {
    return SizedBox(
      width: 65,
      child: TextField(
        controller: TextEditingController(text: initial == '0' || initial == '0.0' ? '' : initial),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(fontSize: 10),
          isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 14),
        onChanged: onChanged,
      ),
    );
  }

  Widget _tag(String text, IconData icon) {
    return Row(children: [
      Icon(icon, size: 14, color: Colors.grey[600]),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
    ]);
  }

  // ──── 完成 ────
  Widget _completedView() {
    final duration = DateTime.now().difference(_startTime).inMinutes;
    final totalSets = _completedSetsCount;
    final totalVolume = _records.values.fold<double>(0, (sum, r) => sum + r.totalVolume);
    final cooldowns = PlanEngine.cooldownRecommendation(widget.workoutDay.dayType);
    final hasWork = totalSets > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Icon(hasWork ? Icons.emoji_events : Icons.info_outline,
            size: 60, color: hasWork ? Colors.orange : Colors.grey),
        const SizedBox(height: 8),
        Text(hasWork ? '训练完成!' : '训练未完成',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        if (!hasWork)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('你还没有完成任何一组', style: TextStyle(color: Colors.grey[600])),
          ),
        const SizedBox(height: 16),
        Card(
          elevation: 0, color: Colors.grey[100],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _statRow('训练时长', '$duration 分钟'),
              _statRow('完成动作', '${_exercises.length} 个'),
              _statRow('完成组数', '$totalSets 组'),
              _statRow('总容量', '${totalVolume.toStringAsFixed(0)} kg'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        const Align(alignment: Alignment.centerLeft,
            child: Text('拉伸建议', style: TextStyle(fontWeight: FontWeight.bold))),
        ...cooldowns.map((c) => ListTile(
              leading: const Icon(Icons.spa, color: Colors.green, size: 18),
              title: Text(c, style: const TextStyle(fontSize: 13)),
              dense: true,
            )),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveAndExit,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: Text(hasWork ? '保存并返回' : '结束训练'),
          ),
        ),
      ]),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../workout/exercise_detail_screen.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  BodyPart? _selectedPart;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final exercises = context.watch<AppState>().exercises;
    var filtered = exercises.where((e) {
      if (_selectedPart != null && e.bodyPart != _selectedPart) return false;
      if (_search.isNotEmpty && !e.name.toLowerCase().contains(_search.toLowerCase())) return false;
      return true;
    }).toList();

    // 按部位分组
    final grouped = <BodyPart, List<Exercise>>{};
    for (final e in filtered) {
      grouped.putIfAbsent(e.bodyPart, () => []).add(e);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('动作库')),
      body: Column(children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索动作',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        // 部位筛选
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _filterChip('全部', _selectedPart == null, () => setState(() => _selectedPart = null)),
              ...BodyPart.values.where((b) => b != BodyPart.fullBody && b != BodyPart.cardio).map((b) =>
                  _filterChip(b.displayName, _selectedPart == b, () => setState(() => _selectedPart = b))),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: ListView(
            children: grouped.entries.map((entry) {
              return ExpansionTile(
                title: Text(entry.key.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                initiallyExpanded: true,
                children: entry.value.map((ex) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade50,
                        child: const Icon(Icons.fitness_center, color: Colors.orange, size: 18),
                      ),
                      title: Text(ex.name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text('${ex.equipment.displayName} · ${ex.difficulty.displayName}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: ex.isCompound
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                              child: const Text('复合', style: TextStyle(fontSize: 10, color: Colors.blue)),
                            )
                          : null,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ExerciseDetailScreen(exerciseId: ex.id))),
                    )).toList(),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _filterChip(String text, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? Colors.orange : Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87)),
        ),
      ),
    );
  }
}

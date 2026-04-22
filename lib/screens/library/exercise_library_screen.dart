import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/cards/chip_tag.dart';
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
    final theme = Theme.of(context);
    final exercises = context.watch<AppState>().exercises;
    final filtered = exercises.where((e) {
      if (_selectedPart != null && e.bodyPart != _selectedPart) return false;
      if (_search.isNotEmpty &&
          !e.name.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    // 按部位分组
    final grouped = <BodyPart, List<Exercise>>{};
    for (final e in filtered) {
      grouped.putIfAbsent(e.bodyPart, () => []).add(e);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('动作库')),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.sm,
              AppSpacing.screenH,
              0,
            ),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索动作',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          // 部位筛选
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH - 6,
                vertical: AppSpacing.sm,
              ),
              children: [
                ChipTag(
                  label: '全部',
                  selected: _selectedPart == null,
                  onTap: () => setState(() => _selectedPart = null),
                ),
                const SizedBox(width: AppSpacing.sm),
                ...BodyPart.values
                    .where(
                      (b) => b != BodyPart.fullBody && b != BodyPart.cardio,
                    )
                    .map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChipTag(
                          label: b.displayName,
                          selected: _selectedPart == b,
                          onTap: () => setState(() => _selectedPart = b),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: ListView(
              children: grouped.entries.map((entry) {
                return ExpansionTile(
                  title: Text(
                    entry.key.displayName,
                    style: theme.textTheme.titleSmall,
                  ),
                  initiallyExpanded: true,
                  children: entry.value
                      .map(
                        (ex) => ListTile(
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: AppRadius.brSm,
                            ),
                            child: const Icon(
                              Icons.fitness_center,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            ex.name,
                            style: theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            '${ex.equipment.displayName} · ${ex.difficulty.displayName}',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: ex.isCompound
                              ? ChipTag(
                                  label: '复合',
                                  color: AppColors.back,
                                  selected: true,
                                  textStyle: theme.textTheme.labelSmall!
                                      .copyWith(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                )
                              : null,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ExerciseDetailScreen(exerciseId: ex.id),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

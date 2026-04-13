import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: profile == null
          ? const Center(child: Text('请先完成个人资料设置'))
          : ListView(
              children: [
                // 个人信息
                _sectionHeader('个人信息'),
                _infoTile('身高', '${profile.heightCm.round()} cm'),
                _infoTile('体重', '${profile.weightKg.toStringAsFixed(1)} kg'),
                _infoTile('年龄', '${profile.age} 岁'),
                ListTile(
                  title: const Text('目标'),
                  trailing: DropdownButton<FitnessGoal>(
                    value: profile.goal,
                    underline: const SizedBox(),
                    items: FitnessGoal.values.map((g) =>
                        DropdownMenuItem(value: g, child: Text(g.displayName))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        profile.goal = v;
                        state.updateProfile(profile);
                      }
                    },
                  ),
                ),
                ListTile(
                  title: const Text('每周频率'),
                  trailing: DropdownButton<int>(
                    value: profile.weeklyFrequency,
                    underline: const SizedBox(),
                    items: List.generate(6, (i) =>
                        DropdownMenuItem(value: i + 1, child: Text('${i + 1} 次/周'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        profile.weeklyFrequency = v;
                        state.updateProfile(profile);
                      }
                    },
                  ),
                ),
                const Divider(),
                _sectionHeader('训练数据'),
                _infoTile('BMR (基础代谢)', '${profile.bmr.round()} kcal'),
                _infoTile('TDEE (每日消耗)', '${profile.tdee.round()} kcal'),
                const Divider(),
                _sectionHeader('关于'),
                _infoTile('版本', '1.0.0'),
                _infoTile('应用', 'FitForge 智能健身助手'),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600])),
      );

  Widget _infoTile(String title, String value) => ListTile(
        title: Text(title),
        trailing: Text(value, style: TextStyle(color: Colors.grey[600])),
        dense: true,
      );
}

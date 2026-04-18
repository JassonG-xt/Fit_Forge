import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final profile = state.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: profile == null
          ? Center(child: Text('请先完成个人资料设置', style: theme.textTheme.bodyMedium))
          : ListView(
              children: [
                _sectionHeader(theme, '个人信息'),
                _infoTile(theme, '身高', '${profile.heightCm.round()} cm'),
                _infoTile(theme, '体重', '${profile.weightKg.toStringAsFixed(1)} kg'),
                _infoTile(theme, '年龄', '${profile.age} 岁'),
                ListTile(
                  title: const Text('目标'),
                  trailing: DropdownButton<FitnessGoal>(
                    value: profile.goal,
                    underline: const SizedBox(),
                    dropdownColor: AppColors.bgSurface,
                    items: FitnessGoal.values.map((g) =>
                        DropdownMenuItem(value: g, child: Text(g.displayName))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        state.updateProfile(profile.copyWith(goal: v));
                      }
                    },
                  ),
                ),
                ListTile(
                  title: const Text('每周频率'),
                  trailing: DropdownButton<int>(
                    value: profile.weeklyFrequency,
                    underline: const SizedBox(),
                    dropdownColor: AppColors.bgSurface,
                    items: List.generate(6, (i) =>
                        DropdownMenuItem(value: i + 1, child: Text('${i + 1} 次/周'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        state.updateProfile(profile.copyWith(weeklyFrequency: v));
                      }
                    },
                  ),
                ),
                const Divider(),
                _sectionHeader(theme, '训练数据'),
                _infoTile(theme, 'BMR (基础代谢)', '${profile.bmr.round()} kcal'),
                _infoTile(theme, 'TDEE (每日消耗)', '${profile.tdee.round()} kcal'),
                const Divider(),
                _sectionHeader(theme, '外观'),
                ListTile(
                  title: const Text('主题模式'),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16)),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (v) => state.setThemeMode(v.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const Divider(),
                _sectionHeader(theme, '数据管理'),
                ListTile(
                  leading: const Icon(Icons.upload, color: AppColors.accent),
                  title: const Text('导出数据'),
                  subtitle: const Text('复制所有数据到剪贴板'),
                  onTap: () {
                    final jsonStr = state.exportToJson();
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('数据已复制到剪贴板')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download, color: AppColors.back),
                  title: const Text('导入数据'),
                  subtitle: const Text('从剪贴板粘贴导入'),
                  onTap: () => _importFromClipboard(context, state),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh, color: AppColors.warning),
                  title: const Text('重新设置个人信息'),
                  subtitle: const Text('回到初始设置页面，保留训练数据'),
                  onTap: () => _confirmAction(
                    context,
                    '重新设置',
                    '将返回初始设置页面重新填写个人信息。\n你的训练记录和成就不会丢失。',
                    () {
                      state.restartOnboarding();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: AppColors.danger),
                  title: const Text('清除所有数据', style: TextStyle(color: AppColors.danger)),
                  subtitle: const Text('删除个人信息、训练记录、成就等所有数据'),
                  onTap: () => _confirmAction(
                    context,
                    '清除所有数据',
                    '此操作不可恢复！所有训练记录、身体数据、成就都将被永久删除。',
                    () async {
                      await state.resetAllData();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    isDangerous: true,
                  ),
                ),
                const Divider(),
                _sectionHeader(theme, '关于'),
                _infoTile(theme, '版本', '1.0.0'),
                _infoTile(theme, '应用', 'FitForge 智能健身助手'),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  void _confirmAction(BuildContext context, String title, String message,
      VoidCallback onConfirm, {bool isDangerous = false}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(
              '确认',
              style: TextStyle(color: isDangerous ? AppColors.danger : null),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromClipboard(BuildContext context, AppState state) async {
    // 1) 读剪贴板
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    final jsonStr = clipData?.text?.trim();
    if (!context.mounted) return;
    if (jsonStr == null || jsonStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板为空')),
      );
      return;
    }

    // 2) 二次确认（导入会覆盖现有数据，危险操作）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: const Text(
          '导入将覆盖当前个人信息、训练计划、训练记录、身体数据和成就。\n\n此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导入', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // 3) 执行导入，展示结果（null=成功；非 null=错误消息）
    final error = state.importFromJson(jsonStr);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '导入成功')),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
        child: Text(text, style: theme.textTheme.labelMedium!.copyWith(color: AppColors.textTertiary)),
      );

  Widget _infoTile(ThemeData theme, String title, String value) => ListTile(
        title: Text(title),
        trailing: Text(value, style: theme.textTheme.bodySmall),
        dense: true,
      );
}

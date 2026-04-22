import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/brand/glow_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _step = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 表单数据
  Gender _gender = Gender.male;
  int _age = 25;
  double _heightCm = 170;
  double _weightKg = 70;
  FitnessGoal _goal = FitnessGoal.buildMuscle;
  int _weeklyFrequency = 4;
  ExperienceLevel _level = ExperienceLevel.beginner;
  final List<Equipment> _equipment = [
    Equipment.bodyweight,
    Equipment.dumbbell,
    Equipment.barbell,
    Equipment.bench,
  ];

  void _next() {
    if (_step < 7) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    }
  }

  void _prev() {
    if (_step > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step--);
    }
  }

  void _finish() {
    final profile = UserProfile(
      heightCm: _heightCm,
      weightKg: _weightKg,
      age: _age,
      gender: _gender,
      goal: _goal,
      weeklyFrequency: _weeklyFrequency,
      experienceLevel: _level,
      availableEquipment: _equipment,
    );
    context.read<AppState>().saveProfile(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 进度指示
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: LinearProgressIndicator(
                value: (_step + 1) / 8,
                borderRadius: AppRadius.brFull,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _welcomePage(),
                  _genderAgePage(),
                  _bodyPage(),
                  _goalPage(),
                  _frequencyPage(),
                  _levelPage(),
                  _equipmentPage(),
                  _summaryPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──── Step 0: 欢迎 ────
  Widget _welcomePage() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              gradient: AppColors.heatGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fitness_center,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('欢迎来到 FitForge', style: theme.textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.sm),
          Text('你的私人智能健身助手', style: theme.textTheme.bodyMedium),
          const Spacer(),
          GlowButton(label: '开始设置', onPressed: _next),
        ],
      ),
    );
  }

  // ──── Step 1: 性别年龄 ────
  Widget _genderAgePage() => _pageWrapper('基本信息', [
    Text('性别', style: Theme.of(context).textTheme.titleSmall),
    const SizedBox(height: AppSpacing.sm),
    Row(
      children: Gender.values
          .map(
            (g) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: _selectCard(
                  g.displayName,
                  _gender == g,
                  () => setState(() => _gender = g),
                ),
              ),
            ),
          )
          .toList(),
    ),
    const SizedBox(height: AppSpacing.lg),
    Text('年龄: $_age 岁', style: Theme.of(context).textTheme.titleSmall),
    Slider(
      value: _age.toDouble(),
      min: 14,
      max: 80,
      divisions: 66,
      label: '$_age',
      onChanged: (v) => setState(() => _age = v.round()),
    ),
  ]);

  // ──── Step 2: 身高体重 ────
  Widget _bodyPage() => _pageWrapper('身体数据', [
    Text(
      '身高: ${_heightCm.round()} cm',
      style: Theme.of(
        context,
      ).textTheme.headlineSmall!.copyWith(color: AppColors.primary),
    ),
    Slider(
      value: _heightCm,
      min: 140,
      max: 220,
      divisions: 80,
      onChanged: (v) => setState(() => _heightCm = v),
    ),
    const SizedBox(height: AppSpacing.md),
    Text(
      '体重: ${_weightKg.toStringAsFixed(1)} kg',
      style: Theme.of(
        context,
      ).textTheme.headlineSmall!.copyWith(color: AppColors.primary),
    ),
    Slider(
      value: _weightKg,
      min: 35,
      max: 150,
      divisions: 230,
      onChanged: (v) =>
          setState(() => _weightKg = double.parse(v.toStringAsFixed(1))),
    ),
  ]);

  // ──── Step 3: 目标 ────
  Widget _goalPage() => _pageWrapper('你的目标', [
    ...FitnessGoal.values.map(
      (g) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: _selectCard(
          '${g.icon}  ${g.displayName}',
          _goal == g,
          () => setState(() => _goal = g),
          height: 56,
        ),
      ),
    ),
  ]);

  // ──── Step 4: 频率 ────
  Widget _frequencyPage() => _pageWrapper('每周训练几次？', [
    ...List.generate(6, (i) {
      final freq = i + 1;
      final hint = freq <= 2 ? '推荐新手' : (freq <= 4 ? '推荐' : '高级');
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: _selectCard(
          '每周 $freq 次 ($hint)',
          _weeklyFrequency == freq,
          () => setState(() => _weeklyFrequency = freq),
          height: 48,
        ),
      );
    }),
  ]);

  // ──── Step 5: 经验等级 ────
  Widget _levelPage() => _pageWrapper('你的训练经验', [
    ...ExperienceLevel.values.map(
      (l) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: _selectCard(
          '${l.displayName} — ${l.description}',
          _level == l,
          () => setState(() => _level = l),
          height: 56,
        ),
      ),
    ),
  ]);

  // ──── Step 6: 器械 ────
  Widget _equipmentPage() => _pageWrapper('你有哪些器械？', [
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: Equipment.values.map((e) {
        final selected = _equipment.contains(e);
        return FilterChip(
          label: Text(e.displayName),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) {
              _equipment.add(e);
            } else {
              _equipment.remove(e);
            }
          }),
        );
      }).toList(),
    ),
  ]);

  // ──── Step 7: 总结 ────
  Widget _summaryPage() => _pageWrapper('一切就绪!', [
    _infoRow('性别', _gender.displayName),
    _infoRow('年龄', '$_age 岁'),
    _infoRow('身高', '${_heightCm.round()} cm'),
    _infoRow('体重', '${_weightKg.toStringAsFixed(1)} kg'),
    _infoRow('目标', _goal.displayName),
    _infoRow('频率', '每周 $_weeklyFrequency 次'),
    _infoRow('经验', _level.displayName),
    _infoRow('器械', '${_equipment.length} 种'),
    const SizedBox(height: AppSpacing.lg),
    GlowButton(
      label: '开始训练',
      icon: Icons.play_arrow_rounded,
      onPressed: _finish,
    ),
  ], showNav: false);

  // ──── 辅助组件 ────

  Widget _pageWrapper(
    String title,
    List<Widget> children, {
    bool showNav = true,
  }) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
          ...children,
          if (showNav) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _prev,
                      child: const Text('上一步'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: AppSpacing.cardGap),
                Expanded(
                  child: GlowButton(label: '下一步', onPressed: _next),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _selectCard(
    String text,
    bool isSelected,
    VoidCallback onTap, {
    double height = 64,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : (isDark ? AppColors.bgElevated : AppColors.bgBaseLight),
          borderRadius: AppRadius.brMd,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 0.5,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.primary : null,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

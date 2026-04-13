import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/app_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _step = 0;

  // 表单数据
  Gender _gender = Gender.male;
  int _age = 25;
  double _heightCm = 170;
  double _weightKg = 70;
  FitnessGoal _goal = FitnessGoal.buildMuscle;
  int _weeklyFrequency = 4;
  ExperienceLevel _level = ExperienceLevel.beginner;
  List<Equipment> _equipment = [Equipment.bodyweight, Equipment.dumbbell, Equipment.barbell, Equipment.bench];

  void _next() {
    if (_step < 7) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _step++);
    }
  }

  void _prev() {
    if (_step > 0) {
      _controller.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: LinearProgressIndicator(
                value: (_step + 1) / 8,
                backgroundColor: Colors.grey[200],
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
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
  Widget _welcomePage() => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fitness_center, size: 80, color: Colors.orange),
            const SizedBox(height: 24),
            const Text('欢迎来到 FitForge', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('你的私人智能健身助手', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const Spacer(),
            _primaryButton('开始设置', _next),
          ],
        ),
      );

  // ──── Step 1: 性别年龄 ────
  Widget _genderAgePage() => _pageWrapper('基本信息', [
        const Text('性别', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: Gender.values.map((g) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _selectCard(g.displayName, _gender == g, () => setState(() => _gender = g)),
                ),
              )).toList(),
        ),
        const SizedBox(height: 24),
        Text('年龄: $_age 岁', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Slider(
          value: _age.toDouble(), min: 14, max: 80, divisions: 66,
          activeColor: Colors.orange,
          label: '$_age',
          onChanged: (v) => setState(() => _age = v.round()),
        ),
      ]);

  // ──── Step 2: 身高体重 ────
  Widget _bodyPage() => _pageWrapper('身体数据', [
        Text('身高: ${_heightCm.round()} cm',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
        Slider(
          value: _heightCm, min: 140, max: 220, divisions: 80,
          activeColor: Colors.orange,
          onChanged: (v) => setState(() => _heightCm = v),
        ),
        const SizedBox(height: 16),
        Text('体重: ${_weightKg.toStringAsFixed(1)} kg',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
        Slider(
          value: _weightKg, min: 35, max: 150, divisions: 230,
          activeColor: Colors.orange,
          onChanged: (v) => setState(() => _weightKg = double.parse(v.toStringAsFixed(1))),
        ),
      ]);

  // ──── Step 3: 目标 ────
  Widget _goalPage() => _pageWrapper('你的目标', [
        ...FitnessGoal.values.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _selectCard(
                '${g.icon}  ${g.displayName}',
                _goal == g,
                () => setState(() => _goal = g),
                height: 56,
              ),
            )),
      ]);

  // ──── Step 4: 频率 ────
  Widget _frequencyPage() => _pageWrapper('每周训练几次？', [
        ...List.generate(6, (i) {
          final freq = i + 1;
          final hint = freq <= 2 ? '推荐新手' : (freq <= 4 ? '推荐' : '高级');
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
        ...ExperienceLevel.values.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _selectCard(
                '${l.displayName} — ${l.description}',
                _level == l,
                () => setState(() => _level = l),
                height: 56,
              ),
            )),
      ]);

  // ──── Step 6: 器械 ────
  Widget _equipmentPage() => _pageWrapper('你有哪些器械？', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Equipment.values.map((e) {
            final selected = _equipment.contains(e);
            return FilterChip(
              label: Text(e.displayName),
              selected: selected,
              selectedColor: Colors.orange.shade100,
              checkmarkColor: Colors.orange,
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
        const SizedBox(height: 24),
        _primaryButton('开始训练', _finish),
      ], showNav: false);

  // ──── 辅助组件 ────

  Widget _pageWrapper(String title, List<Widget> children, {bool showNav = true}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ...children,
          if (showNav) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _prev,
                      child: const Text('上一步'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(child: _primaryButton('下一步', _next)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _selectCard(String text, bool isSelected, VoidCallback onTap, {double height = 64}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.shade50 : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.orange : Colors.transparent, width: 2),
        ),
        child: Text(text, style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.orange.shade800 : null,
        )),
      ),
    );
  }

  Widget _primaryButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_radius.dart';
import '../../widgets/cards/section_card.dart';

class BodyMetricsScreen extends StatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  State<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends State<BodyMetricsScreen> {
  String _metricType = 'weight';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = context.watch<AppState>().bodyMetrics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据追踪'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 指标选择
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'weight', label: Text('体重')),
                ButtonSegment(value: 'bodyFat', label: Text('体脂')),
                ButtonSegment(value: 'waist', label: Text('腰围')),
                ButtonSegment(value: 'arm', label: Text('臂围')),
              ],
              selected: {_metricType},
              onSelectionChanged: (v) => setState(() => _metricType = v.first),
            ),
            const SizedBox(height: AppSpacing.md),

            // 图表
            _chartSection(theme, metrics),
            const SizedBox(height: AppSpacing.lg),

            // 历史列表
            Text('记录历史', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ...metrics
                .take(20)
                .map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SectionCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        children: [
                          Text(
                            '${m.date.month}/${m.date.day}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const Spacer(),
                          if (m.weightKg != null)
                            _badge(theme, '${m.weightKg}kg'),
                          if (m.bodyFatPercentage != null)
                            _badge(theme, '${m.bodyFatPercentage}%'),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _chartSection(ThemeData theme, List<BodyMetric> metrics) {
    final points = metrics.reversed
        .map((m) {
          double? val;
          switch (_metricType) {
            case 'weight':
              val = m.weightKg;
            case 'bodyFat':
              val = m.bodyFatPercentage;
            case 'waist':
              val = m.waistCm;
            case 'arm':
              val = m.armCm;
          }
          return val != null
              ? FlSpot(m.date.millisecondsSinceEpoch.toDouble(), val)
              : null;
        })
        .whereType<FlSpot>()
        .toList();

    if (points.isEmpty) {
      return SectionCard(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxl,
          horizontal: AppSpacing.md,
        ),
        child: Center(
          child: Text('暂无数据，请先记录', style: theme.textTheme.bodySmall),
        ),
      );
    }

    return SectionCard(
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.bgSurface,
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: points,
                isCurved: true,
                color: AppColors.primary,
                barWidth: 3,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                        radius: 3,
                        color: AppColors.primary,
                        strokeColor: AppColors.bgElevated,
                        strokeWidth: 2,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.2),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(ThemeData theme, String text) {
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: AppRadius.brSm,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMetricSheet(
        onSave: (metric) {
          context.read<AppState>().addBodyMetric(metric);
        },
      ),
    );
  }
}

/// 独立 StatefulWidget，确保 4 个 TextEditingController 被正确 dispose。
class _AddMetricSheet extends StatefulWidget {
  const _AddMetricSheet({required this.onSave});
  final ValueChanged<BodyMetric> onSave;

  @override
  State<_AddMetricSheet> createState() => _AddMetricSheetState();
}

class _AddMetricSheetState extends State<_AddMetricSheet> {
  static const _uuid = Uuid();
  final _formKey = GlobalKey<FormState>();
  final _weightCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _armCtrl = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _fatCtrl.dispose();
    _waistCtrl.dispose();
    _armCtrl.dispose();
    super.dispose();
  }

  bool get _hasAnyValue =>
      _weightCtrl.text.isNotEmpty ||
      _fatCtrl.text.isNotEmpty ||
      _waistCtrl.text.isNotEmpty ||
      _armCtrl.text.isNotEmpty;

  String? _validateRange(String? value, double min, double max, String unit) {
    if (value == null || value.isEmpty) return null; // optional
    final v = double.tryParse(value);
    if (v == null) return '请输入有效数字';
    if (v < min || v > max) return '范围: $min-$max $unit';
    return null;
  }

  void _save() {
    if (!_hasAnyValue) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少填写一项数据')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final metric = BodyMetric(
      id: _uuid.v4(),
      weightKg: double.tryParse(_weightCtrl.text),
      bodyFatPercentage: double.tryParse(_fatCtrl.text),
      waistCm: double.tryParse(_waistCtrl.text),
      armCm: double.tryParse(_armCtrl.text),
    );
    widget.onSave(metric);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('记录身体数据', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            _input('体重 (kg)', _weightCtrl, 30, 300, 'kg'),
            _input('体脂率 (%)', _fatCtrl, 3, 60, '%'),
            _input('腰围 (cm)', _waistCtrl, 40, 200, 'cm'),
            _input('臂围 (cm)', _armCtrl, 15, 60, 'cm'),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController ctrl,
    double min,
    double max,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        validator: (v) => _validateRange(v, min, max, unit),
      ),
    );
  }
}

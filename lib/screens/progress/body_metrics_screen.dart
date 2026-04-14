import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/app_state.dart';

class BodyMetricsScreen extends StatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  State<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends State<BodyMetricsScreen> {
  String _metricType = 'weight';
  static const _uuid = Uuid();

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<AppState>().bodyMetrics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据追踪'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddDialog(context))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? Colors.orange : null),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? Colors.white : null),
            ),
          ),
          const SizedBox(height: 16),

          // 图表
          _chartSection(metrics),
          const SizedBox(height: 16),

          // 历史列表
          const Text('记录历史', style: TextStyle(fontWeight: FontWeight.bold)),
          ...metrics.take(20).map((m) => Card(
                elevation: 0, color: Colors.grey[100],
                margin: const EdgeInsets.only(top: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Text('${m.date.month}/${m.date.day}', style: TextStyle(color: Colors.grey[600])),
                    const Spacer(),
                    if (m.weightKg != null) _badge('${m.weightKg}kg'),
                    if (m.bodyFatPercentage != null) _badge('${m.bodyFatPercentage}%'),
                  ]),
                ),
              )),
        ]),
      ),
    );
  }

  Widget _chartSection(List<BodyMetric> metrics) {
    final points = metrics.reversed.map((m) {
      double? val;
      switch (_metricType) {
        case 'weight': val = m.weightKg;
        case 'bodyFat': val = m.bodyFatPercentage;
        case 'waist': val = m.waistCm;
        case 'arm': val = m.armCm;
      }
      return val != null ? FlSpot(m.date.millisecondsSinceEpoch.toDouble(), val) : null;
    }).whereType<FlSpot>().toList();

    if (points.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        child: Text('暂无数据，请先记录', style: TextStyle(color: Colors.grey[500])),
      );
    }

    return SizedBox(
      height: 200,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            color: Colors.orange,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: Colors.orange.withValues(alpha: 0.1)),
          ),
        ],
      )),
    );
  }

  Widget _badge(String text) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  void _showAddDialog(BuildContext context) {
    final weightCtrl = TextEditingController();
    final fatCtrl = TextEditingController();
    final waistCtrl = TextEditingController();
    final armCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('记录身体数据', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _input('体重 (kg)', weightCtrl),
          _input('体脂率 (%)', fatCtrl),
          _input('腰围 (cm)', waistCtrl),
          _input('臂围 (cm)', armCtrl),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              onPressed: () {
                final metric = BodyMetric(
                  id: _uuid.v4(),
                  weightKg: double.tryParse(weightCtrl.text),
                  bodyFatPercentage: double.tryParse(fatCtrl.text),
                  waistCm: double.tryParse(waistCtrl.text),
                  armCm: double.tryParse(armCtrl.text),
                );
                context.read<AppState>().addBodyMetric(metric);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _input(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

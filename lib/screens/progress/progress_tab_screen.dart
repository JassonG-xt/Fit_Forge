import 'package:flutter/material.dart';
import 'body_metrics_screen.dart';
import 'calendar_screen.dart';
import 'achievements_screen.dart';

class ProgressTabScreen extends StatelessWidget {
  const ProgressTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('进度追踪')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _navCard(context, '身体数据', '记录体重、体脂、围度变化',
              Icons.show_chart, Colors.cyan, const BodyMetricsScreen()),
          _navCard(context, '训练日历', '查看训练历史和安排',
              Icons.calendar_month, Colors.blue, const CalendarScreen()),
          _navCard(context, '成就', '你的健身里程碑',
              Icons.emoji_events, Colors.orange, const AchievementsScreen()),
        ],
      ),
    );
  }

  Widget _navCard(BuildContext ctx, String title, String subtitle, IconData icon, Color color, Widget screen) {
    return Card(
      elevation: 0, color: Colors.grey[100],
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}

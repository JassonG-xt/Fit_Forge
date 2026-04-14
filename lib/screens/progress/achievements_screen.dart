import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final achievements = context.watch<AppState>().achievements;
    return Scaffold(
      appBar: AppBar(title: const Text('成就')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
        children: achievements.map((a) => _card(a)).toList(),
      ),
    );
  }

  Widget _card(Achievement achievement) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: achievement.isUnlocked ? Colors.orange : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(achievement.icon, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(height: 8),
        Text(achievement.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center),
        Text(achievement.description,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        if (!achievement.isUnlocked) ...[
          LinearProgressIndicator(
            value: achievement.progressPercentage,
            backgroundColor: Colors.grey[300],
            color: Colors.orange,
            borderRadius: BorderRadius.circular(4),
          ),
          Text('${achievement.currentProgress}/${achievement.threshold}',
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ] else
          Text('已解锁', style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

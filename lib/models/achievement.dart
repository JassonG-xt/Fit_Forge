import 'enums.dart';

/// 成就
class Achievement {
  final String id;
  final AchievementType type;
  final String title;
  final String description;
  final String icon;
  final int threshold;
  int currentProgress;
  bool isUnlocked;
  DateTime? unlockedAt;

  Achievement({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.threshold,
    this.currentProgress = 0,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  double get progressPercentage {
    if (threshold <= 0) return 0;
    return (currentProgress / threshold).clamp(0.0, 1.0);
  }

  void unlock() {
    isUnlocked = true;
    unlockedAt = DateTime.now();
    currentProgress = threshold;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description,
        'icon': icon,
        'threshold': threshold,
        'currentProgress': currentProgress,
        'isUnlocked': isUnlocked,
        'unlockedAt': unlockedAt?.toIso8601String(),
      };

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
        id: json['id'] as String,
        type: AchievementType.values.byName(json['type'] as String),
        title: json['title'] as String,
        description: json['description'] as String,
        icon: json['icon'] as String,
        threshold: json['threshold'] as int,
        currentProgress: json['currentProgress'] as int? ?? 0,
        isUnlocked: json['isUnlocked'] as bool? ?? false,
        unlockedAt: json['unlockedAt'] != null
            ? DateTime.parse(json['unlockedAt'] as String)
            : null,
      );
}

/// 预置成就列表
List<Achievement> defaultAchievements() => [
      Achievement(id: 'a01', type: AchievementType.streak, title: '初试牛刀', description: '连续训练 3 天', icon: '🔥', threshold: 3),
      Achievement(id: 'a02', type: AchievementType.streak, title: '坚持不懈', description: '连续训练 7 天', icon: '🔥', threshold: 7),
      Achievement(id: 'a03', type: AchievementType.streak, title: '习惯养成', description: '连续训练 21 天', icon: '⭐', threshold: 21),
      Achievement(id: 'a04', type: AchievementType.streak, title: '铁人意志', description: '连续训练 30 天', icon: '👑', threshold: 30),
      Achievement(id: 'a05', type: AchievementType.totalWorkouts, title: '起步了', description: '累计完成 10 次训练', icon: '🚶', threshold: 10),
      Achievement(id: 'a06', type: AchievementType.totalWorkouts, title: '训练达人', description: '累计完成 50 次训练', icon: '🏃', threshold: 50),
      Achievement(id: 'a07', type: AchievementType.totalWorkouts, title: '健身战士', description: '累计完成 100 次训练', icon: '💪', threshold: 100),
      Achievement(id: 'a08', type: AchievementType.personalRecord, title: '突破自我', description: '第一次打破个人记录', icon: '⚡', threshold: 1),
      Achievement(id: 'a09', type: AchievementType.personalRecord, title: '记录粉碎机', description: '打破 10 次个人记录', icon: '⚡', threshold: 10),
    ];

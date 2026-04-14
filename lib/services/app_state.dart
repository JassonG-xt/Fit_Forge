import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../engines/plan_engine.dart';

/// 全局应用状态（Provider ChangeNotifier）
class AppState extends ChangeNotifier {
  // ──── 状态 ────
  UserProfile? _profile;
  List<Exercise> _exercises = [];
  WorkoutPlan? _activePlan;
  List<WorkoutSession> _sessions = [];
  List<BodyMetric> _bodyMetrics = [];
  List<Achievement> _achievements = [];
  bool _hasCompletedOnboarding = false;

  // ──── Getters ────
  UserProfile? get profile => _profile;
  List<Exercise> get exercises => _exercises;
  WorkoutPlan? get activePlan => _activePlan;
  List<WorkoutSession> get sessions => _sessions;
  List<BodyMetric> get bodyMetrics => _bodyMetrics;
  List<Achievement> get achievements => _achievements;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  List<WorkoutSession> get completedSessions =>
      _sessions.where((s) => s.isCompleted).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  int get streakDays {
    var streak = 0;
    var checkDate = DateTime.now();
    checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day);

    for (final session in completedSessions) {
      final sessionDay = DateTime(session.date.year, session.date.month, session.date.day);
      if (sessionDay == checkDate) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (sessionDay.isBefore(checkDate)) {
        break;
      }
    }
    return streak;
  }

  int get totalWorkoutsThisWeek {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    return completedSessions.where((s) => s.date.isAfter(start)).length;
  }

  // ──── 初始化 ────
  Future<void> init() async {
    await _loadExercises();
    await _loadFromPrefs();
    if (_achievements.isEmpty) {
      _achievements = defaultAchievements();
    }
  }

  Future<void> _loadExercises() async {
    final jsonStr = await rootBundle.loadString('assets/data/exercise_library.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    _exercises = (data['exercises'] as List)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ──── 用户画像 ────
  void saveProfile(UserProfile profile) {
    _profile = profile;
    _hasCompletedOnboarding = true;
    notifyListeners();
    _persist();
  }

  void updateProfile(UserProfile profile) {
    _profile = profile;
    notifyListeners();
    _persist();
  }

  // ──── 训练计划 ────

  /// 生成计划预览，不修改状态、不持久化。
  /// 用户确认后再调用 adoptPlan()。
  WorkoutPlan previewPlan() {
    if (_profile == null) throw StateError('Profile not set');
    return PlanEngine.generatePlan(_profile!, _exercises);
  }

  void adoptPlan(WorkoutPlan plan) {
    _activePlan = plan;
    notifyListeners();
    _persist();
  }

  /// 获取今日训练日
  WorkoutDay? get todayWorkout {
    if (_activePlan == null) return null;
    final weekday = DateTime.now().weekday; // 1=Monday
    try {
      final day = _activePlan!.days.firstWhere(
          (d) => d.dayOfWeek == weekday && d.dayType != WorkoutDayType.rest);
      return day;
    } catch (_) {
      return null;
    }
  }

  // ──── 训练记录 ────
  void saveSession(WorkoutSession session) {
    _sessions.add(session);
    _updateAchievements(session);
    notifyListeners();
    _persist();
  }

  // ──── 身体数据 ────
  void addBodyMetric(BodyMetric metric) {
    _bodyMetrics.add(metric);
    _bodyMetrics.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    _persist();
  }

  // ──── 成就 ────
  void _updateAchievements(WorkoutSession latestSession) {
    final totalCompleted = completedSessions.length;
    final streak = streakDays;

    // 计算本次训练中有多少个 PR（个人记录突破）
    final newPRCount = _countPersonalRecords(latestSession);

    for (final a in _achievements) {
      if (a.isUnlocked) continue;
      switch (a.type) {
        case AchievementType.streak:
          a.currentProgress = streak;
          if (streak >= a.threshold) a.unlock();
        case AchievementType.totalWorkouts:
          a.currentProgress = totalCompleted;
          if (totalCompleted >= a.threshold) a.unlock();
        case AchievementType.personalRecord:
          if (newPRCount > 0) {
            a.currentProgress += newPRCount;
            if (a.currentProgress >= a.threshold) a.unlock();
          }
        default:
          break;
      }
    }
  }

  /// 对比本次训练中每个动作的最大单组重量 vs 历史最高
  int _countPersonalRecords(WorkoutSession session) {
    var prCount = 0;
    for (final record in session.exerciseRecords) {
      final currentMax = record.sets
          .where((s) => s.isCompleted && s.weightKg > 0)
          .fold<double>(0, (max, s) => s.weightKg > max ? s.weightKg : max);
      if (currentMax <= 0) continue;

      // 在历史记录中查找该动作的最高重量
      double historicalMax = 0;
      for (final oldSession in _sessions) {
        if (oldSession.id == session.id) continue;
        for (final oldRecord in oldSession.exerciseRecords) {
          if (oldRecord.exerciseId == record.exerciseId) {
            for (final s in oldRecord.sets) {
              if (s.isCompleted && s.weightKg > historicalMax) {
                historicalMax = s.weightKg;
              }
            }
          }
        }
      }

      if (currentMax > historicalMax && historicalMax > 0) {
        prCount++;
      }
    }
    return prCount;
  }

  // ──── 持久化 ────
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_profile != null) {
      prefs.setString('profile', json.encode(_profile!.toJson()));
    }
    if (_activePlan != null) {
      prefs.setString('activePlan', json.encode(_activePlan!.toJson()));
    }
    prefs.setString('sessions', json.encode(_sessions.map((s) => s.toJson()).toList()));
    prefs.setString('bodyMetrics', json.encode(_bodyMetrics.map((m) => m.toJson()).toList()));
    prefs.setString('achievements', json.encode(_achievements.map((a) => a.toJson()).toList()));
    prefs.setBool('hasCompletedOnboarding', _hasCompletedOnboarding);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _hasCompletedOnboarding = prefs.getBool('hasCompletedOnboarding') ?? false;

    final profileStr = prefs.getString('profile');
    if (profileStr != null) {
      _profile = UserProfile.fromJson(json.decode(profileStr));
    }

    final planStr = prefs.getString('activePlan');
    if (planStr != null) {
      _activePlan = WorkoutPlan.fromJson(json.decode(planStr));
    }

    final sessionsStr = prefs.getString('sessions');
    if (sessionsStr != null) {
      _sessions = (json.decode(sessionsStr) as List)
          .map((s) => WorkoutSession.fromJson(s))
          .toList();
    }

    final metricsStr = prefs.getString('bodyMetrics');
    if (metricsStr != null) {
      _bodyMetrics = (json.decode(metricsStr) as List)
          .map((m) => BodyMetric.fromJson(m))
          .toList();
    }

    final achievementsStr = prefs.getString('achievements');
    if (achievementsStr != null) {
      _achievements = (json.decode(achievementsStr) as List)
          .map((a) => Achievement.fromJson(a))
          .toList();
    }

    notifyListeners();
  }
}

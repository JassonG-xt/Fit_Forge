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
  List<Food> _foods = [];
  WorkoutPlan? _activePlan;
  List<WorkoutSession> _sessions = [];
  List<BodyMetric> _bodyMetrics = [];
  List<Achievement> _achievements = [];
  bool _hasCompletedOnboarding = false;
  ThemeMode _themeMode = ThemeMode.dark;

  // ──── 缓存 ────
  List<WorkoutSession>? _completedSessionsCache;

  /// 每个动作的历史最高单组重量。
  /// key = exerciseId, value = max weightKg。
  /// 在 _loadFromPrefs 后重建，saveSession 时增量更新。
  final Map<String, double> _prCache = {};

  // ──── Getters ────
  UserProfile? get profile => _profile;
  List<Exercise> get exercises => _exercises;
  List<Food> get foods => _foods;
  WorkoutPlan? get activePlan => _activePlan;
  List<WorkoutSession> get sessions => _sessions;
  List<BodyMetric> get bodyMetrics => _bodyMetrics;
  List<Achievement> get achievements => _achievements;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  ThemeMode get themeMode => _themeMode;

  /// 已完成的训练记录（按日期降序），带缓存。
  List<WorkoutSession> get completedSessions {
    return _completedSessionsCache ??= _sessions
        .where((s) => s.isCompleted)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  int get streakDays {
    var streak = 0;
    var checkDate = DateTime.now();
    checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day);

    // If no workout today, check if yesterday had one — don't break streak at midnight.
    final hasTodayWorkout = completedSessions.any((s) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      return d == checkDate;
    });
    if (!hasTodayWorkout) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

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
    await _loadFoods();
    await _loadFromPrefs();
    _rebuildPrCache();
    if (_achievements.isEmpty) {
      _achievements = defaultAchievements();
    }
    await checkForRecoverableSession();
  }

  Future<void> _loadExercises() async {
    final jsonStr = await rootBundle.loadString('assets/data/exercise_library.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    _exercises = (data['exercises'] as List)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadFoods() async {
    final jsonStr = await rootBundle.loadString('assets/data/food_database.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    _foods = (data['foods'] as List)
        .map((f) => Food.fromJson(f as Map<String, dynamic>))
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

  // ──── 主题 ────
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _persist();
  }

  // ──── 重置 ────
  Future<void> resetAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _profile = null;
    _activePlan = null;
    _sessions = [];
    _bodyMetrics = [];
    _achievements = defaultAchievements();
    _hasCompletedOnboarding = false;
    _themeMode = ThemeMode.dark;
    _invalidateCompletedCache();
    _prCache.clear();
    notifyListeners();
  }

  void restartOnboarding() {
    _hasCompletedOnboarding = false;
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
    _invalidateCompletedCache();
    // Snapshot PR cache before update to detect new PRs
    final prSnapshot = Map<String, double>.from(_prCache);
    _updatePrCache(session);
    final newPRCount = _countNewPRs(session, prSnapshot);
    _updateAchievements(session, newPRCount);
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

  // ──── 历史查询（用于训练预填充）────

  /// 返回该动作上次使用的重量，若无历史返回 0。
  double lastWeightForExercise(String exerciseId) {
    for (final session in completedSessions) {
      for (final record in session.exerciseRecords) {
        if (record.exerciseId == exerciseId) {
          final completedSets = record.sets.where((s) => s.isCompleted && s.weightKg > 0);
          if (completedSets.isNotEmpty) return completedSets.first.weightKg;
        }
      }
    }
    return 0;
  }

  /// 返回该动作上次使用的次数，若无历史返回 0。
  int lastRepsForExercise(String exerciseId) {
    for (final session in completedSessions) {
      for (final record in session.exerciseRecords) {
        if (record.exerciseId == exerciseId) {
          final completedSets = record.sets.where((s) => s.isCompleted && s.reps > 0);
          if (completedSets.isNotEmpty) return completedSets.first.reps;
        }
      }
    }
    return 0;
  }

  // ──── 缓存管理 ────

  void _invalidateCompletedCache() {
    _completedSessionsCache = null;
  }

  /// 从全量历史重建 PR cache。仅在 init 时调用一次。
  void _rebuildPrCache() {
    _prCache.clear();
    for (final session in _sessions) {
      _updatePrCache(session);
    }
  }

  /// 增量更新：扫描 session 里每组完成数据，更新各动作的最高重量。
  void _updatePrCache(WorkoutSession session) {
    for (final record in session.exerciseRecords) {
      for (final s in record.sets) {
        if (!s.isCompleted || s.weightKg <= 0) continue;
        final current = _prCache[record.exerciseId] ?? 0;
        if (s.weightKg > current) {
          _prCache[record.exerciseId] = s.weightKg;
        }
      }
    }
  }

  // ──── 成就 ────
  void _updateAchievements(WorkoutSession latestSession, int newPRCount) {
    final totalCompleted = completedSessions.length;
    final streak = streakDays;

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
        case AchievementType.bodyPartMastery:
          // Count sessions targeting any body part in this achievement's tracked group.
          // Use the session dayType -> targetBodyParts mapping.
          final targetParts = latestSession.dayType.targetBodyParts;
          if (targetParts.isNotEmpty) {
            // Each completed session that hits a muscle group counts as 1 toward mastery.
            // Count all historical sessions for this body part group.
            final bodyPartSessions = completedSessions.where((s) =>
                s.dayType.targetBodyParts.any((bp) => targetParts.contains(bp))).length;
            a.currentProgress = bodyPartSessions;
            if (bodyPartSessions >= a.threshold) a.unlock();
          }
        case AchievementType.nutritionStreak:
          // Nutrition tracking not yet implemented; skip silently.
          break;
      }
    }
  }

  /// Compares each exercise's max weight in the session against the
  /// pre-update snapshot. O(exercises * sets) — no nested session loop.
  int _countNewPRs(WorkoutSession session, Map<String, double> prSnapshot) {
    var count = 0;
    for (final record in session.exerciseRecords) {
      final sessionMax = record.sets
          .where((s) => s.isCompleted && s.weightKg > 0)
          .fold<double>(0, (max, s) => s.weightKg > max ? s.weightKg : max);
      if (sessionMax <= 0) continue;
      final oldMax = prSnapshot[record.exerciseId] ?? 0;
      if (oldMax > 0 && sessionMax > oldMax) count++;
    }
    return count;
  }

  // ──── 持久化 ────
  static const _kProfile = 'profile';
  static const _kActivePlan = 'activePlan';
  static const _kSessions = 'sessions';
  static const _kBodyMetrics = 'bodyMetrics';
  static const _kAchievements = 'achievements';
  static const _kOnboarding = 'hasCompletedOnboarding';
  static const _kThemeMode = 'themeMode';
  static const _kInProgressSession = 'inProgressSession';

  bool _persistScheduled = false;

  Future<void> _persist() async {
    // Debounce: collapse rapid successive writes into one.
    if (_persistScheduled) return;
    _persistScheduled = true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _persistScheduled = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_profile != null) {
        await prefs.setString(_kProfile, json.encode(_profile!.toJson()));
      }
      if (_activePlan != null) {
        await prefs.setString(_kActivePlan, json.encode(_activePlan!.toJson()));
      }
      await prefs.setString(_kSessions, json.encode(_sessions.map((s) => s.toJson()).toList()));
      await prefs.setString(_kBodyMetrics, json.encode(_bodyMetrics.map((m) => m.toJson()).toList()));
      await prefs.setString(_kAchievements, json.encode(_achievements.map((a) => a.toJson()).toList()));
      await prefs.setBool(_kOnboarding, _hasCompletedOnboarding);
      await prefs.setString(_kThemeMode, _themeMode.name);
    } catch (e) {
      debugPrint('FitForge: persist failed: $e');
    }
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _hasCompletedOnboarding = prefs.getBool(_kOnboarding) ?? false;

    final themeModeStr = prefs.getString(_kThemeMode);
    if (themeModeStr != null) {
      _themeMode = ThemeMode.values.where((m) => m.name == themeModeStr).firstOrNull ?? ThemeMode.dark;
    }

    final profileStr = prefs.getString(_kProfile);
    if (profileStr != null) {
      _profile = UserProfile.fromJson(json.decode(profileStr) as Map<String, dynamic>);
    }

    final planStr = prefs.getString(_kActivePlan);
    if (planStr != null) {
      _activePlan = WorkoutPlan.fromJson(json.decode(planStr) as Map<String, dynamic>);
    }

    final sessionsStr = prefs.getString(_kSessions);
    if (sessionsStr != null) {
      _sessions = (json.decode(sessionsStr) as List)
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    final metricsStr = prefs.getString(_kBodyMetrics);
    if (metricsStr != null) {
      _bodyMetrics = (json.decode(metricsStr) as List)
          .map((m) => BodyMetric.fromJson(m as Map<String, dynamic>))
          .toList();
    }

    final achievementsStr = prefs.getString(_kAchievements);
    if (achievementsStr != null) {
      _achievements = (json.decode(achievementsStr) as List)
          .map((a) => Achievement.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    notifyListeners();
  }

  // ──── 训练崩溃恢复 ────

  /// 保存进行中的训练状态，用于崩溃恢复。
  Future<void> saveInProgressSession(Map<String, dynamic> sessionData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInProgressSession, json.encode(sessionData));
  }

  /// 读取崩溃前保存的训练状态，返回 null 表示没有。
  Future<Map<String, dynamic>?> loadInProgressSession() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kInProgressSession);
    if (str == null) return null;
    return json.decode(str) as Map<String, dynamic>;
  }

  /// 清除进行中的训练状态（训练完成或用户放弃恢复时调用）。
  Future<void> clearInProgressSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kInProgressSession);
  }

  /// 是否有未完成的训练可恢复。
  bool _hasRecoverableSession = false;
  Map<String, dynamic>? _recoverableSessionData;

  bool get hasRecoverableSession => _hasRecoverableSession;
  Map<String, dynamic>? get recoverableSessionData => _recoverableSessionData;

  Future<void> checkForRecoverableSession() async {
    _recoverableSessionData = await loadInProgressSession();
    _hasRecoverableSession = _recoverableSessionData != null;
    notifyListeners();
  }

  void dismissRecoverableSession() {
    _hasRecoverableSession = false;
    _recoverableSessionData = null;
    clearInProgressSession();
    notifyListeners();
  }

  // ──── 数据导出/导入 ────

  /// Exports all user data as a JSON string.
  String exportToJson() {
    final data = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': _profile?.toJson(),
      'activePlan': _activePlan?.toJson(),
      'sessions': _sessions.map((s) => s.toJson()).toList(),
      'bodyMetrics': _bodyMetrics.map((m) => m.toJson()).toList(),
      'achievements': _achievements.map((a) => a.toJson()).toList(),
      'themeMode': _themeMode.name,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Imports user data from a JSON string. Returns error message or null on success.
  String? importFromJson(String jsonStr) {
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      if (data['version'] == null) return '无效的导出文件格式';

      if (data['profile'] != null) {
        _profile = UserProfile.fromJson(data['profile'] as Map<String, dynamic>);
        _hasCompletedOnboarding = true;
      }
      if (data['activePlan'] != null) {
        _activePlan = WorkoutPlan.fromJson(data['activePlan'] as Map<String, dynamic>);
      }
      if (data['sessions'] != null) {
        _sessions = (data['sessions'] as List)
            .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
            .toList();
      }
      if (data['bodyMetrics'] != null) {
        _bodyMetrics = (data['bodyMetrics'] as List)
            .map((m) => BodyMetric.fromJson(m as Map<String, dynamic>))
            .toList();
      }
      if (data['achievements'] != null) {
        _achievements = (data['achievements'] as List)
            .map((a) => Achievement.fromJson(a as Map<String, dynamic>))
            .toList();
      }
      if (data['themeMode'] != null) {
        _themeMode = ThemeMode.values
            .where((m) => m.name == data['themeMode'])
            .firstOrNull ?? ThemeMode.dark;
      }

      _invalidateCompletedCache();
      _rebuildPrCache();
      notifyListeners();
      _persist();
      return null;
    } catch (e) {
      return '导入失败: $e';
    }
  }
}

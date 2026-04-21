import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../engines/plan_engine.dart';
import 'app_state_store.dart';
import 'session_queries.dart';

/// 全局应用状态（Provider ChangeNotifier）
class AppState extends ChangeNotifier {
  AppState({AppStateStore store = const AppStateStore()}) : _store = store;

  final AppStateStore _store;

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
  List<Exercise> get exercises => UnmodifiableListView(_exercises);
  List<Food> get foods => UnmodifiableListView(_foods);
  WorkoutPlan? get activePlan => _activePlan;
  List<WorkoutSession> get sessions => UnmodifiableListView(_sessions);
  List<BodyMetric> get bodyMetrics => UnmodifiableListView(_bodyMetrics);
  List<Achievement> get achievements => UnmodifiableListView(_achievements);
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  ThemeMode get themeMode => _themeMode;

  /// 已完成的训练记录（按日期降序），带缓存。
  List<WorkoutSession> get completedSessions {
    return UnmodifiableListView(
      _completedSessionsCache ??= SessionQueries.completedSessions(_sessions),
    );
  }

  int get streakDays => SessionQueries.streakDays(completedSessions);

  int get totalWorkoutsThisWeek =>
      SessionQueries.totalWorkoutsThisWeek(completedSessions);

  List<double> weekActivityForCurrentWeek({DateTime? now}) =>
      SessionQueries.weekActivity(completedSessions, now: now);

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
    final jsonStr = await rootBundle.loadString(
      'assets/data/exercise_library.json',
    );
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    _exercises = (data['exercises'] as List)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadFoods() async {
    final jsonStr = await rootBundle.loadString(
      'assets/data/food_database.json',
    );
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
    await _store.clear();
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
        (d) => d.dayOfWeek == weekday && d.dayType != WorkoutDayType.rest,
      );
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
    _updateAchievements(newPRCount);
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
    return SessionQueries.lastWeightForExercise(completedSessions, exerciseId);
  }

  /// 返回该动作上次使用的次数，若无历史返回 0。
  int lastRepsForExercise(String exerciseId) {
    return SessionQueries.lastRepsForExercise(completedSessions, exerciseId);
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
  void _updateAchievements(int newPRCount) {
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
          final targetBodyPart = a.targetBodyPart;
          if (targetBodyPart == null) break;
          final bodyPartSessions = completedSessions
              .where((s) => s.dayType.targetBodyParts.contains(targetBodyPart))
              .length;
          a.currentProgress = bodyPartSessions;
          if (bodyPartSessions >= a.threshold) a.unlock();
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
  static const _persistDebounceDuration = Duration(milliseconds: 100);
  Timer? _persistTimer;
  Future<void>? _persistInFlight;

  void _persist() {
    // Debounce: collapse rapid successive writes into one.
    if (_persistTimer?.isActive ?? false) return;
    _persistTimer = Timer(_persistDebounceDuration, () {
      _persistTimer = null;
      _startPersistWrite();
    });
  }

  /// Immediately writes any pending debounced state to storage.
  ///
  /// Widget tests run inside a fake async zone and fail if a debounced timer is
  /// still pending at teardown. This also gives production lifecycle hooks a
  /// deterministic way to force persistence before shutdown.
  Future<void> flushPendingPersistence() async {
    final timer = _persistTimer;
    if (timer != null) {
      timer.cancel();
      _persistTimer = null;
      _startPersistWrite();
    }
    await _persistInFlight;
  }

  void _startPersistWrite() {
    final write = _writePrefs();
    _persistInFlight = write;
    write.whenComplete(() {
      if (identical(_persistInFlight, write)) {
        _persistInFlight = null;
      }
    });
  }

  Future<void> _writePrefs() async {
    try {
      await _store.write(
        AppStateSnapshot(
          profile: _profile,
          activePlan: _activePlan,
          sessions: _sessions,
          bodyMetrics: _bodyMetrics,
          achievements: _achievements,
          hasCompletedOnboarding: _hasCompletedOnboarding,
          themeMode: _themeMode,
        ),
      );
    } catch (e) {
      debugPrint('FitForge: persist failed: $e');
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    super.dispose();
  }

  Future<void> _loadFromPrefs() async {
    final snapshot = await _store.load();
    _hasCompletedOnboarding = snapshot.hasCompletedOnboarding;
    _themeMode = snapshot.themeMode;
    _profile = snapshot.profile;
    _activePlan = snapshot.activePlan;
    _sessions = snapshot.sessions;
    _bodyMetrics = snapshot.bodyMetrics;
    _achievements = snapshot.achievements;

    notifyListeners();
  }

  // ──── 训练崩溃恢复 ────

  /// 保存进行中的训练状态，用于崩溃恢复。
  Future<void> saveInProgressSession(Map<String, dynamic> sessionData) async {
    await _store.saveInProgressSession(sessionData);
  }

  /// 读取崩溃前保存的训练状态，返回 null 表示没有。
  Future<Map<String, dynamic>?> loadInProgressSession() async {
    return _store.loadInProgressSession();
  }

  /// 清除进行中的训练状态（训练完成或用户放弃恢复时调用）。
  Future<void> clearInProgressSession() async {
    await _store.clearInProgressSession();
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

  void markRecoverableSessionRestored() {
    _hasRecoverableSession = false;
    _recoverableSessionData = null;
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
        _profile = UserProfile.fromJson(
          data['profile'] as Map<String, dynamic>,
        );
        _hasCompletedOnboarding = true;
      }
      if (data['activePlan'] != null) {
        _activePlan = WorkoutPlan.fromJson(
          data['activePlan'] as Map<String, dynamic>,
        );
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
        _themeMode =
            ThemeMode.values
                .where((m) => m.name == data['themeMode'])
                .firstOrNull ??
            ThemeMode.dark;
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

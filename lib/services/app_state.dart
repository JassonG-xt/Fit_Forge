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

  static const int currentExportVersion = AppStateSnapshot.currentVersion;
  static const int maxImportJsonChars = 1000000;
  static const int _maxImportedPlanDays = 14;
  static const int _maxImportedExercisesPerDay = 20;
  static const int _maxImportedSessions = 1000;
  static const int _maxImportedBodyMetrics = 1000;

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
  ThemeMode _themeMode = ThemeMode.light;

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
  ProfileState get profileState => ProfileState._(this);
  WorkoutState get workoutState => WorkoutState._(this);
  ProgressState get progressState => ProgressState._(this);
  SettingsState get settingsState => SettingsState._(this);

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
    _achievements = _migrateAchievements(_achievements);
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
    if (_shouldClearPlanForProfile(profile)) {
      _activePlan = null;
    }
    _profile = profile;
    _hasCompletedOnboarding = true;
    notifyListeners();
    _persist();
  }

  void updateProfile(UserProfile profile) {
    if (_shouldClearPlanForProfile(profile)) {
      _activePlan = null;
    }
    _profile = profile;
    notifyListeners();
    _persist();
  }

  bool _shouldClearPlanForProfile(UserProfile nextProfile) {
    final currentProfile = _profile;
    return _activePlan != null &&
        currentProfile != null &&
        _planInputsChanged(currentProfile, nextProfile);
  }

  bool _planInputsChanged(UserProfile before, UserProfile after) {
    return before.goal != after.goal ||
        before.weeklyFrequency != after.weeklyFrequency ||
        before.experienceLevel != after.experienceLevel ||
        !_sameEquipment(before.availableEquipment, after.availableEquipment);
  }

  bool _sameEquipment(List<Equipment> a, List<Equipment> b) {
    final aSet = a.toSet();
    final bSet = b.toSet();
    return aSet.length == bSet.length && aSet.containsAll(bSet);
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
    _themeMode = ThemeMode.light;
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
  List<Achievement> _migrateAchievements(List<Achievement> achievements) {
    final defaults = defaultAchievements();
    if (achievements.isEmpty) return defaults;

    final existingById = {for (final a in achievements) a.id: a};
    final defaultIds = defaults.map((a) => a.id).toSet();

    return [
      for (final fallback in defaults)
        _mergeAchievement(existingById[fallback.id], fallback),
      ...achievements.where((a) => !defaultIds.contains(a.id)),
    ];
  }

  Achievement _mergeAchievement(Achievement? existing, Achievement fallback) {
    if (existing == null) return fallback;
    return Achievement(
      id: fallback.id,
      type: fallback.type,
      title: fallback.title,
      description: fallback.description,
      icon: fallback.icon,
      threshold: fallback.threshold,
      targetBodyPart: existing.targetBodyPart ?? fallback.targetBodyPart,
      currentProgress: existing.currentProgress,
      isUnlocked: existing.isUnlocked,
      unlockedAt: existing.unlockedAt,
    );
  }

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
  Future<void> _persistQueue = Future<void>.value();
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
    }
    final write = _startPersistWrite();
    await write;
  }

  Future<void> _startPersistWrite() {
    final write = _persistQueue.then((_) => _writePrefs());
    _persistQueue = write.catchError((Object error, StackTrace stackTrace) {
      debugPrint('FitForge: persist queue failed: $error');
    });
    _persistInFlight = write;
    write.whenComplete(() {
      if (identical(_persistInFlight, write)) {
        _persistInFlight = null;
      }
    });
    return write;
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
      'version': currentExportVersion,
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

  /// Parses and validates an import without mutating current state.
  AppStateImportPreview previewImportJson(String jsonStr) {
    try {
      if (jsonStr.length > maxImportJsonChars) {
        return const AppStateImportPreview.invalid('导入文件过大，请选择较小的备份文件。');
      }
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final version = data['version'];
      if (version is! int) {
        return const AppStateImportPreview.invalid('无效的导出文件格式');
      }
      if (version > currentExportVersion) {
        return AppStateImportPreview.invalid('不支持的导出版本: $version');
      }

      _validateImportBounds(data);
      final snapshot = _snapshotFromImportData(data, version);
      return AppStateImportPreview.valid(snapshot);
    } catch (e) {
      return AppStateImportPreview.invalid('导入失败: $e');
    }
  }

  /// Imports user data from a JSON string. Returns error message or null on success.
  String? importFromJson(String jsonStr) {
    final preview = previewImportJson(jsonStr);
    if (!preview.isValid) return preview.error;

    _applySnapshot(preview.snapshot!);
    notifyListeners();
    _persist();
    return null;
  }

  AppStateSnapshot _snapshotFromImportData(
    Map<String, dynamic> data,
    int version,
  ) {
    var nextHasCompletedOnboarding = _hasCompletedOnboarding;
    var nextThemeMode = _themeMode;
    var nextProfile = _profile;
    var nextActivePlan = _activePlan;
    var nextSessions = List<WorkoutSession>.of(_sessions);
    var nextBodyMetrics = List<BodyMetric>.of(_bodyMetrics);
    var nextAchievements = List<Achievement>.of(_achievements);

    if (data.containsKey('profile')) {
      final value = data['profile'];
      nextProfile = value == null
          ? null
          : UserProfile.fromJson(value as Map<String, dynamic>);
      nextHasCompletedOnboarding = nextProfile != null;
    }
    if (data.containsKey('activePlan')) {
      final value = data['activePlan'];
      nextActivePlan = value == null
          ? null
          : WorkoutPlan.fromJson(value as Map<String, dynamic>);
    }
    if (data.containsKey('sessions')) {
      nextSessions = (data['sessions'] as List)
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('bodyMetrics')) {
      nextBodyMetrics = (data['bodyMetrics'] as List)
          .map((m) => BodyMetric.fromJson(m as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('achievements')) {
      nextAchievements = (data['achievements'] as List)
          .map((a) => Achievement.fromJson(a as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('themeMode')) {
      nextThemeMode =
          ThemeMode.values
              .where((m) => m.name == data['themeMode'])
              .firstOrNull ??
          ThemeMode.light;
    }

    return AppStateSnapshot(
      version: version,
      profile: nextProfile,
      activePlan: nextActivePlan,
      sessions: nextSessions,
      bodyMetrics: nextBodyMetrics,
      achievements: _migrateAchievements(nextAchievements),
      hasCompletedOnboarding: nextHasCompletedOnboarding,
      themeMode: nextThemeMode,
    );
  }

  void _validateImportBounds(Map<String, dynamic> data) {
    final profile = data['profile'];
    if (profile != null) {
      if (profile is! Map<String, dynamic>) {
        throw const FormatException('个人资料格式无效。');
      }
      _validateProfileImport(profile);
    }

    final plan = data['activePlan'];
    if (plan != null) {
      if (plan is! Map<String, dynamic>) {
        throw const FormatException('训练计划格式无效。');
      }
      _validatePlanImport(plan);
    }

    final sessions = data['sessions'];
    if (sessions != null) {
      if (sessions is! List) throw const FormatException('训练记录格式无效。');
      if (sessions.length > _maxImportedSessions) {
        throw const FormatException('训练记录数量过多。');
      }
      for (final raw in sessions) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('训练记录格式无效。');
        }
        _validateSessionImport(raw);
      }
    }

    final metrics = data['bodyMetrics'];
    if (metrics != null) {
      if (metrics is! List) throw const FormatException('身体数据格式无效。');
      if (metrics.length > _maxImportedBodyMetrics) {
        throw const FormatException('身体数据数量过多。');
      }
      for (final raw in metrics) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('身体数据格式无效。');
        }
        _validateBodyMetricImport(raw);
      }
    }
  }

  void _validateProfileImport(Map<String, dynamic> profile) {
    _requireNumRange(profile, 'age', 13, 100, '年龄');
    _requireNumRange(profile, 'heightCm', 100, 250, '身高');
    _requireNumRange(profile, 'weightKg', 30, 300, '体重');
    _requireNumRange(profile, 'weeklyFrequency', 1, 14, '训练频率');
    _requireKnownEnum<Gender>(profile, 'gender', Gender.values, '性别');
    _requireKnownEnum<FitnessGoal>(profile, 'goal', FitnessGoal.values, '目标');
    _requireKnownEnum<ExperienceLevel>(
      profile,
      'experienceLevel',
      ExperienceLevel.values,
      '经验等级',
    );
    final equipment = profile['availableEquipment'];
    if (equipment is! List || equipment.length > Equipment.values.length) {
      throw const FormatException('器械列表格式无效。');
    }
    for (final item in equipment) {
      if (item is! String ||
          !Equipment.values.any((value) => value.name == item)) {
        throw const FormatException('器械列表包含未知值。');
      }
    }
    _requireParsableDate(profile, 'createdAt', '个人资料创建时间');
  }

  void _validatePlanImport(Map<String, dynamic> plan) {
    _requireString(plan, 'id', 1, 100, '训练计划 id');
    _requireString(plan, 'name', 1, 120, '训练计划名称');
    _requireKnownEnum<FitnessGoal>(plan, 'goal', FitnessGoal.values, '训练目标');
    _requireKnownEnum<TrainingSplit>(
      plan,
      'split',
      TrainingSplit.values,
      '训练分化',
    );
    _requireNumRange(plan, 'weeklyFrequency', 1, 14, '训练频率');
    _requireParsableDate(plan, 'createdAt', '训练计划创建时间');
    final days = plan['days'];
    if (days is! List) throw const FormatException('训练计划天数格式无效。');
    if (days.length > _maxImportedPlanDays) {
      throw const FormatException('训练计划天数过多。');
    }
    for (final rawDay in days) {
      if (rawDay is! Map<String, dynamic>) {
        throw const FormatException('训练计划日格式无效。');
      }
      _validateWorkoutDayImport(rawDay);
    }
  }

  void _validateWorkoutDayImport(Map<String, dynamic> day) {
    _requireNumRange(day, 'dayOfWeek', 1, 7, '训练日');
    _requireKnownEnum<WorkoutDayType>(
      day,
      'dayType',
      WorkoutDayType.values,
      '训练日类型',
    );
    final exercises = day['exercises'];
    if (exercises is! List) throw const FormatException('训练动作格式无效。');
    if (exercises.length > _maxImportedExercisesPerDay) {
      throw const FormatException('单日训练动作过多。');
    }
    for (final rawExercise in exercises) {
      if (rawExercise is! Map<String, dynamic>) {
        throw const FormatException('训练动作格式无效。');
      }
      _validatePlannedExerciseImport(rawExercise);
    }
  }

  void _validatePlannedExerciseImport(Map<String, dynamic> exercise) {
    _requireString(exercise, 'exerciseId', 1, 100, '动作 id');
    _requireString(exercise, 'exerciseName', 1, 120, '动作名称');
    _requireNumRange(exercise, 'targetSets', 1, 20, '目标组数');
    _requireNumRange(exercise, 'targetReps', 1, 100, '目标次数');
    _requireNumRange(exercise, 'restSeconds', 0, 600, '休息时间');
  }

  void _validateSessionImport(Map<String, dynamic> session) {
    _requireString(session, 'id', 1, 100, '训练记录 id');
    _requireParsableDate(session, 'date', '训练记录日期');
    _requireKnownEnum<WorkoutDayType>(
      session,
      'dayType',
      WorkoutDayType.values,
      '训练记录类型',
    );
    _requireNumRange(session, 'durationMinutes', 0, 600, '训练时长');
    final records = session['exerciseRecords'];
    if (records is! List || records.length > 50) {
      throw const FormatException('训练记录动作数量无效。');
    }
    for (final rawRecord in records) {
      if (rawRecord is! Map<String, dynamic>) {
        throw const FormatException('训练记录动作格式无效。');
      }
      _requireString(rawRecord, 'exerciseId', 1, 100, '训练记录动作 id');
      _requireString(rawRecord, 'exerciseName', 1, 120, '训练记录动作名称');
      final sets = rawRecord['sets'];
      if (sets is! List || sets.length > 50) {
        throw const FormatException('训练组数格式无效。');
      }
      for (final rawSet in sets) {
        if (rawSet is! Map<String, dynamic>) {
          throw const FormatException('训练组格式无效。');
        }
        _requireNumRange(rawSet, 'setNumber', 1, 100, '组序号');
        _requireNumRange(rawSet, 'weightKg', 0, 1000, '训练重量');
        _requireNumRange(rawSet, 'reps', 0, 1000, '训练次数');
      }
    }
  }

  void _validateBodyMetricImport(Map<String, dynamic> metric) {
    _requireString(metric, 'id', 1, 100, '身体数据 id');
    _requireParsableDate(metric, 'date', '身体数据日期');
    _optionalNumRange(metric, 'weightKg', 30, 300, '身体数据体重');
    _optionalNumRange(metric, 'bodyFatPercentage', 0, 100, '身体数据体脂率');
    for (final field in ['chestCm', 'waistCm', 'hipsCm', 'armCm', 'thighCm']) {
      _optionalNumRange(metric, field, 0, 300, '身体数据');
    }
  }

  void _requireString(
    Map<String, dynamic> data,
    String field,
    int minLength,
    int maxLength,
    String label,
  ) {
    final value = data[field];
    if (value is! String ||
        value.trim().length < minLength ||
        value.length > maxLength) {
      throw FormatException('$label 超出允许范围。');
    }
  }

  void _requireNumRange(
    Map<String, dynamic> data,
    String field,
    num min,
    num max,
    String label,
  ) {
    final value = data[field];
    if (value is! num || value < min || value > max) {
      throw FormatException('$label 超出允许范围。');
    }
  }

  void _optionalNumRange(
    Map<String, dynamic> data,
    String field,
    num min,
    num max,
    String label,
  ) {
    final value = data[field];
    if (value == null) return;
    if (value is! num || value < min || value > max) {
      throw FormatException('$label 超出允许范围。');
    }
  }

  void _requireKnownEnum<T extends Enum>(
    Map<String, dynamic> data,
    String field,
    List<T> values,
    String label,
  ) {
    final value = data[field];
    if (value is! String || !values.any((e) => e.name == value)) {
      throw FormatException('$label 包含未知值。');
    }
  }

  void _requireParsableDate(
    Map<String, dynamic> data,
    String field,
    String label,
  ) {
    final value = data[field];
    if (value is! String || DateTime.tryParse(value) == null) {
      throw FormatException('$label 无效。');
    }
  }

  void _applySnapshot(AppStateSnapshot snapshot) {
    _hasCompletedOnboarding = snapshot.hasCompletedOnboarding;
    _themeMode = snapshot.themeMode;
    _profile = snapshot.profile;
    _activePlan = snapshot.activePlan;
    _sessions = snapshot.sessions;
    _bodyMetrics = snapshot.bodyMetrics;
    _achievements = snapshot.achievements;
    _invalidateCompletedCache();
    _rebuildPrCache();
  }
}

class AppStateImportPreview {
  const AppStateImportPreview.valid(this.snapshot) : error = null;
  const AppStateImportPreview.invalid(this.error) : snapshot = null;

  final AppStateSnapshot? snapshot;
  final String? error;

  bool get isValid => snapshot != null;
}

class ProfileState {
  const ProfileState._(this._state);

  final AppState _state;

  UserProfile? get profile => _state.profile;
  bool get hasCompletedOnboarding => _state.hasCompletedOnboarding;

  void saveProfile(UserProfile profile) => _state.saveProfile(profile);

  void updateProfile(UserProfile profile) => _state.updateProfile(profile);
}

class WorkoutState {
  const WorkoutState._(this._state);

  final AppState _state;

  WorkoutPlan? get activePlan => _state.activePlan;
  List<WorkoutSession> get sessions => _state.sessions;
  WorkoutDay? get todayWorkout => _state.todayWorkout;

  WorkoutPlan previewPlan() => _state.previewPlan();

  void adoptPlan(WorkoutPlan plan) => _state.adoptPlan(plan);

  void saveSession(WorkoutSession session) => _state.saveSession(session);

  double lastWeightForExercise(String exerciseId) {
    return _state.lastWeightForExercise(exerciseId);
  }

  int lastRepsForExercise(String exerciseId) {
    return _state.lastRepsForExercise(exerciseId);
  }
}

class ProgressState {
  const ProgressState._(this._state);

  final AppState _state;

  List<WorkoutSession> get completedSessions => _state.completedSessions;
  List<BodyMetric> get bodyMetrics => _state.bodyMetrics;
  List<Achievement> get achievements => _state.achievements;
  int get streakDays => _state.streakDays;
  int get totalWorkoutsThisWeek => _state.totalWorkoutsThisWeek;

  void addBodyMetric(BodyMetric metric) => _state.addBodyMetric(metric);
}

class SettingsState {
  const SettingsState._(this._state);

  final AppState _state;

  ThemeMode get themeMode => _state.themeMode;

  void setThemeMode(ThemeMode mode) => _state.setThemeMode(mode);

  String exportToJson() => _state.exportToJson();

  AppStateImportPreview previewImportJson(String jsonStr) {
    return _state.previewImportJson(jsonStr);
  }

  String? importFromJson(String jsonStr) => _state.importFromJson(jsonStr);

  Future<void> resetAllData() => _state.resetAllData();
}

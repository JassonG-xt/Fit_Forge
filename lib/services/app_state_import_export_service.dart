import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'app_clock.dart';
import 'app_state_import_preview.dart';
import 'app_state_store.dart';

class AppStateImportExportService {
  const AppStateImportExportService({required AppClock clock}) : _clock = clock;

  static const int maxImportJsonChars = 1000000;
  static const int _maxImportedPlanDays = 14;
  static const int _maxImportedExercisesPerDay = 20;
  static const int _maxImportedSessions = 1000;
  static const int _maxImportedBodyMetrics = 1000;

  final AppClock _clock;

  String exportToJson(AppStateSnapshot snapshot) {
    final data = <String, dynamic>{
      'version': AppStateSnapshot.currentVersion,
      'exportedAt': _clock.now().toIso8601String(),
      'profile': snapshot.profile?.toJson(),
      'activePlan': snapshot.activePlan?.toJson(),
      'sessions': snapshot.sessions.map((s) => s.toJson()).toList(),
      'bodyMetrics': snapshot.bodyMetrics.map((m) => m.toJson()).toList(),
      'achievements': snapshot.achievements.map((a) => a.toJson()).toList(),
      'themeMode': snapshot.themeMode.name,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  AppStateImportPreview previewImportJson({
    required String jsonStr,
    required AppStateSnapshot currentSnapshot,
  }) {
    try {
      if (jsonStr.length > maxImportJsonChars) {
        return const AppStateImportPreview.invalid('导入文件过大，请选择较小的备份文件。');
      }
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final version = data['version'];
      if (version is! int) {
        return const AppStateImportPreview.invalid('无效的导出文件格式');
      }
      if (version > AppStateSnapshot.currentVersion) {
        return AppStateImportPreview.invalid('不支持的导出版本: $version');
      }

      _validateImportBounds(data);
      final snapshot = _snapshotFromImportData(data, version, currentSnapshot);
      return AppStateImportPreview.valid(snapshot);
    } catch (e) {
      return AppStateImportPreview.invalid('导入失败: $e');
    }
  }

  AppStateSnapshot _snapshotFromImportData(
    Map<String, dynamic> data,
    int version,
    AppStateSnapshot currentSnapshot,
  ) {
    var nextHasCompletedOnboarding = currentSnapshot.hasCompletedOnboarding;
    var nextThemeMode = currentSnapshot.themeMode;
    var nextProfile = currentSnapshot.profile;
    var nextActivePlan = currentSnapshot.activePlan;
    var nextSessions = List<WorkoutSession>.of(currentSnapshot.sessions);
    var nextBodyMetrics = List<BodyMetric>.of(currentSnapshot.bodyMetrics);
    var nextAchievements = List<Achievement>.of(currentSnapshot.achievements);

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
}

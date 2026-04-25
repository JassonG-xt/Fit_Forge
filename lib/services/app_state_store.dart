import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Serializable snapshot of user-owned application state.
class AppStateSnapshot {
  const AppStateSnapshot({
    this.profile,
    this.activePlan,
    this.sessions = const [],
    this.bodyMetrics = const [],
    this.achievements = const [],
    this.hasCompletedOnboarding = false,
    this.themeMode = ThemeMode.light,
  });

  final UserProfile? profile;
  final WorkoutPlan? activePlan;
  final List<WorkoutSession> sessions;
  final List<BodyMetric> bodyMetrics;
  final List<Achievement> achievements;
  final bool hasCompletedOnboarding;
  final ThemeMode themeMode;
}

/// Local persistence boundary for AppState.
class AppStateStore {
  const AppStateStore();

  static const _kProfile = 'profile';
  static const _kActivePlan = 'activePlan';
  static const _kSessions = 'sessions';
  static const _kBodyMetrics = 'bodyMetrics';
  static const _kAchievements = 'achievements';
  static const _kOnboarding = 'hasCompletedOnboarding';
  static const _kThemeMode = 'themeMode';
  static const _kVisualRefreshV1 = 'visualRefreshV1';
  static const _kInProgressSession = 'inProgressSession';

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> write(AppStateSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await _setJsonOrRemove(prefs, _kProfile, snapshot.profile?.toJson());
    await _setJsonOrRemove(prefs, _kActivePlan, snapshot.activePlan?.toJson());
    await prefs.setString(
      _kSessions,
      json.encode(snapshot.sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setString(
      _kBodyMetrics,
      json.encode(snapshot.bodyMetrics.map((m) => m.toJson()).toList()),
    );
    await prefs.setString(
      _kAchievements,
      json.encode(snapshot.achievements.map((a) => a.toJson()).toList()),
    );
    await prefs.setBool(_kOnboarding, snapshot.hasCompletedOnboarding);
    await prefs.setString(_kThemeMode, snapshot.themeMode.name);
  }

  Future<AppStateSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeMode = await _loadThemeModeWithMigration(prefs);
    return AppStateSnapshot(
      hasCompletedOnboarding: prefs.getBool(_kOnboarding) ?? false,
      themeMode: themeMode,
      profile: _safeLoad<UserProfile?>(() => _loadProfile(prefs), null),
      activePlan: _safeLoad<WorkoutPlan?>(() => _loadPlan(prefs), null),
      sessions: _safeLoad(() => _loadSessions(prefs), const []),
      bodyMetrics: _safeLoad(() => _loadBodyMetrics(prefs), const []),
      achievements: _safeLoad(() => _loadAchievements(prefs), const []),
    );
  }

  Future<void> saveInProgressSession(Map<String, dynamic> sessionData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInProgressSession, json.encode(sessionData));
  }

  Future<Map<String, dynamic>?> loadInProgressSession() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kInProgressSession);
    if (str == null) return null;
    try {
      return json.decode(str) as Map<String, dynamic>;
    } catch (_) {
      await prefs.remove(_kInProgressSession);
      return null;
    }
  }

  Future<void> clearInProgressSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kInProgressSession);
  }

  T _safeLoad<T>(T Function() load, T fallback) {
    try {
      return load();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _setJsonOrRemove(
    SharedPreferences prefs,
    String key,
    Map<String, dynamic>? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, json.encode(value));
    }
  }

  Future<ThemeMode> _loadThemeModeWithMigration(SharedPreferences prefs) async {
    final themeMode = _safeLoad(() => _loadThemeMode(prefs), ThemeMode.light);
    final hasVisualRefresh = prefs.getBool(_kVisualRefreshV1) ?? false;
    if (!hasVisualRefresh) {
      await prefs.setBool(_kVisualRefreshV1, true);
      if (themeMode == ThemeMode.dark) {
        await prefs.setString(_kThemeMode, ThemeMode.light.name);
        return ThemeMode.light;
      }
    }
    return themeMode;
  }

  ThemeMode _loadThemeMode(SharedPreferences prefs) {
    final themeModeStr = prefs.getString(_kThemeMode);
    if (themeModeStr == null) return ThemeMode.light;
    return ThemeMode.values.where((m) => m.name == themeModeStr).firstOrNull ??
        ThemeMode.light;
  }

  UserProfile? _loadProfile(SharedPreferences prefs) {
    final profileStr = prefs.getString(_kProfile);
    if (profileStr == null) return null;
    return UserProfile.fromJson(
      json.decode(profileStr) as Map<String, dynamic>,
    );
  }

  WorkoutPlan? _loadPlan(SharedPreferences prefs) {
    final planStr = prefs.getString(_kActivePlan);
    if (planStr == null) return null;
    return WorkoutPlan.fromJson(json.decode(planStr) as Map<String, dynamic>);
  }

  List<WorkoutSession> _loadSessions(SharedPreferences prefs) {
    final sessionsStr = prefs.getString(_kSessions);
    if (sessionsStr == null) return const [];
    return (json.decode(sessionsStr) as List)
        .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  List<BodyMetric> _loadBodyMetrics(SharedPreferences prefs) {
    final metricsStr = prefs.getString(_kBodyMetrics);
    if (metricsStr == null) return const [];
    return (json.decode(metricsStr) as List)
        .map((m) => BodyMetric.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  List<Achievement> _loadAchievements(SharedPreferences prefs) {
    final achievementsStr = prefs.getString(_kAchievements);
    if (achievementsStr == null) return const [];
    return (json.decode(achievementsStr) as List)
        .map((a) => Achievement.fromJson(a as Map<String, dynamic>))
        .toList();
  }
}

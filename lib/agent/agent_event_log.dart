import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/agent_action.dart';
import 'models/agent_event.dart';

/// In-memory ring buffer + SharedPreferences-backed log of coach turns.
///
/// Records one [AgentEvent] per `userMessage → agentMessage` cycle.
/// Outcome flags (accepted / executed / failureReason) are mutated when
/// the user confirms or cancels the action presented in that turn.
///
/// Capped at [maxEvents] entries — older events are dropped FIFO when
/// the cap is exceeded. Persistence runs through a tiny debounce to
/// avoid hammering SharedPreferences on consecutive updates.
class AgentEventLog extends ChangeNotifier {
  AgentEventLog({this.maxEvents = 50, Duration? persistDebounce})
    : _persistDebounce = persistDebounce ?? const Duration(milliseconds: 50);

  static const String _prefsKey = 'fitforge.agent_event_log.v1';
  static const int maxMessageChars = 500;
  static const String _redacted = '[redacted]';

  final int maxEvents;
  final Duration _persistDebounce;
  final List<AgentEvent> _events = <AgentEvent>[];
  Timer? _persistTimer;

  List<AgentEvent> get events => List.unmodifiable(_events);

  /// Loads any persisted events into memory. Safe to call multiple times;
  /// subsequent calls are no-ops once events have been hydrated.
  bool _hydrated = false;
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      _events
        ..clear()
        ..addAll(
          list.map(
            (e) =>
                _sanitizeEvent(AgentEvent.fromJson(e as Map<String, dynamic>)),
          ),
        );
      notifyListeners();
    } catch (_) {
      // Corrupt log — drop it rather than crashing the app on launch.
      await prefs.remove(_prefsKey);
    }
  }

  /// Records a fresh turn. Returns the stored event so callers can
  /// pass its id to [updateOutcome] later.
  AgentEvent record({
    required String id,
    required String userMessage,
    required String agentMessage,
    List<AgentAction> actions = const [],
  }) {
    final event = AgentEvent(
      id: id,
      userMessage: _sanitizeMessage(userMessage),
      agentMessage: _sanitizeMessage(agentMessage),
      actions: List.unmodifiable(actions),
      accepted: false,
      executed: false,
      createdAt: DateTime.now(),
    );
    _events.add(event);
    while (_events.length > maxEvents) {
      _events.removeAt(0);
    }
    notifyListeners();
    _schedulePersist();
    return event;
  }

  /// Finds the latest event whose `actions` contain [actionId] and
  /// rewrites its outcome flags. No-op if no matching event exists.
  void updateOutcome({
    required String actionId,
    required bool accepted,
    required bool executed,
    String? failureReason,
  }) {
    for (var i = _events.length - 1; i >= 0; i--) {
      final event = _events[i];
      if (event.actions.any((a) => a.id == actionId)) {
        _events[i] = event.copyWith(
          accepted: accepted,
          executed: executed,
          failureReason: failureReason,
        );
        notifyListeners();
        _schedulePersist();
        return;
      }
    }
  }

  Future<void> clear() async {
    _events.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _persistTimer?.cancel();
    _persistTimer = null;
  }

  /// Cancels any pending debounce and writes immediately. Tests use
  /// this to assert persistence without waiting on a real Timer.
  Future<void> flushPending() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistNow();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persistNow);
  }

  Future<void> _persistNow() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_events.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }

  static AgentEvent _sanitizeEvent(AgentEvent event) => AgentEvent(
    id: event.id,
    userMessage: _sanitizeMessage(event.userMessage),
    agentMessage: _sanitizeMessage(event.agentMessage),
    actions: event.actions,
    accepted: event.accepted,
    executed: event.executed,
    failureReason: event.failureReason == null
        ? null
        : _sanitizeMessage(event.failureReason!),
    createdAt: event.createdAt,
  );

  static String _sanitizeMessage(String input) {
    var text = input.trim();
    text = text.replaceAll(
      RegExp(
        r'\b\d{1,3}(?:\.\d+)?\s*(?:kg|公斤|斤|cm|厘米|岁|%|bmi)\b',
        caseSensitive: false,
      ),
      _redacted,
    );
    text = text.replaceAll(
      RegExp(
        r'(体重|身高|年龄|BMI|体脂率|胸痛|头晕|怀孕|厌食|暴食|饮食障碍|'
        r'weight|height|age|chest pain|dizzy|pregnant|eating disorder)',
        caseSensitive: false,
      ),
      _redacted,
    );
    if (text.length > maxMessageChars) {
      text = '${text.substring(0, maxMessageChars)}…';
    }
    return text;
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistTimer = null;
    super.dispose();
  }
}

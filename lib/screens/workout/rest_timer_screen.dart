import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/brand/progress_ring.dart';
import 'package:google_fonts/google_fonts.dart';

class RestTimerScreen extends StatefulWidget {
  const RestTimerScreen({super.key, required this.seconds});
  final int seconds;

  @override
  State<RestTimerScreen> createState() => _RestTimerScreenState();
}

class _RestTimerScreenState extends State<RestTimerScreen> {
  late int _remaining;
  Timer? _timer;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining > 0) {
        setState(() => _remaining--);
      } else {
        _timer?.cancel();
        setState(() => _isRunning = false);
      }
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  double get _progress => _remaining / widget.seconds;

  String get _timeString {
    final min = _remaining ~/ 60;
    final sec = _remaining % 60;
    return min > 0 ? '$min:${sec.toString().padLeft(2, '0')}' : '$sec';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('组间休息')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // 大环形倒计时
          ProgressRing(
            progress: _progress,
            size: 200,
            strokeWidth: 10,
            gradientColors: _remaining > 10
                ? const [AppColors.primary, AppColors.primaryGlow]
                : const [AppColors.danger, AppColors.warning],
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _timeString,
                style: GoogleFonts.manrope(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text('秒', style: theme.textTheme.bodySmall),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),

          // 控制按钮
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
              onPressed: () => setState(() => _remaining = (_remaining - 15).clamp(0, 9999)),
              child: const Text('-15s'),
            ),
            const SizedBox(width: AppSpacing.md),
            FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _isRunning ? _pause : _start,
              child: Icon(_isRunning ? Icons.pause : Icons.play_arrow, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.md),
            OutlinedButton(
              onPressed: () => setState(() => _remaining += 15),
              child: const Text('+15s'),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),

          // 预设时长
          Wrap(spacing: AppSpacing.sm, children: [30, 60, 90, 120].map((s) =>
            ActionChip(
              label: Text('${s}s'),
              onPressed: () {
                _timer?.cancel();
                setState(() => _remaining = s);
                _start();
              },
            ),
          ).toList()),
          const SizedBox(height: AppSpacing.xl),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('跳过休息', style: theme.textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}

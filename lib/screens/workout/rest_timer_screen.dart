import 'dart:async';
import 'package:flutter/material.dart';

class RestTimerScreen extends StatefulWidget {
  final int seconds;
  const RestTimerScreen({super.key, required this.seconds});

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
    return Scaffold(
      appBar: AppBar(title: const Text('组间休息')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 200, height: 200,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 10,
                  backgroundColor: Colors.grey[200],
                  color: Colors.orange,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_timeString,
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                Text('秒', style: TextStyle(color: Colors.grey[600])),
              ]),
            ]),
          ),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
              onPressed: () => setState(() => _remaining = (_remaining - 15).clamp(0, 9999)),
              child: const Text('-15s'),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              backgroundColor: Colors.orange,
              onPressed: _isRunning ? _pause : _start,
              child: Icon(_isRunning ? Icons.pause : Icons.play_arrow, color: Colors.white),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => setState(() => _remaining += 15),
              child: const Text('+15s'),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [30, 60, 90, 120].map((s) =>
            ActionChip(
              label: Text('${s}s'),
              onPressed: () {
                _timer?.cancel();
                setState(() => _remaining = s);
                _start();
              },
            ),
          ).toList()),
          const SizedBox(height: 32),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('跳过休息', style: TextStyle(color: Colors.grey)),
          ),
        ]),
      ),
    );
  }
}

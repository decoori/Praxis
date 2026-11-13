import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/game_config.dart';

class FocusTimerScreen extends StatefulWidget {
  final Map<String, dynamic> quest;
  final EraConfig era;
  final VoidCallback onComplete;

  const FocusTimerScreen({
    super.key,
    required this.quest,
    required this.era,
    required this.onComplete,
  });

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen>
    with WidgetsBindingObserver {
  late int _totalSeconds;
  int _remainingSeconds = 0;
  DateTime? _targetEndTime;
  Timer? _ticker;
  bool _isRunning = false;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final minutes =
        (widget.quest['timer_duration_minutes'] as num?)?.toInt() ?? 25;
    _totalSeconds = minutes * 60;
    _remainingSeconds = _totalSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      _updateRemaining();
      _ticker?.cancel();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateRemaining(),
      );
    } else if (state == AppLifecycleState.paused && _isRunning) {
      _ticker?.cancel();
    }
  }

  void _startTimer() {
    setState(() {
      _isRunning = true;
      _targetEndTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (_targetEndTime == null || !_isRunning) return;

    final diff = _targetEndTime!.difference(DateTime.now()).inSeconds;

    if (diff <= 0) {
      _ticker?.cancel();
      setState(() {
        _remainingSeconds = 0;
        _isRunning = false;
        _isFinished = true;
      });
    } else {
      setState(() {
        _remainingSeconds = diff;
      });
    }
  }

  void _pauseTimer() {
    _ticker?.cancel();
    setState(() {
      _isRunning = false;
      _targetEndTime = null;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<bool> _onWillPop() async {
    if (_isFinished) return true;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Прервать фокус?'),
        content: const Text(
          'Таймер сбросится. Награда — только за полную сессию.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Продолжить'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сдаться'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalSeconds > 0
        ? (_totalSeconds - _remainingSeconds) / _totalSeconds
        : 1.0;

    return PopScope(
      canPop: _isFinished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _onWillPop();
        if (shouldLeave && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E2C),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () async {
              if (await _onWillPop()) {
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          title: Text(
            widget.era.name,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                const Spacer(flex: 1),
                Text(
                  widget.quest['title'] ?? 'Фокус',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isFinished
                      ? 'Сессия завершена. Заберите награду'
                      : (_isRunning ? 'Не отвлекайтесь' : 'Фокус на паузе'),
                  style: TextStyle(
                    color: _isFinished ? Colors.greenAccent : Colors.white60,
                    fontSize: 14,
                  ),
                ),
                const Spacer(flex: 2),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 12,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _isFinished
                                ? const Color(0xFF58CC02)
                                : widget.era.primaryColor,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(_remainingSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '+${widget.quest['xp_reward']} XP  •  +${widget.quest['gold_reward']}',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.monetization_on_rounded,
                                size: 14,
                                color: Colors.amberAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                if (!_isFinished) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRunning
                              ? Colors.orange.shade800
                              : widget.era.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _isRunning ? _pauseTimer : _startTimer,
                        icon: Icon(
                          _isRunning
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                        ),
                        label: Text(
                          _isRunning ? 'Пауза' : 'Продолжить',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF58CC02),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onComplete();
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 26),
                      label: const Text(
                        'Сдать квест (1 энергия)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

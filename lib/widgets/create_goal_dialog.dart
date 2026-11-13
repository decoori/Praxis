import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../services/backend_warmer.dart';

class CreateGoalDialog extends StatefulWidget {
  final Color primaryColor;
  final String userId;
  final VoidCallback onGoalCreated;

  const CreateGoalDialog({
    super.key,
    required this.primaryColor,
    required this.userId,
    required this.onGoalCreated,
  });

  @override
  State<CreateGoalDialog> createState() => _CreateGoalDialogState();
}

class _CreateGoalDialogState extends State<CreateGoalDialog> {
  late final TextEditingController _controller;
  bool isGenerating = false;

  /// Сервис не ответил быстро — скорее всего, он просыпается после простоя.
  bool isWakingUp = false;
  String? errorMessage;

  Timer? _wakeUpHintTimer;

  /// Сколько ждём сам ответ генерации (после того как сервис проснулся).
  static const Duration _generationTimeout = Duration(seconds: 60);

  /// Через сколько секунд ожидания признаёмся, что сервис просыпается.
  static const Duration _wakeUpHintDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();

    // Пока игрок вводит цель, контейнер уже начинает подниматься: бесплатный
    // Render останавливает его после ~15 минут простоя, и эти секунды
    // набора текста экономят ожидание потом. Запрос не блокирует интерфейс.
    backendWarmer.ping();
  }

  @override
  void dispose() {
    _wakeUpHintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitGoal() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      isGenerating = true;
      isWakingUp = false;
      errorMessage = null;
    });

    _wakeUpHintTimer?.cancel();
    _wakeUpHintTimer = Timer(_wakeUpHintDelay, () {
      if (mounted && isGenerating) {
        setState(() => isWakingUp = true);
      }
    });

    try {
      // Сначала будим сервис: если контейнер спал, здесь проходит его
      // пробуждение, и запрос генерации уходит уже на поднятый сервер.
      // Так игрок ждёт один раз, и мы не отправляем запрос генерации дважды
      // (повтор мог бы создать вторую ветку квестов).
      await backendWarmer.ensureAwake();

      final response = await http
          .post(
            Uri.parse(backendApiUrl),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'user_id': widget.userId, 'goal_text': text}),
          )
          .timeout(_generationTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        _wakeUpHintTimer?.cancel();
        Navigator.pop(context);
        widget.onGoalCreated();
      } else {
        setState(() {
          isGenerating = false;
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          isGenerating = false;
          errorMessage =
              'Сервис не ответил. '
              'Нажмите «Создать» ещё раз.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isGenerating = false;
          errorMessage = 'Нет связи с сервисом';
        });
      }
    } finally {
      _wakeUpHintTimer?.cancel();
      _wakeUpHintTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1D24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x28FFFFFF)),
      ),
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: Color(0xFF00B0FF), size: 24),
          SizedBox(width: 10),
          Text(
            'Новая цель через ИИ',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Опишите цель — ИИ разобьёт её на шаги',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF8E95A5),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !isGenerating,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: 'например: Выучить базовый Python',
                hintStyle: const TextStyle(color: Color(0xFF5D6475)),
                filled: true,
                fillColor: const Color(0xFF14171E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (isGenerating) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  isWakingUp
                      ? 'Сервис просыпается. Это займёт до минуты.'
                      : 'Составляем шаги…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isWakingUp
                        ? const Color(0xFFF5A623)
                        : const Color(0xFF8E95A5),
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                errorMessage!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isGenerating ? null : () => Navigator.pop(context),
          child: const Text(
            'Отмена',
            style: TextStyle(color: Color(0xFF8E95A5)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: isGenerating ? null : _submitGoal,
          child: const Text(
            'Создать',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

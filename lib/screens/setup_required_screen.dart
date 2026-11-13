import 'package:flutter/material.dart';

/// Экран, который показывается вместо игры, если при сборке не переданы
/// параметры Supabase.
///
/// Так первый запуск свежего клона объясняет, чего не хватает, вместо
/// падения внутри `Supabase.instance`. Значения задаются через
/// `--dart-define-from-file=env.json`; шаблон лежит в `env.example.json`.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key, this.details});

  /// Текст ошибки инициализации, если ключи заданы, но не подошли.
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/logo.png',
                      width: 88,
                      height: 88,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.key_rounded, size: 64),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'Нужны ключи Supabase',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Скопируйте env.example.json в env.json и заполните значения.',
                    style: TextStyle(fontSize: 15, color: Color(0xFFB8BEC9)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Затем перезапустите приложение командой:',
                    style: TextStyle(fontSize: 15, color: Color(0xFFB8BEC9)),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14171E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: const SelectableText(
                      'flutter run --dart-define-from-file=env.json',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0xFFF5A623),
                      ),
                    ),
                  ),
                  if (details != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Ошибка инициализации: $details',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFFF8A80),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Инструкция и шаблон лежат в README, раздел «Настройка».',
                    style: TextStyle(fontSize: 13, color: Color(0xFF7D8592)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

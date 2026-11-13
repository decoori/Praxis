import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Стиль текстов интерфейса.
///
/// Эти правила появились после ревизии: приложение выглядело написанным
/// генератором — длинные пояснения, восклицания в системных сообщениях,
/// транслит «стрик», заголовки в Title Case (в русском так не пишут) и шесть
/// разных сообщений об ошибке с одинаковым «Попробуйте позже».
///
/// Тест держит стиль: новая строка с таким признаком не пройдёт.
void main() {
  /// Строковые литералы с кириллицей — то, что видит игрок.
  final literal = RegExp(r"'((?:[^'\\\n]|\\.)*[А-Яа-яЁё](?:[^'\\\n]|\\.)*)'");

  /// Файлы, где кириллица в литералах — это имена и названия, а не текст
  /// интерфейса: аватары, постройки, эпохи. Title Case для них правильный.
  const namesOnly = {
    'lib/constants/avatars_config.dart',
    'lib/constants/game_config.dart',
  };

  /// Строки, которые должны остаться как есть (устоявшиеся названия и авторы
  /// пресетов — это контент, а не текст интерфейса).
  const allowedPhrases = {
    'Совет Атлетов',
    'Гильдия Кодеров',
    'Орден Мыслителей',
    'Послы Цивилизаций',
    'Хранители Знаний',
    'Совет Здоровья',
  };

  final rules = <String, bool Function(String, String)>{};

  rules['восклицание в тексте'] = (text, path) => text.contains('!');

  rules['транслит «стрик» вместо «серия»'] = (text, path) =>
      text.toLowerCase().contains('стрик');

  rules['«эра» вместо «эпоха»'] = (text, path) =>
      RegExp(r'\bэр[аыуе]\b', caseSensitive: false).hasMatch(text);

  rules['«древо» вместо «шаги»'] = (text, path) =>
      text.toLowerCase().contains('древ');

  rules['обращение к игроку вместо подписи'] = (text, path) =>
      text.contains('Вы можете') ||
      text.contains('вы можете') ||
      text.contains('убедитесь') ||
      text.toLowerCase().contains('пожалуйста');

  rules['шаблонная ошибка «Попробуйте позже»'] = (text, path) =>
      text.contains('Попробуйте позже');

  rules['заголовок в Title Case'] = (text, path) {
    if (namesOnly.contains(path) || allowedPhrases.contains(text)) return false;
    return RegExp(r'^(?:[А-ЯЁ][а-яё]+\s+){1,3}[А-ЯЁ][а-яё]+$').hasMatch(text);
  };

  rules['слишком длинная фраза'] = (text, path) {
    // Длинный литерал с подстановкой — это длинная СТРОКА КОДА, а не длинный
    // текст: в интерфейсе на месте $... окажется короткое число.
    if (text.contains(r'$')) return false;
    return text.length > 90;
  };

  test('тексты интерфейса без признаков генерации', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsStringSync().split('\n');

      for (var i = 0; i < lines.length; i++) {
        final comment = lines[i].indexOf('//');
        final line = comment == -1 ? lines[i] : lines[i].substring(0, comment);

        for (final match in literal.allMatches(line)) {
          final text = match.group(1)!;
          for (final rule in rules.entries) {
            if (rule.value(text, relative)) {
              offenders.add('${entity.path}:${i + 1} — ${rule.key}: «$text»');
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'тексты, которые выглядят сгенерированными:\n${offenders.join('\n')}',
    );
  });

  test('«серия» используется вместо «стрик» везде', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains('стрик')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'в интерфейсе серия называется «серия»:\n${offenders.join('\n')}',
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Структурная проверка блоков INSERT в миграциях.
///
/// Появилась после реальной ошибки: скрипт, переписывавший цены в миграции 022,
/// добавил запятую после последней строки VALUES, и вся миграция упала на
/// разборе — `syntax error at or near "on"`. Ошибка разбора означает, что не
/// применилась ни одна строка файла.
///
/// Тест проверяет два свойства блоков `insert ... values`:
///   * нет запятой после последней строки перед `on conflict` или `;`;
///   * в каждой строке столько значений, сколько колонок объявлено.
void main() {
  const migrationsDir = 'migrations';

  /// Делит SQL по запятым верхнего уровня, учитывая скобки и строковые литералы.
  List<String> splitTopLevel(String text) {
    final parts = <String>[];
    final current = StringBuffer();
    var depth = 0;
    var inQuote = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];

      if (inQuote) {
        current.write(char);
        if (char == "'") {
          // Две кавычки подряд — экранирование внутри строки.
          if (i + 1 < text.length && text[i + 1] == "'") {
            current.write(text[i + 1]);
            i++;
          } else {
            inQuote = false;
          }
        }
        continue;
      }

      if (char == "'") {
        inQuote = true;
        current.write(char);
      } else if (char == '(') {
        depth++;
        current.write(char);
      } else if (char == ')') {
        depth--;
        current.write(char);
      } else if (char == ',' && depth == 0) {
        parts.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }

    final tail = current.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  List<String> checkFile(File file) {
    final problems = <String>[];
    final text = file.readAsStringSync();
    final upper = text.toUpperCase();

    final insert = RegExp(
      r'insert\s+into\s+public\.(\w+)\s*\(',
      caseSensitive: false,
    );

    for (final match in insert.allMatches(text)) {
      final table = match.group(1)!;

      // Колонки: от открывающей скобки до парной закрывающей.
      var depth = 0;
      var index = match.end - 1;
      while (index < text.length) {
        if (text[index] == '(') depth++;
        if (text[index] == ')') {
          depth--;
          if (depth == 0) break;
        }
        index++;
      }
      final columns = splitTopLevel(text.substring(match.end, index));
      if (columns.length == 1 && columns.first.isEmpty) continue;

      final valuesAt = upper.indexOf('VALUES', index);
      // insert ... select вместо values — не наше дело.
      if (valuesAt == -1 || valuesAt - index > 20) continue;

      final bodyStart = valuesAt + 'VALUES'.length;
      final terminators = <int>[
        upper.indexOf('ON CONFLICT', bodyStart),
        upper.indexOf('RETURNING', bodyStart),
        text.indexOf(';', bodyStart),
        text.length,
      ].where((value) => value != -1).toList()..sort();

      final body = text.substring(bodyStart, terminators.first);

      if (body.trimRight().endsWith(',')) {
        final line =
            '\n'.allMatches(text.substring(0, bodyStart)).length +
            '\n'.allMatches(body).length +
            1;
        problems.add(
          '${file.path}:$line — запятая после последней строки VALUES '
          'перед on conflict: миграция не разберётся',
        );
      }

      final rows = splitTopLevel(body.trim().replaceAll(RegExp(r',$'), ''))
          .where((row) => row.startsWith('('))
          .toList();

      for (final row in rows) {
        final inner = row.trimRight().endsWith(')')
            ? row.substring(1, row.lastIndexOf(')'))
            : row;
        final count = splitTopLevel(inner).length;
        if (count != columns.length) {
          problems.add(
            '${file.path} — $table: в строке $count значений, '
            'а колонок ${columns.length}: ${row.trim()}',
          );
        }
      }
    }

    return problems;
  }

  test('блоки INSERT в миграциях разбираются без ошибок', () {
    final files = Directory(migrationsDir)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sql'))
        .toList();

    expect(files, isNotEmpty, reason: 'не найдено ни одной миграции');

    final problems = <String>[];
    for (final file in files) {
      problems.addAll(checkFile(file));
    }

    expect(
      problems,
      isEmpty,
      reason: 'блоки INSERT с ошибками:\n${problems.join('\n')}',
    );
  });
}

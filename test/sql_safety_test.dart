import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Статические проверки SQL-миграций.
///
/// Поводом стала реальная ошибка: в complete_quest_atomic я сравнил
/// uuid-колонку goals.user_id с текстовым параметром p_user_id. PostgreSQL
/// такое сравнение не приводит неявно, и сдача квестов сломалась с ошибкой
/// 42883 «operator does not exist: uuid = text». Живой базы в тестах нет,
/// поэтому проверяем исходники.
///
/// Проверяются только АКТУАЛЬНЫЕ определения функций — самые поздние по
/// номеру миграции. Промежуточные версии остаются в истории и намеренно не
/// проверяются: в 006 лежит сломанный вариант, который исправляет 008.
void main() {
  final migrationsDir = Directory('migrations');

  test('каталог миграций на месте', () {
    expect(migrationsDir.existsSync(), isTrue);
  });

  test('актуальные определения функций не сравнивают uuid с text', () {
    final latest = _latestDefinitions(migrationsDir);
    expect(
      latest,
      isNotEmpty,
      reason: 'не найдено ни одного определения функции',
    );

    final offenders = <String>[];

    for (final def in latest.values) {
      // Комментарии исключаем: в них встречаются примеры ошибочного SQL.
      for (final line in _codeLines(def.body)) {
        for (final pattern in _forbiddenComparisons) {
          if (pattern.hasMatch(line.text)) {
            offenders.add('${def.file}:${line.number} → ${line.text.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'uuid-колонка сравнивается с text без явного каста — '
          'на живой базе это упадёт с ошибкой 42883:\n${offenders.join('\n')}',
    );
  });

  test('в актуальной версии сдачи квеста нет смешения uuid и text', () {
    final latest = _latestDefinitions(migrationsDir);
    final questFn = latest['complete_quest_atomic'];

    expect(
      questFn,
      isNotNull,
      reason: 'не найдено актуальное определение complete_quest_atomic',
    );

    final body = questFn!.body;

    // Сравнение владельца квеста должно быть однотипным. Каст на параметре
    // (вариант 008) ошибку 42883 не убрал, поэтому в 009 обе стороны сравнения
    // приводятся к text. Здесь проверяем, что смешения типов не осталось.
    final ownerCompareByText = body.contains('g.user_id::text = v_uid');
    final ownerCompareByUuid = body.contains('g.user_id = p_user_id::uuid');

    expect(
      ownerCompareByText || ownerCompareByUuid,
      isTrue,
      reason:
          'сравнение владельца квеста должно быть приведено к одному типу '
          '(файл ${questFn.file})',
    );
  });

  test('text не присваивается в enum-колонку без каста', () {
    final latest = _latestDefinitions(migrationsDir);
    final offenders = <String>[];

    for (final def in latest.values) {
      for (final line in _codeLines(def.body)) {
        for (final match in _enumAssignment.allMatches(line.text)) {
          final value = match.group(1)!;
          final cast = match.group(2);
          // Литералы ('bronze_age') PostgreSQL приводит сам, переменные — нет.
          final isLiteral = value.startsWith("'");
          if (!isLiteral && cast == null) {
            offenders.add('${def.file}:${line.number} → ${line.text.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'переменная присваивается в enum-колонку current_era без каста '
          '::era_type — при выполнении это упадёт:\n${offenders.join('\n')}',
    );
  });

  test('evolve_era возвращает current_era — ключ, который читает клиент', () {
    final latest = _latestDefinitions(migrationsDir);
    final fn = latest['evolve_era'];

    expect(fn, isNotNull, reason: 'не найдено определение evolve_era');

    // Реальный баг: 012 возвращала эпоху под ключом 'era', а клиент читает
    // 'current_era'. После эволюции в базе всё менялось, но интерфейс оставался
    // на старой эпохе и показывал цены построек старой эпохи — игрок получал
    // «недостаточно золота» там, где золота хватало.
    expect(
      fn!.body.contains("'current_era'"),
      isTrue,
      reason:
          'ответ evolve_era должен содержать ключ current_era '
          '(файл ${fn.file})',
    );
  });

  test('сдача квеста с таймером требует серверную сессию фокуса', () {
    final latest = _latestDefinitions(migrationsDir);
    final fn = latest['complete_quest_atomic'];

    expect(
      fn,
      isNotNull,
      reason: 'не найдено определение complete_quest_atomic',
    );

    // Раньше длинный квест можно было сдать мгновенно прямым вызовом RPC:
    // таймер шёл только на клиенте. Теперь сервер требует сессию и проверяет,
    // что с момента старта прошло нужное время.
    expect(
      fn!.body.contains('QUEST_TIMER_NOT_ELAPSED'),
      isTrue,
      reason: 'нужна проверка, что время фокуса истекло (файл ${fn.file})',
    );
    expect(
      fn.body.contains('QUEST_TIMER_NOT_STARTED'),
      isTrue,
      reason: 'нужна проверка, что сессия фокуса вообще была начата',
    );
    expect(
      fn.body.contains('focus_sessions'),
      isTrue,
      reason: 'проверка должна опираться на серверную таблицу сессий',
    );
  });

  test('plpgsql-функции закрываются end; перед концом тела', () {
    // Реальная ошибка: в open_league_season я забыл `end;`, и миграция падала
    // с «syntax error at end of input». Ошибка разбора означает, что не
    // применилась ни одна строка файла — то есть вся миграция целиком.
    final pattern = RegExp(
      r'create\s+or\s+replace\s+function\s+public\.(\w+)([\s\S]*?)(\$function\$|\$\$)([\s\S]*?)\3',
      caseSensitive: false,
    );

    final offenders = <String>[];

    for (final file in Directory('migrations').listSync().whereType<File>()) {
      if (!file.path.endsWith('.sql')) continue;
      final sql = file.readAsStringSync();

      for (final match in pattern.allMatches(sql)) {
        final name = match.group(1)!;
        final header = match.group(2)!;
        // SQL-функции (language sql) не требуют begin/end.
        if (!header.toLowerCase().contains('language plpgsql')) continue;

        final bodyLines = _codeLines(match.group(4)!)
            .map((line) => line.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
        if (bodyLines.isEmpty) continue;

        final last = bodyLines.last;
        if (last.toLowerCase() != 'end;') {
          offenders.add('${file.path}: $name → последняя строка тела [$last]');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'тело plpgsql-функции должно заканчиваться на end; иначе '
          'PostgreSQL не разберёт файл и миграция не применится:\n'
          '${offenders.join('\n')}',
    );
  });

  test('сезон не просрочивается в прошлое без сдвига начала', () {
    // Реальная ошибка в инструкции по проверке: `set ends_at = now() - '1 hour'`
    // при только что созданном сезоне даёт конец РАНЬШЕ начала и нарушает
    // check (ends_at > started_at). Двигать нужно оба поля.
    final offenders = <String>[];

    for (final file in Directory('migrations').listSync().whereType<File>()) {
      if (!file.path.endsWith('.sql')) continue;
      final lines = file.readAsStringSync().split('\n');

      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('update public.league_seasons')) continue;

        final statement = <String>[];
        for (var j = i; j < lines.length && j < i + 6; j++) {
          statement.add(lines[j]);
          if (lines[j].trimRight().endsWith(';')) break;
        }
        final text = statement.join('\n');

        // Проверяем только те запросы, которые меняют конец сезона:
        // `set settled_at = ...` — это закрытие сезона, оно безопасно.
        if (!text.contains('ends_at')) continue;

        if (!text.contains('started_at')) {
          offenders.add(
            '${file.path}:${i + 1} → ${text.split('\n').first.trim()}',
          );
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'при просрочке сезона сдвигайте и started_at, и ends_at, '
          'иначе нарушается check (ends_at > started_at):\n'
          '${offenders.join('\n')}',
    );
  });

  test('таблица лиги и награды используют одно правило зачёта', () {
    // Реальное расхождение, найденное на живых данных: список лиги показывал
    // призовое место игроку с нулевым сезонным опытом, а settle_league_season
    // награждает только тех, у кого season_xp > 0. Игрок видел место, за
    // которое золото не придёт.
    final latest = _latestDefinitions(migrationsDir);
    // Комментарии внутри функции отбрасываем: иначе проверка проходит на
    // тексте пояснения, а не на коде. На этом уже спотыкались: строка
    // «partition by» осталась в комментарии, и страж молчал, даже когда
    // сам partition by из запроса убрали.
    final board = _codeLines(latest['get_league_leaderboard']!.body)
        .map((line) => line.text)
        .join('\n');
    final settle = _codeLines(latest['settle_league_season']!.body)
        .map((line) => line.text)
        .join('\n');

    expect(
      settle,
      contains('season_xp, 0) > 0'),
      reason:
          'подведение итогов больше не требует сезонного опыта — '
          'награду получат те, кто в сезоне не играл',
    );
    expect(
      board,
      contains('season_xp, 0) > 0'),
      reason:
          'таблица лиги снова показывает места игрокам без сезонного '
          'опыта, которым награда не положена',
    );
    expect(
      board,
      contains('partition by'),
      reason:
          'нумерация мест должна идти подряд только среди набравших '
          'опыт: без partition by игрок без опыта «съедает» номер, и '
          'следующее место оказывается 3 вместо 2',
    );
  });

  test('функции с id игрока в параметрах сверяют его с auth.uid()', () {
    // Историческая особенность: часть функций принимает id игрока параметром.
    // Если такую функцию не сверять с текущей сессией, любой зарегистрированный
    // игрок сможет выполнить действие за другого, зная его id.
    //
    // Образец правильного поведения — redeem_promo_code: он сравнивает
    // p_user_id с auth.uid() и отказывает при расхождении.
    final latest = _latestDefinitions(migrationsDir);
    final offenders = <String>[];

    for (final def in latest.values) {
      final header = def.body.split(RegExp(r'as\s+\$')).first;
      if (!header.contains('p_user_id')) continue;

      if (!def.body.contains('auth.uid()')) {
        offenders.add('${def.file}: ${def.name}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'функция принимает id игрока, но не сверяет его с auth.uid() — '
          'её можно вызвать за другого игрока:\n${offenders.join('\n')}',
    );
  });

  test('множитель серии ограничен сверху', () {
    // Без предела множитель растёт на 0.5% в день бесконечно, а он умножает
    // золото за квест: при неограниченном росте любая цена зелья энергии
    // становится выгодной, и суточный лимит энергии перестаёт ограничивать.
    final latest = _latestDefinitions(migrationsDir);
    final quest = _codeLines(latest['complete_quest_atomic']!.body)
        .map((line) => line.text)
        .join('\n');

    expect(
      quest,
      contains('least('),
      reason: 'рост множителя серии снова без предела — см. миграцию 022',
    );
    expect(
      RegExp(r'least\([^)]*streak_multiplier[^)]*\)').hasMatch(quest),
      isTrue,
      reason: 'множитель серии растёт без ограничения сверху',
    );
  });

  test('актуальные версии есть у всех серверных функций', () {
    final latest = _latestDefinitions(migrationsDir);
    for (final name in const [
      'complete_quest_atomic',
      'buy_consumable',
      'upgrade_camp',
      'redeem_promo_code',
      'camp_bonuses',
      'evolve_era',
      'restore_streak',
      'apply_daily_reset',
      'buy_goal_slot',
      'recompute_preset_score',
      'register_preset_use',
      'start_focus_session',
      'league_tier_for_xp',
      'open_league_season',
      'settle_league_season',
      'get_league_leaderboard',
    ]) {
      expect(
        latest.containsKey(name),
        isTrue,
        reason: 'не найдено определение функции $name ни в одной миграции',
      );
    }
  });
}

/// Определение функции и файл, где оно лежит.
class _FunctionDef {
  final String name;
  final String file;
  final int migrationNumber;
  final String body;

  _FunctionDef(this.name, this.file, this.migrationNumber, this.body);
}

/// Возвращает последнее (по номеру миграции) определение каждой функции.
Map<String, _FunctionDef> _latestDefinitions(Directory dir) {
  final result = <String, _FunctionDef>{};

  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort(
          (a, b) =>
              _migrationNumber(a.path).compareTo(_migrationNumber(b.path)),
        );

  for (final file in files) {
    final number = _migrationNumber(file.path);
    final sql = file.readAsStringSync();
    // Тело функции может быть заключено как в $function$ ... $function$,
    // так и в $$ ... $$ — поддерживаем оба варианта.
    final pattern = RegExp(
      r'create\s+or\s+replace\s+function\s+public\.(\w+)[\s\S]*?(\$function\$|\$\$)([\s\S]*?)\2',
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(sql)) {
      final name = match.group(1);
      if (name == null) continue;
      // Проверяем только тело функции, а не её объявление с параметрами.
      final def = _FunctionDef(name, file.path, number, match.group(3) ?? '');
      final previous = result[name];
      if (previous == null || number >= previous.migrationNumber) {
        result[name] = def;
      }
    }
  }

  return result;
}

int _migrationNumber(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final match = RegExp(r'^(\d+)').firstMatch(name);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// Строка SQL без комментария, с сохранением исходного номера.
({int number, String text}) _stripComment(int number, String line) {
  if (line.trimLeft().startsWith('--')) return (number: number, text: '');
  final idx = line.indexOf('--');
  return (number: number, text: idx == -1 ? line : line.substring(0, idx));
}

/// Строки кода без комментариев, с исходной нумерацией.
Iterable<({int number, String text})> _codeLines(String sql) sync* {
  final lines = sql.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final stripped = _stripComment(i + 1, lines[i]);
    if (stripped.text.trim().isEmpty) continue;
    yield stripped;
  }
}

/// Сравнения, которые PostgreSQL не выполнит без явного приведения типов.
final List<RegExp> _forbiddenComparisons = [
  // goals.user_id — uuid, p_user_id приходит текстом.
  RegExp(r'g\.user_id\s*=\s*p_user_id(?!\s*::)'),
  RegExp(r'p_user_id\s*=\s*g\.user_id(?!\s*::)'),
  // uuid-колонка против текстовой переменной сервера.
  RegExp(r'\bid\s*=\s*v_uid\b'),
  RegExp(r'\bv_uid\s*=\s*id\b'),
];

/// Присваивание в enum-колонку current_era: значение и необязательный каст.
final RegExp _enumAssignment = RegExp(
  r"current_era\s*=\s*('[^']*'|[A-Za-z_][A-Za-z0-9_]*)\s*(::\s*[A-Za-z_][A-Za-z0-9_]*)?",
  caseSensitive: false,
);

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Инварианты клиентского кода, которые легко нарушить при правках.
///
/// Экономика игры должна считаться на сервере: цена, лимиты и начисления —
/// в SQL-функциях, а клиент только отправляет намерение и берёт из ответа
/// новое состояние. Прямая запись абсолютных значений из приложения означает,
/// что через обычный запрос к API их можно выставить любыми.
/// Убирает построчные комментарии, чтобы проверки не срабатывали на текст,
/// который встречается только в пояснениях.
String _codeOnly(String source) {
  return source
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');
}

/// Код файла без комментариев.
String _read(String path) => _codeOnly(File(path).readAsStringSync());

/// Тело именованного члена по отступу: от строки с именем до строки,
/// которая снова начинается на уровне объявления или выше.
/// Нужно, чтобы проверять, ЧТО вызывается внутри конкретного метода.
String _functionBody(String source, String name) {
  final lines = source.split('\n');
  final start = lines.indexWhere((line) => line.contains(name));
  if (start == -1) return '';

  final indent = lines[start].length - lines[start].trimLeft().length;
  final body = <String>[lines[start]];

  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      body.add(line);
      continue;
    }
    final currentIndent = line.length - line.trimLeft().length;
    if (currentIndent <= indent) break;
    body.add(line);
  }

  return body.join('\n');
}

void main() {
  test('контроллер не пишет профиль напрямую', () {
    final file = File('lib/controllers/game_controller.dart');
    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();
    final writes = <String>[];

    for (final pattern in [
      RegExp(r"from\('profiles'\)\s*\.\s*update"),
      RegExp(r"from\('profiles'\)\s*\.\s*delete"),
      RegExp(r"from\('quests'\)\s*\.\s*update"),
    ]) {
      for (final match in pattern.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        writes.add('lib/controllers/game_controller.dart:$line');
      }
    }

    expect(
      writes,
      isEmpty,
      reason:
          'все изменения прогресса должны идти через серверные функции '
          '(complete_quest_atomic, buy_consumable, upgrade_camp, evolve_era, '
          'restore_streak, apply_daily_reset). Найдена прямая запись:\n'
          '${writes.join('\n')}',
    );
  });

  test('в контроллере нет локального расчёта суточного пересчёта', () {
    final source = File('lib/controllers/game_controller.dart')
        .readAsStringSync();

    // Признаки того, что клиент снова начал считать упадок стрика сам.
    expect(
      source.contains('unshieldedDays'),
      isFalse,
      reason: 'логика расхода щитов должна жить в apply_daily_reset, а не в клиенте',
    );
    expect(
      source.contains('daysDiff'),
      isFalse,
      reason: 'разница дат считается на сервере (apply_daily_reset)',
    );
  });

  test('рейтинг не строит весь список сразу', () {
    final source = File('lib/widgets/tabs/leaderboard_tab.dart')
        .readAsStringSync();

    // Раньше строки строились через List.generate(currentList.length, ...) —
    // все пятьдесят карточек на каждое обновление состояния.
    expect(
      source.contains('List.generate(currentList.length'),
      isFalse,
      reason:
          'список рейтинга должен строиться порциями (_visibleCount), '
          'иначе все карточки пересобираются на каждое обновление',
    );
    expect(
      source.contains('_visibleCount'),
      isTrue,
      reason: 'постраничная отрисовка рейтинга потеряна',
    );
  });

  test('переход на вкладку рейтинга не дублирует загрузку данных', () {
    // Комментарии исключаем: в них встречается упоминание loadGameData,
    // и тест не должен на них срабатывать.
    final source = _codeOnly(
      File('lib/screens/game_screen.dart').readAsStringSync(),
    );

    // Было: onTap тянул loadGameData (3 запроса) И вкладка грузила свои (ещё 2-3).
    final bottomNav = source.substring(source.indexOf('bottomNavigationBar'));
    expect(
      bottomNav.contains('loadGameData'),
      isFalse,
      reason:
          'данные рейтинга обновляет сама вкладка при входе на неё '
          '(LeaderboardTab.isVisible), дублировать загрузку не нужно',
    );
  });

  test('вкладки строятся при первом открытии, а не все сразу', () {
    final source = _codeOnly(
      File('lib/screens/game_screen.dart').readAsStringSync(),
    );

    // IndexedStack создаёт все children сразу: без этой защиты вкладка «Рейтинг»
    // грузила данные из сети при каждом запуске игры.
    expect(
      source.contains('_visitedTabs'),
      isTrue,
      reason: 'вкладки должны создаваться лениво (см. _visitedTabs)',
    );
    expect(
      RegExp(r'if \(!_visitedTabs\.contains\(1\)\)').hasMatch(source),
      isTrue,
      reason: 'вкладка квестов должна создаваться при первом открытии',
    );
    expect(
      RegExp(r'if \(!_visitedTabs\.contains\(3\)\)').hasMatch(source),
      isTrue,
      reason: 'вкладка рейтинга не должна грузить сеть до первого открытия',
    );
  });

  test('шрифт подключён локально, а не скачивается из сети', () {
    // Раньше google_fonts тянул Nunito с fonts.gstatic.com при запуске:
    // первый кадр шёл системным шрифтом, потом происходила подмена.
    final pubspec = File('pubspec.yaml').readAsStringSync();

    // Ищем именно строку зависимости, а не упоминание в комментарии.
    expect(
      RegExp(r'^\s{2}google_fonts:', multiLine: true).hasMatch(pubspec),
      isFalse,
      reason: 'зависимость google_fonts должна быть удалена',
    );
    expect(
      pubspec.contains('family: Nunito'),
      isTrue,
      reason: 'в pubspec.yaml должно быть объявлено семейство Nunito',
    );

    // Каждое объявленное начертание должно существовать на диске: забытый
    // файл шрифта не ломает сборку, но текст молча рисуется другим шрифтом.
    for (final asset in const [
      'assets/fonts/Nunito-Regular.ttf',
      'assets/fonts/Nunito-Bold.ttf',
      'assets/fonts/Nunito-Black.ttf',
    ]) {
      expect(
        File(asset).existsSync(),
        isTrue,
        reason: 'нет файла шрифта $asset',
      );
      expect(
        pubspec.contains(asset),
        isTrue,
        reason: '$asset не объявлен в pubspec.yaml',
      );
    }

    // Ни один файл приложения не должен импортировать google_fonts.
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      expect(
        entity.readAsStringSync().contains('package:google_fonts'),
        isFalse,
        reason: '${entity.path} всё ещё использует пакет google_fonts',
      );
    }
  });

  test('в интерфейсе нет эмодзи — только значки', () {
    // Эмодзи выглядят по-разному на разных устройствах и не совпадают с
    // остальной иконографикой приложения, поэтому в интерфейсе их быть не
    // должно: смысловые заменены на Icon, декоративные убраны.
    final emoji = RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{2300}-\u{23FF}\u{FE0F}]',
      unicode: true,
    );

    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = _codeOnly(entity.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (emoji.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1} → ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'эмодзи в интерфейсе: замените на Icon (смысловые) или уберите '
          'из строки (декоративные):\n${offenders.join('\n')}',
    );
  });

  test('в интерфейсе нет светлых остатков старой темы', () {
    // Приложение полностью тёмное. Отдельные места оставались от прежней
    // светлой версии: белый фон диалога эволюции, персиковые плашки
    // amber.shade50, коричневый текст, серые «отключённые» кнопки.
    // Прозрачные white12/white24 — это НЕ светлые элементы, их не трогаем.
    final forbidden = <RegExp>[
      RegExp(r'Colors\.amber\.shade'),
      RegExp(r'Colors\.green\.shade'),
      RegExp(r'Colors\.grey\.shade'),
      RegExp(r'Colors\.brown'),
      RegExp(r'Colors\.yellow'),
      RegExp(r'backgroundColor:\s*Colors\.white\b(?!\d)'),
    ];

    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = _codeOnly(entity.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final pattern in forbidden) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1} → ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'светлые элементы в тёмном интерфейсе — используйте палитру '
          'приложения (0xFF1A1D24, 0xFF14171E, 0xFFF5A623, 0xFF8E95A5, '
          '0xFF232732 для неактивных кнопок):\n${offenders.join('\n')}',
    );
  });

  test('итоги сезона лиги подводятся при загрузке игры', () {
    // Награды за топ-3 начисляет серверная функция settle_league_season.
    // Если её перестать вызывать при заходе, награды не будут приходить
    // вообще: отдельного планировщика в проекте нет.
    final controller = _read('lib/controllers/game_controller.dart');
    final loadGame = _functionBody(controller, 'loadGameData');

    expect(
      loadGame,
      contains('settleLeagueSeason'),
      reason: 'подведение итогов сезона не вызывается при загрузке данных',
    );
    expect(
      controller,
      contains("_callRpc('settle_league_season')"),
      reason: 'нет вызова серверной функции подведения итогов',
    );
    expect(
      loadGame.indexOf('_applyDailyReset'),
      lessThan(loadGame.indexOf('settleLeagueSeason')),
      reason: 'итоги сезона должны подводиться после суточного пересчёта',
    );
  });

  test('рейтинг берёт данные из серверной функции, а не из таблиц', () {
    // Лига, сезон, награды и места считаются на сервере: клиент не должен
    // сам решать, кто в какой лиге и кто получил награду.
    final tab = _read('lib/widgets/tabs/leaderboard_tab.dart');

    expect(
      tab,
      contains('loadLeagueLeaderboard'),
      reason: 'вкладка рейтинга не запрашивает таблицу лиги',
    );
    expect(
      tab.contains("from('profiles')"),
      isFalse,
      reason: 'вкладка рейтинга снова читает profiles напрямую',
    );
    expect(
      tab.contains("from('friendships')"),
      isFalse,
      reason: 'вкладка рейтинга снова читает friendships напрямую',
    );
    expect(
      tab.contains('season_xp'),
      isTrue,
      reason: 'места в лиге должны считаться по опыту за сезон',
    );
  });

  test('обновление вкладки рейтинга тоже подводит итоги сезона', () {
    // Иначе награду пришлось бы ждать до перезапуска приложения, а баннер
    // показывал бы «подведение итогов» вместо обратного отсчёта.
    final tab = _read('lib/widgets/tabs/leaderboard_tab.dart');

    final settle = tab.indexOf('settleLeagueSeason');
    final board = tab.indexOf('loadLeagueLeaderboard');

    expect(
      settle,
      isNot(-1),
      reason: 'вкладка рейтинга не подводит итоги сезона',
    );
    expect(
      board,
      isNot(-1),
      reason: 'вкладка рейтинга не запрашивает таблицу лиги',
    );
    expect(
      settle,
      lessThan(board),
      reason:
          'итоги должны подводиться ДО запроса таблицы, иначе таблица '
          'покажет уже закрытый сезон',
    );
  });

  test('счётчики лиг синхронизируются из ответов сервера', () {
    final controller = _read('lib/controllers/game_controller.dart');
    final keys = _functionBody(controller, '_serverIntKeys');

    expect(
      keys,
      contains("'total_xp'"),
      reason: 'total_xp не попадает в состояние из ответов сервера',
    );
    expect(
      keys,
      contains("'season_xp'"),
      reason: 'season_xp не попадает в состояние из ответов сервера',
    );
  });

  test('в интерфейсе не осталось обещаний престижа', () {
    // Престиж не реализован, поэтому упоминаний в интерфейсе быть не должно.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = _codeOnly(entity.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains('престиж')) {
          offenders.add('${entity.path}:${i + 1} → ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'престиж не реализован — уберите обещание из интерфейса:\n'
          '${offenders.join('\n')}',
    );
  });

  test('игра прогревает backend, который засыпает на бесплатном тарифе', () {
    // Контейнер Render останавливается после ~15 минут простоя, и первый
    // запрос ждёт пробуждения. Прогрев при запуске игры прячет это ожидание
    // за временем, которое игрок и так тратит на переходы по экранам.
    final screen = _read('lib/screens/game_screen.dart');

    expect(
      screen,
      contains('backendWarmer.start()'),
      reason: 'прогрев backend не запускается при входе в игру',
    );
    expect(
      screen,
      contains('backendWarmer.stop()'),
      reason:
          'прогрев не останавливается при выходе — таймер продолжит '
          'будить телефон впустую',
    );
  });

  test('генерация цели будит сервис до отправки запроса', () {
    final dialog = _read('lib/widgets/create_goal_dialog.dart');

    final awake = dialog.indexOf('ensureAwake');
    final generate = dialog.indexOf('Uri.parse(backendApiUrl)');

    expect(
      awake,
      isNot(-1),
      reason: 'диалог не ждёт пробуждения сервиса — игрок будет ждать молча',
    );
    expect(generate, isNot(-1), reason: 'запрос генерации пропал');
    expect(
      awake,
      lessThan(generate),
      reason:
          'пробуждение должно идти ДО запроса генерации, иначе игрок '
          'ждёт холодного старта вместо уже поднятого сервиса',
    );
  });

  test('запрос генерации не повторяется автоматически', () {
    // Повтор POST может создать вторую ветку квестов: сервер не знает, что
    // первый запрос был продублирован клиентом.
    final dialog = _read('lib/widgets/create_goal_dialog.dart');
    final calls = 'Uri.parse(backendApiUrl)'.allMatches(dialog).length;

    expect(
      calls,
      1,
      reason:
          'запрос генерации должен отправляться ровно один раз: '
          'автоповтор создаст вторую ветку квестов',
    );
  });

  test('прямые записи остались только в известных местах', () {
    // Остались только косметика и редактирование контента владельцем:
    //   profile_screen.dart     — смена ника;
    //   avatar_picker_dialog    — выбор аватара (пишет только свой профиль);
    //   game_screen.dart        — правка названия и таймера своего квеста.
    // Экономика (золото, XP, энергия, щиты, слоты, эволюция, стрик, рейтинг
    // пресетов) считается серверными функциями и сюда попадать не должна.
    const expectedFiles = {
      'lib/screens/profile_screen.dart',
      'lib/widgets/avatar_picker_dialog.dart',
      'lib/screens/game_screen.dart',
    };

    final found = <String>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(r"from\('profiles'\)\s*\.\s*update").hasMatch(source) ||
          RegExp(r"from\('goal_presets'\)\s*\.\s*update").hasMatch(source)) {
        found.add(entity.path.replaceAll(r'\', '/'));
      }
    }

    final unexpected = found.difference(expectedFiles);
    expect(
      unexpected,
      isEmpty,
      reason:
          'появились новые прямые записи мимо сервера:\n'
          '${unexpected.join('\n')}',
    );
  });

  test('экономика профиля не пишется с клиента', () {
    // В game_screen разрешена только правка квеста — проверяем, что там нет
    // записи профиля.
    final source = File('lib/screens/game_screen.dart').readAsStringSync();
    expect(
      RegExp(r"from\('profiles'\)\s*\.\s*update").hasMatch(source),
      isFalse,
      reason:
          'золото, энергия, щиты и слоты должны меняться серверными '
          'функциями (buy_consumable, upgrade_camp, buy_goal_slot, '
          'evolve_era, restore_streak, apply_daily_reset), а не клиентом',
    );
  });

  test('статистика пресетов не пишется с клиента', () {
    final source = File('lib/screens/preset_library_screen.dart')
        .readAsStringSync();
    expect(
      RegExp(r"from\('goal_presets'\)\s*\.\s*update").hasMatch(source),
      isFalse,
      reason:
          'рейтинг и счётчик активаций меняют recompute_preset_score и '
          'register_preset_use — иначе рейтинг можно накрутить запросом',
    );
  });
}

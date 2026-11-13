import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_of_aim_app/constants/game_config.dart';

/// Сверяет конфиг построек в Dart с таблицей camp_building_effects в SQL.
///
/// Эффекты намеренно дублируются: сервер обязан сам проверять цены и начислять
/// бонусы, иначе клиент пришлёт свои значения. Цена дублирования — риск
/// расхождения, поэтому здесь он ловится автоматически.
///
/// Если этот тест упал — правьте ОБА места: lib/constants/game_config.dart и
/// migrations/006_camp_bonuses_source_of_truth.sql.
void main() {
  /// Путь от корня пакета: flutter test запускается из корня проекта.
  late Map<
    String,
    ({
      int price,
      int shields,
      int maxEnergy,
      int instantEnergy,
      double gold,
      double xp,
    })
  >
  sqlRows;

  setUpAll(() {
    sqlRows = _parseCampEffects(_latestSeedingSql('camp_building_effects'));
  });

  test('в миграции ровно 24 постройки', () {
    expect(sqlRows.length, 24);
  });

  test('каждая постройка из Dart есть в SQL с теми же цифрами', () {
    final mismatches = <String>[];

    for (final entry in eraCampBuildings.entries) {
      for (final building in entry.value) {
        final key = '${entry.key}#${building.reqLevel}';
        final sql = sqlRows[key];

        if (sql == null) {
          mismatches.add('$key (${building.name}): нет строки в SQL');
          continue;
        }

        if (sql.price != building.price) {
          mismatches.add('$key: цена Dart=${building.price}, SQL=${sql.price}');
        }
        if (sql.shields != building.effect.shields) {
          mismatches.add(
            '$key: щиты Dart=${building.effect.shields}, SQL=${sql.shields}',
          );
        }
        if (sql.maxEnergy != building.effect.maxEnergy) {
          mismatches.add(
            '$key: макс. энергия Dart=${building.effect.maxEnergy}, SQL=${sql.maxEnergy}',
          );
        }
        if (sql.instantEnergy != building.effect.instantEnergy) {
          mismatches.add(
            '$key: мгновенная энергия Dart=${building.effect.instantEnergy}, SQL=${sql.instantEnergy}',
          );
        }
        if ((sql.gold - building.effect.goldBonus).abs() > 1e-9) {
          mismatches.add(
            '$key: бонус золота Dart=${building.effect.goldBonus}, SQL=${sql.gold}',
          );
        }
        if ((sql.xp - building.effect.xpBonus).abs() > 1e-9) {
          mismatches.add(
            '$key: бонус XP Dart=${building.effect.xpBonus}, SQL=${sql.xp}',
          );
        }
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason: 'Dart-конфиг и SQL разошлись:\n${mismatches.join('\n')}',
    );
  });

  test('в SQL нет построек, которых нет в Dart', () {
    final dartKeys = <String>{
      for (final entry in eraCampBuildings.entries)
        for (final building in entry.value) '${entry.key}#${building.reqLevel}',
    };

    final extra = sqlRows.keys.where((k) => !dartKeys.contains(k)).toList();
    expect(extra, isEmpty, reason: 'лишние строки в SQL: ${extra.join(', ')}');
  });

  test('бонусы SQL совпадают с расчётом campBonusMultipliers по эпохам', () {
    for (final eraId in eraOrder) {
      for (int level = 1; level <= 5; level++) {
        double sqlGold = 0;
        double sqlXp = 0;
        for (int unlock = 2; unlock <= level; unlock++) {
          final row = sqlRows['$eraId#$unlock'];
          if (row != null) {
            sqlGold += row.gold;
            sqlXp += row.xp;
          }
        }

        final dart = campBonusMultipliers(eraId, level);
        expect(
          dart.gold,
          closeTo(sqlGold, 1e-9),
          reason: '$eraId уровень $level: бонус золота в Dart и SQL расходится',
        );
        expect(
          dart.xp,
          closeTo(sqlXp, 1e-9),
          reason: '$eraId уровень $level: бонус XP в Dart и SQL расходится',
        );
      }
    }
  });

  // ---------------------------------------------------------------------------
  // Эпохи: пороги XP и бонусы проверяет серверный evolve_era, поэтому значения
  // обязаны совпадать с lib/constants/game_config.dart.
  // ---------------------------------------------------------------------------
  group('справочник эпох', () {
    late Map<
      String,
      ({int order, int xpRequired, int goldBonus, bool increasesMaxEnergy})
    >
    eraRows;

    setUpAll(() {
      eraRows = _parseEraConfig(_latestSeedingSql('era_config'));
    });

    test('в SQL ровно 6 эпох', () {
      expect(eraRows.length, 6);
    });

    test('порядок эпох в SQL совпадает с eraOrder', () {
      for (var i = 0; i < eraOrder.length; i++) {
        final eraId = eraOrder[i];
        final row = eraRows[eraId];
        expect(row, isNotNull, reason: 'эпоха $eraId отсутствует в SQL');
        expect(
          row!.order,
          i + 1,
          reason: '$eraId: в SQL порядок ${row.order}, в Dart ${i + 1}',
        );
      }
    });

    test('пороги XP, бонусы золота и рост энергии совпадают с Dart', () {
      final mismatches = <String>[];

      for (final entry in eras.entries) {
        final eraId = entry.key;
        final era = entry.value;
        final sql = eraRows[eraId];

        if (sql == null) {
          mismatches.add('$eraId: нет строки в SQL');
          continue;
        }
        if (sql.xpRequired != era.xpRequired) {
          mismatches.add(
            '$eraId: XP Dart=${era.xpRequired}, SQL=${sql.xpRequired}',
          );
        }
        if (sql.goldBonus != era.goldBonus) {
          mismatches.add(
            '$eraId: золото Dart=${era.goldBonus}, SQL=${sql.goldBonus}',
          );
        }
        if (sql.increasesMaxEnergy != era.increasesMaxEnergy) {
          mismatches.add(
            '$eraId: рост энергии Dart=${era.increasesMaxEnergy}, SQL=${sql.increasesMaxEnergy}',
          );
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason:
            'Dart-конфиг эпох и era_config разошлись:\n${mismatches.join('\n')}',
      );
    });

    test('в SQL нет эпох, которых нет в Dart', () {
      final extra = eraRows.keys.where((k) => !eras.containsKey(k)).toList();
      expect(extra, isEmpty, reason: 'лишние эпохи в SQL: ${extra.join(', ')}');
    });
  });

  // ---------------------------------------------------------------------------
  // Цены на слоты целей: проверяет серверный buy_goal_slot.
  // ---------------------------------------------------------------------------
  group('цены на слоты целей', () {
    late Map<int, int> slotRows;

    setUpAll(() {
      slotRows = _parseGoalSlotPrices(_latestSeedingSql('goal_slot_prices'));
    });

    test('цены в SQL совпадают с goalSlotPrices', () {
      expect(
        slotRows,
        isNotEmpty,
        reason: 'в миграции не найдены цены на слоты',
      );

      final mismatches = <String>[];
      for (final entry in goalSlotPrices.entries) {
        final sqlPrice = slotRows[entry.key];
        if (sqlPrice == null) {
          mismatches.add('уровень ${entry.key}: нет строки в SQL');
        } else if (sqlPrice != entry.value) {
          mismatches.add(
            'уровень ${entry.key}: Dart=${entry.value}, SQL=$sqlPrice',
          );
        }
      }
      for (final level in slotRows.keys) {
        if (!goalSlotPrices.containsKey(level)) {
          mismatches.add('лишний уровень в SQL: $level');
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'цены слотов в Dart и SQL разошлись:\n${mismatches.join('\n')}',
      );
    });

    test('максимум слотов выводится из таблицы и совпадает с Dart', () {
      // Сервер считает максимум как max(level) + 1, отдельной константы нет.
      final sqlMax = slotRows.keys.reduce((a, b) => a > b ? a : b) + 1;
      expect(
        sqlMax,
        maxGoalSlots,
        reason: 'в SQL максимум $sqlMax слотов, в Dart $maxGoalSlots',
      );
    });
  });
}

/// Текст последней миграции, которая заполняет таблицу [table].
///
/// Значения баланса меняются новыми миграциями, поэтому сверять надо с самой
/// свежей, а не с той, где таблица появилась впервые. Раньше здесь были
/// прописаны конкретные файлы (006, 012, 015), и после миграции 022 сверка
/// начала ругаться на устаревшие числа вместо реального расхождения.
String _latestSeedingSql(String table) {
  final candidates =
      Directory('migrations')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .where(
            (file) =>
                file.readAsStringSync().contains('insert into public.$table'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  expect(
    candidates,
    isNotEmpty,
    reason: 'не найдено ни одной миграции с insert into public.$table',
  );
  return candidates.last.readAsStringSync();
}

/// Разбирает блоки VALUES из миграции в карту «эпоха#уровень → эффекты».
Map<
  String,
  ({
    int price,
    int shields,
    int maxEnergy,
    int instantEnergy,
    double gold,
    double xp,
  })
>
_parseCampEffects(String sql) {
  // Строка вида ('stone_age', 2, 'Кострище', 40, 1, 0, 0, 0.00, 0.00),
  final rowPattern = RegExp(
    r"\(\s*'([a-z_]+)'\s*,\s*(\d+)\s*,\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)",
  );

  final insertIndex = sql.indexOf('insert into public.camp_building_effects');
  if (insertIndex == -1) {
    fail('в миграции не найден INSERT в camp_building_effects');
  }
  final valuesIndex = sql.indexOf('values', insertIndex);
  final endIndex = sql.indexOf('on conflict', valuesIndex);
  if (valuesIndex == -1 || endIndex == -1) {
    fail('не удалось выделить блок VALUES в миграции');
  }

  final block = sql.substring(valuesIndex, endIndex);
  final rows =
      <
        String,
        ({
          int price,
          int shields,
          int maxEnergy,
          int instantEnergy,
          double gold,
          double xp,
        })
      >{};

  for (final match in rowPattern.allMatches(block)) {
    final key = '${match.group(1)}#${match.group(2)}';
    rows[key] = (
      price: int.parse(match.group(3)!),
      shields: int.parse(match.group(4)!),
      maxEnergy: int.parse(match.group(5)!),
      instantEnergy: int.parse(match.group(6)!),
      gold: double.parse(match.group(7)!),
      xp: double.parse(match.group(8)!),
    );
  }

  return rows;
}

/// Разбирает INSERT в goal_slot_prices из миграции 015.
Map<int, int> _parseGoalSlotPrices(String sql) {
  final insertIndex = sql.indexOf('insert into public.goal_slot_prices');
  if (insertIndex == -1) {
    fail('в миграции 015 не найден INSERT в goal_slot_prices');
  }
  final valuesIndex = sql.indexOf('values', insertIndex);
  final endIndex = sql.indexOf('on conflict', valuesIndex);
  if (valuesIndex == -1 || endIndex == -1) {
    fail('не удалось выделить блок VALUES для goal_slot_prices');
  }

  final block = sql.substring(valuesIndex, endIndex);
  final rowPattern = RegExp(r'\(\s*(\d+)\s*,\s*(\d+)\s*\)');
  final rows = <int, int>{};

  for (final match in rowPattern.allMatches(block)) {
    rows[int.parse(match.group(1)!)] = int.parse(match.group(2)!);
  }

  return rows;
}

/// Разбирает INSERT в era_config из миграции 012.
Map<
  String,
  ({int order, int xpRequired, int goldBonus, bool increasesMaxEnergy})
>
_parseEraConfig(String sql) {
  // Строка вида ('stone_age',   1,  100,    0, false, 'Каменный век'),
  final rowPattern = RegExp(
    r"\(\s*'([a-z_]+)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(true|false)\s*,\s*'[^']*'\s*\)",
  );

  final insertIndex = sql.indexOf('insert into public.era_config');
  if (insertIndex == -1) {
    fail('в миграции 012 не найден INSERT в era_config');
  }
  final valuesIndex = sql.indexOf('values', insertIndex);
  final endIndex = sql.indexOf('on conflict', valuesIndex);
  if (valuesIndex == -1 || endIndex == -1) {
    fail('не удалось выделить блок VALUES для era_config');
  }

  final block = sql.substring(valuesIndex, endIndex);
  final rows =
      <
        String,
        ({int order, int xpRequired, int goldBonus, bool increasesMaxEnergy})
      >{};

  for (final match in rowPattern.allMatches(block)) {
    rows[match.group(1)!] = (
      order: int.parse(match.group(2)!),
      xpRequired: int.parse(match.group(3)!),
      goldBonus: int.parse(match.group(4)!),
      increasesMaxEnergy: match.group(5) == 'true',
    );
  }

  return rows;
}

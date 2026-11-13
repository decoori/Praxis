import 'package:flutter_test/flutter_test.dart';
import 'package:game_of_aim_app/constants/game_config.dart';

void main() {
  group('campBonusMultipliers', () {
    test('на первом уровне построек нет — бонусов нет', () {
      for (final eraId in eraOrder) {
        final bonus = campBonusMultipliers(eraId, 1);
        expect(bonus.gold, 0.0, reason: 'эпоха $eraId, уровень 1');
        expect(bonus.xp, 0.0, reason: 'эпоха $eraId, уровень 1');
      }
    });

    test('бонусы растут вместе с уровнем лагеря (каменный век)', () {
      // 2: Кострище (+1 щит), 3: Мастерская кремня (+5% XP),
      // 4: Шаманский тотем (+10% золота), 5: Хижина вождя (+1 макс. энергии)
      expect(campBonusMultipliers('stone_age', 2), (gold: 0.0, xp: 0.0));
      expect(campBonusMultipliers('stone_age', 3).xp, closeTo(0.05, 1e-9));
      expect(campBonusMultipliers('stone_age', 4).gold, closeTo(0.10, 1e-9));
      expect(campBonusMultipliers('stone_age', 4).xp, closeTo(0.05, 1e-9));
      expect(campBonusMultipliers('stone_age', 5).gold, closeTo(0.10, 1e-9));
      expect(campBonusMultipliers('stone_age', 5).xp, closeTo(0.05, 1e-9));
    });

    test('сумма бонусов совпадает с суммой эффектов построенных зданий', () {
      for (final eraId in eraOrder) {
        for (int level = 1; level <= 5; level++) {
          final fromBuildings = builtCampBuildings(eraId, level);
          final expectedGold = fromBuildings.fold<double>(
            0,
            (sum, b) => sum + b.effect.goldBonus,
          );
          final expectedXp = fromBuildings.fold<double>(
            0,
            (sum, b) => sum + b.effect.xpBonus,
          );

          final bonus = campBonusMultipliers(eraId, level);
          expect(
            bonus.gold,
            closeTo(expectedGold, 1e-9),
            reason: '$eraId уровень $level: золото',
          );
          expect(
            bonus.xp,
            closeTo(expectedXp, 1e-9),
            reason: '$eraId уровень $level: опыт',
          );
        }
      }
    });

    test('пятый уровень собирает все четыре постройки эпохи', () {
      for (final eraId in eraOrder) {
        expect(builtCampBuildings(eraId, 5).length, 4, reason: eraId);
        expect(eraCampBuildings[eraId]!.length, 4, reason: eraId);
      }
    });
  });

  group('nextCampBuilding', () {
    test('возвращает постройку по уровню лагеря', () {
      final first = nextCampBuilding('stone_age', 1);
      expect(first, isNotNull);
      expect(first!.reqLevel, 2);
      expect(first.name, 'Кострище');
    });

    test('на максимальном лагере возвращает null', () {
      for (final eraId in eraOrder) {
        expect(nextCampBuilding(eraId, 5), isNull, reason: eraId);
      }
    });

    test('цепочка построек покрывает уровни 2..5 последовательно', () {
      for (final eraId in eraOrder) {
        for (int level = 1; level <= 4; level++) {
          final building = nextCampBuilding(eraId, level);
          expect(building, isNotNull, reason: '$eraId уровень $level');
          expect(
            building!.reqLevel,
            level + 1,
            reason: '$eraId уровень $level',
          );
        }
      }
    });
  });

  group('цены и лимиты магазина', () {
    test('цена следующего слота растёт с каждым уровнем', () {
      // Сверяем не с числами, а со структурой: цены заданы в goalSlotPrices,
      // и тест на конкретные значения дублировал бы конфиг.
      int? previous;
      for (int slots = 2; slots < maxGoalSlots; slots++) {
        final price = nextGoalSlotPrice(slots);
        expect(price, isNotNull, reason: 'слот $slots должен иметь цену');
        if (previous != null) {
          expect(
            price!,
            greaterThan(previous),
            reason:
                'слот $slots стоит $price — не дороже предыдущего ($previous)',
          );
        }
        previous = price;
      }
    });

    test('на пределе слотов цена не выдаётся', () {
      expect(nextGoalSlotPrice(maxGoalSlots), isNull);
      expect(nextGoalSlotPrice(6), isNull);
    });
  });

  group('эффекты построек', () {
    test('каждая постройка либо даёт эффект, либо это ошибка конфига', () {
      for (final entry in eraCampBuildings.entries) {
        for (final building in entry.value) {
          final hasEffect =
              building.effect.shields > 0 ||
              building.effect.maxEnergy > 0 ||
              building.effect.instantEnergy > 0 ||
              building.effect.goldBonus > 0 ||
              building.effect.xpBonus > 0;
          expect(
            hasEffect,
            isTrue,
            reason: '${entry.key}/${building.name}: постройка без эффекта',
          );
        }
      }
    });

    test('описание бонуса не противоречит полям эффекта', () {
      for (final entry in eraCampBuildings.entries) {
        for (final building in entry.value) {
          final desc = building.bonusDesc.toLowerCase();
          if (desc.contains('щит')) {
            expect(
              building.effect.shields,
              greaterThan(0),
              reason:
                  '${entry.key}/${building.name}: в описании щиты, эффекта нет',
            );
          }
          if (desc.contains('% xp') || desc.contains('опыт')) {
            expect(
              building.effect.xpBonus,
              greaterThan(0),
              reason:
                  '${entry.key}/${building.name}: в описании опыт, эффекта нет',
            );
          }
          if (desc.contains('% золот') || desc.contains('казна')) {
            expect(
              building.effect.goldBonus,
              greaterThan(0),
              reason:
                  '${entry.key}/${building.name}: в описании золото, эффекта нет',
            );
          }
          if (desc.contains('энерг')) {
            final givesEnergy =
                building.effect.maxEnergy > 0 ||
                building.effect.instantEnergy > 0;
            expect(
              givesEnergy,
              isTrue,
              reason:
                  '${entry.key}/${building.name}: в описании энергия, эффекта нет',
            );
          }
        }
      }
    });

    test('цены построек растут внутри эпохи', () {
      for (final entry in eraCampBuildings.entries) {
        final prices = entry.value.map((b) => b.price).toList();
        for (int i = 1; i < prices.length; i++) {
          expect(
            prices[i],
            greaterThan(prices[i - 1]),
            reason: '${entry.key}: цена постройки ${i + 1} не выше предыдущей',
          );
        }
      }
    });
  });
}

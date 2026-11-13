import 'package:flutter_test/flutter_test.dart';

import 'package:game_of_aim_app/constants/game_config.dart';

/// Проверки плавности прогрессии.
///
/// Задача этих тестов — не «проверить, что числа равны ожидаемым» (тогда любая
/// правка баланса ломала бы тест и её пришлось бы править вслепую), а поймать
/// СКАЧОК. Кривая может ехать целиком, но оставаться плавной.
///
/// Что именно ловим — на реальном примере: раньше порог опыта рос вдвое
/// (100 → 4000), а награда за квест от эпохи не зависела, поэтому последняя
/// эпоха требовала в 36 раз больше квестов, чем первая. А полный лагерь всех
/// эпох стоил 84 230 золота при доходе около сотни в день — стена на два года.
void main() {
  /// Предел множителя серии (миграция 022: least(..., 1.5)).
  ///
  /// Он нужен не только «чтобы не росло бесконечно»: множитель умножает золото
  /// за квест, а значит при неограниченном росте любая цена зелья энергии
  /// рано или поздно становится выгодной, и суточный лимит перестаёт работать.
  const multiplierCap = 0.5;

  /// Максимальный бонус лагеря к золоту (последние эпохи: +30%).
  const maxCampBonus = 0.30;

  /// Сколько энергии даёт одно зелье.
  const potionEnergy = 3;

  /// Сколько квестов нужно, чтобы набрать опыт эпохи.
  double questsPerEra(String eraId) {
    final era = eras[eraId]!;
    return era.xpRequired / economyFor(eraId).xpMid;
  }

  /// Доход эпохи в золоте: столько даёт прохождение её квестов.
  double eraGoldIncome(String eraId) =>
      questsPerEra(eraId) * economyFor(eraId).goldMid;

  test('порог опыта растёт, но без скачков', () {
    int? previous;
    for (final eraId in eraOrder) {
      final era = eras[eraId]!;
      expect(
        era.xpRequired,
        greaterThan(0),
        reason: '$eraId: порог должен быть больше нуля',
      );

      if (previous != null) {
        final ratio = era.xpRequired / previous;
        expect(
          ratio,
          inInclusiveRange(1.5, 2.2),
          reason:
              '$eraId: порог вырос в ${ratio.toStringAsFixed(2)} раза — '
              'это рывок или застой, а не плавный рост',
        );
      }
      previous = era.xpRequired;
    }
  });

  test('награда за квест растёт вместе с порогом', () {
    double? previousXp;
    double? previousGold;
    for (final eraId in eraOrder) {
      final economy = economyFor(eraId);

      expect(
        economy.xpMax,
        greaterThan(economy.xpMin),
        reason: '$eraId: пустой коридор XP',
      );
      expect(
        economy.goldMax,
        greaterThan(economy.goldMin),
        reason: '$eraId: пустой коридор золота',
      );

      if (previousXp != null) {
        final xpRatio = economy.xpMid / previousXp;
        final goldRatio = economy.goldMid / previousGold!;
        expect(
          xpRatio,
          inInclusiveRange(1.4, 2.2),
          reason:
              '$eraId: опыт за квест вырос в ${xpRatio.toStringAsFixed(2)} раза',
        );
        expect(
          goldRatio,
          inInclusiveRange(1.4, 2.2),
          reason:
              '$eraId: золото за квест выросло в ${goldRatio.toStringAsFixed(2)} раза',
        );
      }

      previousXp = economy.xpMid.toDouble();
      previousGold = economy.goldMid.toDouble();
    }
  });

  test('эпоха занимает 18–42 квеста', () {
    for (final eraId in eraOrder) {
      final quests = questsPerEra(eraId);
      expect(
        quests,
        inInclusiveRange(18, 42),
        reason:
            '$eraId: ${quests.toStringAsFixed(1)} квестов на эпоху — '
            'либо эпоха проскакивается, либо превращается в стену',
      );
    }
  });

  test('разброс длительности эпох не больше двух раз', () {
    final durations = eraOrder.map(questsPerEra).toList();
    final shortest = durations.reduce((a, b) => a < b ? a : b);
    final longest = durations.reduce((a, b) => a > b ? a : b);
    expect(
      longest / shortest,
      lessThan(2.0),
      reason:
          'самая долгая эпоха в ${(longest / shortest).toStringAsFixed(2)} раза '
          'дольше самой короткой',
    );
  });

  test('лагерь посилен из дохода своей эпохи', () {
    for (final eraId in eraOrder) {
      final cost = campTotalPrice(eraId);
      // Награда за вход в эпоху тоже идёт в казну.
      final budget = eraGoldIncome(eraId) + eras[eraId]!.goldBonus;
      final ratio = cost / budget;

      expect(
        ratio,
        inInclusiveRange(0.7, 1.6),
        reason:
            '$eraId: лагерь стоит ${ratio.toStringAsFixed(2)} дохода эпохи '
            '($cost золота при доходе ${budget.toStringAsFixed(0)})',
      );
    }
  });

  test('стоимость лагеря по эпохам растёт плавно', () {
    int? previous;
    for (final eraId in eraOrder) {
      final cost = campTotalPrice(eraId);
      if (previous != null) {
        final ratio = cost / previous;
        expect(
          ratio,
          inInclusiveRange(1.4, 2.6),
          reason: '$eraId: лагерь подорожал в ${ratio.toStringAsFixed(2)} раза',
        );
      }
      previous = cost;
    }
  });

  test('полный лагерь всех эпох достижим', () {
    final total = eraOrder.fold<int>(
      0,
      (sum, eraId) => sum + campTotalPrice(eraId),
    );
    // Прежние 84 230 золота при доходе около сотни в день были стеной.
    expect(
      total,
      lessThan(25000),
      reason: 'лагерь всех эпох стоит $total золота',
    );

    final income = eraOrder.fold<double>(
      0,
      (sum, eraId) => sum + eraGoldIncome(eraId),
    );
    final bonuses = eraOrder.fold<int>(
      0,
      (sum, eraId) => sum + eras[eraId]!.goldBonus,
    );

    // Доход целенаправленно НЕ покрывает лагерь целиком: по эпохам он стоит
    // около 1.27 дохода, то есть золото — чуть более узкое горлышко, чем опыт.
    // Иначе казна копилась бы без применения, а покупки не были бы выбором.
    // Проверяем именно разумность разрыва, а не полное покрытие.
    expect(
      income + bonuses,
      greaterThan(total * 0.75),
      reason:
          'доход ${(income + bonuses).toStringAsFixed(0)} при лагере $total — '
          'разрыв больше четверти, игрок упрётся в золото',
    );
    expect(
      income + bonuses,
      lessThan(total * 1.15),
      reason:
          'доход ${(income + bonuses).toStringAsFixed(0)} почти покрывает '
          'лагерь $total — золото перестанет быть выбором',
    );
  });

  test('цены услуг соразмерны доходу эпохи', () {
    for (final eraId in eraOrder) {
      final economy = economyFor(eraId);
      final gold = economy.goldMid;

      final shieldInQuests = economy.shieldPrice / gold;
      expect(
        shieldInQuests,
        inInclusiveRange(3.0, 6.0),
        reason:
            '$eraId: щит стоит ${shieldInQuests.toStringAsFixed(2)} квестов',
      );

      final streakInQuests = economy.streakRestorePrice / gold;
      expect(
        streakInQuests,
        inInclusiveRange(4.5, 7.5),
        reason:
            '$eraId: спасение серии стоит ${streakInQuests.toStringAsFixed(2)} квестов',
      );
    }
  });

  test('энергию нельзя покупать с прибылью', () {
    // Зелье даёт 3 энергии, то есть 3 квеста. Считаем ХУДШИЙ случай для
    // баланса: игрок с максимальным бонусом лагеря и максимальным множителем
    // серии, и квесты ему выпадают по верхней границе коридора. Если зелье
    // дешевле, энергию можно покупать с прибылью, и суточный лимит — главный
    // ограничитель игры — перестаёт что-либо ограничивать.
    for (final eraId in eraOrder) {
      final economy = economyFor(eraId);
      final worstIncome =
          potionEnergy * economy.goldMax * (1 + maxCampBonus + multiplierCap);

      expect(
        economy.energyPotionPrice,
        greaterThan(worstIncome),
        reason:
            '$eraId: зелье за ${economy.energyPotionPrice} окупается — три квеста '
            'в худшем случае дают ${worstIncome.toStringAsFixed(0)} золота',
      );
    }
  });

  test('награда за эволюцию не затмевает игру', () {
    final totalBonus = eraOrder.fold<int>(
      0,
      (sum, eraId) => sum + eras[eraId]!.goldBonus,
    );
    final income = eraOrder.fold<double>(
      0,
      (sum, eraId) => sum + eraGoldIncome(eraId),
    );
    final share = totalBonus / income;

    expect(
      share,
      lessThan(0.4),
      reason:
          'награды за эволюцию дают ${(share * 100).toStringAsFixed(0)} % дохода — '
          'прогресс должен идти от игры, а не от переходов',
    );
  });

  test('слоты целей посильны и не обесцениваются', () {
    final incomes = eraOrder.map(eraGoldIncome).toList();
    for (final entry in goalSlotPrices.entries) {
      // Слот покупается в начале игры: сравниваем с доходом первых эпох.
      final price = entry.value;
      expect(
        price,
        lessThan(incomes[2]),
        reason:
            'слот ${entry.key} стоит $price — это больше дохода целой эпохи',
      );
      expect(
        price,
        greaterThan(incomes[0] * 0.3),
        reason:
            'слот ${entry.key} стоит $price — слишком дёшево, покупка без выбора',
      );
    }
  });

  test('каждая эпоха описана в экономике ровно один раз', () {
    expect(
      eraEconomy.length,
      eraOrder.length,
      reason: 'эпох ${eraOrder.length}, записей экономики ${eraEconomy.length}',
    );
    for (final eraId in eraOrder) {
      expect(
        eraEconomy.containsKey(eraId),
        isTrue,
        reason: 'нет экономики для $eraId',
      );
    }
  });

  test('награда за один квест в эпоху не превышает её порог', () {
    for (final eraId in eraOrder) {
      final economy = economyFor(eraId);
      expect(
        economy.xpMax,
        lessThan(eras[eraId]!.xpRequired),
        reason: '$eraId: один квест не должен закрывать эпоху целиком',
      );
    }
  });
}

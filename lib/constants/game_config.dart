import 'package:flutter/material.dart';

/// Экономика и прогрессия игры.
///
/// ЧИСЛА ЗДЕСЬ И В SQL ДУБЛИРУЮТСЯ НАМЕРЕННО: сервер обязан сам считать цены,
/// награды и лимиты, иначе клиент пришлёт свои. Расхождение ловится тестами
/// `test/server_config_sync_test.dart` (Dart ↔ SQL) и `test/balance_test.dart`
/// (плавность кривой). Если правку не подтверждает ни один из них — править
/// надо оба места.
///
/// ПРИНЦИП БАЛАНСА: одна эпоха — это примерно одинаковое усилие. Порог опыта
/// растёт примерно в 1.7–2 раза за эпоху, и награда за квест растёт так же,
/// поэтому число квестов на эпоху остаётся в узком коридоре (см. eraEconomy).
/// Стоимость лагеря привязана к доходу эпохи, а не растёт сама по себе.
class EraConfig {
  final String id;
  final String name;
  final IconData icon;
  final int xpRequired;
  final int goldBonus;
  final bool increasesMaxEnergy;
  final Color primaryColor;
  final Color accentColor;

  const EraConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.xpRequired,
    required this.goldBonus,
    required this.increasesMaxEnergy,
    required this.primaryColor,
    required this.accentColor,
  });
}

/// Пороги опыта подобраны так, чтобы эпоха занимала 20–35 квестов.
///
/// Раньше пороги росли вдвое (100 → 200 → 500 → 1000 → 2000 → 4000 = 7800 XP),
/// а награда за квест не зависела от эпохи: последняя эпоха требовала в 36 раз
/// больше квестов, чем первая. Теперь порог и награда растут согласованно.
const Map<String, EraConfig> eras = {
  'stone_age': EraConfig(
    id: 'stone_age',
    name: 'Каменный век',
    icon: Icons.fireplace_rounded,
    xpRequired: 120,
    goldBonus: 0,
    increasesMaxEnergy: false,
    primaryColor: Color(0xFF546E7A),
    accentColor: Color(0xFF90A4AE),
  ),
  'bronze_age': EraConfig(
    id: 'bronze_age',
    name: 'Бронзовый век',
    icon: Icons.shield_rounded,
    xpRequired: 240,
    goldBonus: 100,
    increasesMaxEnergy: false,
    primaryColor: Color(0xFFE65100), // Теплая медно-бронзовая гамма
    accentColor: Color(0xFFFF8A65),
  ),
  'iron_age': EraConfig(
    id: 'iron_age',
    name: 'Железный век',
    icon: Icons.fort_rounded,
    xpRequired: 480,
    goldBonus: 250,
    increasesMaxEnergy: true,
    primaryColor: Color(0xFF00897B), // Бирюзово-зеленый (нефрит / кремень)
    accentColor: Color(0xFF4DB6AC),
  ),
  'middle_ages': EraConfig(
    id: 'middle_ages',
    name: 'Средневековье',
    icon: Icons.castle_rounded,
    xpRequired: 900,
    goldBonus: 500,
    increasesMaxEnergy: false,
    primaryColor: Color(0xFF7B1FA2),
    accentColor: Color(0xFFBA68C8),
  ),
  'modern_age': EraConfig(
    id: 'modern_age',
    name: 'Индустриальная эпоха',
    icon: Icons.precision_manufacturing_rounded,
    xpRequired: 1600,
    goldBonus: 900,
    increasesMaxEnergy: true,
    primaryColor: Color(0xFF0097A7),
    accentColor: Color(0xFF4DD0E1),
  ),
  'space_age': EraConfig(
    id: 'space_age',
    name: 'Космическая эпоха',
    icon: Icons.rocket_launch_rounded,
    xpRequired: 2800,
    goldBonus: 1500,
    increasesMaxEnergy: true,
    primaryColor: Color(0xFF651FFF), // Неоновый ультрамарин/космос
    accentColor: Color(0xFF7C4DFF),
  ),
};

const List<String> eraOrder = [
  'stone_age',
  'bronze_age',
  'iron_age',
  'middle_ages',
  'modern_age',
  'space_age',
];

/// Экономика одной эпохи: сколько даёт квест и сколько стоят услуги.
///
/// Награда за квест задана коридором, а не одним числом: квесты бывают разной
/// тяжести, и источник награды тоже разный (ручной конструктор, пресет, ИИ).
/// Сервер приводит любую награду в этот коридор триггером
/// `clamp_quest_rewards`, поэтому здесь он же служит рамкой для интерфейса.
class EraEconomy {
  /// Минимум и максимум опыта за один квест.
  final int xpMin;
  final int xpMax;

  /// Минимум и максимум золота за один квест.
  final int goldMin;
  final int goldMax;

  /// Цена зелья энергии (даёт 3 энергии).
  final int energyPotionPrice;

  /// Цена щита заморозки.
  final int shieldPrice;

  /// Цена спасения серии.
  final int streakRestorePrice;

  const EraEconomy({
    required this.xpMin,
    required this.xpMax,
    required this.goldMin,
    required this.goldMax,
    required this.energyPotionPrice,
    required this.shieldPrice,
    required this.streakRestorePrice,
  });

  int get xpMid => ((xpMin + xpMax) / 2).round();
  int get goldMid => ((goldMin + goldMax) / 2).round();
}

/// Цены услуг привязаны к доходу эпохи, а не к фиксированным числам.
///
/// Раньше зелье стоило 50 золота всегда: в Каменном веке это было 4–6 квестов,
/// а в Космической эре — треть квеста. Одна и та же покупка была то разорением,
/// то мелочью.
const Map<String, EraEconomy> eraEconomy = {
  'stone_age': EraEconomy(
    xpMin: 4,
    xpMax: 7,
    goldMin: 8,
    goldMax: 14,
    energyPotionPrice: 80,
    shieldPrice: 45,
    streakRestorePrice: 65,
  ),
  'bronze_age': EraEconomy(
    xpMin: 7,
    xpMax: 12,
    goldMin: 14,
    goldMax: 24,
    energyPotionPrice: 130,
    shieldPrice: 75,
    streakRestorePrice: 115,
  ),
  'iron_age': EraEconomy(
    xpMin: 13,
    xpMax: 20,
    goldMin: 25,
    goldMax: 40,
    energyPotionPrice: 220,
    shieldPrice: 130,
    streakRestorePrice: 190,
  ),
  'middle_ages': EraEconomy(
    xpMin: 22,
    xpMax: 34,
    goldMin: 42,
    goldMax: 65,
    energyPotionPrice: 355,
    shieldPrice: 210,
    streakRestorePrice: 320,
  ),
  'modern_age': EraEconomy(
    xpMin: 38,
    xpMax: 58,
    goldMin: 70,
    goldMax: 105,
    energyPotionPrice: 575,
    shieldPrice: 350,
    streakRestorePrice: 520,
  ),
  'space_age': EraEconomy(
    xpMin: 65,
    xpMax: 95,
    goldMin: 115,
    goldMax: 165,
    energyPotionPrice: 900,
    shieldPrice: 560,
    streakRestorePrice: 840,
  ),
};

/// Экономика эпохи с запасным вариантом для неизвестного идентификатора.
EraEconomy economyFor(String eraId) =>
    eraEconomy[eraId] ?? eraEconomy['stone_age']!;

/// Коридор награды за квест в текущей эпохе.
({int xpMin, int xpMax, int goldMin, int goldMax}) questRewardRange(
  String eraId,
) {
  final economy = economyFor(eraId);
  return (
    xpMin: economy.xpMin,
    xpMax: economy.xpMax,
    goldMin: economy.goldMin,
    goldMax: economy.goldMax,
  );
}

/// Награда за один шаг цели в эпоху [eraId] с весом [weight] из суммы [totalWeight].
///
/// Середина коридора — «средний» шаг, вес сдвигает награду вверх или вниз, но
/// не выводит её за коридор. Итог по цели предсказуем: число шагов × середина.
({int xp, int gold}) stepReward(
  String eraId,
  double weight,
  double totalWeight,
) {
  final economy = economyFor(eraId);
  if (totalWeight <= 0) {
    return (xp: economy.xpMin, gold: economy.goldMin);
  }

  // Вес шага относительно среднего веса в цели.
  final share = weight / totalWeight;

  final xp = (economy.xpMid * share * _stepCountFactor).round().clamp(
    economy.xpMin,
    economy.xpMax,
  );
  final gold = (economy.goldMid * share * _stepCountFactor).round().clamp(
    economy.goldMin,
    economy.goldMax,
  );

  return (xp: xp, gold: gold);
}

/// Во сколько раз вес шага умножается при расчёте награды.
///
/// Веса нормированы на единицу, поэтому «средний» шаг имеет долю 1/N; чтобы
/// награда не зависела от числа шагов, доля умножается обратно на их количество.
/// Здесь для простоты берётся типичная цель из 5 шагов — так награда за шаг
/// остаётся в коридоре и не «схлопывается» в минимум на больших целях.
const double _stepCountFactor = 5.0;

/// Экономические эффекты одной постройки лагеря.
///
/// Это единственный источник правды: и текст бонуса, и фактическое начисление
/// читаются отсюда. Раньше эффекты были продублированы жёсткой цепочкой `if`
/// внутри диалога постройки, из-за чего описание и реальный эффект могли
/// разойтись.
class CampBuildingEffect {
  /// Сколько щитов заморозки добавляется сразу при постройке.
  final int shields;

  /// На сколько увеличивается максимум энергии.
  final int maxEnergy;

  /// Сколько энергии выдаётся сразу при постройке.
  final int instantEnergy;

  /// Постоянный множитель золота за квесты (0.10 = +10%).
  final double goldBonus;

  /// Постоянный множитель опыта за квесты (0.10 = +10%).
  final double xpBonus;

  const CampBuildingEffect({
    this.shields = 0,
    this.maxEnergy = 0,
    this.instantEnergy = 0,
    this.goldBonus = 0.0,
    this.xpBonus = 0.0,
  });
}

class CampBuildingConfig {
  final int reqLevel;
  final String name;
  final IconData icon;
  final int price;
  final String bonusDesc;
  final CampBuildingEffect effect;

  const CampBuildingConfig({
    required this.reqLevel,
    required this.name,
    required this.icon,
    required this.price,
    required this.bonusDesc,
    required this.effect,
  });
}

/// Цены лагеря привязаны к доходу эпохи: полный лагерь стоит примерно 1.2–1.3
/// дохода эпохи плюс награда за вход в неё.
///
/// Раньше цены росли сами по себе: полный лагерь всех шести эпох стоил 84 230
/// золота при доходе около сотни в день — это стена примерно на два года игры,
/// из-за которой развитие останавливалось уже на второй эпохе.
const Map<String, List<CampBuildingConfig>> eraCampBuildings = {
  'stone_age': [
    CampBuildingConfig(
      reqLevel: 2,
      name: 'Кострище',
      icon: Icons.local_fire_department_rounded,
      price: 30,
      bonusDesc: '+1 щит заморозки',
      effect: CampBuildingEffect(shields: 1),
    ),
    CampBuildingConfig(
      reqLevel: 3,
      name: 'Мастерская кремня',
      icon: Icons.handyman_rounded,
      price: 50,
      bonusDesc: '+5% XP за квесты',
      effect: CampBuildingEffect(xpBonus: 0.05),
    ),
    CampBuildingConfig(
      reqLevel: 4,
      name: 'Шаманский тотем',
      icon: Icons.auto_awesome_rounded,
      price: 80,
      bonusDesc: '+10% золота за квесты',
      effect: CampBuildingEffect(goldBonus: 0.10),
    ),
    CampBuildingConfig(
      reqLevel: 5,
      name: 'Хижина вождя',
      icon: Icons.holiday_village_rounded,
      price: 120,
      bonusDesc: '+1 к максимуму энергии',
      effect: CampBuildingEffect(maxEnergy: 1, instantEnergy: 1),
    ),
  ],
  'bronze_age': [
    CampBuildingConfig(
      reqLevel: 2,
      name: 'Медный рудник',
      icon: Icons.terrain_rounded,
      price: 90,
      bonusDesc: '+10% золота за квесты',
      effect: CampBuildingEffect(goldBonus: 0.10),
    ),
    CampBuildingConfig(
      reqLevel: 3,
      name: 'Гончарный склад',
      icon: Icons.inventory_2_rounded,
      price: 140,
      bonusDesc: '+1 щит заморозки',
      effect: CampBuildingEffect(shields: 1),
    ),
    CampBuildingConfig(
      reqLevel: 4,
      name: 'Бронзовая кузница',
      icon: Icons.hardware_rounded,
      price: 200,
      bonusDesc: '+10% XP за квесты',
      effect: CampBuildingEffect(xpBonus: 0.10),
    ),
    CampBuildingConfig(
      reqLevel: 5,
      name: 'Дворец правителя',
      icon: Icons.account_balance_rounded,
      price: 290,
      bonusDesc: '+1 к максимуму энергии',
      effect: CampBuildingEffect(maxEnergy: 1, instantEnergy: 1),
    ),
  ],
  'iron_age': [
    CampBuildingConfig(
      reqLevel: 2,
      name: 'Плавильня железа',
      icon: Icons.whatshot_rounded,
      price: 190,
      bonusDesc: '+15% золота за квесты',
      effect: CampBuildingEffect(goldBonus: 0.15),
    ),
    CampBuildingConfig(
      reqLevel: 3,
      name: 'Частокол легиона',
      icon: Icons.fence_rounded,
      price: 290,
      bonusDesc: '+2 щита заморозки',
      effect: CampBuildingEffect(shields: 2),
    ),
    CampBuildingConfig(
      reqLevel: 4,
      name: 'Оружейный арсенал',
      icon: Icons.shield_moon_rounded,
      price: 410,
      bonusDesc: '+15% XP за квесты',
      effect: CampBuildingEffect(xpBonus: 0.15),
    ),
    CampBuildingConfig(
      reqLevel: 5,
      name: 'Цитадель легиона',
      icon: Icons.fort_rounded,
      price: 600,
      bonusDesc: '+1 к максимуму энергии',
      effect: CampBuildingEffect(maxEnergy: 1, instantEnergy: 1),
    ),
  ],
  'middle_ages': [
    CampBuildingConfig(
      reqLevel: 2,
      name: 'Торговая площадь',
      icon: Icons.storefront_rounded,
      price: 380,
      bonusDesc: '+20% золота за квесты',
      effect: CampBuildingEffect(goldBonus: 0.20),
    ),
    CampBuildingConfig(
      reqLevel: 3,
      name: 'Башня алхимиков',
      icon: Icons.science_rounded,
      price: 560,
      bonusDesc: '+2 энергии сразу',
      effect: CampBuildingEffect(instantEnergy: 2),
    ),
    CampBuildingConfig(
      reqLevel: 4,
      name: 'Рыцарский орден',
      icon: Icons.military_tech_rounded,
      price: 780,
      bonusDesc: '+20% XP за квесты',
      effect: CampBuildingEffect(xpBonus: 0.20),
    ),
    CampBuildingConfig(
      reqLevel: 5,
      name: 'Кафедральный собор',
      icon: Icons.church_rounded,
      price: 1100,
      bonusDesc: '+1 к максимуму энергии',
      effect: CampBuildingEffect(maxEnergy: 1, instantEnergy: 1),
    ),
  ],
  'modern_age': [
    CampBuildingConfig(
      reqLevel: 2,
      name: 'Паровая фабрика',
      icon: Icons.factory_rounded,
      price: 640,
      bonusDesc: '+25% золота за квесты',
      effect: CampBuildingEffect(goldBonus: 0.25),
    ),
    CampBuildingConfig(
      reqLevel: 3,
      name: 'Телеграфная вышка',
      icon: Icons.cell_tower_rounded,
      price: 950,
      bonusDesc: '+25% XP за квесты',
      effect: CampBuildingEffect(xpBonus: 0.25),
    ),
    CampBuildingConfig(
      reqLevel: 4,
      name: 'Железная дорога',
      icon: Icons.train_rounded,
      price: 1350,
      bonusDesc: '+3 щита заморозки',
      effect: CampBuildingEffect(shields: 3),
    ),
    CampBuildingConfig(
      reqLevel: 5,
      name: 'Академия наук',
      icon: Icons.school_rounded,
      price: 1900,
      bonusDesc: '+2 к максимуму энергии',
      effect: CampBuildingEffect(maxEnergy: 2, instantEnergy: 2),
    ),
  ],
  'space_age': [
    CampBuildingConfig(
      reqLevel: 2,
      name: 'Солнечная ферма',
      icon: Icons.solar_power_rounded,
      price: 1100,
      bonusDesc: '+30% золота за квесты',
      effect: CampBuildingEffect(goldBonus: 0.30),
    ),
    CampBuildingConfig(
      reqLevel: 3,
      name: 'Орбитальный лифт',
      icon: Icons.flight_takeoff_rounded,
      price: 1650,
      bonusDesc: '+3 щита заморозки',
      effect: CampBuildingEffect(shields: 3),
    ),
    CampBuildingConfig(
      reqLevel: 4,
      name: 'Спутниковый ЦУП',
      icon: Icons.satellite_alt_rounded,
      price: 2300,
      bonusDesc: '+30% XP за квесты',
      effect: CampBuildingEffect(xpBonus: 0.30),
    ),
    CampBuildingConfig(
      reqLevel: 5,
      name: 'Космодром Альфа',
      icon: Icons.rocket_launch_rounded,
      price: 3200,
      bonusDesc: '+2 к максимуму энергии',
      effect: CampBuildingEffect(maxEnergy: 2, instantEnergy: 2),
    ),
  ],
};

/// Постройки, уже возведённые в текущей эпохе.
///
/// Уровень лагеря 1 = построек нет. Каждая постройка имеет `reqLevel` 2..5,
/// поэтому построено ровно `campLevel - 1` первых элементов списка.
List<CampBuildingConfig> builtCampBuildings(String eraId, int campLevel) {
  final buildings = eraCampBuildings[eraId] ?? const <CampBuildingConfig>[];
  if (campLevel <= 1) return const <CampBuildingConfig>[];
  final built = (campLevel - 1).clamp(0, buildings.length);
  return buildings.sublist(0, built);
}

/// Следующая постройка, которую можно возвести, или null если лагерь полон.
CampBuildingConfig? nextCampBuilding(String eraId, int campLevel) {
  final buildings = eraCampBuildings[eraId] ?? const <CampBuildingConfig>[];
  if (campLevel >= 5 || buildings.isEmpty) return null;
  final index = campLevel - 1;
  if (index < 0 || index >= buildings.length) return null;
  return buildings[index];
}

/// Единый расчёт постоянных бонусов лагеря для текущей эпохи.
({double gold, double xp}) campBonusMultipliers(String eraId, int campLevel) {
  double gold = 0.0;
  double xp = 0.0;
  for (final building in builtCampBuildings(eraId, campLevel)) {
    gold += building.effect.goldBonus;
    xp += building.effect.xpBonus;
  }
  return (gold: gold, xp: xp);
}

/// Полная стоимость лагеря эпохи: столько нужно, чтобы получить право на эволюцию.
int campTotalPrice(String eraId) {
  final buildings = eraCampBuildings[eraId] ?? const <CampBuildingConfig>[];
  return buildings.fold(0, (sum, building) => sum + building.price);
}

/// Цены на слоты целей. Единственный источник правды для магазина и диалога.
const Map<int, int> goalSlotPrices = {2: 150, 3: 400, 4: 900};

/// Максимальное количество слотов целей.
const int maxGoalSlots = 5;

/// Стоимость следующего слота целей, или null если достигнут предел.
int? nextGoalSlotPrice(int currentSlots) => goalSlotPrices[currentSlots];

/// Максимальный запас щитов заморозки.
const int maxShields = 5;

/// Экономика магазина расходников для Каменного века — значения по умолчанию.
///
/// Реальные цены зависят от эпохи игрока: см. `economyFor(currentEra)`.
const int energyPotionAmount = 3;

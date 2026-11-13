import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:game_of_aim_app/constants/game_config.dart';
import 'package:game_of_aim_app/controllers/game_controller.dart';
import 'package:game_of_aim_app/widgets/promo_code_dialog.dart';
import 'package:game_of_aim_app/widgets/tabs/shop_tab.dart';

/// Виджет-тесты. Сеть не используется: все сценарии идут по веткам, которые
/// не обращаются к Supabase.
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _shop({
  required int gold,
  required int energy,
  required int shields,
  String eraId = 'stone_age',
}) {
  return ShopTab(
    gold: gold,
    energy: energy,
    maxEnergy: 5,
    shields: shields,
    goalSlots: 2,
    primaryColor: const Color(0xFFF5A623),
    eraId: eraId,
    onBuyEnergy: (_) {},
    onBuyShield: (_) {},
    onBuyGoalSlot: () {},
  );
}

/// Кнопка внутри карточки магазина с указанным ключом.
ElevatedButton _cardButton(WidgetTester tester, String key) {
  final button = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(ElevatedButton),
  );
  expect(
    button,
    findsOneWidget,
    reason: 'в карточке $key должна быть одна кнопка',
  );
  return tester.widget<ElevatedButton>(button);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShopTab: лимиты покупок', () {
    testWidgets('щиты на максимуме — кнопка щитов заблокирована', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_shop(gold: 10000, energy: 5, shields: maxShields)),
      );

      expect(_cardButton(tester, 'shop_card_shields').onPressed, isNull);
      // Энергия тоже полная — зелья не продаются.
      expect(_cardButton(tester, 'shop_card_energy').onPressed, isNull);
      // Слоты купить можно: 10000 золота хватает на цену слота в этой эпохе.
      expect(_cardButton(tester, 'shop_card_slots').onPressed, isNotNull);
    });

    testWidgets('не хватает золота — остальное не продаётся', (tester) async {
      // В Каменном веке зелье стоит 75, щит 45, слот 150.
      await tester.pumpWidget(_host(_shop(gold: 45, energy: 0, shields: 0)));

      // Щита за 45 ровно хватает.
      expect(_cardButton(tester, 'shop_card_shields').onPressed, isNotNull);
      // Зелье стоит 75 — не хватает: энергия не должна окупаться.
      expect(_cardButton(tester, 'shop_card_energy').onPressed, isNull);
      // Слот стоит 150 — не хватает.
      expect(_cardButton(tester, 'shop_card_slots').onPressed, isNull);
    });

    testWidgets('цена в магазине растёт вместе с эпохой', (tester) async {
      // Одна и та же покупка не должна быть разорением в начале и мелочью
      // в конце: цены привязаны к доходу эпохи.
      await tester.pumpWidget(_host(_shop(gold: 45, energy: 0, shields: 0)));
      expect(
        _cardButton(tester, 'shop_card_shields').onPressed,
        isNotNull,
        reason: 'в Каменном веке щита за 45 хватает',
      );

      await tester.pumpWidget(
        _host(_shop(gold: 45, energy: 0, shields: 0, eraId: 'space_age')),
      );
      expect(
        _cardButton(tester, 'shop_card_shields').onPressed,
        isNull,
        reason: 'в Космической эре щит стоит 560 — 45 золота мало',
      );
    });

    testWidgets('диалог энергии не продаёт лишние зелья', (tester) async {
      // Не хватает 1 единицы: влезает ровно одно зелье (+3), второе сгорит.
      await tester.pumpWidget(_host(_shop(gold: 10000, energy: 4, shields: 0)));

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('shop_card_energy')),
          matching: find.byType(ElevatedButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Количество'), findsOneWidget);
      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'начальное количество — 1',
      );

      final plus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline_rounded),
      );
      expect(
        plus.onPressed,
        isNull,
        reason: 'нельзя продать зелья, которые не поместятся в запас',
      );

      expect(
        find.textContaining(
          'Итого: ${economyFor('stone_age').energyPotionPrice}',
        ),
        findsOneWidget,
        reason: 'цена — за одно зелье, по ценам текущей эпохи',
      );
    });
  });

  group('PromoCodeDialog', () {
    testWidgets('пустой код не уходит на сервер', (tester) async {
      final controller = GameController.offlineDemo();

      await tester.pumpWidget(
        _host(
          PromoCodeDialog(
            controller: controller,
            primaryColor: const Color(0xFFF5A623),
          ),
        ),
      );

      await tester.tap(find.text('Активировать'));
      await tester.pump();

      expect(find.text('Введите промокод.'), findsOneWidget);
    });

    testWidgets('в офлайне активация запрещена', (tester) async {
      final controller = GameController.offlineDemo();

      await tester.pumpWidget(
        _host(
          PromoCodeDialog(
            controller: controller,
            primaryColor: const Color(0xFFF5A623),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'praxis2026');
      await tester.tap(find.text('Активировать'));
      await tester.pump();

      expect(
        find.textContaining('только онлайн'),
        findsOneWidget,
        reason: 'награды промокода обязан подтверждать сервер',
      );
    });

    testWidgets('поле ввода отсекает недопустимые символы', (tester) async {
      final controller = GameController.offlineDemo();

      await tester.pumpWidget(
        _host(
          PromoCodeDialog(
            controller: controller,
            primaryColor: const Color(0xFFF5A623),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'pra xis!@#2026');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'praxis2026');
    });
  });

  group('GameController в офлайне', () {
    test('демо-профиль заполнен и не требует Supabase', () {
      final controller = GameController.offlineDemo();

      expect(controller.isOfflineMode, isTrue);
      expect(controller.profile, isNotNull);
      expect(controller.quests, isNotEmpty);
      expect(controller.xp, greaterThan(0));
      expect(controller.completedQuestIds, isNotEmpty);
    });

    test('множители учитывают бонусы построек лагеря', () {
      final controller = GameController.offlineDemo();

      // Демо-профиль: железный век, лагерь 1 уровня — построек нет.
      expect(controller.campGoldBonusMultiplier, 0.0);
      expect(controller.campXpBonusMultiplier, 0.0);
      expect(controller.effectiveGoldMultiplier, controller.streakMultiplier);

      // После постройки всех зданий эпохи бонусы появляются.
      controller.updateLocalProfile({
        'camp_level': 5,
        'current_era': 'space_age',
      });
      expect(controller.campGoldBonusMultiplier, closeTo(0.30, 1e-9));
      expect(controller.campXpBonusMultiplier, closeTo(0.30, 1e-9));
      expect(
        controller.effectiveGoldMultiplier,
        closeTo(controller.streakMultiplier * 1.30, 1e-9),
      );
    });

    test('условие эволюции требует опыт и полный лагерь', () {
      final controller = GameController.offlineDemo();

      // Демо: 365 XP при требовании 500 для железного века — мало.
      expect(controller.canEvolve, isFalse);

      controller.updateLocalProfile({'xp': 500, 'camp_level': 5});
      expect(controller.canEvolve, isTrue);
    });

    test('офлайн-сдача квеста списывает энергию и начисляет награду', () {
      final controller = GameController.offlineDemo();
      final energyBefore = controller.energy;
      final xpBefore = controller.xp;
      final quest = controller.quests.firstWhere(
        (q) => q['is_completed'] != true,
        orElse: () => controller.quests.first,
      );

      final rewards = (quest['xp_reward'] as num).toInt();
      expect(rewards, greaterThan(0));

      // В демо-данных все квесты закрыты, поэтому снимаем флаг у первого.
      quest['is_completed'] = false;
      controller.updateCompletedQuestIds();

      return controller.completeQuestAtomic(quest).then((ok) {
        expect(ok, isTrue);
        expect(quest['is_completed'], isTrue);
        expect(controller.xp, greaterThan(xpBefore));
        expect(controller.energy, energyBefore - 1);
      });
    });

    test('одна сдача квеста даёт одну перерисовку, а не четыре', () async {
      final controller = GameController.offlineDemo();
      final quest = controller.quests.first;
      quest['is_completed'] = false;
      controller.updateCompletedQuestIds();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.completeQuestAtomic(quest);
      // Ждём выполнения запланированной микрозадачи.
      await Future<void>.delayed(Duration.zero);

      expect(
        notifications,
        1,
        reason:
            'уведомления должны объединяться: без этого весь экран '
            'перерисовывался четыре раза на одну сдачу квеста',
      );
    });
  });
}

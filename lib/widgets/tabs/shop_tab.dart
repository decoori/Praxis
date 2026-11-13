import 'package:flutter/material.dart';

import '../../constants/game_config.dart';

class ShopTab extends StatelessWidget {
  final int gold;
  final int energy;
  final int maxEnergy;
  final int shields;
  final int goalSlots;
  final Color primaryColor;

  /// Эпоха игрока: от неё зависят цены. Раньше зелье стоило 50 золота всегда —
  /// в Каменном веке это было 4–6 квестов, а в Космической эре треть квеста.
  final String eraId;

  final ValueChanged<int> onBuyEnergy;
  final ValueChanged<int> onBuyShield;
  final VoidCallback onBuyGoalSlot;

  const ShopTab({
    super.key,
    required this.gold,
    required this.energy,
    required this.maxEnergy,
    required this.shields,
    required this.goalSlots,
    required this.primaryColor,
    required this.eraId,
    required this.onBuyEnergy,
    required this.onBuyShield,
    required this.onBuyGoalSlot,
  });

  void _showQuantityDialog({
    required BuildContext context,
    required IconData icon,
    required String title,
    required int unitPrice,
    required int maxAllowed,
    required int affordable,
    required ValueChanged<int> onConfirm,
  }) {
    int count = 1;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final int safeMax = maxAllowed < 1 ? 1 : maxAllowed;
          // Выше этого количества кнопка «+» не пускает: иначе итог превысит
          // казну и сервер отклонит покупку. Жёсткий предел по лимиту
          // характеристик всё равно проверяет сервер.
          final int selectableMax = affordable.clamp(1, safeMax);
          final int currentCount = count > selectableMax
              ? selectableMax
              : count;
          final totalCost = currentCount * unitPrice;
          final canAfford = gold >= totalCost;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1D24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0x28FFFFFF)),
            ),
            title: Row(
              children: [
                Icon(icon, color: const Color(0xFFF5A623), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Количество',
                  style: TextStyle(color: Color(0xFF8E95A5), fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Максимум $selectableMax шт.',
                  style: const TextStyle(
                    color: Color(0xFF5D6475),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 30,
                      ),
                      color: currentCount > 1
                          ? const Color(0xFFF5A623)
                          : const Color(0xFF454B58),
                      onPressed: currentCount > 1
                          ? () => setDialogState(() => count = currentCount - 1)
                          : null,
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14171E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x28FFFFFF)),
                      ),
                      child: Text(
                        '$currentCount',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 30,
                      ),
                      color: currentCount < selectableMax
                          ? const Color(0xFFF5A623)
                          : const Color(0xFF454B58),
                      onPressed: currentCount < selectableMax
                          ? () => setDialogState(() => count = currentCount + 1)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: canAfford
                          ? const Color(0xFFF5A623).withValues(alpha: 0.4)
                          : Colors.redAccent,
                    ),
                  ),
                  child: Text(
                    'Итого: $totalCost золота (в казне: $gold)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: canAfford
                          ? const Color(0xFFF5A623)
                          : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Color(0xFF8E95A5)),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford
                      ? const Color(0xFFF5A623)
                      : const Color(0xFF2A2E39),
                  foregroundColor: canAfford
                      ? Colors.black
                      : const Color(0xFF8E95A5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: canAfford
                    ? () {
                        Navigator.pop(ctx);
                        onConfirm(currentCount);
                      }
                    : null,
                child: Text(
                  'Купить за $totalCost золота',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Цены зависят от эпохи игрока.
    final economy = economyFor(eraId);
    final energyPotionPrice = economy.energyPotionPrice;
    final shieldPrice = economy.shieldPrice;

    final neededEnergy = (maxEnergy - energy).clamp(0, 1 << 20);
    // Продаём ровно столько зелий, сколько влезет в текущий запас:
    // округление вверх, без «запасных» штук, которые сгорят.
    final int maxPotionsAllowed =
        ((neededEnergy + energyPotionAmount - 1) ~/ energyPotionAmount).clamp(
          1,
          99,
        );

    final int maxShieldsAllowed = (maxShields - shields).clamp(0, maxShields);
    final bool isShieldsMax = shields >= maxShields;
    // Достаточно денег на ОДИН щит, а не на все доступные сразу: иначе при
    // цене 45 и лимите 5 кнопка требовала бы 225 золота, и купить один щит
    // было нельзя вообще. Количество ограничивает диалог покупки.
    final bool canBuyShields =
        !isShieldsMax && maxShieldsAllowed > 0 && gold >= shieldPrice;

    final int? nextSlotPrice = nextGoalSlotPrice(goalSlots);
    final bool isSlotsMax = goalSlots >= maxGoalSlots || nextSlotPrice == null;
    // Если слоты не на максимуме, цена гарантированно известна.
    final bool canBuySlots = !isSlotsMax && gold >= nextSlotPrice;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      children: [
        // Верхний блок казны в темном стиле
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D24),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFF5A623).withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF5A623).withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF14171E),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF5A623).withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFF5A623),
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Казна',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Color(0xFF8E95A5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$gold Золота',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFF5A623),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Снаряжение',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        _shopCard(
          key: const ValueKey('shop_card_energy'),
          icon: Icons.bolt_rounded,
          iconColor: const Color(0xFF00B0FF),
          title: 'Зелье энергии (+$energyPotionAmount)',
          description: energy >= maxEnergy
              ? 'Полный запас ($energy/$maxEnergy)'
              : 'В запасе $energy/$maxEnergy · $energyPotionPrice золота',
          buttonLabel: energy >= maxEnergy ? 'МАКС' : 'Купить',
          buttonColor: const Color(0xFF00B0FF),
          enabled: energy < maxEnergy && gold >= energyPotionPrice,
          onTap: () => _showQuantityDialog(
            context: context,
            icon: Icons.bolt_rounded,
            title: 'Зелье энергии',
            unitPrice: energyPotionPrice,
            maxAllowed: maxPotionsAllowed,
            affordable: gold ~/ energyPotionPrice,
            onConfirm: onBuyEnergy,
          ),
        ),
        const SizedBox(height: 12),
        _shopCard(
          key: const ValueKey('shop_card_shields'),
          icon: Icons.shield_rounded,
          iconColor: const Color(0xFF00E676),
          title: 'Щит заморозки (+1)',
          description: isShieldsMax
              ? 'Максимум: $shields/$maxShields'
              : 'В запасе $shields/$maxShields · $shieldPrice золота',
          buttonLabel: isShieldsMax ? 'МАКС' : 'Купить',
          buttonColor: const Color(0xFF00E676),
          enabled: canBuyShields,
          onTap: () => _showQuantityDialog(
            context: context,
            icon: Icons.shield_rounded,
            title: 'Щит заморозки',
            unitPrice: shieldPrice,
            maxAllowed: maxShieldsAllowed,
            affordable: gold ~/ shieldPrice,
            onConfirm: onBuyShield,
          ),
        ),
        const SizedBox(height: 12),
        _shopCard(
          key: const ValueKey('shop_card_slots'),
          icon: Icons.account_balance_rounded,
          iconColor: const Color(0xFFAB47BC),
          title: 'Слот для цели (+1)',
          description: isSlotsMax
              ? 'Максимум: $maxGoalSlots слотов'
              : 'Открыто $goalSlots из $maxGoalSlots · $nextSlotPrice золота',
          buttonLabel: isSlotsMax ? 'МАКС' : 'Купить',
          buttonColor: const Color(0xFFAB47BC),
          enabled: canBuySlots,
          onTap: onBuyGoalSlot,
        ),
      ],
    );
  }

  Widget _shopCard({
    Key? key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String buttonLabel,
    required Color buttonColor,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF14171E),
              shape: BoxShape.circle,
              border: Border.all(color: iconColor.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E95A5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled ? buttonColor : const Color(0xFF232732),
              foregroundColor: enabled ? Colors.black : const Color(0xFF5D6475),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: enabled ? 3 : 0,
            ),
            onPressed: enabled ? onTap : null,
            child: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

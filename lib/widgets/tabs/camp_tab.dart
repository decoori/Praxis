import 'package:flutter/material.dart';

import '../../constants/game_config.dart';

class CampTab extends StatelessWidget {
  final EraConfig era;
  final int eraIndex;
  final int currentXp;
  final double progressPercent;
  final bool isMaxEra;
  final Map<String, dynamic>? profile;
  final int campLevel;
  final bool canEvolve;
  final VoidCallback onLogout;
  final VoidCallback onRestoreStreak;
  final VoidCallback onUpgradeCamp;
  final VoidCallback onEvolve;

  const CampTab({
    super.key,
    required this.era,
    required this.eraIndex,
    required this.currentXp,
    required this.progressPercent,
    required this.isMaxEra,
    required this.profile,
    required this.campLevel,
    required this.canEvolve,
    required this.onLogout,
    required this.onRestoreStreak,
    required this.onUpgradeCamp,
    required this.onEvolve,
  });

  @override
  Widget build(BuildContext context) {
    final maxEnergy = profile?['max_energy'] ?? 5;
    final streak = profile?['streak_count'] ?? 0;
    final isDecayed = profile?['is_decayed'] == true;
    final isMaxCamp = campLevel >= 5;
    final buildings = eraCampBuildings[era.id] ?? [];

    const cardBg = Color(0xFF1A1D24);
    const borderColor = Color(0x14FFFFFF);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        children: [
          if (isDecayed) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 30,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Серия прервана',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.redAccent,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Щитов нет. Серия сгорит через 24 ч.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E95A5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onRestoreStreak,
                    child: const Text(
                      'Спасти',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Заголовок эпохи
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: era.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: era.primaryColor.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'Эпоха ${eraIndex + 1} из ${eraOrder.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: era.primaryColor,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            era.name.toUpperCase(),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Игровая диорама цивилизации
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                // Мягкая подсветка в цвет эпохи вместо чужеродного оранжевого
                color: era.primaryColor.withValues(
                  alpha: isMaxCamp ? 0.45 : 0.2,
                ),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: era.primaryColor.withValues(
                    alpha: isMaxCamp ? 0.2 : 0.08,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14171E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: era.primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'Построек: ${campLevel - 1}/4',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: era.primaryColor,
                        ),
                      ),
                    ),
                    Text(
                      'Уровень лагеря: $campLevel/5',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8E95A5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Сетка построек с центральным объектом
                SizedBox(
                  height: 245,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Фоновая аура центра
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              era.primaryColor.withValues(alpha: 0.28),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // Центральное здание эпохи (увеличено на 29%)
                      Container(
                        width: 106,
                        height: 106,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF14171E),
                          border: Border.all(
                            color: era.primaryColor,
                            width: 3.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: era.primaryColor.withValues(alpha: 0.35),
                              blurRadius: 22,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            era.icon,
                            size: 52,
                            color: era.primaryColor,
                          ),
                        ),
                      ),
                      if (buildings.length >= 4) ...[
                        Positioned(
                          top: 4,
                          left: 4,
                          child: _satelliteBadge(
                            icon: buildings[0].icon,
                            label: buildings[0].name,
                            isUnlocked: campLevel >= 2,
                            color: era.primaryColor,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _satelliteBadge(
                            icon: buildings[1].icon,
                            label: buildings[1].name,
                            isUnlocked: campLevel >= 3,
                            color: era.primaryColor,
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: _satelliteBadge(
                            icon: buildings[2].icon,
                            label: buildings[2].name,
                            isUnlocked: campLevel >= 4,
                            color: era.primaryColor,
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: _satelliteBadge(
                            icon: buildings[3].icon,
                            label: buildings[3].name,
                            isUnlocked: campLevel >= 5,
                            color: era.primaryColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Кнопка возведения или эволюции
                if (canEvolve) ...[
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF5A623), Color(0xFFFF5722)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF5A623).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: onEvolve,
                      icon: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.black,
                        size: 24,
                      ),
                      label: const Text(
                        'Перейти в новую эпоху',
                        style: TextStyle(
                          color: Color(0xFF0F1015),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isMaxCamp
                            ? const Color(0xFF222733)
                            : era.primaryColor,
                        foregroundColor: isMaxCamp
                            ? const Color(0xFF8E95A5)
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: isMaxCamp ? 0 : 4,
                      ),
                      onPressed: isMaxCamp ? null : onUpgradeCamp,
                      icon: Icon(
                        isMaxCamp
                            ? Icons.lock_outline_rounded
                            : Icons.add_business_rounded,
                        size: 20,
                      ),
                      label: Text(
                        isMaxCamp
                            ? (isMaxEra ? 'Последняя эпоха' : 'Лагерь отстроен')
                            : 'Построить',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Карточка характеристик
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _campStatItem(
                  'Энергия',
                  '$maxEnergy',
                  icon: Icons.bolt_rounded,
                  iconColor: const Color(0xFF00B0FF),
                ),
                Container(width: 1, height: 28, color: const Color(0x1FFFFFFF)),
                _campStatItem('Серия', '$streak дн.'),
                Container(width: 1, height: 28, color: const Color(0x1FFFFFFF)),
                _campStatItem(
                  'Бонус эпохи',
                  '+${era.goldBonus}',
                  icon: Icons.monetization_on_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Прогрессбар опыта
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Прогресс:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isMaxEra
                          ? '$currentXp XP'
                          : '$currentXp / ${era.xpRequired} XP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: era.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: isMaxEra ? 1.0 : progressPercent,
                    minHeight: 12,
                    backgroundColor: const Color(0xFF14171E),
                    valueColor: AlwaysStoppedAnimation<Color>(era.primaryColor),
                  ),
                ),
                const SizedBox(height: 12),
                if (!isMaxEra) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: canEvolve
                          ? const Color(0xFFF5A623).withValues(alpha: 0.12)
                          : const Color(0xFF14171E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: canEvolve
                            ? const Color(0xFFF5A623).withValues(alpha: 0.5)
                            : borderColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          canEvolve
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                          color: canEvolve
                              ? const Color(0xFFF5A623)
                              : const Color(0xFF8E95A5),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            canEvolve
                                ? 'Всё готово к переходу'
                                : 'Нужно: ${era.xpRequired} XP (${currentXp >= era.xpRequired ? "есть" : "не хватает"}) и лагерь 4/4 (${campLevel >= 5 ? "есть" : "${campLevel - 1}/4"}).',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: canEvolve
                                  ? const Color(0xFFF5A623)
                                  : const Color(0xFF8E95A5),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Выход
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5252),
            ),
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text(
              'Выйти из аккаунта',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Узел постройки с устраненным переполнением названия
  Widget _satelliteBadge({
    required IconData icon,
    required String label,
    required bool isUnlocked,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isUnlocked
                ? const Color(0xFF14171E)
                : const Color(0xFF181B22),
            border: Border.all(
              color: isUnlocked ? color : const Color(0x28FFFFFF),
              width: isUnlocked ? 2 : 1.2,
            ),
            boxShadow: isUnlocked
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Icon(
              isUnlocked ? icon : Icons.lock_outline_rounded,
              size: isUnlocked ? 24 : 18,
              color: isUnlocked ? color : const Color(0xFF8E95A5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Фикс переполнения: 2 строки, ширина 110px, выравнивание по центру без эллипсиса
        SizedBox(
          width: 110,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            softWrap: true,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1.2,
              color: isUnlocked ? Colors.white : const Color(0xFF8E95A5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _campStatItem(
    String label,
    String value, {
    IconData? icon,
    Color iconColor = const Color(0xFFF5A623),
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8E95A5)),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 3),
              Icon(icon, size: 14, color: iconColor),
            ],
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

class AvatarConfig {
  final String id;
  final String name;
  final String eraName;
  final IconData icon;
  final List<Color> gradient;
  final Color glowColor;

  const AvatarConfig({
    required this.id,
    required this.name,
    required this.eraName,
    required this.icon,
    required this.gradient,
    required this.glowColor,
  });
}

const List<AvatarConfig> gameAvatars = [
  // Каменный век (Охота, Духи, Огонь)
  AvatarConfig(
    id: 'cave_hunter',
    name: 'Охотник тундры',
    eraName: 'Каменный век',
    icon: Icons.pets_rounded,
    gradient: [Color(0xFF00897B), Color(0xFF004D40)],
    glowColor: Color(0xFF00897B),
  ),
  AvatarConfig(
    id: 'shaman_mask',
    name: 'Тотемный шаман',
    eraName: 'Каменный век',
    icon: Icons.theater_comedy_rounded,
    gradient: [Color(0xFF26A69A), Color(0xFF004D40)],
    glowColor: Color(0xFF26A69A),
  ),
  AvatarConfig(
    id: 'fire_keeper',
    name: 'Хранитель пламени',
    eraName: 'Каменный век',
    icon: Icons.whatshot_rounded,
    gradient: [Color(0xFF4DB6AC), Color(0xFF00695C)],
    glowColor: Color(0xFF4DB6AC),
  ),

  // Бронзовый век (Мифы, Античность, Фараоны)
  AvatarConfig(
    id: 'spartan',
    name: 'Спартанский воин',
    eraName: 'Бронзовый век',
    icon: Icons.sports_martial_arts_rounded,
    gradient: [Color(0xFFE65100), Color(0xFFBF360C)],
    glowColor: Color(0xFFE65100),
  ),
  AvatarConfig(
    id: 'pharaoh',
    name: 'Золотой фараон',
    eraName: 'Бронзовый век',
    icon: Icons.brightness_7_rounded,
    gradient: [Color(0xFFFF8F00), Color(0xFFE65100)],
    glowColor: Color(0xFFFF8F00),
  ),
  AvatarConfig(
    id: 'minotaur',
    name: 'Страж лабиринта',
    eraName: 'Бронзовый век',
    icon: Icons.psychology_alt_rounded,
    gradient: [Color(0xFFD84315), Color(0xFF870000)],
    glowColor: Color(0xFFD84315),
  ),

  // Железный век (Легионы, Сенат, Гладиаторы)
  AvatarConfig(
    id: 'centurion',
    name: 'Легат легиона',
    eraName: 'Железный век',
    icon: Icons.military_tech_rounded,
    gradient: [Color(0xFF546E7A), Color(0xFF263238)],
    glowColor: Color(0xFF78909C),
  ),
  AvatarConfig(
    id: 'gladiator',
    name: 'Гладиатор Колизея',
    eraName: 'Железный век',
    icon: Icons.sports_mma_rounded,
    gradient: [Color(0xFF455A64), Color(0xFF1C313A)],
    glowColor: Color(0xFF90A4AE),
  ),
  AvatarConfig(
    id: 'senator',
    name: 'Римский трибун',
    eraName: 'Железный век',
    icon: Icons.gavel_rounded,
    gradient: [Color(0xFF607D8B), Color(0xFF37474F)],
    glowColor: Color(0xFFB0BEC5),
  ),

  // Средневековье (Рыцари, Алхимики, Монархи)
  AvatarConfig(
    id: 'paladin',
    name: 'Рыцарь ордена',
    eraName: 'Средневековье',
    icon: Icons.shield_rounded,
    gradient: [Color(0xFF8E24AA), Color(0xFF4A148C)],
    glowColor: Color(0xFFBA68C8),
  ),
  AvatarConfig(
    id: 'alchemist',
    name: 'Магистр алхимии',
    eraName: 'Средневековье',
    icon: Icons.science_rounded,
    gradient: [Color(0xFFAB47BC), Color(0xFF6A1B9A)],
    glowColor: Color(0xFFCE93D8),
  ),
  AvatarConfig(
    id: 'monarch',
    name: 'Венценосный монарх',
    eraName: 'Средневековье',
    icon: Icons.workspace_premium_rounded,
    gradient: [Color(0xFF7B1FA2), Color(0xFF311B92)],
    glowColor: Color(0xFFE1BEE7),
  ),

  // Индустриальная эра (Паровые инженеры, Детективы, Авиаторы)
  AvatarConfig(
    id: 'steam_inventor',
    name: 'Инженер пара',
    eraName: 'Индустриальная эпоха',
    icon: Icons.settings_suggest_rounded,
    gradient: [Color(0xFF00ACC1), Color(0xFF006064)],
    glowColor: Color(0xFF4DD0E1),
  ),
  AvatarConfig(
    id: 'aviator',
    name: 'Пионер авиации',
    eraName: 'Индустриальная эпоха',
    icon: Icons.airplanemode_active_rounded,
    gradient: [Color(0xFF0097A7), Color(0xFF00838F)],
    glowColor: Color(0xFF80DEEA),
  ),
  AvatarConfig(
    id: 'detective',
    name: 'Тайный детектив',
    eraName: 'Индустриальная эпоха',
    icon: Icons.fingerprint_rounded,
    gradient: [Color(0xFF26C6DA), Color(0xFF004D40)],
    glowColor: Color(0xFF26C6DA),
  ),

  // Космическая эра (Пилоты, Киборги, ИИ)
  AvatarConfig(
    id: 'star_pilot',
    name: 'Звёздный пилот',
    eraName: 'Космическая эпоха',
    icon: Icons.rocket_launch_rounded,
    gradient: [Color(0xFF651FFF), Color(0xFF311B92)],
    glowColor: Color(0xFF7C4DFF),
  ),
  AvatarConfig(
    id: 'cyborg',
    name: 'Кибер-стратег',
    eraName: 'Космическая эпоха',
    icon: Icons.memory_rounded,
    gradient: [Color(0xFF6200EA), Color(0xFF1A237E)],
    glowColor: Color(0xFFB388FF),
  ),
  AvatarConfig(
    id: 'cosmic_ai',
    name: 'Разум Сингулярности',
    eraName: 'Космическая эпоха',
    icon: Icons.all_inclusive_rounded,
    gradient: [Color(0xFF7C4DFF), Color(0xFF4A148C)],
    glowColor: Color(0xFFEA80FC),
  ),
];

AvatarConfig getAvatarById(String? id) {
  return gameAvatars.firstWhere(
    (a) => a.id == id,
    orElse: () => gameAvatars.first,
  );
}

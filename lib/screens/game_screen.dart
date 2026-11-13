import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/game_controller.dart';
import '../constants/game_config.dart';
import '../services/backend_warmer.dart';
import '../widgets/create_goal_dialog.dart';
import '../widgets/resource_badge.dart';
import '../widgets/tabs/camp_tab.dart';
import '../widgets/tabs/quests_tab.dart';
import '../widgets/tabs/shop_tab.dart';
import '../widgets/tabs/leaderboard_tab.dart';
import 'auth_screen.dart';
import 'focus_timer_screen.dart';
import 'manual_goal_builder_screen.dart';
import 'profile_screen.dart';
import '../widgets/avatar_widget.dart';
import 'preset_library_screen.dart';
import '../widgets/publish_preset_dialog.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GameController controller = GameController();
  SupabaseClient get supabase => controller.supabase;

  String get currentUserId => controller.currentUserId;
  int get gold => controller.gold;
  int get energy => controller.energy;
  int get maxEnergy => controller.maxEnergy;
  int get xp => controller.xp;
  int get streak => controller.streak;
  int get shields => controller.shields;
  int get maxGoals => controller.maxGoals;
  int get campLevel => controller.campLevel;

  bool get isInitialLoading => controller.isInitialLoading;
  String? get loadErrorMessage => controller.loadErrorMessage;
  bool get isOfflineMode => controller.isOfflineMode;
  bool get isCompletingQuest => controller.isCompletingQuest;

  Map<String, dynamic>? get profile => controller.profile;
  List<Map<String, dynamic>> get quests => controller.quests;
  List<Map<String, dynamic>> get goals => controller.goals;
  Set<String> get completedQuestIds => controller.completedQuestIds;

  EraConfig get currentEra => controller.currentEra;
  int get currentEraIndex => controller.currentEraIndex;
  bool get isMaxEra => controller.isMaxEra;
  bool get canEvolve => controller.canEvolve;
  double get streakMultiplier => controller.streakMultiplier;
  bool get isDecayed => controller.isDecayed;

  int _selectedTabIndex = 0;
  String? selectedGoalId;
  bool hideCompleted = false;

  /// Вкладки, которые игрок уже открывал. Остальные не строятся: раньше
  /// IndexedStack создавал все четыре сразу, и вкладка «Рейтинг» тянула
  /// данные из сети при запуске игры, даже если её не открывали.
  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerUpdate);

    // Прогрев backend: бесплатный тариф Render останавливает контейнер после
    // ~15 минут простоя, поэтому держим его разбуженным, пока игра открыта.
    backendWarmer.start();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.loadGameData();
      _showLeagueAwardIfAny();
    });
  }

  /// Награда за прошедший сезон лиги: сервер начислил золото при загрузке,
  /// игроку надо об этом сказать. Показываем один раз.
  void _showLeagueAwardIfAny() {
    final message = controller.consumeLeagueAwardMessage();
    if (message == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    backendWarmer.stop();
    controller.removeListener(_onControllerUpdate);
    controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _openPublishPresetDialog([String? goalId]) {
    if (goals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет своих целей для публикации')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => PublishPresetDialog(
        userId: currentUserId,
        authorName: profile?['username'] ?? 'Правитель',
        primaryColor: currentEra.primaryColor,
        goals: goals,
        quests: quests,
        initialGoalId: goalId,
        onPublished: () {},
      ),
    );
  }

  void _updateCompletedQuestIds() => controller.updateCompletedQuestIds();

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: currentUserId,
          isCurrentUser: true,
          initialProfile: profile,
          controller: controller,
          onPromoRedeemed: () => loadGameData(isSilent: true),
          onLogout: _logout,
        ),
      ),
    ).then((_) => loadGameData(isSilent: true));
  }

  void _enableOfflineDemo() {
    controller.enableOfflineDemo();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Офлайн-режим. Прогресс не сохраняется.')),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Выход из аккаунта'),
        content: const Text('Выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> loadGameData({bool isSilent = false}) async {
    await controller.loadGameData(isSilent: isSilent);
    _showLeagueAwardIfAny();
  }

  bool isQuestUnlocked(Map<String, dynamic> quest) =>
      controller.isQuestUnlocked(quest);

  Future<void> completeQuest(Map<String, dynamic> quest) async {
    if (controller.energy <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Энергия закончилась. Восстановится завтра.'),
        ),
      );
      return;
    }

    final success = await controller.completeQuestAtomic(quest);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.lastQuestError ?? 'Не удалось сохранить. Повторите.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _editGoalTitle(String goalId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Редактировать цель',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Название цели',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentEra.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == currentTitle) {
      return;
    }

    setState(() {
      final goalIndex = goals.indexWhere((g) => g['id'].toString() == goalId);
      if (goalIndex != -1) {
        goals[goalIndex]['title'] = newTitle;
      }
    });

    if (!isOfflineMode) {
      try {
        await supabase
            .from('goals')
            .update({'title': newTitle})
            .eq('id', goalId)
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('Error updating goal title: $e');
      }
    }
  }

  Future<void> _deleteGoal(String goalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить цель?'),
        content: const Text(
          'Цель и её квесты удалятся. XP и золото останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      goals.removeWhere((g) => g['id'].toString() == goalId);
      quests.removeWhere((q) => q['goal_id'].toString() == goalId);
      _updateCompletedQuestIds();
      if (selectedGoalId == goalId) {
        selectedGoalId = null;
      }
    });

    if (!isOfflineMode) {
      try {
        await supabase
            .from('quests')
            .delete()
            .eq('goal_id', goalId)
            .timeout(const Duration(seconds: 5));
        await supabase
            .from('goals')
            .delete()
            .eq('id', goalId)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Error deleting goal: $e');
      }
    }
  }

  Future<void> _editQuest(Map<String, dynamic> quest) async {
    final titleController = TextEditingController(text: quest['title'] ?? '');
    final durationController = TextEditingController(
      text: (quest['timer_duration_minutes'] ?? 25).toString(),
    );
    bool isTimer = quest['is_timer_based'] == true;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Редактировать квест',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Задача',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8E95A5)),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: titleController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: Color(0xFFF5A623),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Награда: +${quest['xp_reward']} XP  •  +${quest['gold_reward']}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF5A623),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.monetization_on_rounded,
                            size: 13,
                            color: Color(0xFFF5A623),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Таймер фокуса',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: isTimer,
                  activeThumbColor: currentEra.primaryColor,
                  onChanged: (val) => setDialogState(() => isTimer = val),
                ),
                if (isTimer) ...[
                  const Text(
                    'Минут фокуса',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8E95A5)),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: currentEra.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (updated != true) return;

    final newTitle = titleController.text.trim();
    if (newTitle.isEmpty) return;

    final newDuration = int.tryParse(durationController.text.trim()) ?? 25;

    setState(() {
      quest['title'] = newTitle;
      quest['is_timer_based'] = isTimer;
      quest['timer_duration_minutes'] = isTimer ? newDuration : null;
    });

    if (!isOfflineMode) {
      try {
        await supabase
            .from('quests')
            .update({
              'title': newTitle,
              'is_timer_based': isTimer,
              'timer_duration_minutes': isTimer ? newDuration : null,
            })
            .eq('id', quest['id'])
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('Error updating quest: $e');
      }
    }
  }

  /// Единая точка покупки в магазине.
  ///
  /// Цену, лимиты и достаток золота проверяет серверная функция
  /// `buy_consumable`. Клиент только отправляет вид товара и количество,
  /// а состояние профиля берёт из ответа — локально ничего не досчитывается.
  Future<void> _buyShopItem({required String kind, required int count}) async {
    if (count <= 0) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    final result = await controller.buyConsumable(kind, count);
    if (!mounted) return;

    if (!result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final parts = <String>[];
    if (result.energyAdded > 0) parts.add('+${result.energyAdded} энергии');
    if (result.shieldsAdded > 0) parts.add('+${result.shieldsAdded} щитов');

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Куплено: ${parts.isEmpty ? (result.detail ?? kind) : parts.join(' ')}'
          '${result.paid > 0 ? ' за ${result.paid} золота' : ''}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _restoreStreakDialog() async {
    const int restorePrice = 150;
    final currentGold = (profile?['gold'] as num?)?.toInt() ?? 0;
    final streak = profile?['streak_count'] ?? 0;
    final canAfford = currentGold >= restorePrice;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.account_balance_rounded,
              size: 26,
              color: currentEra.primaryColor,
            ),
            const SizedBox(width: 8),
            const Text(
              'Серия прервана',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Пропущен день, щитов нет. Серия $streak дн. заморожена.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    size: 20,
                    color: Color(0xFFF5A623),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Стоимость: $restorePrice золота\n(У вас: $currentGold)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: canAfford
                          ? const Color(0xFFF5A623)
                          : const Color(0xFFFF5252),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Если не восстановить сегодня, серия обнулится.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8E95A5)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Позже'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canAfford
                  ? currentEra.primaryColor
                  : const Color(0xFF232732),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: canAfford
                ? () async {
                    Navigator.pop(ctx);

                    if (isOfflineMode) {
                      controller.updateLocalProfile({
                        'gold': currentGold - restorePrice,
                        'is_decayed': false,
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Серия восстановлена'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      return;
                    }

                    // Онлайн: цену и условие упадка проверяет сервер.
                    final result = await controller.restoreStreak();
                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.success
                              ? 'Серия восстановлена'
                              : result.message,
                        ),
                        backgroundColor: result.success
                            ? Colors.green
                            : Colors.redAccent,
                      ),
                    );
                  }
                : null,
            child: const Text('Восстановить серию ($restorePrice золота)'),
          ),
        ],
      ),
    );
  }

  void _upgradeCampDialog() {
    // Выбор следующей постройки вынесен в конфиг, чтобы индексы и цены
    // не расходились между интерфейсом и расчётом бонусов.
    final nextBuilding = nextCampBuilding(currentEra.id, campLevel);
    if (nextBuilding == null) return;

    final price = nextBuilding.price;
    final canAfford = gold >= price;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Icon(nextBuilding.icon, size: 28, color: currentEra.primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Постройка: ${nextBuilding.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Лагерь, уровень ${nextBuilding.reqLevel}/5',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8E95A5),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF14171E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFF00E676),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nextBuilding.bonusDesc,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E676),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF14171E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF5A623).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      size: 20,
                      color: Color(0xFFF5A623),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Стоимость: $price золота\n(В казне: $gold)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: canAfford
                            ? const Color(0xFFF5A623)
                            : const Color(0xFFFF5252),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canAfford
                    ? currentEra.primaryColor
                    : const Color(0xFF232732),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (canAfford && !isProcessing)
                  ? () async {
                      setDialogState(() => isProcessing = true);
                      Navigator.pop(ctx);

                      // Цену, эффект постройки и достаток золота проверяет серверная
                      // функция upgrade_camp. Клиент ничего не досчитывает — раньше
                      // здесь дублировалась вся арифметика и писался абсолютный профиль.
                      final result = await controller.upgradeCamp();
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.success
                                ? '${result.detail ?? nextBuilding.name} построен. Бонус активен.'
                                : result.message,
                          ),
                          backgroundColor: result.success
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                      );
                    }
                  : null,
              child: Text('Построить за $price золота'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerEvolution() async {
    final nextIndex = eraOrder.indexOf(currentEra.id) + 1;
    if (nextIndex >= eraOrder.length) return;

    final nextEra = eras[eraOrder[nextIndex]]!;

    if (isOfflineMode) {
      // Офлайн: сервера нет, эволюция идёт по локальному конфигу.
      final eraConfig = eras[currentEra.id]!;
      final int newXp = (xp - eraConfig.xpRequired).clamp(0, 1 << 30);
      final int newGold = gold + nextEra.goldBonus;
      final int newMaxEnergy = maxEnergy + (nextEra.increasesMaxEnergy ? 1 : 0);

      controller.updateLocalProfile({
        'current_era': nextEra.id,
        'xp': newXp,
        'gold': newGold,
        'max_energy': newMaxEnergy,
        'energy': newMaxEnergy,
        'camp_level': 1,
      });
      showEvolutionDialog(nextEra);
      return;
    }

    // Онлайн: пороги XP, бонус и сброс лагеря проверяет сервер. Клиент только
    // получает новое состояние и показывает диалог.
    final result = await controller.evolveEra(nextEra.id);
    if (!mounted) return;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showEvolutionDialog(nextEra);
  }

  void showEvolutionDialog(EraConfig newEra) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: newEra.primaryColor.withValues(alpha: 0.4)),
        ),
        backgroundColor: const Color(0xFF1A1D24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Icon(newEra.icon, size: 64, color: newEra.primaryColor),
            const SizedBox(height: 12),
            const Text(
              'Новая эпоха',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Color(0xFFF5A623),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              newEra.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: newEra.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        size: 16,
                        color: Color(0xFFF5A623),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Награда',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF5A623),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+${newEra.goldBonus} золота',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Энергия восстановлена',
                    style: TextStyle(color: Color(0xFF8E95A5)),
                  ),
                  if (newEra.increasesMaxEnergy)
                    const Text(
                      'Максимум энергии +1',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: newEra.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Дальше',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExpandSlotsDialog({
    required int currentSlots,
    required int nextPrice,
  }) {
    final currentGold = (profile?['gold'] as num?)?.toInt() ?? 0;
    final canAfford = currentGold >= nextPrice;
    final nextSlotNum = currentSlots + 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.account_balance_rounded,
              size: 26,
              color: Color(0xFFF5A623),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Слот №$nextSlotNum',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Все слоты заняты. Откройте новый, чтобы взять ещё направление.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    size: 22,
                    color: Color(0xFFF5A623),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Стоимость: $nextPrice золота\n(У вас: $currentGold)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: canAfford
                          ? const Color(0xFFF5A623)
                          : const Color(0xFFFF5252),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canAfford
                  ? currentEra.primaryColor
                  : const Color(0xFF232732),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: canAfford
                ? () async {
                    Navigator.pop(ctx);

                    if (isOfflineMode) {
                      controller.updateLocalProfile({
                        'gold': currentGold - nextPrice,
                        'max_active_goals': nextSlotNum,
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Слот №$nextSlotNum открыт'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        showCreateGoalDialog();
                      }
                      return;
                    }

                    // Онлайн: цену и лимит слотов проверяет серверная функция.
                    final result = await controller.buyGoalSlot();
                    if (!mounted) return;

                    if (!result.success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result.message),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Слот открыт'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    showCreateGoalDialog();
                  }
                : null,
            child: Text('Купить за $nextPrice золота'),
          ),
        ],
      ),
    );
  }

  void showCreateGoalDialog() {
    final int maxAllowedSlots =
        (profile?['max_active_goals'] as num?)?.toInt() ?? 2;

    final activeGoals = goals.where((g) {
      final goalQuests = quests.where(
        (q) => q['goal_id']?.toString() == g['id']?.toString(),
      );
      return goalQuests.any((q) => q['is_completed'] != true);
    }).toList();

    if (activeGoals.length >= maxAllowedSlots) {
      final nextPrice = nextGoalSlotPrice(maxAllowedSlots);

      if (nextPrice != null) {
        _showExpandSlotsDialog(
          currentSlots: maxAllowedSlots,
          nextPrice: nextPrice,
        );
      } else {
        _showLimitAlert(
          title: 'Все слоты заняты',
          message: 'Активных направлений 5 из 5.\n\nЗавершите или удалите цель, чтобы взять новую.',
        );
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Позволяет шторке подстраиваться по высоте
      backgroundColor: const Color(0xFF14171E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF14171E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Color(0x28FFFFFF), width: 1.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Новая цель',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'В работе: ${activeGoals.length} из $maxAllowedSlots направлений',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E95A5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                _creationOptionTile(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: const Color(0xFF00B0FF),
                  title: 'Сгенерировать цель',
                  subtitle: 'ИИ разобьёт цель на шаги',
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (dialogCtx) => CreateGoalDialog(
                        primaryColor: currentEra.primaryColor,
                        userId: currentUserId,
                        onGoalCreated: () => loadGameData(isSilent: true),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _creationOptionTile(
                  icon: Icons.local_library_rounded,
                  iconColor: const Color(0xFF00E676),
                  title: 'Библиотека целей',
                  subtitle: 'Готовые цели: спорт, учёба, привычки',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PresetLibraryScreen(
                          userId: currentUserId,
                          primaryColor: currentEra.primaryColor,
                          currentActiveGoalsCount: activeGoals.length,
                          maxAllowedGoals: maxAllowedSlots,
                          controller: controller,
                          onGoalActivated: () => loadGameData(isSilent: true),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _creationOptionTile(
                  icon: Icons.edit_note_rounded,
                  iconColor: const Color(0xFFF5A623),
                  title: 'Собрать вручную',
                  subtitle: 'Свои шаги и сложность',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ManualGoalBuilderScreen(
                          primaryColor: currentEra.primaryColor,
                          userId: currentUserId,
                          eraId: currentEra.id,
                          onGoalCreated: () => loadGameData(isSilent: true),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _creationOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                shape: BoxShape.circle,
                border: Border.all(color: iconColor.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: iconColor, size: 24),
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
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8E95A5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Color(0xFF8E95A5),
            ),
          ],
        ),
      ),
    );
  }

  void _showLimitAlert({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.account_balance_rounded,
              size: 26,
              color: Color(0xFFF5A623),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentEra.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  void showQuestDetailsSheet(Map<String, dynamic> q, bool isUnlocked) {
    if (isCompletingQuest) return;

    final isCompleted = q['is_completed'] == true;
    final era = currentEra;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14171E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF14171E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Color(0x28FFFFFF), width: 1.5)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Полоска перетаскивания шторки
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Верхняя плашка статуса и наград
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF00E676).withValues(alpha: 0.15)
                        : (isUnlocked
                              ? era.primaryColor.withValues(alpha: 0.18)
                              : const Color(0xFF1A1D24)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCompleted
                          ? const Color(0xFF00E676).withValues(alpha: 0.5)
                          : (isUnlocked
                                ? era.primaryColor.withValues(alpha: 0.5)
                                : const Color(0x1AFFFFFF)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCompleted
                            ? Icons.check_circle_rounded
                            : (isUnlocked
                                  ? Icons.bolt_rounded
                                  : Icons.lock_rounded),
                        size: 14,
                        color: isCompleted
                            ? const Color(0xFF00E676)
                            : (isUnlocked
                                  ? era.primaryColor
                                  : const Color(0xFF8E95A5)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCompleted
                            ? 'Выполнено'
                            : (isUnlocked ? 'Активный квест' : 'Заблокировано'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isCompleted
                              ? const Color(0xFF00E676)
                              : (isUnlocked
                                    ? era.primaryColor
                                    : const Color(0xFF8E95A5)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '+${q['xp_reward']} XP',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: era.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '+${q['gold_reward']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: Color(0xFFF5A623),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.monetization_on_rounded,
                            size: 14,
                            color: Color(0xFFF5A623),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isCompleted) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: Color(0xFF8E95A5),
                    ),
                    tooltip: 'Редактировать',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editQuest(q);
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Название квеста (теперь ярко-белое и четкое)
            Text(
              q['title'] ?? '',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.3,
              ),
            ),

            if (q['is_timer_based'] == true) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D24),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: Color(0xFFF5A623),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Фокус: ${q['timer_duration_minutes']} мин',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Кнопка действия
            if (!isCompleted && isUnlocked)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: era.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  onPressed: () async {
                    if (controller.energy <= 0) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Энергия закончилась. Восстановится завтра.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(ctx);
                    if (q['is_timer_based'] == true) {
                      // Серверная сессия фокуса: фиксирует время старта, без неё
                      // квест с таймером сдать нельзя. Запускаем до открытия
                      // экрана, чтобы отсчёт сервера и клиента совпадали.
                      if (!isOfflineMode) {
                        await controller.startFocusSession(q['id'].toString());
                        if (!mounted) return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FocusTimerScreen(
                            quest: q,
                            era: era,
                            onComplete: () => completeQuest(q),
                          ),
                        ),
                      );
                    } else {
                      completeQuest(q);
                    }
                  },
                  icon: Icon(
                    q['is_timer_based'] == true
                        ? Icons.play_arrow_rounded
                        : Icons.check_circle_rounded,
                    size: 22,
                  ),
                  label: Text(
                    q['is_timer_based'] == true
                        ? 'Начать фокус (${q['timer_duration_minutes'] ?? 25} мин)'
                        : 'Сдать квест (1 энергия)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            else if (!isUnlocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D24),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Color(0xFF8E95A5),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Сначала закройте предыдущий шаг',
                      style: TextStyle(
                        color: Color(0xFF8E95A5),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showResourceInfo(
    IconData icon,
    String title,
    String description,
    List<String> bulletPoints,
    Color color,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF8E95A5),
              ),
            ),
            const SizedBox(height: 16),
            ...bulletPoints.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withValues(alpha: 0.2),
              foregroundColor: color,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: color.withValues(alpha: 0.5)),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Понятно',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitialLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Загрузка…',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8E95A5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (loadErrorMessage != null && profile == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 72,
                  color: Color(0xFFF5A623),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Нет связи с сервером',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  loadErrorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8E95A5),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => loadGameData(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'Повторить',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8E95A5),
                    side: const BorderSide(color: Color(0x28FFFFFF)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _enableOfflineDemo,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(
                    'Демо-режим (офлайн)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final era = currentEra;
    final int currentXp = (profile?['xp'] as num?)?.toInt() ?? 0;
    final double progressPercent = (currentXp / era.xpRequired).clamp(0.0, 1.0);
    final topPadding = MediaQuery.paddingOf(context).top;

    final double streakMult =
        (profile?['streak_multiplier'] as num?)?.toDouble() ?? 1.0;
    final double streakBonusPercent = ((streakMult - 1.0) * 100).clamp(
      0.0,
      999.0,
    );

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60 + topPadding),
        child: Container(
          padding: EdgeInsets.only(
            top: topPadding + 6,
            left: 10,
            right: 10,
            bottom: 8,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF14171E),
            border: Border(
              bottom: BorderSide(color: Color(0x14FFFFFF), width: 1.2),
            ),
          ),
          child: Row(
            children: [
              AvatarWidget(
                avatarId: profile?['avatar_id'],
                size: 36,
                showGlow: true,
                onTap: _openProfile,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ResourceBadge(
                  icon: (profile?['is_decayed'] == true)
                      ? Icons.warning_rounded
                      : Icons.local_fire_department_rounded,
                  text: (profile?['is_decayed'] == true)
                      ? '${profile?['streak_count'] ?? 0} SOS'
                      : '${profile?['streak_count'] ?? 0} (+${streakBonusPercent.toStringAsFixed(0)}%)',
                  color: (profile?['is_decayed'] == true)
                      ? const Color(0xFFFF5252)
                      : const Color(0xFFFF7A00),
                  onTap: () {
                    if (profile?['is_decayed'] == true) {
                      _restoreStreakDialog();
                    } else {
                      _showResourceInfo(
                        Icons.local_fire_department_rounded,
                        'Серия и множитель',
                        'Дней подряд с квестами',
                        [
                          'Каждый день серии даёт +0.5% к наградам',
                          'Множитель ×${streakMult.toStringAsFixed(2)} (+${((streakMult - 1.0) * 100).toStringAsFixed(1)}%)',
                          'Пропуск дня списывает 1 щит',
                          'Без щитов серию можно спасти за золото в течение суток',
                        ],
                        const Color(0xFFFF7A00),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ResourceBadge(
                  icon: Icons.bolt_rounded,
                  text:
                      '${profile?['energy'] ?? 0}/${profile?['max_energy'] ?? 5}',
                  color: const Color(0xFF00B0FF),
                  onTap: () => _showResourceInfo(
                    Icons.bolt_rounded,
                    'Запас энергии',
                    'Тратится на квесты',
                    const [
                      'Квест стоит 1 энергии',
                      'Восполняется раз в сутки',
                      '+1 к лимиту на каждой второй эпохе',
                    ],
                    const Color(0xFF00B0FF),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ResourceBadge(
                  icon: Icons.shield_rounded,
                  text: '${profile?['shields_left'] ?? 3}',
                  color: const Color(0xFF00E676),
                  onTap: () => _showResourceInfo(
                    Icons.shield_rounded,
                    'Щиты заморозки',
                    'Защищают серию при пропуске дня',
                    const [
                      'Пропуск дня списывает 1 щит',
                      'Сохраняют серию и множитель',
                      'Продаются в магазине',
                    ],
                    const Color(0xFF00E676),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ResourceBadge(
                  icon: Icons.monetization_on_rounded,
                  text: '${profile?['gold'] ?? 0}',
                  color: const Color(0xFFF5A623),
                  onTap: () => _showResourceInfo(
                    Icons.monetization_on_rounded,
                    'Казна',
                    'Золото за квесты',
                    const [
                      'Начисляется за квесты',
                      'Бонус за переход в новую эпоху',
                      'Тратится в магазине',
                    ],
                    const Color(0xFFF5A623),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          // Вкладка строится при первом открытии и остаётся в дереве дальше,
          // поэтому её состояние (прокрутка, фильтры) сохраняется. До первого
          // открытия на её месте заглушка: иначе IndexedStack создавал все
          // вкладки сразу, и «Рейтинг» тянул данные из сети при запуске игры.
          CampTab(
            era: era,
            eraIndex: currentEraIndex,
            currentXp: currentXp,
            progressPercent: progressPercent,
            isMaxEra: isMaxEra,
            profile: profile,
            campLevel: campLevel,
            canEvolve: canEvolve,
            onLogout: _logout,
            onRestoreStreak: _restoreStreakDialog,
            onUpgradeCamp: _upgradeCampDialog,
            onEvolve: _triggerEvolution,
          ),
          if (!_visitedTabs.contains(1))
            const SizedBox.shrink()
          else
            QuestsTab(
              era: era,
              quests: quests,
              goals: goals,
              selectedGoalId: selectedGoalId,
              hideCompleted: hideCompleted,
              isQuestUnlocked: isQuestUnlocked,
              onQuestTap: (q, unlocked) => showQuestDetailsSheet(q, unlocked),
              onGoalSelected: (id) => setState(() => selectedGoalId = id),
              onToggleHideCompleted: () =>
                  setState(() => hideCompleted = !hideCompleted),
              onEditGoal: _editGoalTitle,
              onDeleteGoal: _deleteGoal,
              onShareGoal: (goalId) => _openPublishPresetDialog(goalId),
              onOpenPresetsLibrary: () {
                final maxAllowedSlots =
                    (profile?['max_active_goals'] as num?)?.toInt() ?? 2;
                final activeCount = goals.where((g) {
                  final gq = quests.where(
                    (q) => q['goal_id']?.toString() == g['id']?.toString(),
                  );
                  return gq.any((q) => q['is_completed'] != true);
                }).length;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PresetLibraryScreen(
                      userId: currentUserId,
                      primaryColor: currentEra.primaryColor,
                      currentActiveGoalsCount: activeCount,
                      maxAllowedGoals: maxAllowedSlots,
                      controller: controller,
                      onGoalActivated: () => loadGameData(isSilent: true),
                    ),
                  ),
                );
              },
            ),
          if (!_visitedTabs.contains(2))
            const SizedBox.shrink()
          else
            ShopTab(
              gold: (profile?['gold'] as num?)?.toInt() ?? 0,
              energy: (profile?['energy'] as num?)?.toInt() ?? 0,
              maxEnergy: (profile?['max_energy'] as num?)?.toInt() ?? 5,
              shields: (profile?['shields_left'] as num?)?.toInt() ?? 0,
              goalSlots: (profile?['max_active_goals'] as num?)?.toInt() ?? 2,
              primaryColor: era.primaryColor,
              eraId: era.id,
              onBuyGoalSlot: () {
                final cur =
                    (profile?['max_active_goals'] as num?)?.toInt() ?? 2;
                final price = nextGoalSlotPrice(cur);
                if (price != null) {
                  _showExpandSlotsDialog(currentSlots: cur, nextPrice: price);
                }
              },
              // Количество продаваемого ограничивает сервер: он отвечает
              // SHOP_COUNT_TOO_HIGH, если зелий не влезет или щиты упрутся
              // в максимум. Клиент ничего не клампит молча.
              onBuyEnergy: (count) =>
                  _buyShopItem(kind: 'energy', count: count),
              onBuyShield: (count) =>
                  _buyShopItem(kind: 'shields', count: count),
            ),
          if (!_visitedTabs.contains(3))
            const SizedBox.shrink()
          else
            LeaderboardTab(
              era: era,
              profile: profile,
              currentUserId: currentUserId,
              controller: controller,
              isVisible: _selectedTabIndex == 3,
            ),
        ],
      ),
      floatingActionButton: _selectedTabIndex == 1
          ? FloatingActionButton.extended(
              backgroundColor: era.primaryColor,
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: showCreateGoalDialog,
              icon: const Icon(Icons.add),
              label: const Text(
                'Новая цель',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        // Переход на «Рейтинг» больше не тянет loadGameData: сама вкладка
        // обновляет данные при входе на неё. Раньше это давало до шести
        // сетевых запросов на одно нажатие.
        onTap: (index) => setState(() {
          _selectedTabIndex = index;
          _visitedTabs.add(index);
        }),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF14171E),
        selectedItemColor: const Color(0xFFF5A623),
        unselectedItemColor: const Color(0xFF8E95A5),
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Лагерь',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.alt_route_rounded),
            label: 'Квесты',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag_rounded),
            label: 'Магазин',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_rounded),
            label: 'Рейтинг',
          ),
        ],
      ),
    );
  }
}

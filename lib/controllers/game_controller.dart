// FILE: lib/controllers/game_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/game_config.dart';

class GameController extends ChangeNotifier {
  /// Ленивая инициализация: клиент запрашивается только при первом обращении
  /// к сети. В офлайн-режиме Supabase вообще не нужен — новичок мог включить
  /// демо-режим раньше, чем приложение подключилось к проекту.
  SupabaseClient get supabase => Supabase.instance.client;

  /// Контроллер в офлайн-режиме с демо-данными (для тестов и демо-входа).
  factory GameController.offlineDemo() => GameController()..enableOfflineDemo();

  GameController();

  /// Флаг «уведомление уже запланировано», чтобы несколько изменений подряд
  /// давали одну перерисовку. Одна сдача квеста меняет профиль, список
  /// квестов и флаг «идёт сдача» — раньше это было четыре перерисовки всего
  /// экрана, включая невидимые вкладки.
  bool _notifyScheduled = false;
  bool _isDisposed = false;

  /// Планирует перерисовку один раз на текущую микрозадачу.
  void _notify() {
    if (_notifyScheduled || _isDisposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_isDisposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  bool isInitialLoading = true;
  String? loadErrorMessage;
  bool isCompletingQuest = false;
  bool isOfflineMode = false;

  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> quests = [];
  List<Map<String, dynamic>> goals = [];
  Set<String> completedQuestIds = {};

  /// Квесты, по которым уже идёт запрос на сдачу — защита от двойного нажатия.
  final Set<String> _questsInFlight = {};

  /// Активные серверные сессии фокуса: id квеста → id сессии.
  /// Нужны, чтобы передать серверу доказательство, что время фокуса прошло.
  final Map<String, String> _focusSessions = {};

  /// Текст последней неудачной сдачи квеста — показывается игроку вместо
  /// общего «не удалось подтвердить».
  String? lastQuestError;

  /// ID текущего игрока.
  ///
  /// В офлайн-режиме обращаться к Supabase нельзя: демо может работать без
  /// подключённого проекта. Раньше геттер всегда дёргал клиент и падал
  /// с ошибкой инициализации.
  String get currentUserId {
    if (isOfflineMode) return _offlineUserId;
    return supabase.auth.currentUser?.id ?? '';
  }

  static const String _offlineUserId = 'offline_demo_user';
  String get userTag => profile?['user_tag'] ?? '';
  int get gold => (profile?['gold'] as num?)?.toInt() ?? 0;
  int get energy => (profile?['energy'] as num?)?.toInt() ?? 0;
  int get maxEnergy => (profile?['max_energy'] as num?)?.toInt() ?? 5;
  int get xp => (profile?['xp'] as num?)?.toInt() ?? 0;
  int get streak => (profile?['streak_count'] as num?)?.toInt() ?? 0;
  int get shields => (profile?['shields_left'] as num?)?.toInt() ?? 0;
  int get maxGoals => (profile?['max_active_goals'] as num?)?.toInt() ?? 2;
  int get campLevel => (profile?['camp_level'] as num?)?.toInt() ?? 1;
  double get streakMultiplier =>
      (profile?['streak_multiplier'] as num?)?.toDouble() ?? 1.0;
  bool get isDecayed => profile?['is_decayed'] == true;

  EraConfig get currentEra =>
      eras[profile?['current_era']] ?? eras['stone_age']!;
  int get currentEraIndex =>
      eraOrder.indexOf(profile?['current_era'] ?? 'stone_age');
  bool get isMaxEra => currentEraIndex == eraOrder.length - 1;

  /// Постоянные бонусы построек лагеря. Считаются из конфига построек,
  /// поэтому цифра в описании постройки и реальный эффект всегда совпадают.
  double get campGoldBonusMultiplier =>
      campBonusMultipliers(currentEra.id, campLevel).gold;

  double get campXpBonusMultiplier =>
      campBonusMultipliers(currentEra.id, campLevel).xp;

  /// Итоговый множитель золота за квест: серия * бонусы лагеря.
  double get effectiveGoldMultiplier =>
      streakMultiplier * (1.0 + campGoldBonusMultiplier);

  /// Итоговый множитель опыта за квест: серия * бонусы лагеря.
  double get effectiveXpMultiplier =>
      streakMultiplier * (1.0 + campXpBonusMultiplier);

  bool get canEvolve {
    final nextIndex = currentEraIndex + 1;
    if (nextIndex >= eraOrder.length) return false;
    return xp >= currentEra.xpRequired && campLevel >= 5;
  }

  void updateCompletedQuestIds() {
    completedQuestIds = quests
        .where((q) => q['is_completed'] == true)
        .map<String>((q) => q['id'].toString())
        .toSet();
    _notify();
  }

  void enableOfflineDemo() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    isOfflineMode = true;
    loadErrorMessage = null;
    profile = {
      'id': currentUserId,
      'xp': 365,
      'gold': 55,
      'energy': 6,
      'max_energy': 6,
      'current_era': 'iron_age',
      'streak_count': 2,
      'streak_multiplier': 1.02,
      'shields_left': 6,
      'is_decayed': false,
      'last_active_date': today,
    };
    goals = [
      {'id': 'goal_1', 'user_id': currentUserId, 'title': 'научиться моргать'},
    ];
    quests = [
      // Награды офлайн-демо берутся из коридора Каменного века — той же
      // кривой, что и в игре, иначе демо показывало бы неправду.
      {
        'id': 'quest_1',
        'goal_id': 'goal_1',
        'title': 'Изучить основы по цели: научиться моргать',
        'xp_reward': economyFor('stone_age').xpMax,
        'gold_reward': economyFor('stone_age').goldMax,
        'is_completed': true,
        'parent_quest_id': null,
        'is_timer_based': false,
      },
      {
        'id': 'quest_2',
        'goal_id': 'goal_1',
        'title': '25 минут непрерывной практики',
        'xp_reward': economyFor('stone_age').xpMid,
        'gold_reward': economyFor('stone_age').goldMid,
        'is_completed': true,
        'parent_quest_id': 'quest_1',
        'is_timer_based': true,
        'timer_duration_minutes': 25,
      },
      {
        'id': 'quest_3',
        'goal_id': 'goal_1',
        'title': 'Закрепить первый результат на практике',
        'xp_reward': economyFor('stone_age').xpMax,
        'gold_reward': economyFor('stone_age').goldMax,
        'is_completed': true,
        'parent_quest_id': 'quest_2',
        'is_timer_based': false,
      },
    ];
    updateCompletedQuestIds();
    _notify();
  }

  bool isQuestUnlocked(Map<String, dynamic> quest) {
    if (quest['is_completed'] == true) return true;
    final parentId = quest['parent_quest_id']?.toString();
    if (parentId == null || parentId.isEmpty) return true;
    return completedQuestIds.contains(parentId);
  }

  Future<void> loadGameData({bool isSilent = false}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (!isSilent && profile == null) {
      isInitialLoading = true;
      loadErrorMessage = null;
      _notify();
    }

    try {
      final results = await Future.wait([
        supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 6)),
        supabase
            .from('goals')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 6)),
        supabase
            .from('quests')
            .select('*, goals!inner(user_id)')
            .eq('goals.user_id', user.id)
            .order('created_at', ascending: true)
            .timeout(const Duration(seconds: 6)),
      ]);

      final profileRes = results[0] as Map<String, dynamic>?;
      goals = List<Map<String, dynamic>>.from((results[1] as List?) ?? []);
      final rawQuests = List<Map<String, dynamic>>.from(
        (results[2] as List?) ?? [],
      );

      // Топологическая сортировка: выстраиваем квесты строго по цепочке от корня
      final List<Map<String, dynamic>> sortedQuests = [];
      final Map<String?, List<Map<String, dynamic>>> byParent = {};
      for (var q in rawQuests) {
        final pId = q['parent_quest_id']?.toString();
        byParent.putIfAbsent(pId, () => []).add(q);
      }

      void appendBranch(String? parentId) {
        final children = byParent[parentId] ?? [];
        for (var child in children) {
          sortedQuests.add(child);
          appendBranch(child['id'].toString());
        }
      }

      appendBranch(null); // Начинаем с корневых квестов без родителя
      // Добавляем оставшиеся оторванные квесты (если есть)
      for (var q in rawQuests) {
        if (!sortedQuests.contains(q)) sortedQuests.add(q);
      }
      quests = sortedQuests;

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      Map<String, dynamic> profileData;

      if (profileRes == null) {
        final metaTag = (user.userMetadata?['user_tag'] as String?)
            ?.toLowerCase();
        final userEmail = user.email ?? '';
        final fallbackTag =
            metaTag ??
            (userEmail.contains('@')
                ? userEmail.split('@').first
                : 'player_${user.id.substring(0, 5)}');

        profileData = {
          'id': user.id,
          'user_tag': fallbackTag,
          'username': fallbackTag,
          'xp': 0,
          'gold': 100,
          'energy': 5,
          'max_energy': 5,
          'max_active_goals': 2,
          'camp_level': 1,
          'current_era': 'stone_age',
          'streak_count': 1,
          'streak_multiplier': 1.0,
          'shields_left': 3,
          'is_decayed': false,
          'last_active_date': todayStr,
        };
        try {
          await supabase
              .from('profiles')
              .upsert(profileData, ignoreDuplicates: true)
              .timeout(const Duration(seconds: 4));
        } catch (e) {
          // Дубликат означает, что профиль уже создан параллельным запросом —
          // это не ошибка. Молча проглатываем только дубликат, остальное логируем.
          final text = e.toString();
          final isDuplicate =
              text.contains('23505') ||
              text.toLowerCase().contains('duplicate');
          if (!isDuplicate) {
            debugPrint('Profile creation failed: $e');
          }
        }
      } else {
        profileData = Map<String, dynamic>.from(profileRes);
      }

      // Суточный пересчёт (энергия, щиты, серия, упадок) выполняет серверная
      // функция apply_daily_reset. Раньше это считалось здесь и записывалось
      // в profiles абсолютными значениями — то есть энергия и щиты были
      // подконтрольны клиенту.
      await _applyDailyReset(profileData);

      // Итоги сезона лиги подводит первый зашедший: награда за топ-3 каждой
      // лиги начисляется здесь же.
      await settleLeagueSeason(profileData);

      profile = profileData;
      updateCompletedQuestIds();
      loadErrorMessage = null;
      isOfflineMode = false;
    } catch (e) {
      if (profile == null) loadErrorMessage = e.toString();
    } finally {
      isInitialLoading = false;
      _notify();
    }
  }

  /// Атомарная сдача квеста через PostgreSQL RPC.
  ///
  /// Награда целиком считается на сервере: там учтены и серия, и бонусы
  /// построек лагеря (единственный источник — таблица camp_building_effects).
  /// Клиент ничего не досчитывает, а берёт готовое состояние из ответа.
  ///
  /// Раньше здесь ответ сервера умножался на бонусы лагеря ещё раз — награда
  /// начислялась с двойным бонусом.
  Future<bool> completeQuestAtomic(Map<String, dynamic> quest) async {
    if (isCompletingQuest || energy <= 0) return false;

    // Защита от двойной сдачи одного и того же квеста (двойной тап,
    // повторное срабатывание таймера).
    final questId = quest['id'].toString();
    if (_questsInFlight.contains(questId)) return false;
    _questsInFlight.add(questId);

    isCompletingQuest = true;
    lastQuestError = null;
    _notify();

    try {
      int earnedXp;
      int earnedGold;
      int energyLeft;

      if (!isOfflineMode) {
        // Для квеста с таймером передаём серверную сессию фокуса: без неё
        // (или до истечения времени) сервер сдачу не подтвердит.
        final params = <String, dynamic>{
          'p_user_id': currentUserId,
          'p_quest_id': questId,
        };
        if (quest['is_timer_based'] == true) {
          final sessionId = _focusSessions[questId];
          if (sessionId == null || sessionId.isEmpty) {
            throw StateError('Focus session was not started');
          }
          params['p_session_id'] = sessionId;
        }

        final res = await supabase
            .rpc('complete_quest_atomic', params: params)
            .timeout(const Duration(seconds: 6));

        final data = res is Map ? Map<String, dynamic>.from(res) : null;
        if (data == null) {
          throw StateError('Server rejected quest completion');
        }

        // Никаких локальных досчётов: сервер вернул итоговые значения.
        earnedXp = _asInt(data['earned_xp']);
        earnedGold = _asInt(data['earned_gold']);
        energyLeft = _asInt(
          data['energy_left'],
          fallback: (energy - 1).clamp(0, maxEnergy),
        );

        quest['is_completed'] = true;
        profile?['energy'] = energyLeft;
        // Если сервер вернул полное состояние (миграция 006) — берём его,
        // иначе считаем от текущего (совместимость со старой версией функции).
        profile?['xp'] = _asInt(data['xp'], fallback: xp + earnedXp);
        profile?['gold'] = _asInt(data['gold'], fallback: gold + earnedGold);
        profile?['streak_count'] = _asInt(
          data['streak_count'],
          fallback: streak,
        );
        profile?['streak_multiplier'] = _asDouble(
          data['streak_multiplier'],
          fallback: streakMultiplier,
        );
        profile?['max_energy'] = _asInt(
          data['max_energy'],
          fallback: maxEnergy,
        );
        profile?['shields_left'] = _asInt(
          data['shields_left'],
          fallback: shields,
        );
        profile?['last_active_date'] = DateTime.now()
            .toIso8601String()
            .substring(0, 10);
        profile?['is_decayed'] = false;

        // Сессия израсходована — повторно использовать её нельзя.
        _focusSessions.remove(questId);
      } else {
        // Офлайн фоллбэк: сервера нет, поэтому серию и бонусы лагеря считаем
        // сами по локальному конфигу.
        quest['is_completed'] = true;
        earnedXp =
            ((_asInt(quest['xp_reward'], fallback: 20) * effectiveXpMultiplier)
                    .round())
                .clamp(0, 1 << 30);
        earnedGold =
            ((_asInt(quest['gold_reward'], fallback: 10) *
                        effectiveGoldMultiplier)
                    .round())
                .clamp(0, 1 << 30);

        profile?['energy'] = (energy - 1).clamp(0, maxEnergy);
        profile?['xp'] = xp + earnedXp;
        profile?['gold'] = gold + earnedGold;
      }

      updateCompletedQuestIds();
      _notify();
      return true;
    } on PostgrestException catch (e) {
      debugPrint('completeQuestAtomic rejected: ${e.message}');
      lastQuestError = _economyErrorMessage(
        e.message,
        'Не удалось сохранить. Повторите.',
      );
      return false;
    } catch (e) {
      debugPrint('Error in completeQuestAtomic: $e');
      // Сессия фокуса не найдена — её нужно начать заново.
      lastQuestError = 'Сессия не найдена. Запустите фокус снова.';
      return false;
    } finally {
      _questsInFlight.remove(questId);
      isCompletingQuest = false;
      _notify();
    }
  }

  /// Покупка в магазине. Цену, лимиты и достаток золота проверяет сервер:
  /// клиент только отправляет вид товара и количество.
  Future<ShopActionResult> buyConsumable(String kind, int count) async {
    return _runEconomyAction(
      action: () => supabase.rpc(
        'buy_consumable',
        params: {'p_kind': kind, 'p_count': count},
      ),
      fallbackError: 'Покупка не прошла',
    );
  }

  /// Постройка в лагере. Цена и эффект берутся из camp_building_effects.
  Future<ShopActionResult> upgradeCamp() async {
    return _runEconomyAction(
      action: () => supabase.rpc('upgrade_camp'),
      fallbackError: 'Постройка не удалась',
    );
  }

  /// Эволюция эпохи. Пороги XP, бонус золота и сброс лагеря проверяет сервер.
  Future<ShopActionResult> evolveEra(String nextEraId) async {
    return _runEconomyAction(
      action: () =>
          supabase.rpc('evolve_era', params: {'p_next_era': nextEraId}),
      fallbackError: 'Эволюция не удалась',
    );
  }

  /// Восстановление серии из состояния упадка. Цену и условие проверяет сервер.
  Future<ShopActionResult> restoreStreak() async {
    return _runEconomyAction(
      action: () => supabase.rpc('restore_streak'),
      fallbackError: 'Не удалось восстановить серию',
    );
  }

  /// Старт серверной сессии фокуса для квеста с таймером.
  ///
  /// Сервер фиксирует момент старта и требуемую длительность, поэтому сдать
  /// такой квест раньше времени нельзя — даже прямым вызовом RPC.
  Future<bool> startFocusSession(String questId) async {
    if (isOfflineMode || currentUserId.isEmpty) return false;

    try {
      final res = await supabase
          .rpc('start_focus_session', params: {'p_quest_id': questId})
          .timeout(const Duration(seconds: 8));

      final data = res is Map ? Map<String, dynamic>.from(res) : null;
      final sessionId = data == null ? null : data['session_id']?.toString();
      if (sessionId == null || sessionId.isEmpty) return false;

      _focusSessions[questId] = sessionId;
      return true;
    } catch (e) {
      debugPrint('start_focus_session failed: $e');
      return false;
    }
  }

  /// Покупка слота цели. Цену и лимит слотов проверяет сервер.
  Future<ShopActionResult> buyGoalSlot() async {
    return _runEconomyAction(
      action: () => supabase.rpc('buy_goal_slot'),
      fallbackError: 'Не удалось открыть слот',
    );
  }

  /// Пересчёт рейтинга пресета из голосов. Возвращает новый рейтинг или null,
  /// если сервер не ответил.
  Future<int?> recomputePresetScore(String presetId) async {
    final data = await _callRpc(
      'recompute_preset_score',
      params: {'p_preset_id': presetId},
    );
    if (data == null) return null;
    return _asInt(data['score']);
  }

  /// Атомарный инкремент счётчика активаций пресета.
  Future<int?> registerPresetUse(String presetId) async {
    final data = await _callRpc(
      'register_preset_use',
      params: {'p_preset_id': presetId},
    );
    if (data == null) return null;
    return _asInt(data['uses_count']);
  }

  /// Вызов серверной функции, возвращающей объект. Ошибки только логируются:
  /// вызывающий код решает, что показать игроку.
  Future<Map<String, dynamic>?> _callRpc(
    String name, {
    Map<String, dynamic>? params,
  }) async {
    if (isOfflineMode || currentUserId.isEmpty) return null;

    try {
      final res = await supabase
          .rpc(name, params: params)
          .timeout(const Duration(seconds: 8));
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      debugPrint('RPC $name failed: $e');
      return null;
    }
  }

  /// Общая обвязка серверных операций экономики: вызов, синхронизация
  /// состояния из ответа и перевод кодов ошибок в понятный текст.
  Future<ShopActionResult> _runEconomyAction({
    required Future<dynamic> Function() action,
    required String fallbackError,
  }) async {
    if (isOfflineMode) {
      return const ShopActionResult.failure(
        'В офлайн-режиме покупки недоступны',
      );
    }

    if (currentUserId.isEmpty) {
      return const ShopActionResult.failure('Вы не авторизованы.');
    }

    try {
      final res = await action().timeout(const Duration(seconds: 8));
      final data = res is Map ? Map<String, dynamic>.from(res) : null;
      if (data == null) {
        return ShopActionResult.failure(fallbackError);
      }

      _syncProfileFromServer(data);

      return ShopActionResult(
        success: true,
        message: 'Готово',
        detail:
            _promoText(data['building']) ??
            _promoText(data['kind']) ??
            _promoText(data['era_name']),
        paid: _asInt(data['paid']),
        energyAdded: _asInt(data['energy_added']),
        shieldsAdded: _asInt(data['shields_added']),
      );
    } on PostgrestException catch (e) {
      debugPrint('_runEconomyAction rejected: ${e.message}');
      return ShopActionResult.failure(
        _economyErrorMessage(e.message, fallbackError),
      );
    } catch (e) {
      debugPrint('Error in _runEconomyAction: $e');
      return const ShopActionResult.failure('Нет связи. Проверьте интернет.');
    }
  }

  /// Целочисленные поля состояния профиля, которые приходят от сервера.
  static const List<String> _serverIntKeys = [
    'gold',
    'xp',
    'total_xp',
    'season_xp',
    'energy',
    'max_energy',
    'shields_left',
    'streak_count',
    'camp_level',
    'max_active_goals',
  ];

  /// Переносит состояние профиля из ответа сервера в целевую карту.
  ///
  /// Обновляются только те поля, которые сервер прислал. Числа приводятся к
  /// нужному типу: numeric из PostgreSQL приходит строкой, и без разбора
  /// геттеры получили бы null и подставили значение по умолчанию.
  static void _applyServerState(
    Map<String, dynamic> target,
    Map<String, dynamic> data,
  ) {
    for (final key in _serverIntKeys) {
      if (data.containsKey(key)) {
        target[key] = _asInt(data[key], fallback: _asInt(target[key]));
      }
    }
    if (data.containsKey('streak_multiplier')) {
      target['streak_multiplier'] = _asDouble(
        data['streak_multiplier'],
        fallback: _asDouble(target['streak_multiplier']),
      );
    }
    if (data['current_era'] is String) {
      target['current_era'] = data['current_era'];
    } else if (data['era'] is String) {
      // evolve_era до миграции 016 отдавал эпоху под ключом 'era'.
      // Без этой ветки интерфейс оставался на старой эпохе, а сервер уже
      // считал цены для новой — игрок видел «недостаточно золота» на постройке,
      // которая в новой эпохе стоит дороже.
      target['current_era'] = data['era'];
    }
    if (data['last_active_date'] is String) {
      target['last_active_date'] = data['last_active_date'];
    }
    if (data.containsKey('is_decayed')) {
      target['is_decayed'] = data['is_decayed'] == true;
    }
  }

  /// Применяет состояние профиля из ответа сервера к текущему профилю.
  void _syncProfileFromServer(Map<String, dynamic> data) {
    final p = profile;
    if (p == null) {
      unawaited(loadGameData(isSilent: true));
      return;
    }

    _applyServerState(p, data);
    _notify();
  }

  /// Суточный пересчёт (энергия, щиты, серия, упадок).
  ///
  /// Всю арифметику делает серверная функция apply_daily_reset: она
  /// идемпотентна — повторный вызов в тот же день ничего не меняет.
  /// Ошибку не пробрасываем: неудачный пересчёт не должен мешать загрузке
  /// игры, состояние всё равно придёт из выборки профиля.
  Future<void> _applyDailyReset(Map<String, dynamic> profileData) async {
    if (isOfflineMode) return;

    try {
      final res = await supabase
          .rpc('apply_daily_reset')
          .timeout(const Duration(seconds: 6));

      final data = res is Map ? Map<String, dynamic>.from(res) : null;
      if (data != null && data['changed'] == true) {
        _applyServerState(profileData, data);
      }
    } catch (e) {
      debugPrint('apply_daily_reset failed: $e');
    }
  }

  /// Награда за прошедший сезон лиги, о которой игроку надо сообщить.
  /// Заполняется при подведении итогов, очищается после показа.
  Map<String, dynamic>? pendingLeagueAward;

  /// Подведение итогов сезона лиги.
  ///
  /// Отдельного планировщика нет, поэтому итоги подводит первый зашедший
  /// игрок. Функция идемпотентна, начисление защищено уникальностью
  /// (сезон, игрок), поэтому вызывать её можно сколько угодно раз.
  ///
  /// [profileData] — куда отразить начисленное золото. При загрузке игры это
  /// ещё не присвоенный профиль, при обновлении вкладки рейтинга — текущий.
  /// Возвращает число закрытых сезонов.
  Future<int> settleLeagueSeason([Map<String, dynamic>? profileData]) async {
    if (isOfflineMode) return 0;

    final target = profileData ?? profile;
    final data = await _callRpc('settle_league_season');
    if (data == null) return 0;

    final award = data['my_award'];
    if (award is Map) {
      final awardMap = Map<String, dynamic>.from(award);
      pendingLeagueAward = awardMap;

      // Сервер уже начислил золото — отражаем это в состоянии, чтобы не
      // делать лишний запрос.
      final gold = _asInt(awardMap['gold']);
      if (gold > 0 && target != null && target.containsKey('gold')) {
        target['gold'] = _asInt(target['gold']) + gold;
        _notify();
      }
    }

    return _asInt(data['settled_seasons']);
  }

  /// Текст уведомления о награде за сезон. После вызова награда считается
  /// показанной; null означает, что показывать нечего.
  String? consumeLeagueAwardMessage() {
    final award = pendingLeagueAward;
    if (award == null) return null;
    pendingLeagueAward = null;

    final place = _asInt(award['place']);
    final gold = _asInt(award['gold']);
    final tierName = award['tier_name'] as String? ?? 'лиге';

    return 'Сезон завершён: $place место в «$tierName» — +$gold золота';
  }

  /// Таблица лиги: моя лига, конец сезона, награды и игроки лиги
  /// (или союзники) по опыту, набранному за сезон.
  Future<Map<String, dynamic>?> loadLeagueLeaderboard(String mode) async {
    return _callRpc('get_league_leaderboard', params: {'p_mode': mode});
  }

  /// Коды ошибок серверных операций экономики → фразы для игрока.
  static String _economyErrorMessage(String raw, String fallback) {
    final t = raw.toUpperCase();
    if (t.contains('SHOP_NOT_ENOUGH_GOLD') ||
        t.contains('CAMP_NOT_ENOUGH_GOLD')) {
      return 'Не хватает золота';
    }
    if (t.contains('SHOP_ALREADY_MAX')) {
      return 'Щиты уже на максимуме.';
    }
    if (t.contains('SHOP_COUNT_TOO_HIGH')) {
      return 'Столько не поместится';
    }
    if (t.contains('CAMP_MAX_LEVEL')) {
      return 'Лагерь полностью отстроен.';
    }
    if (t.contains('CAMP_NO_BUILDING')) {
      return 'Для этой эпохи больше нет построек.';
    }
    if (t.contains('EVOLVE_NOT_ENOUGH_XP')) {
      return 'Не хватает XP для эволюции';
    }
    if (t.contains('EVOLVE_CAMP_NOT_READY')) {
      return 'Нужен лагерь 5 уровня';
    }
    if (t.contains('EVOLVE_MAX_ERA')) {
      return 'Это последняя эпоха';
    }
    if (t.contains('EVOLVE_WRONG_ERA') || t.contains('EVOLVE_UNKNOWN_ERA')) {
      return 'Данные устарели. Войдите заново.';
    }
    if (t.contains('STREAK_NOT_DECAYED')) {
      return 'Серия не прервана';
    }
    if (t.contains('STREAK_NOT_ENOUGH_GOLD')) {
      return 'Не хватает золота на восстановление';
    }
    if (t.contains('GOAL_SLOT_MAX')) {
      return 'Все слоты уже открыты';
    }
    if (t.contains('GOAL_SLOT_NOT_ENOUGH_GOLD')) {
      return 'Не хватает золота на слот';
    }
    if (t.contains('PRESET_NOT_FOUND')) {
      return 'Пресет не найден';
    }
    if (t.contains('QUEST_TIMER_NOT_ELAPSED')) {
      return 'Фокус ещё идёт';
    }
    if (t.contains('QUEST_TIMER_NOT_STARTED')) {
      return 'Сессия не найдена. Запустите фокус снова.';
    }
    if (t.contains('QUEST_ALREADY_COMPLETED') ||
        t.contains('Quest already completed')) {
      return 'Этот квест уже выполнен.';
    }
    if (t.contains('QUEST_UNAUTHORIZED')) {
      // Сервер принимает id игрока параметром, но сверяет его с сессией:
      // сдать квест за другого нельзя (миграция 021).
      return 'Сдать квест можно только за себя.';
    }
    if (t.contains('NOT ENOUGH ENERGY') || t.contains('Not enough energy')) {
      return 'Энергия закончилась. Восстановится завтра.';
    }
    if (t.contains('FOCUS_NOT_TIMER_QUEST')) {
      return 'У этого квеста нет таймера фокуса.';
    }
    if (t.contains('SHOP_UNKNOWN_ITEM') || t.contains('SHOP_BAD_COUNT')) {
      return 'Некорректный запрос';
    }
    if (t.contains('UNAUTHORIZED')) {
      return 'Вы не авторизованы.';
    }
    if (t.contains('NO_PROFILE')) {
      return 'Профиль не найден. Войдите заново.';
    }
    return fallback;
  }

  /// Безопасное чтение целых чисел из ответов Supabase/RPC.
  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Безопасное чтение дробных чисел из ответов Supabase/RPC.
  /// PostgreSQL возвращает numeric как строку, поэтому нужен разбор.
  static double _asDouble(dynamic value, {double fallback = 1.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Активация промокода.
  ///
  /// Награды и лимиты считает и применяет БД (RPC `redeem_promo_code`):
  /// клиент только отправляет код и показывает результат. Значения профиля
  /// берутся из ответа сервера, поэтому локальное состояние не расходится
  /// с базой.
  Future<PromoRedeemResult> redeemPromoCode(String code) async {
    if (isOfflineMode) {
      return const PromoRedeemResult.failure(
        'Промокоды работают только онлайн',
      );
    }

    final userId = currentUserId;
    if (userId.isEmpty) {
      return const PromoRedeemResult.failure('Вы не авторизованы.');
    }

    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      return const PromoRedeemResult.failure('Введите промокод.');
    }

    try {
      final res = await supabase
          .rpc(
            'redeem_promo_code',
            params: {'p_user_id': userId, 'p_label': normalized},
          )
          .timeout(const Duration(seconds: 10));

      final data = res is Map ? Map<String, dynamic>.from(res) : null;
      if (data == null) {
        return const PromoRedeemResult.failure('Не удалось активировать');
      }

      // Доверяем только серверным значениям, локально ничего не досчитываем.
      // Если профиль ещё не загружен, метод сам подтянет состояние из БД.
      _syncProfileFromServer(data);

      return PromoRedeemResult(
        applied: true,
        message: 'Промокод активирован',
        title: _promoText(data['title']),
        goldAdded: _asInt(data['gold_added']),
        xpAdded: _asInt(data['xp_added']),
        energyAdded: _asInt(data['energy_added']),
        shieldsAdded: _asInt(data['shields_added']),
      );
    } on PostgrestException catch (e) {
      debugPrint('redeemPromoCode rejected: ${e.message}');
      return PromoRedeemResult.failure(_promoErrorMessage(e.message));
    } catch (e) {
      debugPrint('Error in redeemPromoCode: $e');
      return const PromoRedeemResult.failure('Нет связи. Проверьте интернет.');
    }
  }

  static String? _promoText(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Коды ошибок приходят из БД (raise exception 'PROMO_...') — переводим
  /// их в понятные игроку фразы.
  static String _promoErrorMessage(String raw) {
    final text = raw.toUpperCase();
    if (text.contains('PROMO_ALREADY_USED')) {
      return 'Промокод уже активирован';
    }
    if (text.contains('PROMO_EXPIRED')) {
      return 'Срок действия истёк';
    }
    if (text.contains('PROMO_NOT_STARTED')) {
      return 'Промокод ещё не активен.';
    }
    if (text.contains('PROMO_EXHAUSTED')) {
      return 'Лимит активаций исчерпан';
    }
    if (text.contains('PROMO_EMPTY')) {
      return 'Введите промокод.';
    }
    if (text.contains('PROMO_UNAUTHORIZED')) {
      return 'Вы не авторизованы.';
    }
    if (text.contains('PROMO_NO_PROFILE')) {
      return 'Профиль не найден. Войдите заново.';
    }
    if (text.contains('PROMO_INVALID')) {
      return 'Промокод не найден';
    }
    return 'Не удалось активировать';
  }

  void updateLocalProfile(Map<String, dynamic> delta) {
    profile?.addAll(delta);
    _notify();
  }
}

/// Результат активации промокода.
class PromoRedeemResult {
  final bool applied;
  final String message;
  final String? title;
  final int goldAdded;
  final int xpAdded;
  final int energyAdded;
  final int shieldsAdded;

  const PromoRedeemResult({
    required this.applied,
    required this.message,
    this.title,
    this.goldAdded = 0,
    this.xpAdded = 0,
    this.energyAdded = 0,
    this.shieldsAdded = 0,
  });

  const PromoRedeemResult.failure(this.message)
    : applied = false,
      title = null,
      goldAdded = 0,
      xpAdded = 0,
      energyAdded = 0,
      shieldsAdded = 0;
}

/// Результат серверной операции экономики: покупки или постройки.
class ShopActionResult {
  final bool success;
  final String message;

  /// Название постройки или вид товара — для сообщения игроку.
  final String? detail;

  /// Сколько золота списано.
  final int paid;
  final int energyAdded;
  final int shieldsAdded;

  const ShopActionResult({
    required this.success,
    required this.message,
    this.detail,
    this.paid = 0,
    this.energyAdded = 0,
    this.shieldsAdded = 0,
  });

  const ShopActionResult.failure(this.message)
    : success = false,
      detail = null,
      paid = 0,
      energyAdded = 0,
      shieldsAdded = 0;
}

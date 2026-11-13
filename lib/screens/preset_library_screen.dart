import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/game_controller.dart';
import '../utils/uuid.dart';
import '../widgets/game_notification.dart';

class PresetStep {
  final String title;
  final bool isTimer;
  final int durationMinutes;
  final int xpReward;
  final int goldReward;

  const PresetStep({
    required this.title,
    this.isTimer = true,
    this.durationMinutes = 25,
    this.xpReward = 40,
    this.goldReward = 20,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'is_timer': isTimer,
    'duration_minutes': durationMinutes,
    'xp_reward': xpReward,
    'gold_reward': goldReward,
  };

  factory PresetStep.fromMap(Map<String, dynamic> map) => PresetStep(
    title: map['title'] ?? '',
    isTimer: map['is_timer'] == true,
    durationMinutes: map['duration_minutes'] ?? 25,
    xpReward: map['xp_reward'] ?? 40,
    goldReward: map['gold_reward'] ?? 20,
  );
}

class GoalPreset {
  final String id;
  final String? authorId;
  final String title;
  final String category;
  final String description;
  final String authorName;
  final int usesCount;
  final int score;
  final int userVote; // 1 (upvote), -1 (downvote), 0 (none)
  final List<PresetStep> steps;

  const GoalPreset({
    required this.id,
    required this.title,
    this.authorId,
    required this.category,
    required this.description,
    required this.authorName,
    required this.usesCount,
    this.score = 0,
    this.userVote = 0,
    required this.steps,
  });

  GoalPreset copyWith({int? score, int? userVote, int? usesCount}) {
    return GoalPreset(
      id: id,
      title: title,
      category: category,
      description: description,
      authorName: authorName,
      usesCount: usesCount ?? this.usesCount,
      score: score ?? this.score,
      userVote: userVote ?? this.userVote,
      steps: steps,
    );
  }
}

// 6 встроенных системных пресетов
final List<GoalPreset> defaultPresets = [
  const GoalPreset(
    id: 'sys_run_start',
    title: 'Бег с нуля: Первые 5 км',
    category: 'Спорт',
    description:
        'Пошаговый переход от быстрой ходьбы к уверенному непрерывному бегу.',
    authorName: 'Совет Атлетов',
    usesCount: 0,
    score: 0, // Реальный старт без фейковых оценок
    steps: [
      PresetStep(
        title: 'Интервальная разминка: 20 мин быстрой ходьбы',
        durationMinutes: 20,
        xpReward: 30,
        goldReward: 15,
      ),
      PresetStep(
        title: 'Чередование: 2 мин бег / 2 мин ходьба (25 мин)',
        durationMinutes: 25,
        xpReward: 45,
        goldReward: 25,
      ),
      PresetStep(
        title: 'Легкий непрерывный кросс 2 км без остановки',
        durationMinutes: 25,
        xpReward: 60,
        goldReward: 35,
      ),
      PresetStep(
        title: 'Контрольный забег на 5 км в комфортном темпе',
        durationMinutes: 35,
        xpReward: 85,
        goldReward: 50,
      ),
    ],
  ),
  const GoalPreset(
    id: 'sys_python_basics',
    title: 'Основы Python и скрипты',
    category: 'IT & Навыки',
    description:
        'Освойте синтаксис, циклы, функции и напишите своего первого бота.',
    authorName: 'Гильдия Кодеров',
    usesCount: 0,
    score: 0,
    steps: [
      PresetStep(
        title: 'Переменные, условия (if/else) и базовые типы',
        durationMinutes: 30,
        xpReward: 35,
        goldReward: 20,
      ),
      PresetStep(
        title: 'Циклы for/while и работа со списками и словарями',
        durationMinutes: 35,
        xpReward: 45,
        goldReward: 25,
      ),
      PresetStep(
        title: 'Функции, модули и чтение данных из файлов',
        durationMinutes: 40,
        xpReward: 60,
        goldReward: 35,
      ),
      PresetStep(
        title: 'Мини-проект: консольный бот-помощник',
        durationMinutes: 50,
        xpReward: 90,
        goldReward: 55,
      ),
    ],
  ),
  const GoalPreset(
    id: 'sys_deep_focus',
    title: 'Стальная концентрация (Deep Work)',
    category: 'Привычки',
    description:
        'Цифровой детокс, борьба с прокрастинацией и вход в состояние потока.',
    authorName: 'Орден Мыслителей',
    usesCount: 0,
    score: 0,
    steps: [
      PresetStep(
        title: 'Убрать все уведомления и составить список топ-1 дела',
        durationMinutes: 15,
        xpReward: 25,
        goldReward: 10,
      ),
      PresetStep(
        title: 'Первый чистый блок фокуса на 30 мин без соцсетей',
        durationMinutes: 30,
        xpReward: 45,
        goldReward: 25,
      ),
      PresetStep(
        title: 'Глубокая рабочая сессия на 45 минут в тишине',
        durationMinutes: 45,
        xpReward: 70,
        goldReward: 40,
      ),
      PresetStep(
        title: 'Вечерний анализ дня и планирование следующего шага',
        durationMinutes: 20,
        xpReward: 40,
        goldReward: 20,
      ),
    ],
  ),
  const GoalPreset(
    id: 'sys_english_speaking',
    title: 'Разговорный английский: Прорыв',
    category: 'Языки',
    description:
        'Преодоление языкового барьера: слушание, лексика и живая речь.',
    authorName: 'Послы Цивилизаций',
    usesCount: 0,
    score: 0,
    steps: [
      PresetStep(
        title: 'Разбор 20 устойчивых разговорных фраз дня',
        durationMinutes: 20,
        xpReward: 30,
        goldReward: 15,
      ),
      PresetStep(
        title:
            'Просмотр подкаста/видео на слух с теневым повторением (Shadowing)',
        durationMinutes: 30,
        xpReward: 50,
        goldReward: 30,
      ),
      PresetStep(
        title: '5 минут непрерывного монолога о своем дне на английском',
        durationMinutes: 20,
        xpReward: 60,
        goldReward: 35,
      ),
      PresetStep(
        title: 'Закрепление: языковой диалог с собеседником или ИИ',
        durationMinutes: 35,
        xpReward: 80,
        goldReward: 45,
      ),
    ],
  ),
  const GoalPreset(
    id: 'sys_book_reader',
    title: 'Осознанное чтение: 1 книга в неделю',
    category: 'Саморазвитие',
    description: 'Формирование привычки ежедневного чтения с конспектированием ключевых идей.',
    authorName: 'Хранители Знаний',
    usesCount: 0,
    score: 0,
    steps: [
      PresetStep(
        title: 'Чтение 15 страниц без отвлечений и выделение мыслей',
        durationMinutes: 25,
        xpReward: 30,
        goldReward: 15,
      ),
      PresetStep(
        title: 'Чтение 25 страниц и выписка 3 главных инсайтов в блокнот',
        durationMinutes: 35,
        xpReward: 45,
        goldReward: 25,
      ),
      PresetStep(
        title: 'Чтение главы книги и объяснение её сути своими словами',
        durationMinutes: 35,
        xpReward: 60,
        goldReward: 35,
      ),
      PresetStep(
        title: 'Финальный конспект книги и план применения идей в жизни',
        durationMinutes: 40,
        xpReward: 85,
        goldReward: 50,
      ),
    ],
  ),
  const GoalPreset(
    id: 'sys_morning_routine',
    title: 'Утренний заряд энергии',
    category: 'Привычки',
    description: 'Идеальное утро без спешки: гидратация, зарядка, контрастный душ и фокус.',
    authorName: 'Совет Здоровья',
    usesCount: 0,
    score: 0,
    steps: [
      PresetStep(
        title: 'Стакан воды + 10 минут утренней суставной разминки',
        durationMinutes: 15,
        xpReward: 25,
        goldReward: 15,
      ),
      PresetStep(
        title: 'Контрастный бодрящий душ и питательный завтрак',
        durationMinutes: 20,
        xpReward: 35,
        goldReward: 20,
      ),
      PresetStep(
        title: '15 минут чтения или медитации до проверки телефона',
        durationMinutes: 15,
        xpReward: 45,
        goldReward: 25,
      ),
      PresetStep(
        title: 'Постановка главной победы дня и старт первой задачи',
        durationMinutes: 20,
        xpReward: 50,
        goldReward: 30,
      ),
    ],
  ),
];

class PresetLibraryScreen extends StatefulWidget {
  final String userId;
  final Color primaryColor;
  final int currentActiveGoalsCount;
  final int maxAllowedGoals;
  final VoidCallback onGoalActivated;

  /// Контроллер игры: через него считаются рейтинг пресета и счётчик
  /// активаций. Если он не передан, статистика пресетов не обновляется
  /// (серверные функции требуют авторизации игрока).
  final GameController? controller;

  const PresetLibraryScreen({
    super.key,
    required this.userId,
    required this.primaryColor,
    required this.currentActiveGoalsCount,
    required this.maxAllowedGoals,
    required this.onGoalActivated,
    this.controller,
  });

  @override
  State<PresetLibraryScreen> createState() => _PresetLibraryScreenState();
}

class _PresetLibraryScreenState extends State<PresetLibraryScreen> {
  final supabase = Supabase.instance.client;
  String _selectedCategory = 'Все';
  String _searchQuery = '';
  List<GoalPreset> _communityPresets = [];
  bool _isLoading = false;

  final List<String> _categories = [
    'Все',
    'Спорт',
    'IT & Навыки',
    'Привычки',
    'Языки',
    'Саморазвитие',
  ];

  @override
  void initState() {
    super.initState();
    _loadCommunityPresets();
  }

  // Удаление собственного пресета
  Future<void> _deletePreset(GoalPreset preset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x28FFFFFF)),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            SizedBox(width: 10),
            Text(
              'Удалить пресет?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Удалить «${preset.title}» из библиотеки?',
          style: const TextStyle(
            color: Color(0xFF8E95A5),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Color(0xFF8E95A5)),
            ),
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
            child: const Text(
              'Удалить',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Мгновенно убираем из списка
    setState(() {
      _communityPresets.removeWhere((p) => p.id == preset.id);
    });

    try {
      await supabase.from('preset_votes').delete().eq('preset_id', preset.id);
      await supabase
          .from('goal_presets')
          .delete()
          .eq('id', preset.id)
          .eq('author_id', widget.userId);

      if (mounted) {
        showGameNotification(
          context,
          message: 'Пресет удалён',
          type: NotificationType.info,
        );
      }
    } catch (e) {
      debugPrint('Error deleting preset: $e');
      _loadCommunityPresets();
    }
  }

  Future<void> _loadCommunityPresets() async {
    setState(() => _isLoading = true);
    try {
      // 1. Загрузка пресетов
      final res = await supabase
          .from('goal_presets')
          .select()
          .order('score', ascending: false)
          .limit(50);

      // 2. Загрузка голосов текущего игрока
      final votesRes = await supabase
          .from('preset_votes')
          .select('preset_id, vote')
          .eq('user_id', widget.userId);

      final Map<String, int> myVotes = {};
      for (var v in (votesRes as List)) {
        myVotes[v['preset_id'].toString()] = (v['vote'] as num).toInt();
      }

      final Map<String, int> liveCounts = {};
      final Map<String, int> liveScores = {};
      final List<GoalPreset> community = [];

      for (var row in (res as List)) {
        final id = row['id'].toString();
        final uses = (row['uses_count'] as num?)?.toInt() ?? 0;
        final score = (row['score'] as num?)?.toInt() ?? 0;
        liveCounts[id] = uses;
        liveScores[id] = score;

        if (!id.startsWith('sys_')) {
          final stepsRaw = row['steps'];
          List<PresetStep> steps = [];
          if (stepsRaw is List) {
            steps = stepsRaw
                .map((s) => PresetStep.fromMap(Map<String, dynamic>.from(s)))
                .toList();
          } else if (stepsRaw is String) {
            final decoded = jsonDecode(stepsRaw);
            if (decoded is List) {
              steps = decoded
                  .map((s) => PresetStep.fromMap(Map<String, dynamic>.from(s)))
                  .toList();
            }
          }
          community.add(
            GoalPreset(
              id: id,
              authorId: row['author_id']?.toString(), // <-- Сохраняем ID автора
              title: row['title'] ?? '',
              category: row['category'] ?? 'Общее',
              description: row['description'] ?? '',
              authorName: row['author_name'] ?? 'Правитель',
              usesCount: uses,
              score: score,
              userVote: myVotes[id] ?? 0,
              steps: steps,
            ),
          );
        }
      }

      // Обновляем встроенные пресеты
      for (int i = 0; i < defaultPresets.length; i++) {
        final dp = defaultPresets[i];
        final liveScore = liveScores[dp.id] ?? dp.score;
        final liveUses = liveCounts[dp.id] ?? dp.usesCount;
        defaultPresets[i] = GoalPreset(
          id: dp.id,
          title: dp.title,
          category: dp.category,
          description: dp.description,
          authorName: dp.authorName,
          usesCount: liveUses,
          score: liveScore,
          userVote: myVotes[dp.id] ?? 0,
          steps: dp.steps,
        );
      }

      if (mounted) setState(() => _communityPresets = community);
    } catch (e) {
      debugPrint('Error loading presets: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Голосование в стиле Reddit (+ / -)
  Future<void> _handleVote(GoalPreset preset, int direction) async {
    final currentVote = preset.userVote;
    final int newVote = (currentVote == direction) ? 0 : direction;
    final int scoreDelta = newVote - currentVote;
    final int newScore = preset.score + scoreDelta;

    // Мгновенное обновление интерфейса (Optimistic UI)
    setState(() {
      _communityPresets = _communityPresets.map((p) {
        if (p.id == preset.id) {
          return p.copyWith(score: newScore, userVote: newVote);
        }
        return p;
      }).toList();

      for (int i = 0; i < defaultPresets.length; i++) {
        if (defaultPresets[i].id == preset.id) {
          defaultPresets[i] = defaultPresets[i].copyWith(
            score: newScore,
            userVote: newVote,
          );
        }
      }
    });

    try {
      // Сохранение голоса в preset_votes
      if (newVote == 0) {
        await supabase
            .from('preset_votes')
            .delete()
            .eq('preset_id', preset.id)
            .eq('user_id', widget.userId);
      } else {
        await supabase.from('preset_votes').upsert({
          'preset_id': preset.id,
          'user_id': widget.userId,
          'vote': newVote,
        });
      }

      // Рейтинг пересчитывает сервер из таблицы голосов: клиент его не
      // присылает, поэтому одновременные голоса не теряются, а накрутить
      // рейтинг прямым запросом больше нельзя.
      final serverScore = await widget.controller?.recomputePresetScore(
        preset.id,
      );
      if (serverScore != null && mounted) {
        _applyScore(preset.id, serverScore);
      }
    } catch (e) {
      debugPrint('Error voting: $e');
      // Локальный оптимистичный рейтинг мог разойтись с базой — перечитываем.
      _loadCommunityPresets();
    }
  }

  /// Приводит рейтинг в интерфейсе к значению, посчитанному сервером.
  void _applyScore(String presetId, int score) {
    setState(() {
      _communityPresets = _communityPresets.map((p) {
        return p.id == presetId ? p.copyWith(score: score) : p;
      }).toList();

      for (int i = 0; i < defaultPresets.length; i++) {
        if (defaultPresets[i].id == presetId) {
          defaultPresets[i] = defaultPresets[i].copyWith(score: score);
        }
      }
    });
  }

  Future<void> _activatePreset(GoalPreset preset) async {
    if (widget.currentActiveGoalsCount >= widget.maxAllowedGoals) {
      showGameNotification(
        context,
        message: 'Все слоты заняты. Откройте новый в магазине.',
        type: NotificationType.error,
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final goalRes = await supabase
          .from('goals')
          .insert({
            'user_id': widget.userId,
            'title': preset.title,
            'description': preset.description,
            'status': 'in_progress',
          })
          .select()
          .single();

      final goalId = goalRes['id'].toString();
      final List<Map<String, dynamic>> questsPayload = [];
      String? parentId;

      for (var step in preset.steps) {
        final currentQuestId = generateUuid();
        questsPayload.add({
          'id': currentQuestId,
          'goal_id': goalId,
          'parent_quest_id': parentId,
          'title': step.title,
          'xp_reward': step.xpReward,
          'gold_reward': step.goldReward,
          'is_timer_based': step.isTimer,
          'timer_duration_minutes': step.durationMinutes,
          'is_completed': false,
        });
        parentId = currentQuestId;
      }

      await supabase.from('quests').insert(questsPayload);

      // Счётчик активаций увеличивает серверная функция: инкремент в БД
      // атомарный, тогда как read-modify-write с клиента терял активации
      // при одновременных запросах.
      await widget.controller?.registerPresetUse(preset.id);

      if (!mounted) return;
      Navigator.pop(context); // закрыть лоадер
      Navigator.pop(context); // закрыть библиотеку
      widget.onGoalActivated();

      // Стильное игровое уведомление
      showGameNotification(
        context,
        message: 'Цель «${preset.title}» добавлена',
        type: NotificationType.success,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка активации: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showPresetDetails(GoalPreset preset) {
    final totalXp = preset.steps.fold<int>(0, (sum, s) => sum + s.xpReward);
    final totalGold = preset.steps.fold<int>(0, (sum, s) => sum + s.goldReward);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14171E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.primaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      preset.category.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: widget.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'от ${preset.authorName}',
                    style: const TextStyle(
                      color: Color(0xFF8E95A5),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        preset.usesCount == 0
                            ? Icons.eco_rounded
                            : Icons.bolt_rounded,
                        size: 13,
                        color: const Color(0xFFF5A623),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        preset.usesCount == 0
                            ? 'Новый'
                            : '${preset.usesCount} акт.',
                        style: const TextStyle(
                          color: Color(0xFFF5A623),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                preset.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preset.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8E95A5),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D24),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Шагов: ${preset.steps.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Container(width: 1, height: 18, color: Colors.white24),
                    Text(
                      '+$totalXp XP',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: widget.primaryColor,
                      ),
                    ),
                    Container(width: 1, height: 18, color: Colors.white24),
                    Row(
                      children: [
                        Text(
                          '+$totalGold',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
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
              const SizedBox(height: 16),
              const Text(
                'Шаги',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: preset.steps.length,
                  itemBuilder: (context, i) {
                    final step = preset.steps[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D24),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x14FFFFFF)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: widget.primaryColor.withValues(
                              alpha: 0.2,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: widget.primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (step.isTimer)
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.timer_outlined,
                                        size: 12,
                                        color: Color(0xFF8E95A5),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Фокус: ${step.durationMinutes} мин',
                                        style: const TextStyle(
                                          color: Color(0xFF8E95A5),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '+${step.xpReward} XP',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: widget.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _activatePreset(preset);
                  },
                  icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                  label: const Text(
                    'Активировать',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = [...defaultPresets, ..._communityPresets];

    final filtered = all.where((p) {
      final matchesCategory =
          _selectedCategory == 'Все' || p.category == _selectedCategory;
      final matchesSearch =
          _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.authorName.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1015),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Библиотека целей',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: TextField(
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: 'Поиск по цели или автору',
                hintStyle: const TextStyle(
                  color: Color(0xFF5D6475),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: const Color(0xFF14171E),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF8E95A5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // Категории
          SizedBox(
            height: 40,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: widget.primaryColor,
                    backgroundColor: const Color(0xFF14171E),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF8E95A5),
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? widget.primaryColor
                          : const Color(0x1AFFFFFF),
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Список карточек с автором и Reddit-рейтингом (+/-)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Ничего не найдено',
                      style: TextStyle(
                        color: Color(0xFF8E95A5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1D24),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Шапка: категория + имя автора + счётчик
                            // Шапка карточки: категория и автор слева, корзина и молния справа
                            Row(
                              children: [
                                // 1. Категория
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.primaryColor.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    p.category,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      color: widget.primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 2. Автор
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline_rounded,
                                      size: 13,
                                      color: Color(0xFF8E95A5),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      p.authorId == widget.userId
                                          ? '${p.authorName} (Вы)'
                                          : p.authorName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: p.authorId == widget.userId
                                            ? const Color(0xFF00E676)
                                            : const Color(0xFF8E95A5),
                                      ),
                                    ),
                                  ],
                                ),

                                // 3. Отталкиваем корзину и молнию к правому краю
                                const Spacer(),

                                // 4. Корзина (теперь стоит вплотную перед молнией)
                                if (p.authorId == widget.userId) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Удалить мой пресет',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deletePreset(p),
                                  ),
                                  const SizedBox(
                                    width: 8,
                                  ), // Аккуратный отступ 8px до молнии
                                ],

                                // 5. Значок и счётчик активаций
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      p.usesCount == 0
                                          ? Icons.eco_rounded
                                          : Icons.bolt_rounded,
                                      size: 12,
                                      color: p.usesCount == 0
                                          ? const Color(0xFF00E676)
                                          : const Color(0xFFF5A623),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      p.usesCount == 0
                                          ? 'Новый'
                                          : '${p.usesCount}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: p.usesCount == 0
                                            ? const Color(0xFF00E676)
                                            : const Color(0xFFF5A623),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              p.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E95A5),
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Нижняя строка: Reddit-голосование (+ / -) и кнопка «Изучить»
                            Row(
                              children: [
                                // ВИДЖЕТ ГОЛОСОВАНИЯ В СТИЛЕ REDDIT
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF14171E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0x1AFFFFFF),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Upvote (Стрелка вверх)
                                      IconButton(
                                        icon: Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 18,
                                          color: p.userVote == 1
                                              ? const Color(0xFFFF5722)
                                              : const Color(0xFF8E95A5),
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _handleVote(p, 1),
                                      ),
                                      // Число рейтинга
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: Text(
                                          p.score > 0
                                              ? '+${p.score}'
                                              : '${p.score}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            color: p.userVote == 1
                                                ? const Color(0xFFFF5722)
                                                : (p.userVote == -1
                                                      ? const Color(0xFF00B0FF)
                                                      : Colors.white),
                                          ),
                                        ),
                                      ),
                                      // Downvote (Стрелка вниз)
                                      IconButton(
                                        icon: Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 18,
                                          color: p.userVote == -1
                                              ? const Color(0xFF00B0FF)
                                              : const Color(0xFF8E95A5),
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _handleVote(p, -1),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${p.steps.length} шагов',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF8E95A5),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: widget.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => _showPresetDetails(p),
                                  child: const Text(
                                    'Изучить',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

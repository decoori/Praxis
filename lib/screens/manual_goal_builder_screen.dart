import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/game_config.dart';
import '../utils/uuid.dart';

enum StepDifficulty { easy, medium, hard }

class ManualStepData {
  final TextEditingController controller;
  final TextEditingController durationController;
  StepDifficulty difficulty;
  bool isTimer;
  int durationMinutes;

  ManualStepData({
    required String initialText,
    this.difficulty = StepDifficulty.medium,
    this.isTimer = true,
    this.durationMinutes = 25,
  }) : controller = TextEditingController(text: initialText),
       durationController = TextEditingController(
         text: durationMinutes.toString(),
       );

  void dispose() {
    controller.dispose();
    durationController.dispose();
  }

  int get weight {
    int w = difficulty == StepDifficulty.easy
        ? 1
        : (difficulty == StepDifficulty.medium ? 2 : 4);
    return isTimer ? w * 2 : w;
  }
}

class ManualGoalBuilderScreen extends StatefulWidget {
  final Color primaryColor;
  final String userId;
  final VoidCallback onGoalCreated;

  /// Эпоха игрока: награда за шаг задаётся её коридором, а не общим пулом.
  /// Раньше цель всегда давала 220 XP и 120 золота, и в Космической эре это
  /// было в 20 раз меньше, чем нужно для развития.
  final String eraId;

  const ManualGoalBuilderScreen({
    super.key,
    required this.primaryColor,
    required this.userId,
    required this.eraId,
    required this.onGoalCreated,
  });

  @override
  State<ManualGoalBuilderScreen> createState() =>
      _ManualGoalBuilderScreenState();
}

class _ManualGoalBuilderScreenState extends State<ManualGoalBuilderScreen> {
  final _goalTitleController = TextEditingController();
  final List<ManualStepData> _steps = [];
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _steps.add(
      ManualStepData(
        initialText: 'Изучить теорию и настроить окружение',
        difficulty: StepDifficulty.easy,
        isTimer: true,
        durationMinutes: 20,
      ),
    );
    _steps.add(
      ManualStepData(
        initialText: 'Практическая отработка основного навыка',
        difficulty: StepDifficulty.medium,
        isTimer: true,
        durationMinutes: 35,
      ),
    );
    _steps.add(
      ManualStepData(
        initialText: 'Финальный проект / закрепление цели',
        difficulty: StepDifficulty.hard,
        isTimer: true,
        durationMinutes: 45,
      ),
    );
  }

  @override
  void dispose() {
    _goalTitleController.dispose();
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  void _addStep() {
    if (_steps.length >= 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не больше 6 шагов на цель')),
      );
      return;
    }
    setState(() {
      _steps.add(
        ManualStepData(
          initialText: '',
          difficulty: StepDifficulty.medium,
          isTimer: true,
        ),
      );
    });
  }

  void _removeStep(int index) {
    if (_steps.length <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нужен хотя бы один шаг')));
      return;
    }
    setState(() {
      _steps[index].dispose();
      _steps.removeAt(index);
    });
  }

  Map<String, int> _calculateStepReward(int index) {
    final totalWeight = _steps.fold<int>(0, (sum, s) => sum + s.weight);
    if (totalWeight == 0) return {'xp': 20, 'gold': 10};

    // Награда берётся из коридора эпохи: тяжесть шага сдвигает её внутри
    // коридора, но не выводит за границы. Сервер всё равно подрежет значение
    // триггером clamp_quest_rewards.
    final reward = stepReward(
      widget.eraId,
      _steps[index].weight.toDouble(),
      totalWeight.toDouble(),
    );
    return {'xp': reward.xp, 'gold': reward.gold};
  }

  Future<void> _saveGoal() async {
    final goalTitle = _goalTitleController.text.trim();
    if (goalTitle.isEmpty) {
      setState(() => _errorMessage = 'Введите название');
      return;
    }

    for (int i = 0; i < _steps.length; i++) {
      if (_steps[i].controller.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Заполните описание для шага ${i + 1}');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final supabase = Supabase.instance.client;
    String? createdGoalId;

    try {
      final goalRes = await supabase
          .from('goals')
          .insert({
            'user_id': widget.userId,
            'title': goalTitle,
            'description': 'Создано вручную',
            'status': 'in_progress',
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 8));

      createdGoalId = goalRes['id'].toString();

      final List<Map<String, dynamic>> questsPayload = [];
      String? previousQuestId;

      for (int i = 0; i < _steps.length; i++) {
        final step = _steps[i];
        final rewards = _calculateStepReward(i);
        final currentQuestId = generateUuid();

        // Минуты берём из поля ввода, а не из значения по умолчанию:
        // раньше ручные правки длительности не попадали в базу.
        final int duration = step.isTimer
            ? (int.tryParse(step.durationController.text.trim()) ??
                      step.durationMinutes)
                  .clamp(1, 600)
            : 0;

        questsPayload.add({
          'id': currentQuestId,
          'goal_id': createdGoalId,
          'parent_quest_id': previousQuestId,
          'title': step.controller.text.trim(),
          'xp_reward': rewards['xp'],
          'gold_reward': rewards['gold'],
          'is_timer_based': step.isTimer,
          'timer_duration_minutes': step.isTimer ? duration : null,
          'is_completed': false,
        });

        previousQuestId = currentQuestId;
      }

      await supabase
          .from('quests')
          .insert(questsPayload)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      widget.onGoalCreated();
      Navigator.pop(context);
    } catch (e) {
      if (createdGoalId != null) {
        try {
          await supabase.from('goals').delete().eq('id', createdGoalId);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Не удалось создать цель';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1015),
      appBar: AppBar(
        title: const Text(
          'Конструктор цели',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF14171E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'Цель',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalTitleController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Например: изучить основы SQL',
                      hintStyle: const TextStyle(color: Color(0xFF5D6475)),
                      fillColor: const Color(0xFF1A1D24),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14171E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF00B0FF).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: Color(0xFF00B0FF),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Награда за шаг: ${economyFor(widget.eraId).xpMin}–${economyFor(widget.eraId).xpMax} XP, '
                            '${economyFor(widget.eraId).goldMin}–${economyFor(widget.eraId).goldMax} золота.\n'
                            'Сложнее шаг — больше награда.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8E95A5),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Шаги',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: widget.primaryColor,
                        ),
                        onPressed: _addStep,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'Добавить шаг',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._steps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    final stepNum = index + 1;
                    final rewards = _calculateStepReward(index);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D24),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0x14FFFFFF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: widget.primaryColor.withValues(
                                  alpha: 0.2,
                                ),
                                child: Text(
                                  '$stepNum',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: widget.primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Шаг $stepNum',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF14171E),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '+${rewards['xp']} XP',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: widget.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '+${rewards['gold']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFF5A623),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.monetization_on_rounded,
                                      size: 12,
                                      color: Color(0xFFF5A623),
                                    ),
                                  ],
                                ),
                              ),
                              if (_steps.length > 1)
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Color(0xFF8E95A5),
                                  ),
                                  onPressed: () => _removeStep(index),
                                  padding: const EdgeInsets.only(left: 8),
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: step.controller,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Что делать на шаге',
                              hintStyle: const TextStyle(
                                color: Color(0xFF5D6475),
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF14171E),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Адаптивный выбор сложности (без overflow)
                          Row(
                            children: [
                              const Text(
                                'Сложность:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8E95A5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    _diffChip(
                                      step,
                                      StepDifficulty.easy,
                                      'База',
                                      const Color(0xFF00E676),
                                    ),
                                    const SizedBox(width: 6),
                                    _diffChip(
                                      step,
                                      StepDifficulty.medium,
                                      'Норма',
                                      const Color(0xFF00B0FF),
                                    ),
                                    const SizedBox(width: 6),
                                    _diffChip(
                                      step,
                                      StepDifficulty.hard,
                                      'Хард',
                                      const Color(0xFFFF5252),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Строка таймера (адаптивная, без overflow)
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: step.isTimer,
                                  activeColor: widget.primaryColor,
                                  onChanged: (v) =>
                                      setState(() => step.isTimer = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Таймер фокуса',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              if (step.isTimer) ...[
                                SizedBox(
                                  width: 48,
                                  height: 32,
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFF14171E),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    controller: step.durationController,
                                    onChanged: (val) {
                                      step.durationMinutes =
                                          int.tryParse(val) ?? 25;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'мин.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF8E95A5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF14171E),
                border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveGoal,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Создать цель',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diffChip(
    ManualStepData step,
    StepDifficulty diff,
    String label,
    Color color,
  ) {
    final isSelected = step.difficulty == diff;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => step.difficulty = diff),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.2)
                : const Color(0xFF14171E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : const Color(0x1AFFFFFF),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: isSelected ? color : const Color(0xFF8E95A5),
            ),
          ),
        ),
      ),
    );
  }
}

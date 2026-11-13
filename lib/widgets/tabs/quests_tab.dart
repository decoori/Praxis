import 'package:flutter/material.dart';

import '../../constants/game_config.dart';
import '../path_connector_painter.dart';

class QuestsTab extends StatelessWidget {
  final EraConfig era;
  final VoidCallback onOpenPresetsLibrary;
  final List<Map<String, dynamic>> quests;
  final List<Map<String, dynamic>> goals;
  final String? selectedGoalId;
  final bool hideCompleted;
  final bool Function(Map<String, dynamic>) isQuestUnlocked;
  final void Function(Map<String, dynamic>, bool) onQuestTap;
  final ValueChanged<String?> onGoalSelected;
  final VoidCallback onToggleHideCompleted;
  final void Function(String goalId, String currentTitle) onEditGoal;
  final void Function(String goalId) onDeleteGoal;
  final void Function(String goalId) onShareGoal;

  const QuestsTab({
    super.key,
    required this.era,
    required this.quests,
    required this.goals,
    required this.selectedGoalId,
    required this.hideCompleted,
    required this.isQuestUnlocked,
    required this.onQuestTap,
    required this.onGoalSelected,
    required this.onToggleHideCompleted,
    required this.onEditGoal,
    required this.onDeleteGoal,
    required this.onOpenPresetsLibrary,
    required this.onShareGoal,
  });

  @override
  Widget build(BuildContext context) {
    final filteredQuests = quests.where((q) {
      if (selectedGoalId != null &&
          q['goal_id']?.toString() != selectedGoalId) {
        return false;
      }
      if (hideCompleted && q['is_completed'] == true) return false;
      return true;
    }).toList();

    final allCompleted =
        selectedGoalId != null &&
        filteredQuests.isNotEmpty &&
        filteredQuests.every((q) => q['is_completed'] == true);

    Map<String, dynamic>? selectedGoal;
    if (selectedGoalId != null) {
      final match = goals.where((g) => g['id'].toString() == selectedGoalId);
      if (match.isNotEmpty) selectedGoal = match.first;
    }

    return Column(
      children: [
        // Верхняя панель фильтрации в темном стиле
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF14171E),
            border: Border(
              bottom: BorderSide(color: Color(0x14FFFFFF), width: 1.2),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Все квесты'),
                        selected: selectedGoalId == null,
                        onSelected: (_) => onGoalSelected(null),
                        selectedColor: era.primaryColor,
                        backgroundColor: const Color(0xFF1A1D24),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selectedGoalId == null
                              ? Colors.white
                              : const Color(0xFF8E95A5),
                        ),
                        side: BorderSide(
                          color: selectedGoalId == null
                              ? era.primaryColor
                              : const Color(0x1AFFFFFF),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...goals.map((g) {
                        final isSelected = selectedGoalId == g['id'].toString();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(g['title'] ?? ''),
                            selected: isSelected,
                            onSelected: (selected) => onGoalSelected(
                              selected ? g['id'].toString() : null,
                            ),
                            selectedColor: era.primaryColor,
                            backgroundColor: const Color(0xFF1A1D24),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF8E95A5),
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? era.primaryColor
                                  : const Color(0x1AFFFFFF),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              if (selectedGoal != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: const Color(0xFF1A1D24),
                  tooltip: 'Опции цели',
                  onSelected: (value) {
                    final id = selectedGoal!['id'].toString();
                    final title = selectedGoal['title'] ?? '';
                    if (value == 'edit') {
                      onEditGoal(id, title);
                    } else if (value == 'share') {
                      onShareGoal(id);
                    } else if (value == 'delete') {
                      onDeleteGoal(id);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Редактировать',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    // НОВЫЙ ПУНКТ:
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(
                            Icons.share_rounded,
                            size: 20,
                            color: Color(0xFF00E676),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Поделиться в библиотеку',
                            style: TextStyle(color: Color(0xFF00E676)),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Удалить',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              IconButton(
                icon: const Icon(
                  Icons.auto_stories_rounded,
                  color: Color(0xFF00E676),
                ),
                tooltip: 'Библиотека целей',
                onPressed: onOpenPresetsLibrary,
              ),
              IconButton(
                icon: Icon(
                  hideCompleted
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: hideCompleted
                      ? era.primaryColor
                      : const Color(0xFF8E95A5),
                ),
                tooltip: 'Скрыть выполненные',
                onPressed: onToggleHideCompleted,
              ),
            ],
          ),
        ),
        // Древо квестов
        Expanded(
          child: filteredQuests.isEmpty
              ? Center(
                  child: Text(
                    hideCompleted
                        ? 'Все квесты выполнены'
                        : 'В этой цели пока нет квестов',
                    style: const TextStyle(
                      color: Color(0xFF8E95A5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final double availableWidth = constraints.maxWidth - 32;
                    const double circleSize = 72.0;
                    final double circleRadius = circleSize / 2;
                    final double circleOffset =
                        (availableWidth / 2) - circleRadius;

                    return ListView.builder(
                      padding: const EdgeInsets.only(
                        top: 24,
                        bottom: 100,
                        left: 16,
                        right: 16,
                      ),
                      itemCount: filteredQuests.length + (allCompleted ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == filteredQuests.length && allCompleted) {
                          return Container(
                            margin: const EdgeInsets.only(top: 24),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF00E676)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Column(
                              children: [
                                Text(
                                  'Цель завершена',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Создайте новую цель, чтобы продолжить',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final q = filteredQuests[index];
                        final isCompleted = q['is_completed'] == true;
                        final isUnlocked = isQuestUnlocked(q);
                        final isLast = index == filteredQuests.length - 1;

                        // Позиционирование по скетчу: 1-й узел (index 0) — круг справа, описание слева
                        final bool isCircleOnRight = index % 2 == 0;
                        final double currentOffset = isCircleOnRight
                            ? circleOffset
                            : -circleOffset;
                        final bool nextIsCircleOnRight = (index + 1) % 2 == 0;
                        final double nextOffset = nextIsCircleOnRight
                            ? circleOffset
                            : -circleOffset;

                        // Круглый узел квеста
                        final circleWidget = GestureDetector(
                          onTap: () => onQuestTap(q, isUnlocked),
                          child: Container(
                            width: circleSize,
                            height: circleSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCompleted
                                  ? const Color(0xFF00E676)
                                  : (isUnlocked
                                        ? const Color(0xFF14171E)
                                        : const Color(0xFF1A1D24)),
                              border: Border.all(
                                color: isCompleted
                                    ? const Color(0xFFB9F6CA)
                                    : (isUnlocked
                                          ? era.primaryColor
                                          : const Color(0x28FFFFFF)),
                                width: 3.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isCompleted
                                              ? const Color(0xFF00E676)
                                              : (isUnlocked
                                                    ? era.primaryColor
                                                    : Colors.black))
                                          .withValues(
                                            alpha: isUnlocked ? 0.35 : 0.1,
                                          ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                isCompleted
                                    ? Icons.check_rounded
                                    : (isUnlocked
                                          ? (q['is_timer_based'] == true
                                                ? Icons.timer_rounded
                                                : Icons.star_rounded)
                                          : Icons.lock_outline_rounded),
                                size: 32,
                                color: isCompleted
                                    ? Colors.black
                                    : (isUnlocked
                                          ? era.primaryColor
                                          : const Color(0xFF5D6475)),
                              ),
                            ),
                          ),
                        );

                        // Прямоугольная карточка описания со скетча
                        final descriptionCard = Expanded(
                          child: GestureDetector(
                            onTap: () => onQuestTap(q, isUnlocked),
                            child: SizedBox(
                              height: circleSize, // Строго 72px — синхронно с кружком
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1D24),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isCompleted
                                        ? const Color(0xFF00E676)
                                              .withValues(alpha: 0.5)
                                        : (isUnlocked
                                              ? era.primaryColor.withValues(
                                                  alpha: 0.4,
                                                )
                                              : const Color(0x14FFFFFF)),
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      q['title'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isUnlocked
                                            ? Colors.white
                                            : const Color(0xFF5D6475),
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Text(
                                          '+${q['xp_reward']} XP',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: isUnlocked
                                                ? era.primaryColor
                                                : const Color(0xFF5D6475),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '+${q['gold_reward']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: isUnlocked
                                                    ? const Color(0xFFF5A623)
                                                    : const Color(0xFF5D6475),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.monetization_on_rounded,
                                              size: 11,
                                              color: isUnlocked
                                                  ? const Color(0xFFF5A623)
                                                  : const Color(0xFF5D6475),
                                            ),
                                          ],
                                        ),
                                        if (q['is_timer_based'] == true) ...[
                                          const Spacer(),
                                          Icon(
                                            Icons.timer_outlined,
                                            size: 13,
                                            color: isUnlocked
                                                ? const Color(0xFFF5A623)
                                                : const Color(0xFF5D6475),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${q['timer_duration_minutes'] ?? 25}м',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isUnlocked
                                                  ? const Color(0xFF8E95A5)
                                                  : const Color(0xFF5D6475),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );

                        return Column(
                          children: [
                            Row(
                              children: [
                                if (isCircleOnRight) ...[
                                  descriptionCard,
                                  const SizedBox(width: 14),
                                  circleWidget,
                                ] else ...[
                                  circleWidget,
                                  const SizedBox(width: 14),
                                  descriptionCard,
                                ],
                              ],
                            ),
                            if (!isLast)
                              CustomPaint(
                                size: const Size(double.infinity, 44),
                                painter: PathConnectorPainter(
                                  startX: currentOffset,
                                  endX: nextOffset,
                                  // Отдельный графитово-стальной цвет пунктира тропы:
                                  color: const Color(0xFF5E6778),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

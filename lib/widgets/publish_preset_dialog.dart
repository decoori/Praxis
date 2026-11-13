import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/uuid.dart';

class PublishPresetDialog extends StatefulWidget {
  final String userId;
  final String authorName;
  final Color primaryColor;
  final List<Map<String, dynamic>> goals;
  final List<Map<String, dynamic>> quests;
  final String? initialGoalId;
  final VoidCallback onPublished;

  const PublishPresetDialog({
    super.key,
    required this.userId,
    required this.authorName,
    required this.primaryColor,
    required this.goals,
    required this.quests,
    this.initialGoalId,
    required this.onPublished,
  });

  @override
  State<PublishPresetDialog> createState() => _PublishPresetDialogState();
}

class _PublishPresetDialogState extends State<PublishPresetDialog> {
  late String? _selectedGoalId;
  String _selectedCategory = 'Привычки';
  final _descController = TextEditingController();
  bool _isPublishing = false;
  String? _errorMessage;

  final List<String> _categories = [
    'Спорт',
    'IT & Навыки',
    'Привычки',
    'Языки',
    'Саморазвитие',
  ];

  @override
  void initState() {
    super.initState();
    _selectedGoalId =
        widget.initialGoalId ??
        (widget.goals.isNotEmpty ? widget.goals.first['id'].toString() : null);
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_selectedGoalId == null) {
      setState(() => _errorMessage = 'Цель для публикации');
      return;
    }

    final goal = widget.goals.firstWhere(
      (g) => g['id'].toString() == _selectedGoalId,
    );
    final goalQuests = widget.quests
        .where((q) => q['goal_id'].toString() == _selectedGoalId)
        .toList();

    if (goalQuests.isEmpty) {
      setState(() => _errorMessage = 'В цели нет шагов — публиковать нечего');
      return;
    }

    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    final stepsPayload = goalQuests
        .map(
          (q) => {
            'title': q['title'] ?? '',
            'is_timer': q['is_timer_based'] == true,
            'duration_minutes': q['timer_duration_minutes'] ?? 25,
            'xp_reward': q['xp_reward'] ?? 40,
            'gold_reward': q['gold_reward'] ?? 20,
          },
        )
        .toList();

    final supabase = Supabase.instance.client;

    try {
      await supabase.from('goal_presets').insert({
        'id': generateUuid(),
        'author_id': widget.userId,
        'author_name': widget.authorName,
        'title': goal['title'] ?? 'Без названия',
        'category': _selectedCategory,
        'description': _descController.text.trim().isEmpty
            ? 'Пользовательский пресет правителя ${widget.authorName}'
            : _descController.text.trim(),
        'steps': jsonEncode(stepsPayload),
        'uses_count': 0,
        'score': 0,
      });

      if (!mounted) return;
      widget.onPublished();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Цель опубликована в библиотеку'),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _errorMessage = 'Не удалось опубликовать';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14171E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x28FFFFFF)),
      ),
      title: const Row(
        children: [
          Icon(Icons.share_rounded, color: Color(0xFF00E676), size: 24),
          SizedBox(width: 10),
          Text(
            'Опубликовать пресет',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Цель увидят все игроки в библиотеке',
              style: TextStyle(color: Color(0xFF8E95A5), fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Выберите цель:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D24),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGoalId,
                  dropdownColor: const Color(0xFF1A1D24),
                  isExpanded: true,
                  items: widget.goals.map((g) {
                    return DropdownMenuItem<String>(
                      value: g['id'].toString(),
                      child: Text(
                        g['title'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedGoalId = val),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Категория:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D24),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: const Color(0xFF1A1D24),
                  isExpanded: true,
                  items: _categories.map((c) {
                    return DropdownMenuItem<String>(
                      value: c,
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) =>
                      setState(() => _selectedCategory = val ?? 'Привычки'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Описание',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Совет тем, кто пойдёт по цели',
                hintStyle: const TextStyle(
                  color: Color(0xFF5D6475),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1D24),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPublishing ? null : () => Navigator.pop(context),
          child: const Text(
            'Отмена',
            style: TextStyle(color: Color(0xFF8E95A5)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _isPublishing ? null : _publish,
          child: _isPublishing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text(
                  'Опубликовать',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }
}

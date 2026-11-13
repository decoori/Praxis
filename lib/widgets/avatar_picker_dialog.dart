import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/avatars_config.dart';
import 'avatar_widget.dart';

class AvatarPickerDialog extends StatefulWidget {
  final String currentAvatarId;
  final String userId;
  final ValueChanged<String> onAvatarSelected;

  const AvatarPickerDialog({
    super.key,
    required this.currentAvatarId,
    required this.userId,
    required this.onAvatarSelected,
  });

  @override
  State<AvatarPickerDialog> createState() => _AvatarPickerDialogState();
}

class _AvatarPickerDialogState extends State<AvatarPickerDialog> {
  late String _selectedId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentAvatarId;
  }

  Future<void> _saveAvatar(String avatarId) async {
    setState(() {
      _selectedId = avatarId;
      _isSaving = true;
    });

    try {
      // 1. Сначала жестко фиксируем в базе данных
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_id': avatarId})
          .eq('id', widget.userId);

      // 2. Уведомляем интерфейс
      widget.onAvatarSelected(avatarId);
    } catch (e) {
      debugPrint('Ошибка сохранения аватара: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14171E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: Color(0x28FFFFFF)),
      ),
      title: const Row(
        children: [
          Icon(Icons.palette_rounded, color: Color(0xFFF5A623), size: 24),
          SizedBox(width: 10),
          Text(
            'Аватар правителя',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio:
                0.70, // Увеличили высоту ячеек, чтобы текст не вылезал
          ),
          itemCount: gameAvatars.length,
          itemBuilder: (context, index) {
            final a = gameAvatars[index];
            final isSelected = a.id == _selectedId;

            return InkWell(
              onTap: _isSaving ? null : () => _saveAvatar(a.id),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? a.glowColor.withValues(alpha: 0.18)
                      : const Color(0xFF1A1D24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFF5A623)
                        : const Color(0x1AFFFFFF),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Чуть оптимизировали размер с 52 до 46px
                    AvatarWidget(
                      avatarId: a.id,
                      size: 46,
                      showGlow: isSelected,
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Center(
                        child: Text(
                          a.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF8E95A5),
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Закрыть',
            style: TextStyle(color: Color(0xFF8E95A5)),
          ),
        ),
      ],
    );
  }
}

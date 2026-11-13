import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/game_config.dart';
import '../screens/profile_screen.dart';

/// Поиск игрока по неизменяемому ID (@user_tag) и заключение союза.
///
/// Функциональность, которую вытеснила карточка «Друзья»: сама вставка в
/// `friendships` живёт в `ProfileScreen`, а этот диалог даёт найти человека,
/// которого нет в списках — по ID из шапки его профиля.
class AddFriendDialog extends StatefulWidget {
  final String currentUserId;
  final Color primaryColor;
  final VoidCallback onFriendAdded;

  const AddFriendDialog({
    super.key,
    required this.currentUserId,
    required this.primaryColor,
    required this.onFriendAdded,
  });

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final _controller = TextEditingController();
  bool _isSearching = false;
  bool _isAdding = false;
  String? _errorMessage;
  Map<String, dynamic>? _foundUser;

  /// Найденный игрок уже в союзниках — кнопка добавления не нужна.
  bool _alreadyFriends = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Нормализация ввода: убираем @, приводим к нижнему регистру.
  /// Теги в БД хранятся в нижнем регистре (`profiles_user_tag_format`).
  String get _cleanTag =>
      _controller.text.trim().replaceAll('@', '').toLowerCase();

  Future<void> _searchUser() async {
    final cleanTag = _cleanTag;
    if (cleanTag.isEmpty) return;

    if (cleanTag.length < 3) {
      setState(() => _errorMessage = 'ID: минимум 3 символа');
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _foundUser = null;
      _alreadyFriends = false;
    });

    final supabase = Supabase.instance.client;

    try {
      final res = await supabase
          .from('profiles')
          .select()
          .eq('user_tag', cleanTag)
          .maybeSingle();

      final found = res;

      if (!mounted) return;

      if (found == null) {
        setState(() => _errorMessage = 'Игрок с ID @$cleanTag не найден');
        return;
      }

      if (found['id'] == widget.currentUserId) {
        setState(() => _errorMessage = 'Это ваш ID');
        return;
      }

      // Проверяем существующую связь, чтобы не показывать кнопку добавления
      // там, где союз уже заключён.
      final existing = await supabase
          .from('friendships')
          .select('id')
          .eq('user_id', widget.currentUserId)
          .eq('friend_id', found['id'])
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _foundUser = found;
        _alreadyFriends = existing != null;
      });
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = 'Ошибка поиска (${e.code ?? '—'}): ${e.message}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Ошибка поиска: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addFriend() async {
    final target = _foundUser;
    if (target == null || _alreadyFriends) return;

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    final supabase = Supabase.instance.client;
    final targetId = target['id'].toString();

    try {
      await supabase.from('friendships').insert({
        'user_id': widget.currentUserId,
        'friend_id': targetId,
      });

      if (!mounted) return;

      widget.onFriendAdded();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${target['username'] ?? 'Правитель'} теперь ваш союзник!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } on PostgrestException catch (e) {
      // 23505 — связь уже существует (например, создана с другого устройства).
      final isDuplicate =
          e.code == '23505' || (e.message).contains('duplicate');
      if (mounted) {
        setState(() {
          if (isDuplicate) {
            _alreadyFriends = true;
            _errorMessage = 'Уже в союзниках';
          } else {
            _errorMessage = 'Не удалось добавить: ${e.message}';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Не удалось добавить: $e');
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _openProfile(Map<String, dynamic> user) {
    final userId = user['id'].toString();
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: userId,
          isCurrentUser: userId == widget.currentUserId,
          initialProfile: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final found = _foundUser;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1D24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x28FFFFFF)),
      ),
      title: const Row(
        children: [
          Icon(Icons.person_search_rounded, color: Color(0xFFF5A623), size: 24),
          SizedBox(width: 10),
          Text(
            'Найти союзника',
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
              'ID игрока без @',
              style: TextStyle(color: Color(0xFF8E95A5), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_isSearching && !_isAdding,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchUser(),
              inputFormatters: [
                // Формат ID продублирован из БД: латиница, цифры и _.
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                LengthLimitingTextInputFormatter(16),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: 'alex_warrior',
                hintStyle: const TextStyle(color: Color(0xFF5D6475)),
                prefixText: '@',
                prefixStyle: const TextStyle(
                  color: Color(0xFFF5A623),
                  fontWeight: FontWeight.bold,
                ),
                filled: true,
                fillColor: const Color(0xFF14171E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFFF5A623),
                  ),
                  onPressed: _isSearching ? null : _searchUser,
                ),
              ),
            ),
            if (_isSearching) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
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
            if (found != null) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: () => _openProfile(found),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.primaryColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A1D24),
                          border: Border.all(color: widget.primaryColor),
                        ),
                        child: Icon(
                          (eras[found['current_era']] ?? eras['stone_age']!)
                              .icon,
                          color: widget.primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              found['username'] ?? 'Правитель',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '@${found['user_tag'] ?? 'unknown'} • ',
                                  style: const TextStyle(
                                    color: Color(0xFF8E95A5),
                                    fontSize: 11,
                                  ),
                                ),
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 12,
                                  color: Color(0xFFFF7A00),
                                ),
                                Text(
                                  ' ${found['streak_count'] ?? 0} дн.',
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
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF8E95A5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _alreadyFriends
                        ? const Color(0xFF232732)
                        : widget.primaryColor,
                    foregroundColor: _alreadyFriends
                        ? const Color(0xFF8E95A5)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: (_isAdding || _alreadyFriends) ? null : _addFriend,
                  icon: Icon(
                    _alreadyFriends
                        ? Icons.handshake_rounded
                        : Icons.person_add_alt_1_rounded,
                    size: 20,
                  ),
                  label: _isAdding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _alreadyFriends
                              ? 'Уже в союзниках'
                              : 'Заключить союз',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAdding ? null : () => Navigator.pop(context),
          child: const Text(
            'Закрыть',
            style: TextStyle(color: Color(0xFF8E95A5)),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/game_config.dart';
import '../controllers/game_controller.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/avatar_picker_dialog.dart';
import '../widgets/add_friend_dialog.dart';
import '../widgets/promo_code_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isCurrentUser;
  final Map<String, dynamic>? initialProfile;
  final VoidCallback? onLogout;

  /// Контроллер игры нужен для активации промокодов. Если экран открыт
  /// без него (например, из просмотра чужого профиля), кнопка промокода
  /// показывает подсказку вместо вызова сервера.
  final GameController? controller;

  /// Вызывается после успешной активации кода, чтобы материнский экран
  /// обновил свои данные.
  final VoidCallback? onPromoRedeemed;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
    this.initialProfile,
    this.onLogout,
    this.controller,
    this.onPromoRedeemed,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;
  String get activeAuthId => supabase.auth.currentUser?.id ?? '';

  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  int _completedQuestsCount = 0;
  bool _isActionLoading = false;

  // Списки пользователей
  List<Map<String, dynamic>> _friendsList = [];
  List<Map<String, dynamic>> _followersList = [];

  // Флаги отношений между активным игроком и просматриваемым профилем
  bool _iAddedThem = false;
  bool _theyAddedMe = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _loadProfileData();
  }

  String _getEraTitle(String eraId) {
    switch (eraId) {
      case 'stone_age':
        return 'Вождь племени';
      case 'bronze_age':
        return 'Бронзовый полководец';
      case 'iron_age':
        return 'Консул легиона';
      case 'middle_ages':
        return 'Верховный лорд';
      case 'modern_age':
        return 'Индустриальный магнат';
      case 'space_age':
        return 'Командор звёздного флота';
      default:
        return 'Исследователь цивилизации';
    }
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Загрузка профиля
      final profileRes = await supabase
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .maybeSingle();

      if (profileRes != null) {
        _profile = profileRes;
      }

      // 2. Исходящие (кого добавил этот пользователь)
      final outgoingRes = await supabase
          .from('friendships')
          .select('friend_id')
          .eq('user_id', widget.userId);
      final Set<String> outSet = (outgoingRes as List)
          .map((r) => r['friend_id'].toString())
          .toSet();

      // 3. Входящие (кто добавил этого пользователя)
      final incomingRes = await supabase
          .from('friendships')
          .select('user_id')
          .eq('friend_id', widget.userId);
      final Set<String> inSet = (incomingRes as List)
          .map((r) => r['user_id'].toString())
          .toSet();

      // Друзья = взаимно (пересечение множеств)
      final mutualFriendIds = outSet.intersection(inSet).toList();

      // Подписчики = добавили его, НО он не добавил их в ответ (разность множеств)
      final followerOnlyIds = inSet.difference(outSet).toList();

      // 4. Загрузка данных профилей для друзей
      if (mutualFriendIds.isNotEmpty) {
        final res = await supabase
            .from('profiles')
            .select()
            .inFilter('id', mutualFriendIds);
        _friendsList = List<Map<String, dynamic>>.from(res);
      } else {
        _friendsList = [];
      }

      // 5. Загрузка данных профилей для подписчиков
      if (followerOnlyIds.isNotEmpty) {
        final res = await supabase
            .from('profiles')
            .select()
            .inFilter('id', followerOnlyIds);
        _followersList = List<Map<String, dynamic>>.from(res);
      } else {
        _followersList = [];
      }

      // 6. Проверка связи между мной и открытым профилем (если смотрим чужой)
      if (!widget.isCurrentUser && activeAuthId.isNotEmpty) {
        final rel1 = await supabase
            .from('friendships')
            .select('id')
            .eq('user_id', activeAuthId)
            .eq('friend_id', widget.userId)
            .maybeSingle();
        _iAddedThem = rel1 != null;

        final rel2 = await supabase
            .from('friendships')
            .select('id')
            .eq('user_id', widget.userId)
            .eq('friend_id', activeAuthId)
            .maybeSingle();
        _theyAddedMe = rel2 != null;
      }

      // 7. Количество закрытых квестов
      final questsRes = await supabase
          .from('quests')
          .select('id, goals!inner(user_id)')
          .eq('goals.user_id', widget.userId)
          .eq('is_completed', true);
      _completedQuestsCount = (questsRes as List).length;
    } catch (e) {
      debugPrint('Profile load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Кнопка дружбы / подписки на чужом профиле
  Future<void> _toggleFriendship() async {
    if (widget.isCurrentUser || activeAuthId.isEmpty) return;
    setState(() => _isActionLoading = true);

    try {
      if (_iAddedThem) {
        // Удалить из друзей / отписаться
        await supabase
            .from('friendships')
            .delete()
            .eq('user_id', activeAuthId)
            .eq('friend_id', widget.userId);
      } else {
        // Добавить. Уникальный индекс (user_id, friend_id) из миграции 003
        // не даст создать дубликат: гонка двух тапов упрётся в БД, а не
        // в проверку в коде.
        await supabase.from('friendships').insert({
          'user_id': activeAuthId,
          'friend_id': widget.userId,
        });
      }
      await _loadProfileData();
    } on PostgrestException catch (e) {
      // 23505 — связь уже существует, состояние просто было устаревшим.
      if (e.code == '23505') {
        await _loadProfileData();
      } else {
        debugPrint('Error toggling friendship: ${e.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось изменить список'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling friendship: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // Добавить подписчика в друзья в ответ
  Future<void> _addBackUser(String targetId) async {
    try {
      await supabase.from('friendships').insert({
        'user_id': activeAuthId,
        'friend_id': targetId,
      });

      // После await окно со списком подписчиков могло быть закрыто.
      if (!mounted) return;

      Navigator.pop(context);
      _loadProfileData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Теперь вы друзья'),
          backgroundColor: Colors.green,
        ),
      );
    } on PostgrestException catch (e) {
      // Связь уже могла быть создана — это не ошибка для игрока.
      if (e.code == '23505') {
        if (mounted) _loadProfileData();
        return;
      }
      debugPrint('Add back error: ${e.message}');
    } catch (e) {
      debugPrint('Add back error: $e');
    }
  }

  /// Поиск игрока по неизменяемому ID и заключение союза.
  ///
  /// После добавления список друзей перечитывается из БД: связь пишет сам
  /// диалог, а экран только синхронизирует отображение.
  Future<void> _openAddFriendDialog() async {
    if (!widget.isCurrentUser || activeAuthId.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AddFriendDialog(
        currentUserId: activeAuthId,
        primaryColor:
            (eras[_profile?['current_era']] ?? eras['stone_age']!).primaryColor,
        onFriendAdded: _loadProfileData,
      ),
    );
  }

  Future<void> _editUsername() async {
    if (!widget.isCurrentUser) return;
    final currentName = _profile?['username'] ?? 'Правитель';
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Изменить никнейм',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF14171E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Color(0xFF8E95A5)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5A623),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Сохранить',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      setState(() => _profile?['username'] = newName);
      await supabase
          .from('profiles')
          .update({'username': newName})
          .eq('id', widget.userId);
    }
  }

  void _openAvatarPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AvatarPickerDialog(
        currentAvatarId: _profile?['avatar_id'] ?? 'cave_hunter',
        userId: widget.userId,
        onAvatarSelected: (newId) {
          setState(() {
            // Создаем копию карты, чтобы Flutter гарантированно перерисовал виджет
            _profile = Map<String, dynamic>.from(_profile ?? {});
            _profile!['avatar_id'] = newId;
          });
        },
      ),
    );
  }

  // Открытие списков пользователей (Подписчики / Друзья)
  void _openUsersListModal({
    required String title,
    required List<Map<String, dynamic>> users,
    required bool isFollowersMode,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14171E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D24),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${users.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF5A623),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: users.isEmpty
                    ? Center(
                        child: Text(
                          isFollowersMode ? 'Заявок нет' : 'Друзей пока нет',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF8E95A5),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final u = users[index];
                          final uEra =
                              eras[u['current_era']] ?? eras['stone_age']!;
                          final uId = u['id'].toString();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1D24),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0x14FFFFFF),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Аватар игрока
                                InkWell(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProfileScreen(
                                          userId: uId,
                                          isCurrentUser: uId == activeAuthId,
                                          initialProfile: u,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF14171E),
                                      border: Border.all(
                                        color: uEra.primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      uEra.icon,
                                      color: uEra.primaryColor,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Ник и инфо
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ProfileScreen(
                                            userId: uId,
                                            isCurrentUser: uId == activeAuthId,
                                            initialProfile: u,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          u['username'] ?? 'Правитель',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              '@${u['user_tag'] ?? 'id'} • ${uEra.name} • ',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF8E95A5),
                                              ),
                                            ),
                                            const Icon(
                                              Icons
                                                  .local_fire_department_rounded,
                                              size: 12,
                                              color: Color(0xFFFF7A00),
                                            ),
                                            Text(
                                              ' ${u['streak_count'] ?? 0} дн.',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF8E95A5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Кнопка "В ответ" для подписчиков
                                if (isFollowersMode &&
                                    widget.isCurrentUser) ...[
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF5A623),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => _addBackUser(uId),
                                    child: const Text(
                                      'В друзья',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
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
    final eraId = _profile?['current_era'] ?? 'stone_age';
    final era = eras[eraId] ?? eras['stone_age']!;
    final username = _profile?['username'] ?? 'Правитель';
    final eraTitle = _getEraTitle(eraId);
    final streak = _profile?['streak_count'] ?? 0;
    final gold = _profile?['gold'] ?? 0;
    final campLevel = _profile?['camp_level'] ?? 1;

    // Статус отношений для чужого профиля
    String actionLabel = 'Добавить в друзья';
    IconData actionIcon = Icons.person_add_rounded;
    Color actionBtnColor = era.primaryColor;

    if (_iAddedThem && _theyAddedMe) {
      actionLabel = 'Вы друзья';
      actionIcon = Icons.handshake_rounded;
      actionBtnColor = const Color(0xFF00E676);
    } else if (_iAddedThem && !_theyAddedMe) {
      actionLabel = 'Заявка отправлена';
      actionIcon = Icons.check_rounded;
      actionBtnColor = const Color(0xFF1A1D24);
    } else if (!_iAddedThem && _theyAddedMe) {
      actionLabel = 'Добавить в ответ';
      actionIcon = Icons.person_add_alt_1_rounded;
      actionBtnColor = const Color(0xFFF5A623);
    }

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
        title: Text(
          widget.isCurrentUser ? 'Мой профиль' : 'Профиль игрока',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading && _profile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // 1. АВАТАР ЦИВИЛИЗАЦИИ
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        AvatarWidget(
                          avatarId: _profile?['avatar_id'],
                          size: 110,
                          showGlow: true,
                          onTap: widget.isCurrentUser
                              ? _openAvatarPicker
                              : null,
                        ),
                        if (widget.isCurrentUser)
                          InkWell(
                            onTap: _openAvatarPicker,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF5A623),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.photo_camera_rounded,
                                size: 16,
                                color: Colors.black,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. НИКНЕЙМ
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (widget.isCurrentUser) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _editUsername,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1D24),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x28FFFFFF),
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: Color(0xFFF5A623),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '@${_profile?['user_tag'] ?? 'id'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8E95A5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. ЗВАНИЕ ЭПОХИ
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: era.primaryColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: era.primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      eraTitle.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: era.primaryColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Кнопка дружбы для чужого профиля
                  if (!widget.isCurrentUser) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: actionBtnColor,
                          foregroundColor:
                              (_iAddedThem && _theyAddedMe) ||
                                  (!_iAddedThem && _theyAddedMe)
                              ? Colors.black
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: _iAddedThem
                                  ? const Color(0x28FFFFFF)
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        onPressed: _isActionLoading ? null : _toggleFriendship,
                        icon: Icon(actionIcon, size: 18),
                        label: Text(
                          actionLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // 4. КРАТКАЯ СВОДКА СТАТИСТИКИ
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D24),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Сводка',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF8E95A5),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _statTile('Эпоха', era.name, era.primaryColor),
                            _statTile('Лагерь', '$campLevel/5', Colors.white),
                            _statTile(
                              'Серия дней',
                              '$streak дн.',
                              const Color(0xFFFF7A00),
                            ),
                          ],
                        ),
                        const Divider(color: Color(0x12FFFFFF), height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _statTile(
                              'Квестов закрыто',
                              '$_completedQuestsCount',
                              const Color(0xFF00E676),
                            ),
                            _statTile(
                              'Казна',
                              '$gold',
                              const Color(0xFFF5A623),
                              icon: Icons.monetization_on_rounded,
                            ),
                            _statTile(
                              'Статус',
                              streak > 0 ? 'В строю' : 'Отдых',
                              const Color(0xFF00B0FF),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. Вкладка «ПОДПИСЧИКИ» (Те, кто добавил, но вы не ответили)
                  _socialCardButton(
                    icon: Icons.person_pin_rounded,
                    title: 'Подписчики',
                    count: _followersList.length,
                    onTap: () => _openUsersListModal(
                      title: 'Ждут ответа',
                      users: _followersList,
                      isFollowersMode: true,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 6. Вкладка «ДРУЗЬЯ» (Взаимные союзники) + поиск по ID
                  _socialCardButton(
                    icon: Icons.people_alt_rounded,
                    title: 'Друзья',
                    count: _friendsList.length,
                    onTap: () => _openUsersListModal(
                      title: 'Друзья',
                      users: _friendsList,
                      isFollowersMode: false,
                    ),
                    action: widget.isCurrentUser
                        ? IconButton(
                            icon: const Icon(
                              Icons.person_search_rounded,
                              color: Color(0xFF00E676),
                              size: 22,
                            ),
                            tooltip: 'Найти союзника по ID',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            onPressed: _openAddFriendDialog,
                          )
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Промокоды — только на своём профиле: чужой аккаунт не должен
                  // получать награды с моего кода.
                  if (widget.isCurrentUser) ...[
                    _promoCodeButton(),
                    const SizedBox(height: 12),
                  ],

                  if (widget.isCurrentUser && widget.onLogout != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF5252),
                        side: const BorderSide(color: Color(0x55FF5252)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onLogout!();
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Выйти из аккаунта',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
    );
  }

  /// Открывает диалог активации промокода.
  ///
  /// Профиль перезагружается только после успешной активации: сервер уже
  /// начислил награду, поэтому остаётся синхронизировать экран.
  Future<void> _openPromoCodeDialog() async {
    final controller = widget.controller;
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Промокоды вводятся на игровом экране'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => PromoCodeDialog(
        controller: controller,
        // `era` объявлена внутри build(), поэтому берём конфигурацию заново.
        primaryColor:
            (eras[_profile?['current_era']] ?? eras['stone_age']!).primaryColor,
        onRedeemed: () {
          _loadProfileData();
          widget.onPromoRedeemed?.call();
        },
      ),
    );
  }

  Widget _promoCodeButton() {
    return InkWell(
      onTap: _openPromoCodeDialog,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFF5A623).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF14171E),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.redeem_rounded,
                color: Color(0xFFF5A623),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Промокод',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Введите код, чтобы получить награду',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8E95A5)),
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

  Widget _statTile(String label, String value, Color color, {IconData? icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 3),
              Icon(icon, size: 14, color: color),
            ],
          ],
        ),
      ],
    );
  }

  Widget _socialCardButton({
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onTap,
    Widget? action,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF14171E),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFFF5A623), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
            if (action != null) ...[action, const SizedBox(width: 4)],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Color(0xFFF5A623),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
}

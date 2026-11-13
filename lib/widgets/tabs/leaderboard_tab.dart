import 'package:flutter/material.dart';

import '../../constants/game_config.dart';
import '../../controllers/game_controller.dart';
import '../../screens/profile_screen.dart';
import '../avatar_widget.dart';

class LeaderboardTab extends StatefulWidget {
  final EraConfig era;
  final Map<String, dynamic>? profile;
  final String currentUserId;

  /// Контроллер игры: через него запрашивается таблица лиги
  /// (get_league_leaderboard) — лига, сезон, награды и участники.
  final GameController controller;

  /// Видна ли вкладка сейчас. Данные обновляются при входе на вкладку, а не
  /// при каждом изменении профиля: раньше любое обновление состояния тянуло
  /// сетевую перезагрузку рейтинга.
  final bool isVisible;

  const LeaderboardTab({
    super.key,
    required this.era,
    required this.profile,
    required this.currentUserId,
    required this.controller,
    this.isVisible = true,
  });

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  /// Режим таблицы: 'league' — своя лига, 'friends' — союзники.
  String _mode = 'league';
  bool _isLoading = true;

  /// Ответ серверной функции get_league_leaderboard целиком.
  Map<String, dynamic>? _board;

  /// Когда рейтинг загружался в последний раз — чтобы не дёргать сеть
  /// при быстром переключении вкладок.
  DateTime? _lastLoadedAt;

  static const Duration _refreshTtl = Duration(seconds: 20);

  /// Сколько строк рейтинга построено сейчас. Растёт при прокрутке вниз,
  /// поэтому полсотни карточек не строятся на каждое обновление состояния.
  static const int _pageSize = 15;
  int _visibleCount = _pageSize;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAllRankings(showSpinner: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Подгружаем следующую порцию заранее, за 300 пикселей до конца.
    if (position.pixels >= position.maxScrollExtent - 300) {
      final currentList = _rows;
      if (_visibleCount < currentList.length && mounted) {
        setState(() => _visibleCount += _pageSize);
      }
    }
  }

  @override
  void didUpdateWidget(covariant LeaderboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Обновляем данные только при входе на вкладку и не чаще TTL.
    // Прежнее условие сравнивало поля одного и того же объекта карты
    // (контроллер мутирует её на месте), поэтому срабатывало непредсказуемо.
    if (!oldWidget.isVisible && widget.isVisible) {
      final loadedAt = _lastLoadedAt;
      final isStale =
          loadedAt == null || DateTime.now().difference(loadedAt) > _refreshTtl;
      if (isStale) {
        _loadAllRankings(showSpinner: false);
      }
    }
  }

  bool _isFetching = false;

  Future<void> _loadAllRankings({bool showSpinner = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      // Итоги сезона подводит первый зашедший. Обновление вкладки тоже
      // закрывает просроченный сезон: иначе награду пришлось бы ждать до
      // перезапуска приложения, а баннер показывал бы «Подведение итогов».
      await widget.controller.settleLeagueSeason();

      // Всё считает серверная функция get_league_leaderboard: моя лига,
      // конец сезона, награды и список игроков по СЕЗОННОМУ опыту.
      // Раньше здесь были прямые запросы к profiles и friendships, а рейтинг
      // сортировался по xp — счётчику, который тратится на эволюцию эпохи,
      // из-за чего развивающиеся игроки падали вниз списка.
      final board = await widget.controller.loadLeagueLeaderboard(_mode);
      if (board != null && mounted) {
        setState(() {
          _board = board;
          _lastLoadedAt = DateTime.now();
        });
      }

      _showLeagueAwardIfAny();
    } catch (e) {
      debugPrint('Error in _loadAllRankings: $e');
    } finally {
      _isFetching = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Сообщение о награде за прошедший сезон, если она есть.
  void _showLeagueAwardIfAny() {
    final message = widget.controller.consumeLeagueAwardMessage();
    if (message == null || !mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Строки таблицы из ответа сервера.
  List<Map<String, dynamic>> get _rows {
    final raw = _board?['rows'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  DateTime? get _seasonEndsAt {
    final raw = _board?['season_ends_at'];
    if (raw is! String) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  void _openUserProfile(Map<String, dynamic> user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: user['id'].toString(),
          isCurrentUser: user['id'] == widget.currentUserId,
          initialProfile: user,
        ),
      ),
    ).then((_) => _loadAllRankings());
  }

  /// Сколько осталось до конца сезона. Время приходит с сервера — клиентские
  /// часы могут быть сбиты, а сезон закрывает серверная функция.
  String _getTimeUntilReset() {
    final endsAt = _seasonEndsAt;
    if (endsAt == null) return '—';

    final left = endsAt.difference(DateTime.now());
    if (left.isNegative) return 'Подведение итогов';

    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;

    if (days > 0) return '$days дн. $hours ч.';
    if (hours > 0) return '$hours ч. $minutes мин.';
    return '$minutes мин.';
  }

  /// Моя лига из ответа сервера.
  Map<String, dynamic>? get _tier {
    final raw = _board?['tier'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// Следующая лига и сколько опыта до неё осталось.
  Map<String, dynamic>? get _nextTier {
    final raw = _board?['next_tier'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  int get _myTotalXp =>
      ((_board?['me'] as Map?)?['total_xp'] as num?)?.toInt() ?? 0;
  int get _mySeasonXp =>
      ((_board?['me'] as Map?)?['season_xp'] as num?)?.toInt() ?? 0;
  int get _myPlace => ((_board?['me'] as Map?)?['place'] as num?)?.toInt() ?? 0;

  /// Награды за места из справочника на сервере.
  List<Map<String, dynamic>> get _rewards {
    final raw = _board?['rewards'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String get _rewardLine {
    if (_rewards.isEmpty) return 'Награда за топ-3';
    final parts = _rewards
        .map((r) => '${r['place']} место — ${r['gold']}')
        .join(', ');
    return 'Награда за топ-3: $parts золота';
  }

  /// Переключение режима с перезагрузкой таблицы с сервера.
  void _switchMode(String mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _visibleCount = _pageSize;
      _isLoading = true;
    });
    _loadAllRankings(showSpinner: true);
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _rows;
    final myRank = _myPlace;

    // Показываем не весь список сразу, а порциями: карточек бывает пятьдесят,
    // и строить их все на каждое обновление состояния — лишняя работа.
    final int visibleCount = currentList.length < _visibleCount
        ? currentList.length
        : _visibleCount;

    return Stack(
      children: [
        RefreshIndicator(
          color: widget.era.primaryColor,
          backgroundColor: const Color(0xFF14171E),
          onRefresh: _loadAllRankings,
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
            children: [
              // Переключатель: Лига / Союзники
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF14171E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _modeButton(
                        title: 'Моя лига',
                        icon: Icons.emoji_events_rounded,
                        isActive: _mode == 'league',
                        onTap: () => _switchMode('league'),
                      ),
                    ),
                    Expanded(
                      child: _modeButton(
                        title: 'Среди союзников',
                        icon: Icons.people_alt_rounded,
                        isActive: _mode == 'friends',
                        onTap: () => _switchMode('friends'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Турнирный баннер сезона с таймером
              _seasonLeagueHeader(),
              const SizedBox(height: 18),

              // Заголовок списка с правилами зоны повышения
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _mode == 'league' ? 'Таблица лидеров' : 'Рейтинг союзников',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFF5A623).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.emoji_events_rounded,
                          size: 12,
                          color: Color(0xFFF5A623),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Топ-3: золото',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFF5A623),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (currentList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D24),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.military_tech_outlined,
                        size: 48,
                        color: Color(0xFF8E95A5),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Пока пусто',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'В этой лиге пока никого с опытом',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8E95A5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...List.generate(visibleCount, (index) {
                  final user = currentList[index];
                  // Место приходит с сервера отдельным полем: у игроков без
                  // опыта за сезон места нет вовсе, поэтому нумеровать список
                  // по порядку нельзя — это обещало бы награду, которой не будет.
                  final place = (user['place'] as num?)?.toInt() ?? 0;
                  final isMe = user['id'] == widget.currentUserId;

                  return Column(
                    children: [
                      _leaderboardCard(
                        rank: place,
                        user: user,
                        isMe: isMe,
                        onTap: () => _openUserProfile(user),
                      ),
                      // Граница призовой зоны: награду получают первые три места.
                      // В режиме союзников призов нет, поэтому и границы нет.
                      if (place == 3 && _mode == 'league')
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Divider(
                                  color: Color(0xFF00E676),
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  'ТОП-3 ПОЛУЧАЮТ ЗОЛОТО',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF00E676)
                                        .withValues(alpha: 0.8),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(
                                  color: Color(0xFF00E676),
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                }),
            ],
          ),
        ),

        // Закрепленная нижняя плашка: позиция текущего игрока
        if (myRank > 0)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.era.primaryColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.era.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.era.primaryColor.withValues(alpha: 0.2),
                    ),
                    child: Text(
                      '#$myRank',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: widget.era.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AvatarWidget(
                    avatarId: widget.profile?['avatar_id'],
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _mode == 'league'
                              ? 'Ваше место'
                              : 'Ваше место среди союзников',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E95A5),
                          ),
                        ),
                        Text(
                          '${widget.profile?['username'] ?? 'Правитель'} (Вы)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
                      '$_mySeasonXp XP за сезон',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: widget.era.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // В зачёт лиги попадают только те, кто набрал опыт за сезон:
        // место и награду получают одни и те же игроки. Пока опыта нет,
        // объясняем это прямо, а не показываем пустое место.
        if (myRank == 0 && _mode == 'league' && !_isLoading && _board != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF8E95A5),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Вне зачёта: за сезон опыта нет',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8E95A5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Карточка игрока в ладдере
  Widget _leaderboardCard({
    required int rank,
    required Map<String, dynamic> user,
    required bool isMe,
    required VoidCallback onTap,
  }) {
    final eraConfig = eras[user['current_era']] ?? eras['stone_age']!;
    // Соревнование идёт по опыту, набранному за текущий сезон.
    final int xp = (user['season_xp'] as num?)?.toInt() ?? 0;
    final int streak = (user['streak_count'] as num?)?.toInt() ?? 0;

    // Стилизация топ-3 мест
    Color? rankBadgeBg;
    Widget rankIcon;

    if (rank == 1) {
      rankBadgeBg = const Color(0xFFFFD700);
      rankIcon = const Icon(
        Icons.emoji_events_rounded,
        size: 20,
        color: Color(0xFFFFD700),
      );
    } else if (rank == 2) {
      rankBadgeBg = const Color(0xFFC0C0C0);
      rankIcon = const Icon(
        Icons.emoji_events_rounded,
        size: 20,
        color: Color(0xFFC0C0C0),
      );
    } else if (rank == 3) {
      rankBadgeBg = const Color(0xFFCD7F32);
      rankIcon = const Icon(
        Icons.emoji_events_rounded,
        size: 20,
        color: Color(0xFFCD7F32),
      );
    } else {
      // rank == 0 — игрок в лиге есть, но опыта за сезон ещё нет:
      // места у него нет, показываем прочерк вместо выдуманного номера.
      rankIcon = Text(
        rank > 0 ? '#$rank' : '—',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: rank > 0 ? 14 : 16,
          color: rank > 0 ? const Color(0xFF8E95A5) : const Color(0xFF5D6475),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMe
                ? widget.era.primaryColor.withValues(alpha: 0.14)
                : const Color(0xFF1A1D24),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isMe
                  ? widget.era.primaryColor
                  : (rank <= 3
                        ? (rankBadgeBg ?? const Color(0xFFF5A623)).withValues(
                            alpha: 0.3,
                          )
                        : const Color(0x14FFFFFF)),
              width: isMe ? 2 : 1.2,
            ),
            boxShadow: rank <= 3
                ? [
                    BoxShadow(
                      color: (rankBadgeBg ?? Colors.transparent).withValues(
                        alpha: 0.08,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              // Место в топе
              SizedBox(width: 32, child: Center(child: rankIcon)),
              const SizedBox(width: 10),

              // Аватар персонажа
              AvatarWidget(
                avatarId: user['avatar_id'],
                size: 44,
                showGlow: rank <= 3,
              ),
              const SizedBox(width: 12),

              // Никнейм и текущая эра
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user['username'] ?? 'Правитель',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isMe
                                  ? FontWeight.w900
                                  : FontWeight.bold,
                              fontSize: 14,
                              color: isMe
                                  ? const Color(0xFFF5A623)
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '(Вы)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF5A623),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user['user_tag'] ?? 'id'} • ${eraConfig.name}',
                      style: TextStyle(
                        fontSize: 11,
                        color: eraConfig.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Серия
              if (streak > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 13,
                        color: Color(0xFFFF7A00),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$streak',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Очки опыта (XP)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF14171E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: Text(
                  '$xp XP',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Турнирный баннер: моя лига, конец сезона, награды и путь до следующей лиги.
  Widget _seasonLeagueHeader() {
    final tier = _tier;
    final nextTier = _nextTier;
    final tierName = (tier?['name'] as String?) ?? 'Лига';
    final nextTierName = nextTier?['name'] as String?;
    final nextTierXp = (nextTier?['min_total_xp'] as num?)?.toInt();
    final toNext = nextTierXp == null ? 0 : (nextTierXp - _myTotalXp);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.era.primaryColor,
            widget.era.primaryColor.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.era.primaryColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.era.primaryColor.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF14171E).withValues(alpha: 0.4),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFF5A623),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tierName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'До конца сезона: ${_getTimeUntilReset()}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (toNext > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'До «$nextTierName»: $toNext XP',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF14171E).withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 16,
                  color: Color(0xFFF5A623),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _rewardLine,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: Colors.white70),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Лига — по общему опыту, места — по опыту за сезон',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? widget.era.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : const Color(0xFF8E95A5),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: isActive ? Colors.white : const Color(0xFF8E95A5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

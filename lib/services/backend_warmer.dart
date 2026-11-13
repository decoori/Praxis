import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

/// Прогрев backend, который засыпает на бесплатном тарифе Render.
///
/// Контейнер останавливается после ~15 минут без входящих запросов, а
/// пробуждение занимает десятки секунд. Игрок всё это время ждёт ответа
/// генерации и считает, что приложение зависло.
///
/// Что делает прогрев:
///   * при запуске игры сразу отправляет лёгкий запрос — контейнер начинает
///     подниматься, пока игрок ещё ходит по экранам, а не в момент нажатия
///     «Создать»;
///   * пока приложение на переднем плане, повторяет запрос раз в 10 минут,
///     чтобы сервис не успел заснуть снова.
///
/// Ответ не важен: даже 404 означает, что контейнер проснулся и обработал
/// запрос. Ошибки намеренно проглатываются — прогрев не должен мешать игре
/// и не должен показывать игроку никаких сообщений.
///
/// ВАЖНО: пока приложение свёрнуто, система может останавливать таймеры,
/// поэтому прогрев работает только пока игра открыта. Полностью проблему
/// решает только регулярный внешний пинг (cron) — см. README.
class BackendWarmer {
  BackendWarmer({http.Client? client, this.interval = defaultInterval})
    : _client = client ?? http.Client();

  /// Период прогрева. Render останавливает контейнер после ~15 минут простоя,
  /// поэтому 10 минут дают запас.
  static const Duration defaultInterval = Duration(minutes: 10);

  /// Сколько ждём ответ на фоновый прогрев.
  static const Duration pingTimeout = Duration(seconds: 8);

  /// Сколько готовы ждать пробуждения перед отправкой запроса генерации.
  static const Duration wakeUpTimeout = Duration(seconds: 55);

  final http.Client _client;
  final Duration interval;

  Timer? _timer;
  bool _isAwake = false;
  int _pingCount = 0;

  /// Сервер хотя бы раз ответил — значит контейнер поднимался.
  bool get isAwake => _isAwake;

  /// Сколько раз прогрев получил ответ. Нужно тестам и диагностике.
  int get pingCount => _pingCount;

  /// Запускает прогрев: сразу и далее по таймеру. Повторный вызов безопасен.
  void start() {
    if (_timer != null) return;
    ping();
    _timer = Timer.periodic(interval, (_) => ping());
  }

  /// Останавливает периодический прогрев.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Лёгкий запрос к корню backend. Никогда не бросает исключение.
  Future<void> ping() async {
    try {
      await _client.get(_rootUri).timeout(pingTimeout);
      _isAwake = true;
      _pingCount++;
    } catch (e) {
      debugPrint('BackendWarmer: прогрев не удался: $e');
    }
  }

  /// Ждёт, пока сервис проснётся, и возвращает true, если он ответил.
  ///
  /// Вызывается перед запросом генерации: если контейнер спал, к моменту
  /// отправки основного запроса он уже поднят, и игрок ждёт только один раз.
  Future<bool> ensureAwake({Duration timeout = wakeUpTimeout}) async {
    try {
      await _client.get(_rootUri).timeout(timeout);
      _isAwake = true;
      _pingCount++;
      return true;
    } catch (e) {
      debugPrint('BackendWarmer: не дождались пробуждения: $e');
      return false;
    }
  }

  Uri get _rootUri => Uri.parse(backendBaseUrl);

  void dispose() {
    stop();
    _client.close();
  }
}

/// Общий прогрев на всё приложение: запускается экраном игры, а диалог
/// создания цели ждёт пробуждения перед отправкой запроса.
final BackendWarmer backendWarmer = BackendWarmer();

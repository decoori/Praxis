import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:game_of_aim_app/services/backend_warmer.dart';

/// Прогрев backend, который засыпает на бесплатном тарифе Render.
///
/// Проверки идут на поддельном HTTP-клиенте: сеть в тестах не нужна.
void main() {
  test(
    'прогрев обращается к корню сервиса, а не к эндпоинту генерации',
    () async {
      final requested = <Uri>[];
      final warmer = BackendWarmer(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response('not found', 404);
        }),
      );

      await warmer.ping();

      expect(requested, hasLength(1));
      expect(requested.single.scheme, 'https');
      expect(requested.single.host, 'game-of-aim-backend.onrender.com');
      expect(
        requested.single.path,
        anyOf('', '/'),
        reason:
            'прогрев не должен дергать /api/goals/generate: этот запрос '
            'создаёт ветку квестов',
      );
    },
  );

  test('ответ 404 означает, что контейнер проснулся', () async {
    final warmer = BackendWarmer(
      client: MockClient((_) async => http.Response('nope', 404)),
    );

    await warmer.ping();

    expect(
      warmer.isAwake,
      isTrue,
      reason: 'любой ответ сервера значит, что контейнер поднят',
    );
    expect(warmer.pingCount, 1);
  });

  test('ошибка прогрева не выбрасывается наружу', () async {
    final warmer = BackendWarmer(
      client: MockClient((_) async => throw Exception('нет сети')),
    );

    await expectLater(warmer.ping(), completes);
    expect(warmer.isAwake, isFalse);
    expect(warmer.pingCount, 0);
  });

  test('ensureAwake сообщает, дождались ли пробуждения', () async {
    final awake = BackendWarmer(
      client: MockClient((_) async => http.Response('ok', 200)),
    );
    expect(
      await awake.ensureAwake(timeout: const Duration(milliseconds: 50)),
      isTrue,
    );

    final asleep = BackendWarmer(
      client: MockClient((_) async => throw Exception('сервис не отвечает')),
    );
    expect(
      await asleep.ensureAwake(timeout: const Duration(milliseconds: 50)),
      isFalse,
    );
  });

  testWidgets(
    'start прогревает сразу и повторяет по таймеру, stop останавливает',
    (tester) async {
      // Время двигаем вручную. На реальных задержках тест был нестабилен: под
      // нагрузкой (например, когда параллельно идёт сборка Gradle) таймеры не
      // успевали сработать, и проверка падала не по делу.
      var pings = 0;
      final warmer = BackendWarmer(
        interval: const Duration(milliseconds: 40),
        client: MockClient((_) async {
          pings++;
          return http.Response('ok', 200);
        }),
      );

      warmer.start();

      await tester.pump(const Duration(milliseconds: 5));
      expect(pings, 1, reason: 'первый прогрев уходит сразу при запуске');

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        pings,
        greaterThan(1),
        reason: 'прогрев должен повторяться по таймеру',
      );

      warmer.stop();
      final afterStop = pings;
      await tester.pump(const Duration(milliseconds: 100));
      expect(pings, afterStop, reason: 'после stop повторов быть не должно');

      warmer.dispose();
    },
  );

  test('период прогрева короче, чем простой до засыпания', () {
    // Render останавливает контейнер после ~15 минут без запросов.
    expect(BackendWarmer.defaultInterval.inMinutes, lessThan(15));
    expect(
      BackendWarmer.defaultInterval.inMinutes,
      greaterThanOrEqualTo(5),
      reason: 'слишком частый прогрев зря будит телефон и тратит батарею',
    );
  });
}

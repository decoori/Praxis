/// Конфигурация окружения.
///
/// Значения не лежат в репозитории, а передаются при сборке:
///
/// ```bash
/// flutter run --dart-define-from-file=env.json
/// ```
///
/// Шаблон — `env.example.json`. Локальный `env.json` перечислен в
/// `.gitignore`: в нём адрес и publishable (anon) ключ конкретного проекта
/// Supabase. Ключ публичный по назначению, но репозиторий не должен
/// рекламировать боевую базу: с ним любой желающий читает таблицу лидеров.
library;

/// Адрес проекта Supabase, например `https://abcdefgh.supabase.co`.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Publishable (anon) ключ Supabase.
///
/// Подходит и новый ключ вида `sb_publishable_…`, и прежний JWT-ключ из
/// раздела Project Settings → API. Секретный `service_role` ключ клиенту
/// передавать нельзя ни при каких условиях.
const String supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Эндпоинт генерации целей.
///
/// Здесь стоит публичный демо-backend, чтобы приложение работало без
/// собственного сервера. Свой адрес задаётся так:
///
/// ```bash
/// flutter run --dart-define=BACKEND_API_URL=https://example.com/api/goals/generate
/// ```
const String backendApiUrl = String.fromEnvironment(
  'BACKEND_API_URL',
  defaultValue: 'https://game-of-aim-backend.onrender.com/api/goals/generate',
);

/// Корень backend — используется для прогрева «спящего» сервиса.
///
/// Бесплатный тариф Render останавливает контейнер после ~15 минут без
/// запросов, поэтому приложение само отправляет туда лёгкие запросы:
/// см. lib/services/backend_warmer.dart.
final String backendBaseUrl = Uri.parse(backendApiUrl).origin;

/// Заданы ли параметры Supabase.
///
/// Без них приложение не падает на инициализации, а показывает экран
/// настройки: см. lib/screens/setup_required_screen.dart.
const bool isSupabaseConfigured = supabaseUrl != '' && supabaseKey != '';

-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 019: удаление legacy-таблицы лиг
-- ============================================================================
-- ЗАЧЕМ
--
-- Таблица public.league_participants осталась от прежней, недоделанной попытки
-- сделать лиги: она пустая, и ни одна строка клиентского кода её не использует
-- (проверено поиском по lib/). Настоящая система лиг живёт в league_tiers,
-- league_seasons и league_awards (миграция 018). Пустая таблица с похожим
-- именем рядом с ними только путает.
--
-- БЕЗОПАСНОСТЬ
--
-- Удаление выполнено БЕЗ CASCADE: если от таблицы зависит представление,
-- триггер или функция, PostgreSQL откажет с понятной ошибкой, и ничего не
-- потеряется. Политики доступа уходят вместе с таблицей автоматически.
--
-- ПЕРЕД ПРИМЕНЕНИЕМ (по желанию) — проверка зависимостей, ожидаем 0 строк:
--   select dependent.relname as dependent_object, dependent.relkind
--   from pg_depend d
--   join pg_rewrite r on r.oid = d.objid
--   join pg_class dependent on dependent.oid = r.ev_class
--   join pg_class source on source.oid = d.refobjid
--   where source.relname = 'league_participants'
--     and dependent.relname <> 'league_participants';
--
-- И проверка, что таблица пуста (ожидаем 0):
--   select count(*) from public.league_participants;
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

drop table if exists public.league_participants;

commit;

-- ============================================================================
-- Проверка после применения — таблиц с таким именем быть не должно:
--   select table_name from information_schema.tables
--   where table_schema = 'public' and table_name like 'league%'
--   order by table_name;
-- Ожидаемо после 018: league_awards, league_rewards, league_seasons, league_tiers
-- (и никакого league_participants).
-- ============================================================================

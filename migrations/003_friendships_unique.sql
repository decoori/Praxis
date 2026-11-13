-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 003: уникальность связей дружбы
-- ============================================================================
-- Зачем: в таблице friendships было только PRIMARY KEY (id), поэтому одну и
-- ту же связь можно было создать много раз — повторным тапом, параллельными
-- запросами или через прямой вызов API. Проверка «уже в друзьях» живёт в
-- клиенте и от гонки не защищает.
--
-- Перед применением убедитесь, что дубликатов нет:
--   select user_id, friend_id, count(*) from public.friendships
--   group by user_id, friend_id having count(*) > 1;   -- ожидаем 0 строк
--
-- Если дубликаты уже есть, миграция упадёт — сначала удалите лишние:
--   delete from public.friendships f using public.friendships g
--   where f.ctid < g.ctid and f.user_id = g.user_id and f.friend_id = g.friend_id;
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл → Run.
-- ============================================================================

begin;

-- Направление связи значимо: «я добавил его» и «он добавил меня» — разные
-- строки, поэтому уникальность именно по паре в этом порядке.
alter table public.friendships
  drop constraint if exists friendships_user_friend_key;
alter table public.friendships
  add constraint friendships_user_friend_key unique (user_id, friend_id);

-- Обратный поиск («кто добавил меня») по составному индексу не ускоряется,
-- поэтому добавляем индекс по friend_id.
create index if not exists friendships_friend_id_idx
  on public.friendships (friend_id);

commit;

-- ============================================================================
-- Проверка после применения:
--   -- повторная вставка той же связи должна вернуть 23505
--   insert into public.friendships (user_id, friend_id)
--   values (auth.uid()::text, '<id-другого-игрока>');
-- ============================================================================

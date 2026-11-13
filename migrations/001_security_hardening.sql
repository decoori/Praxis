-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 001: безопасность на стороне БД
-- ============================================================================
-- Сверено с реальной схемой проекта (information_schema, шаг 0).
--
-- ВАЖНО про типы: в этой базе `friendships.user_id`, `preset_votes.user_id` и
-- `goal_presets.author_id` объявлены как text, а не uuid. `auth.uid()`
-- возвращает uuid, и неявного приведения между uuid и text в PostgreSQL нет —
-- поэтому в политиках этих таблиц стоит явный каст `auth.uid()::text`.
-- Без него политики падают с «operator does not exist: uuid = text».
--
-- Таблицы profiles/goals/quests используют uuid и сравниваются напрямую.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- Перед применением выполните диагностику из инструкции (шаг 1): при грязных
-- данных миграция упадёт и откатится целиком — это намеренно.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. ID игрока: один и тот же тег не может принадлежать двум аккаунтам
-- ---------------------------------------------------------------------------
-- Клиент делает SELECT-проверку перед регистрацией, но между проверкой и
-- вставкой тег может занять другой игрок. Надёжная защита — уникальный индекс.

-- Пустые теги не должны блокировать друг друга.
update public.profiles set user_tag = null where user_tag = '';

alter table public.profiles
  drop constraint if exists profiles_user_tag_key;

alter table public.profiles
  add constraint profiles_user_tag_key unique (user_tag);

-- Формат ID дублируем в БД: клиентская валидация обходится запросом.
alter table public.profiles
  drop constraint if exists profiles_user_tag_format;
alter table public.profiles
  add constraint profiles_user_tag_format
  check (user_tag is null or user_tag ~ '^[a-z0-9_]{3,16}$');

-- ---------------------------------------------------------------------------
-- 2. Границы характеристик: никаких отрицательных ресурсов и запредельных
--    значений при прямой записи в таблицу
-- ---------------------------------------------------------------------------
alter table public.profiles
  drop constraint if exists profiles_non_negative;
alter table public.profiles
  add constraint profiles_non_negative
  check (
    coalesce(gold, 0) >= 0
    and coalesce(xp, 0) >= 0
    and coalesce(energy, 0) >= 0
    and coalesce(shields_left, 0) >= 0
    and coalesce(streak_count, 0) >= 0
    and coalesce(camp_level, 1) between 1 and 5
    and coalesce(max_active_goals, 2) between 1 and 5
  );

-- ---------------------------------------------------------------------------
-- 3. RLS: игрок видит чужие профили (нужно для рейтинга), но менять может
--    только свой
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_all on public.profiles
  for select using (true);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert with check (auth.uid() = id);

-- ВНИМАНИЕ: эта политика разрешает игроку менять свои gold/xp/energy.
-- Клиентские правки экономики остаются возможными до перехода на серверные
-- RPC. Политика закрывает только чужой профиль, а границы значений держит
-- CHECK из раздела 2.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists profiles_delete_self on public.profiles;
create policy profiles_delete_self on public.profiles
  for delete using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 4. RLS: цели и квесты принадлежат только своему владельцу
-- ---------------------------------------------------------------------------
alter table public.goals enable row level security;

drop policy if exists goals_owner_all on public.goals;
create policy goals_owner_all on public.goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter table public.quests enable row level security;

drop policy if exists quests_owner_all on public.quests;
create policy quests_owner_all on public.quests
  for all using (
    exists (
      select 1 from public.goals g
      where g.id = quests.goal_id and g.user_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.goals g
      where g.id = quests.goal_id and g.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 5. RLS: дружба, голоса за пресеты и сами пресеты
--    user_id / author_id здесь text → сравнение только через ::text
-- ---------------------------------------------------------------------------
alter table public.friendships enable row level security;

-- Видеть граф связей нужно обоим участникам (для подписчиков и друзей),
-- создавать и удалять — только те связи, где ты инициатор.
drop policy if exists friendships_select_involved on public.friendships;
create policy friendships_select_involved on public.friendships
  for select using (user_id = auth.uid()::text or friend_id = auth.uid()::text);

drop policy if exists friendships_insert_self on public.friendships;
create policy friendships_insert_self on public.friendships
  for insert with check (user_id = auth.uid()::text);

drop policy if exists friendships_delete_self on public.friendships;
create policy friendships_delete_self on public.friendships
  for delete using (user_id = auth.uid()::text);

alter table public.preset_votes enable row level security;

-- Голоса видны всем: по ним считается рейтинг пресета в библиотеке.
drop policy if exists preset_votes_select_all on public.preset_votes;
create policy preset_votes_select_all on public.preset_votes
  for select using (true);

drop policy if exists preset_votes_write_self on public.preset_votes;
create policy preset_votes_write_self on public.preset_votes
  for all using (user_id = auth.uid()::text) with check (user_id = auth.uid()::text);

alter table public.goal_presets enable row level security;

-- Библиотека пресетов публичная: пользовательские — для всех, системные
-- (id вида sys_*) создаются только сервером.
drop policy if exists goal_presets_select_all on public.goal_presets;
create policy goal_presets_select_all on public.goal_presets
  for select using (true);

drop policy if exists goal_presets_insert_self on public.goal_presets;
create policy goal_presets_insert_self on public.goal_presets
  for insert with check (author_id = auth.uid()::text or id like 'sys\_%');

-- Системные пресеты игрок менять не может: их рейтинг обновляет сервер.
drop policy if exists goal_presets_update_all on public.goal_presets;
create policy goal_presets_update_all on public.goal_presets
  for update using (id not like 'sys\_%') with check (id not like 'sys\_%');

drop policy if exists goal_presets_delete_author on public.goal_presets;
create policy goal_presets_delete_author on public.goal_presets
  for delete using (author_id = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- 6. Цепочка квестов: нельзя закрыть шаг, пропустив предыдущий
-- ---------------------------------------------------------------------------
-- Клиент блокирует недоступные квесты в интерфейсе, но прямой запрос к API
-- это обходит. Триггер закрывает дыру на уровне БД.
create or replace function public.enforce_quest_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_done boolean;
begin
  if new.is_completed = true and coalesce(old.is_completed, false) = false then
    if new.parent_quest_id is not null then
      select q.is_completed into parent_done
      from public.quests q
      where q.id = new.parent_quest_id;

      if parent_done is not true then
        raise exception 'QUEST_LOCKED: предыдущий шаг цепочки не выполнен'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists quests_enforce_order on public.quests;
create trigger quests_enforce_order
  before update on public.quests
  for each row execute function public.enforce_quest_order();

commit;

-- ============================================================================
-- Проверка после применения:
--   select id, user_tag from public.profiles where user_tag is not null
--     group by 2 having count(*) > 1;                       -- ожидаем 0 строк
--   select tablename, policyname, cmd from pg_policies
--     where schemaname = 'public' order by tablename;        -- ожидаем список
-- ============================================================================

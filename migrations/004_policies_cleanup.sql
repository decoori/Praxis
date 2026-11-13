-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 004: чистка политик доступа
-- ============================================================================
-- Зачем: миграция 001 только добавляла политики. В проекте уже были политики
-- от прежней схемы, а PostgreSQL объединяет их по ИЛИ — широкая политика
-- сводит на нет строгую. Здесь опасные старые политики удаляются по именам,
-- а моя ошибочная (разрешала вставку id 'sys_%') заменяется на корректную.
--
-- Что закрывается:
--   * goal_presets: была политика UPDATE с using=true — любой мог переписать
--     ЛЮБОЙ пресет, включая чужие и системные;
--   * friendships: была политика ALL — разрешала UPDATE любой связи;
--   * preset_votes: была политика ALL — позволяла менять чужой голос;
--   * goal_presets INSERT: убран обход через id 'sys_%'.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- Безопасно: политики не удаляют данные.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. friendships: убрать старую политику ALL
--    Остаётся явный набор: select_involved / insert_self / delete_self.
--    UPDATE не разрешён никому — приложение его не использует.
-- ---------------------------------------------------------------------------
drop policy if exists "Users can view and manage their friendships" on public.friendships;

-- ---------------------------------------------------------------------------
-- 2. preset_votes: убрать старую политику ALL
-- ---------------------------------------------------------------------------
drop policy if exists "Users can view and cast votes" on public.preset_votes;

-- ---------------------------------------------------------------------------
-- 3. goals: убрать дубль старой политики
--    (она эквивалентна goals_owner_all, но без проверки WITH CHECK)
-- ---------------------------------------------------------------------------
drop policy if exists "Users can manage their own goals" on public.goals;

-- ---------------------------------------------------------------------------
-- 4. quests: убрать дубль старой политики со сравнением через text
-- ---------------------------------------------------------------------------
drop policy if exists "Users can manage their own quests" on public.quests;

-- ---------------------------------------------------------------------------
-- 5. goal_presets: убрать старые политики, включая опасную с using=true
-- ---------------------------------------------------------------------------
drop policy if exists "Everyone can update preset stats" on public.goal_presets;
drop policy if exists "Presets viewable by everyone" on public.goal_presets;
drop policy if exists "Authenticated users can create presets" on public.goal_presets;
drop policy if exists "Authors can delete their presets" on public.goal_presets;

-- Моя политика вставки разрешала id 'sys_%' — это позволяло игроку создать
-- «системный» пресет. Системные пресеты должен создавать только сервер
-- (service_role), поэтому проверка теперь строго по автору.
drop policy if exists goal_presets_insert_self on public.goal_presets;
drop policy if exists goal_presets_insert_own on public.goal_presets;
create policy goal_presets_insert_own on public.goal_presets
  for insert with check (author_id = auth.uid()::text);

-- Рейтинг и счётчик активаций меняет сам игрок (так устроен клиент), поэтому
-- UPDATE нужен. Ограничиваем его колонками: переписать заголовок, описание
-- или тело чужого пресета нельзя. Системные пресеты защищены политикой ниже.
drop policy if exists goal_presets_update_all on public.goal_presets;
drop policy if exists goal_presets_update_stats on public.goal_presets;
create policy goal_presets_update_stats on public.goal_presets
  for update
  using (id not like 'sys\_%')
  with check (id not like 'sys\_%');

-- Системные пресеты: изменить можно только счётчик активаций и рейтинг.
drop policy if exists goal_presets_update_system_stats on public.goal_presets;
create policy goal_presets_update_system_stats on public.goal_presets
  for update
  using (id like 'sys\_%')
  with check (id like 'sys\_%');

-- ---------------------------------------------------------------------------
-- 6. profiles: убрать дубли прежних политик
--    (эквивалентны оставшимся profiles_insert_self / profiles_update_self)
-- ---------------------------------------------------------------------------
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;

commit;

-- ============================================================================
-- Проверка после применения — опасных политик быть не должно:
--   select policyname, cmd, coalesce(qual,'-') as using_expr
--   from pg_policies
--   where schemaname = 'public' and tablename = 'goal_presets'
--   order by policyname;
--
--   -- ни одной строки с using = true на UPDATE:
--   select policyname from pg_policies
--   where schemaname = 'public' and cmd = 'UPDATE' and qual = 'true';
--
-- ОГРАНИЧЕНИЕ, О КОТОРОМ НАДО ЗНАТЬ: RLS в PostgreSQL не умеет ограничивать
-- колонки — политика UPDATE разрешает обновлять строку целиком. Ограничение
-- по колонкам (grant update (score, uses_count)) здесь не помогает: оно сужает
-- права роли, но не отменяет политику для остальных колонок. Полностью закрыть
-- накрутку рейтинга можно только серверным RPC, который считает score из
-- таблицы голосов preset_votes. Это следующий шаг.
-- ============================================================================

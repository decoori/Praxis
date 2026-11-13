-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 015: слоты целей и статистика пресетов
-- ============================================================================
-- Закрывает последние две записи экономики с клиента.
--
-- ЧТО БЫЛО
--
--   1. Покупка слота цели (game_screen.dart):
--        update profiles set gold = <с клиента>, max_active_goals = <с клиента>
--      Цена приходила с клиента, значит проверять её на сервере было нечем.
--
--   2. Рейтинг пресета (preset_library_screen.dart):
--        update goal_presets set score = <посчитано на клиенте>
--      Рейтинг накручивался одним запросом, а при одновременных голосах
--      инкремент терялся (read-modify-write).
--
--   3. Счётчик активаций (preset_library_screen.dart):
--        select uses_count ...; update goal_presets set uses_count = <прочитано + 1>
--      Та же гонка: две одновременные активации теряли одну.
--
-- ЧТО СТАЛО
--
--   * buy_goal_slot() — цену берёт из таблицы goal_slot_prices, проверяет
--     лимит слотов и достаток золота;
--   * recompute_preset_score(id) — рейтинг ПЕРЕСЧИТЫВАЕТСЯ из preset_votes,
--     а не принимается от клиента;
--   * register_preset_use(id) — атомарный инкремент счётчика активаций.
--
-- ДОПОЛНИТЕЛЬНО: политики UPDATE на goal_presets для клиента удаляются.
-- Теперь статистику пресета меняют только серверные функции (они
-- security definer), поэтому «накрутить рейтинг прямым запросом» больше нельзя.
-- Это закрывает пункт, который до сих пор числился в известных ограничениях.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Справочник цен на слоты целей
-- ---------------------------------------------------------------------------
-- Максимальное число слотов выводится как max(level) + 1, чтобы не держать
-- отдельную константу: 4 уровня с ценой → 5 слотов максимум.
create table if not exists public.goal_slot_prices (
  level integer primary key,
  price integer not null,

  constraint goal_slot_prices_level check (level between 2 and 4),
  constraint goal_slot_prices_price check (price > 0)
);

insert into public.goal_slot_prices (level, price)
values (2, 250), (3, 500), (4, 1000)
on conflict (level) do update set price = excluded.price;

-- Справочник баланса: клиент читает цены из своего конфига.
alter table public.goal_slot_prices enable row level security;
drop policy if exists goal_slot_prices_no_client_access on public.goal_slot_prices;
create policy goal_slot_prices_no_client_access on public.goal_slot_prices
  for select using (false);

-- ---------------------------------------------------------------------------
-- 2. Покупка слота цели
-- ---------------------------------------------------------------------------
create or replace function public.buy_goal_slot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_profile profiles%rowtype;
  v_slots   integer;
  v_max     integer;
  v_price   integer;
begin
  if auth.uid() is null then
    raise exception 'GOAL_SLOT_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  select coalesce(max(level), 1) + 1 into v_max from public.goal_slot_prices;

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then
    raise exception 'GOAL_SLOT_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  v_slots := coalesce(v_profile.max_active_goals, 2);

  if v_slots >= v_max then
    raise exception 'GOAL_SLOT_MAX' using errcode = 'invalid_parameter_value';
  end if;

  select price into v_price from public.goal_slot_prices where level = v_slots;
  if v_price is null then
    -- Для текущего числа слотов цены нет — расширять нечего.
    raise exception 'GOAL_SLOT_MAX' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.gold, 0) < v_price then
    raise exception 'GOAL_SLOT_NOT_ENOUGH_GOLD' using errcode = 'invalid_parameter_value';
  end if;

  update public.profiles p
     set gold             = coalesce(p.gold, 0) - v_price,
         max_active_goals = v_slots + 1
   where p.id = v_user_id
   returning p.gold, p.xp, p.energy, p.max_energy,
             coalesce(p.shields_left, 0), p.max_active_goals
   into v_profile.gold, v_profile.xp, v_profile.energy, v_profile.max_energy,
        v_profile.shields_left, v_profile.max_active_goals;

  return jsonb_build_object(
    'ok', true,
    'paid', v_price,
    'max_active_goals', v_profile.max_active_goals,
    'gold', v_profile.gold,
    'xp', v_profile.xp,
    'energy', v_profile.energy,
    'max_energy', v_profile.max_energy,
    'shields_left', v_profile.shields_left
  );
end;
$$;

revoke all on function public.buy_goal_slot() from public, anon;
grant execute on function public.buy_goal_slot() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Пересчёт рейтинга пресета из голосов
-- ---------------------------------------------------------------------------
-- Рейтинг не принимается от клиента: он считается по таблице preset_votes.
-- Поэтому одновременные голоса больше не теряются и накрутка невозможна.
create or replace function public.recompute_preset_score(p_preset_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_score integer;
begin
  if auth.uid() is null then
    raise exception 'PRESET_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;

  if btrim(coalesce(p_preset_id, '')) = '' then
    raise exception 'PRESET_NOT_FOUND' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(sum(v.vote), 0)::integer
    into v_score
  from public.preset_votes v
  where v.preset_id::text = p_preset_id::text;

  update public.goal_presets p
     set score = v_score
   where p.id::text = p_preset_id::text
   returning p.score into v_score;

  if not found then
    raise exception 'PRESET_NOT_FOUND' using errcode = 'invalid_parameter_value';
  end if;

  return jsonb_build_object('ok', true, 'preset_id', p_preset_id, 'score', v_score);
end;
$$;

revoke all on function public.recompute_preset_score(text) from public, anon;
grant execute on function public.recompute_preset_score(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Атомарный счётчик активаций пресета
-- ---------------------------------------------------------------------------
create or replace function public.register_preset_use(p_preset_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uses integer;
begin
  if auth.uid() is null then
    raise exception 'PRESET_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;

  if btrim(coalesce(p_preset_id, '')) = '' then
    raise exception 'PRESET_NOT_FOUND' using errcode = 'invalid_parameter_value';
  end if;

  -- Инкремент выполняет сама БД: read-modify-write с клиента терял
  -- одновременные активации.
  update public.goal_presets p
     set uses_count = coalesce(p.uses_count, 0) + 1
   where p.id::text = p_preset_id::text
   returning p.uses_count into v_uses;

  if not found then
    raise exception 'PRESET_NOT_FOUND' using errcode = 'invalid_parameter_value';
  end if;

  return jsonb_build_object('ok', true, 'preset_id', p_preset_id, 'uses_count', v_uses);
end;
$$;

revoke all on function public.register_preset_use(text) from public, anon;
grant execute on function public.register_preset_use(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Клиент больше не может менять статистику пресетов напрямую
-- ---------------------------------------------------------------------------
-- Рейтинг и счётчик активаций теперь меняют только функции выше. Политики
-- UPDATE для клиента удаляем — иначе накрутка рейтинга оставалась возможной.
drop policy if exists goal_presets_update_stats on public.goal_presets;
drop policy if exists goal_presets_update_system_stats on public.goal_presets;

commit;

-- ============================================================================
-- Проверка:
--   select * from public.goal_slot_prices order by level;   -- 3 строки
--
--   -- ни одной политики UPDATE у goal_presets:
--   select policyname, cmd from pg_policies
--   where schemaname = 'public' and tablename = 'goal_presets' order by cmd;
--
--   -- покупка слота (подставив свой uuid):
--   begin;
--     select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--     select public.buy_goal_slot();
--   rollback;
--
--   -- рейтинг пересчитывается из голосов:
--   begin;
--     select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--     select public.recompute_preset_score('sys_run_start');
--     select public.register_preset_use('sys_run_start');
--   rollback;
-- ============================================================================

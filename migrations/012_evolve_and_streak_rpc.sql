-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 012: эволюция эпохи и спасение стрика
-- ============================================================================
-- Закрывает последние два места, где клиент писал экономику прямыми update
-- с абсолютными значениями: _triggerEvolution и _restoreStreakDialog.
--
-- Теперь:
--   * evolve_era() проверяет на сервере, что XP и лагерь соответствуют эпохе,
--     и сам вычитает XP, даёт бонус золота, сбрасывает лагерь на 1;
--   * restore_streak() проверяет, что стрик действительно в упадке, и сам
--     списывает 150 золота.
--
-- Пороги эпох хранятся в era_config — единственный источник правды на сервере.
-- Значения сверены с lib/constants/game_config.dart (ловит тест
-- test/server_config_sync_test.dart).
--
-- ВАЖНО: обе функции берут id игрока из auth.uid() внутри — параметра нет,
-- чтобы нельзя было вызвать операцию на чужом аккаунте.
--
-- ВАЖНО ПРО ТИПЫ: profiles.current_era — это enum era_type, и присваивание
-- текстовой переменной требует явного каста `::era_type`. PostgreSQL не
-- приводит text к enum неявно, а ошибка проявляется только при выполнении.
-- Тот же класс ошибки уже один раз ломал сдачу квестов (last_active_date).
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Справочник эпох
-- ---------------------------------------------------------------------------
create table if not exists public.era_config (
  era_id             text primary key,
  display_order      integer not null unique,
  xp_required        integer not null,   -- порог XP для эволюции ИЗ этой эпохи
  gold_bonus         integer not null,   -- золото при переходе в СЛЕДУЮЩУЮ эпоху
  increases_max_energy boolean not null default false,
  name               text not null,

  constraint era_config_non_negative check (xp_required >= 0 and gold_bonus >= 0)
);

insert into public.era_config
  (era_id, display_order, xp_required, gold_bonus, increases_max_energy, name)
values
  ('stone_age',   1,  100,    0, false, 'Каменный век'),
  ('bronze_age',  2,  200,  100, false, 'Бронзовый век'),
  ('iron_age',    3,  500,  250, true,  'Железный век'),
  ('middle_ages', 4, 1000,  500, false, 'Средневековье'),
  ('modern_age',  5, 2000, 1000, true,  'Индустриальная эра'),
  ('space_age',   6, 4000, 2000, true,  'Космическая эра')
on conflict (era_id) do update set
  display_order        = excluded.display_order,
  xp_required          = excluded.xp_required,
  gold_bonus           = excluded.gold_bonus,
  increases_max_energy = excluded.increases_max_energy,
  name                 = excluded.name;

-- Справочник баланса: клиент его не читает, доступ не нужен.
alter table public.era_config enable row level security;
drop policy if exists era_config_no_client_access on public.era_config;
create policy era_config_no_client_access on public.era_config
  for select using (false);

-- ---------------------------------------------------------------------------
-- 2. Эволюция эпохи
-- ---------------------------------------------------------------------------
create or replace function public.evolve_era(p_next_era text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id   uuid;
  v_profile   profiles%rowtype;
  v_cur       public.era_config%rowtype;
  v_next      public.era_config%rowtype;
  v_expected  text;
  v_new_xp    integer;
  v_new_gold  integer;
  v_new_max   integer;
begin
  if auth.uid() is null then
    raise exception 'EVOLVE_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then
    raise exception 'EVOLVE_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_cur
  from public.era_config
  where era_id = v_profile.current_era::text;

  if not found then
    raise exception 'EVOLVE_UNKNOWN_ERA' using errcode = 'invalid_parameter_value';
  end if;

  -- Следующая эпоха определяется порядком, а не значением, присланным клиентом.
  select era_id into v_expected
  from public.era_config
  where display_order = v_cur.display_order + 1;

  if v_expected is null then
    raise exception 'EVOLVE_MAX_ERA' using errcode = 'invalid_parameter_value';
  end if;

  -- Параметр используется только как защита от рассинхрона клиента.
  if btrim(coalesce(p_next_era, '')) <> v_expected then
    raise exception 'EVOLVE_WRONG_ERA' using errcode = 'invalid_parameter_value';
  end if;

  -- Условия эволюции: XP текущей эпохи и полностью отстроенный лагерь.
  if coalesce(v_profile.xp, 0) < v_cur.xp_required then
    raise exception 'EVOLVE_NOT_ENOUGH_XP' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.camp_level, 1) < 5 then
    raise exception 'EVOLVE_CAMP_NOT_READY' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_next
  from public.era_config
  where era_id = v_expected;

  -- Остаток XP переносим в новую эпоху, но не уводим в минус.
  v_new_xp := greatest(coalesce(v_profile.xp, 0) - v_cur.xp_required, 0);
  v_new_gold := coalesce(v_profile.gold, 0) + v_next.gold_bonus;

  if v_next.increases_max_energy then
    v_new_max := coalesce(v_profile.max_energy, 5) + 1;
  else
    v_new_max := coalesce(v_profile.max_energy, 5);
  end if;

  update public.profiles p
     set current_era = v_expected::era_type,  -- text → enum требует явного каста
         xp          = v_new_xp,
         gold        = v_new_gold,
         max_energy  = v_new_max,
         energy      = v_new_max,   -- энергия полностью восстанавливается
         camp_level  = 1            -- лагерь сбрасывается
   where p.id = v_user_id
   returning p.xp, p.gold, p.energy, p.max_energy, p.camp_level, p.current_era
   into v_new_xp, v_new_gold, v_profile.energy, v_new_max, v_profile.camp_level, v_profile.current_era;

  return jsonb_build_object(
    'ok', true,
    'era', v_expected,
    'era_name', v_next.name,
    'gold_bonus', v_next.gold_bonus,
    'xp', v_new_xp,
    'gold', v_new_gold,
    'energy', v_profile.energy,
    'max_energy', v_new_max,
    'camp_level', 1
  );
end;
$$;

revoke all on function public.evolve_era(text) from public, anon;
grant execute on function public.evolve_era(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Спасение стрика
-- ---------------------------------------------------------------------------
create or replace function public.restore_streak()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_price   constant integer := 150;
  v_user_id uuid;
  v_profile profiles%rowtype;
  v_new_gold integer;
begin
  if auth.uid() is null then
    raise exception 'STREAK_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then
    raise exception 'STREAK_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  -- Спасать можно только стрик, который реально в упадке.
  if v_profile.is_decayed is not true then
    raise exception 'STREAK_NOT_DECAYED' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.gold, 0) < c_price then
    raise exception 'STREAK_NOT_ENOUGH_GOLD' using errcode = 'invalid_parameter_value';
  end if;

  v_new_gold := coalesce(v_profile.gold, 0) - c_price;

  update public.profiles p
     set gold       = v_new_gold,
         is_decayed = false
   where p.id = v_user_id
   returning p.gold, p.xp, p.energy, p.max_energy,
             coalesce(p.shields_left, 0), p.streak_count, p.streak_multiplier
   into v_new_gold, v_profile.xp, v_profile.energy, v_profile.max_energy,
        v_profile.shields_left, v_profile.streak_count, v_profile.streak_multiplier;

  return jsonb_build_object(
    'ok', true,
    'paid', c_price,
    'gold', v_new_gold,
    'xp', v_profile.xp,
    'energy', v_profile.energy,
    'max_energy', v_profile.max_energy,
    'shields_left', v_profile.shields_left,
    'streak_count', v_profile.streak_count,
    'streak_multiplier', v_profile.streak_multiplier,
    'is_decayed', false
  );
end;
$$;

revoke all on function public.restore_streak() from public, anon;
grant execute on function public.restore_streak() to authenticated;

commit;

-- ============================================================================
-- Проверка:
--   select * from public.era_config order by display_order;  -- 6 строк
--
--   Эволюция (подставив свои id и следующую эпоху):
--   begin;
--     select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--     select public.evolve_era('bronze_age');   -- из stone_age
--   rollback;
--
--   Спасение стрика (только когда is_decayed = true):
--   select public.restore_streak();
-- ============================================================================

-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 008: исправление сравнения uuid и text
-- ============================================================================
-- ЧТО ИСПРАВЛЯЕТСЯ
--
-- В миграции 006 в complete_quest_atomic добавлена проверка владельца квеста:
--     WHERE q.id = p_quest_id AND g.user_id = p_user_id
-- Но goals.user_id — это uuid, а параметр p_user_id объявлен как text.
-- PostgreSQL не приводит их неявно, и запрос падал с ошибкой 42883:
--     operator does not exist: uuid = text
-- Из-за этого сдача ЛЮБОГО квеста перестала работать.
--
-- Ту же ошибку я заложил в buy_consumable и upgrade_camp из миграции 007,
-- но там сравнение шло через `id::text = v_uid`, поэтому оно работало, хотя
-- и мешало использовать индекс первичного ключа.
--
-- РЕШЕНИЕ
--
-- Во всех функциях id игрока приводится к uuid ОДИН раз в начале, а в запросах
-- к таблицам сравнивается uuid с uuid. Для параметра p_user_id используется
-- явный каст `p_user_id::uuid`: он корректен и когда параметр объявлен как
-- text (исходный вариант функции), и когда как uuid.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Сдача квеста
-- ---------------------------------------------------------------------------
create or replace function public.complete_quest_atomic(p_user_id uuid, p_quest_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
DECLARE
    v_profile profiles%ROWTYPE;
    v_quest quests%ROWTYPE;
    v_camp_xp_bonus NUMERIC := 0.0;
    v_camp_gold_bonus NUMERIC := 0.0;
    v_earned_xp INT;
    v_earned_gold INT;
    v_new_energy INT;
    v_new_streak INT;
    v_new_multiplier NUMERIC;
    v_today TEXT := TO_CHAR(NOW(), 'YYYY-MM-DD');
BEGIN
    SELECT * INTO v_profile FROM profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF v_profile.energy <= 0 THEN
        RAISE EXCEPTION 'Not enough energy';
    END IF;

    -- Квест обязан принадлежать цели этого игрока.
    -- ВАЖНО: g.user_id — uuid. Параметр может прийти как text (так объявлена
    -- исходная функция), поэтому приводим его явно. Каст безопасен и тогда,
    -- когда параметр уже uuid: uuid::uuid — тождественное преобразование.
    SELECT q.* INTO v_quest
    FROM quests q
    JOIN goals g ON g.id = q.goal_id
    WHERE q.id = p_quest_id AND g.user_id = p_user_id::uuid
    FOR UPDATE OF q;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quest not found';
    END IF;

    IF v_quest.is_completed THEN
        RAISE EXCEPTION 'Quest already completed';
    END IF;

    -- Бонусы лагеря: единственный источник — camp_building_effects.
    SELECT b.gold_bonus, b.xp_bonus
      INTO v_camp_gold_bonus, v_camp_xp_bonus
      FROM public.camp_bonuses(v_profile.current_era::text, v_profile.camp_level) b;

    v_earned_xp   := ROUND(v_quest.xp_reward * v_profile.streak_multiplier * (1.0 + v_camp_xp_bonus));
    v_earned_gold := ROUND(v_quest.gold_reward * v_profile.streak_multiplier * (1.0 + v_camp_gold_bonus));
    v_new_energy  := v_profile.energy - 1;

    IF v_profile.last_active_date <> v_today::date THEN
        v_new_streak     := v_profile.streak_count + 1;
        v_new_multiplier := v_profile.streak_multiplier + 0.005;
    ELSE
        v_new_streak     := v_profile.streak_count;
        v_new_multiplier := v_profile.streak_multiplier;
    END IF;

    UPDATE quests
    SET is_completed = TRUE, completed_at = NOW()
    WHERE id = p_quest_id;

    UPDATE profiles
    SET xp                = v_profile.xp + v_earned_xp,
        gold              = v_profile.gold + v_earned_gold,
        energy            = v_new_energy,
        streak_count      = v_new_streak,
        streak_multiplier = v_new_multiplier,
        last_active_date  = v_today,
        is_decayed        = FALSE
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'earned_xp', v_earned_xp,
        'earned_gold', v_earned_gold,
        'energy_left', v_new_energy,
        'camp_gold_bonus', v_camp_gold_bonus,
        'camp_xp_bonus', v_camp_xp_bonus,
        'gold', v_profile.gold + v_earned_gold,
        'xp', v_profile.xp + v_earned_xp,
        'energy', v_new_energy,
        'max_energy', v_profile.max_energy,
        'shields_left', coalesce(v_profile.shields_left, 0),
        'streak_count', v_new_streak,
        'streak_multiplier', v_new_multiplier
    );
END;
$function$;

revoke all on function public.complete_quest_atomic(uuid, text) from public, anon;
grant execute on function public.complete_quest_atomic(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Магазин: id игрока приводится к uuid один раз
-- ---------------------------------------------------------------------------
create or replace function public.buy_consumable(p_kind text, p_count integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_energy_price   constant integer := 50;
  c_energy_amount  constant integer := 3;
  c_shield_price   constant integer := 100;
  c_max_shields    constant integer := 5;

  v_user_id     uuid;
  v_profile     profiles%rowtype;
  v_kind        text;
  v_count       integer;
  v_useful      integer;
  v_unit_price  integer;
  v_total_price integer;
  v_energy_add  integer := 0;
  v_shields_add integer := 0;
begin
  if auth.uid() is null then
    raise exception 'SHOP_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  v_kind := lower(btrim(coalesce(p_kind, '')));
  if v_kind not in ('energy', 'shields') then
    raise exception 'SHOP_UNKNOWN_ITEM' using errcode = 'invalid_parameter_value';
  end if;

  v_count := coalesce(p_count, 0);
  if v_count < 1 or v_count > 99 then
    raise exception 'SHOP_BAD_COUNT' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then
    raise exception 'SHOP_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  if v_kind = 'energy' then
    v_unit_price := c_energy_price;
    v_useful := greatest(1,
      ((greatest(coalesce(v_profile.max_energy, 5) - coalesce(v_profile.energy, 0), 0)
        + c_energy_amount - 1) / c_energy_amount));
  else
    v_unit_price := c_shield_price;
    v_useful := greatest(coalesce(c_max_shields - coalesce(v_profile.shields_left, 0), 0), 0);
    if v_useful < 1 then
      raise exception 'SHOP_ALREADY_MAX' using errcode = 'invalid_parameter_value';
    end if;
  end if;

  if v_count > v_useful then
    raise exception 'SHOP_COUNT_TOO_HIGH' using errcode = 'invalid_parameter_value';
  end if;

  v_total_price := v_count * v_unit_price;

  if coalesce(v_profile.gold, 0) < v_total_price then
    raise exception 'SHOP_NOT_ENOUGH_GOLD' using errcode = 'invalid_parameter_value';
  end if;

  if v_kind = 'energy' then
    v_energy_add := least(v_count * c_energy_amount,
                          greatest(coalesce(v_profile.max_energy, 5) - coalesce(v_profile.energy, 0), 0));
  else
    v_shields_add := least(v_count, greatest(c_max_shields - coalesce(v_profile.shields_left, 0), 0));
  end if;

  update public.profiles p
     set gold         = coalesce(p.gold, 0) - v_total_price,
         energy       = least(coalesce(p.max_energy, 5), coalesce(p.energy, 0) + v_energy_add),
         shields_left = least(c_max_shields, coalesce(p.shields_left, 0) + v_shields_add)
   where p.id = v_user_id
   returning p.gold, p.xp, p.energy, p.max_energy, coalesce(p.shields_left, 0)
   into v_profile.gold, v_profile.xp, v_profile.energy, v_profile.max_energy, v_profile.shields_left;

  return jsonb_build_object(
    'ok', true,
    'kind', v_kind,
    'count', v_count,
    'paid', v_total_price,
    'energy_added', v_energy_add,
    'shields_added', v_shields_add,
    'gold', v_profile.gold,
    'xp', v_profile.xp,
    'energy', v_profile.energy,
    'max_energy', v_profile.max_energy,
    'shields_left', v_profile.shields_left
  );
end;
$$;

revoke all on function public.buy_consumable(text, integer) from public, anon;
grant execute on function public.buy_consumable(text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Постройка в лагере: то же исправление
-- ---------------------------------------------------------------------------
create or replace function public.upgrade_camp()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_max_camp_level constant integer := 5;
  c_max_shields    constant integer := 5;

  v_user_id      uuid;
  v_profile      profiles%rowtype;
  v_building     camp_building_effects%rowtype;
  v_new_level    integer;
  v_new_max      integer;
begin
  if auth.uid() is null then
    raise exception 'CAMP_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then
    raise exception 'CAMP_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.camp_level, 1) >= c_max_camp_level then
    raise exception 'CAMP_MAX_LEVEL' using errcode = 'invalid_parameter_value';
  end if;

  v_new_level := coalesce(v_profile.camp_level, 1) + 1;

  select * into v_building
  from public.camp_building_effects e
  where e.era_id = v_profile.current_era::text
    and e.unlock_level = v_new_level;

  if not found then
    raise exception 'CAMP_NO_BUILDING' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.gold, 0) < v_building.price then
    raise exception 'CAMP_NOT_ENOUGH_GOLD' using errcode = 'invalid_parameter_value';
  end if;

  v_new_max := coalesce(v_profile.max_energy, 5) + v_building.max_energy;

  update public.profiles p
     set gold         = coalesce(p.gold, 0) - v_building.price,
         camp_level   = v_new_level,
         shields_left = least(c_max_shields,
                              coalesce(p.shields_left, 0) + v_building.shields),
         max_energy   = v_new_max,
         energy       = least(v_new_max,
                              coalesce(p.energy, 0) + v_building.instant_energy + v_building.max_energy)
   where p.id = v_user_id
   returning p.gold, p.xp, p.energy, p.max_energy, coalesce(p.shields_left, 0), p.camp_level
   into v_profile.gold, v_profile.xp, v_profile.energy, v_profile.max_energy,
        v_profile.shields_left, v_profile.camp_level;

  return jsonb_build_object(
    'ok', true,
    'building', v_building.name,
    'camp_level', v_profile.camp_level,
    'paid', v_building.price,
    'gold', v_profile.gold,
    'xp', v_profile.xp,
    'energy', v_profile.energy,
    'max_energy', v_profile.max_energy,
    'shields_left', v_profile.shields_left
  );
end;
$$;

revoke all on function public.upgrade_camp() from public, anon;
grant execute on function public.upgrade_camp() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Промокоды: то же — убираем сравнение id::text = uid
-- ---------------------------------------------------------------------------
create or replace function public.redeem_promo_code(p_user_id text, p_label text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label       text;
  v_uid         text;
  v_user_id     uuid;
  v_code        public.promo_codes%rowtype;
  v_max_energy  integer;
  v_energy      integer;
  v_shields     integer;
  v_used        integer;
  v_energy_add  integer := 0;
  v_shields_add integer := 0;
  v_new_gold       integer := 0;
  v_new_xp         integer := 0;
  v_new_energy     integer := 0;
  v_new_max_energy integer := 0;
  v_new_shields    integer := 0;
begin
  if auth.uid() is null then
    raise exception 'PROMO_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;

  v_uid := auth.uid()::text;
  v_user_id := auth.uid();

  if p_user_id is null or btrim(p_user_id) <> v_uid then
    raise exception 'PROMO_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;

  v_label := upper(btrim(coalesce(p_label, '')));
  if v_label = '' then
    raise exception 'PROMO_EMPTY' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_code
  from public.promo_codes c
  where upper(c.label) = v_label
  for update;

  if not found then
    raise exception 'PROMO_INVALID' using errcode = 'invalid_parameter_value';
  end if;

  if not v_code.is_active then
    raise exception 'PROMO_INVALID' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.starts_at is not null and now() < v_code.starts_at then
    raise exception 'PROMO_NOT_STARTED' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.expires_at is not null and now() > v_code.expires_at then
    raise exception 'PROMO_EXPIRED' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.max_redemptions is not null
     and v_code.redeemed_count >= v_code.max_redemptions then
    raise exception 'PROMO_EXHAUSTED' using errcode = 'invalid_parameter_value';
  end if;

  select count(*) into v_used
  from public.promo_redemptions r
  where r.code_id = v_code.id and r.user_id = v_uid;

  if v_used >= v_code.max_per_user then
    raise exception 'PROMO_ALREADY_USED' using errcode = 'invalid_parameter_value';
  end if;

  select max_energy, energy, coalesce(shields_left, 0)
    into v_max_energy, v_energy, v_shields
  from public.profiles
  where id = v_user_id
  for update;

  if not found then
    raise exception 'PROMO_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.energy > 0 then
    v_energy_add := greatest(0, least(v_code.energy, v_max_energy - v_energy));
  end if;

  if v_code.shields > 0 then
    v_shields_add := greatest(0, least(v_code.shields, 5 - v_shields));
  end if;

  begin
    insert into public.promo_redemptions (code_id, user_id, gold, xp, energy, shields)
    values (v_code.id, v_uid, v_code.gold, v_code.xp, v_energy_add, v_shields_add);
  exception
    when unique_violation then
      raise exception 'PROMO_ALREADY_USED' using errcode = 'invalid_parameter_value';
  end;

  update public.profiles p
     set gold         = coalesce(p.gold, 0) + v_code.gold,
         xp           = coalesce(p.xp, 0) + v_code.xp,
         energy       = least(coalesce(p.max_energy, 5), v_energy + v_energy_add),
         shields_left = least(5, v_shields + v_shields_add)
   where p.id = v_user_id
   returning p.gold, p.xp, p.energy, p.max_energy, coalesce(p.shields_left, 0)
   into v_new_gold, v_new_xp, v_new_energy, v_new_max_energy, v_new_shields;

  if not found then
    raise exception 'PROMO_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  update public.promo_codes c
     set redeemed_count = c.redeemed_count + 1
   where c.id = v_code.id;

  return jsonb_build_object(
    'ok', true,
    'code', v_code.label,
    'title', coalesce(v_code.description, v_code.label),
    'gold_added', v_code.gold,
    'xp_added', v_code.xp,
    'energy_added', v_energy_add,
    'shields_added', v_shields_add,
    'gold', v_new_gold,
    'xp', v_new_xp,
    'energy', v_new_energy,
    'max_energy', v_new_max_energy,
    'shields_left', v_new_shields
  );
end;
$$;

revoke all on function public.redeem_promo_code(text, text) from public;
grant execute on function public.redeem_promo_code(text, text) to authenticated;

commit;

-- ============================================================================
-- Проверка 1 — типы параметров функций (пришлите вывод, если что-то не так):
--   select p.proname, pg_get_function_arguments(p.oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('complete_quest_atomic','buy_consumable','upgrade_camp','redeem_promo_code')
--   order by p.proname;
--
-- Проверка 2 — в функциях не осталось сравнений uuid-колонки с текстом:
--   select p.proname
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('complete_quest_atomic','buy_consumable','upgrade_camp','redeem_promo_code')
--     and pg_get_functiondef(p.oid) ~ 'id::text\s*=';
-- Ожидаемо: 0 строк.
--
-- ГЛАВНАЯ ПРОВЕРКА — сдать квест в приложении. Именно эту операцию сломала
-- миграция 006, и её надо проверить сразу после применения.
-- ============================================================================

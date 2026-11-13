-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 007: покупки и постройки на сервере
-- ============================================================================
-- ЧТО ЗАКРЫВАЕТСЯ
--
-- Магазин и постройки лагеря писали в profiles абсолютные значения:
--   update profiles set gold = <посчитано на клиенте>, energy = ...,
--                       shields_left = ..., camp_level = ...
-- Значит через прямой запрос к API можно было выставить любое золото,
-- энергию, щиты и уровень лагеря. Цены при этом тоже приходили с клиента,
-- поэтому проверять их на сервере было невозможно.
--
-- РЕШЕНИЕ
--
-- buy_consumable() и upgrade_camp() считают всё сами: цену берут из констант
-- и из camp_building_effects, проверяют достаток золота и лимиты, и только
-- потом пишут в профиль. Клиент получает новое состояние в ответе.
--
-- ВАЖНО: auth.uid() берётся внутри функции. Параметра с id игрока нет
-- намеренно — иначе можно было бы покупать на чужой аккаунт.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- Если Supabase предложит включить RLS — эта миграция RLS не трогает.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Магазин расходников
-- ---------------------------------------------------------------------------
-- kind: 'energy' — зелье +3 энергии за 50 золота (не выше максимума)
--       'shields' — щит заморозки +1 за 100 золота (не выше 5)
create or replace function public.buy_consumable(p_kind text, p_count integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Цены и лимиты дублируют lib/constants/game_config.dart. Дублирование
  -- намеренное: сервер обязан проверять цену сам. Расхождение ловит
  -- test/server_config_sync_test.dart.
  c_energy_price   constant integer := 50;
  c_energy_amount  constant integer := 3;
  c_shield_price   constant integer := 100;
  c_max_shields    constant integer := 5;

  v_uid         text;
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
  v_uid := auth.uid()::text;

  v_kind := lower(btrim(coalesce(p_kind, '')));
  if v_kind not in ('energy', 'shields') then
    raise exception 'SHOP_UNKNOWN_ITEM' using errcode = 'invalid_parameter_value';
  end if;

  v_count := coalesce(p_count, 0);
  if v_count < 1 or v_count > 99 then
    raise exception 'SHOP_BAD_COUNT' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_profile from public.profiles where id::text = v_uid for update;
  if not found then
    raise exception 'SHOP_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  if v_kind = 'energy' then
    v_unit_price := c_energy_price;
    -- Продаём только то, что поместится: округление вверх, без лишних зелий,
    -- за которые списались бы деньги впустую.
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
   where p.id::text = v_uid
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
-- 2. Постройка в лагере
-- ---------------------------------------------------------------------------
-- Цена и эффект берутся из camp_building_effects: клиент их не присылает.
create or replace function public.upgrade_camp()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_max_camp_level constant integer := 5;
  c_max_shields    constant integer := 5;

  v_uid          text;
  v_profile      profiles%rowtype;
  v_building     camp_building_effects%rowtype;
  v_new_level    integer;
  v_new_max      integer;
begin
  if auth.uid() is null then
    raise exception 'CAMP_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_uid := auth.uid()::text;

  select * into v_profile from public.profiles where id::text = v_uid for update;
  if not found then
    raise exception 'CAMP_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.camp_level, 1) >= c_max_camp_level then
    raise exception 'CAMP_MAX_LEVEL' using errcode = 'invalid_parameter_value';
  end if;

  -- Следующая постройка — та, что открывается на текущем уровне + 1.
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
         -- Мгновенная энергия + прибавка к максимуму, но не выше нового потолка.
         energy       = least(v_new_max,
                              coalesce(p.energy, 0) + v_building.instant_energy + v_building.max_energy)
   where p.id::text = v_uid
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

commit;

-- ============================================================================
-- Проверка после применения (под своим аккаунтом из приложения):
--   select public.buy_consumable('energy', 1);   -- списывает 50, даёт до +3
--   select public.upgrade_camp();                -- строит постройку эпохи
--
-- Повторный upgrade_camp при полном золоте и лагере < 5 строит следующую.
-- При лагере 5 ожидается CAMP_MAX_LEVEL.
-- ============================================================================

-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 022: плавная прогрессия и баланс наград
-- ============================================================================
-- ЧТО БЫЛО СЛОМАНО
--
-- 1. ПОРОГ ОПЫТА рос вдвое (100 → 200 → 500 → 1000 → 2000 → 4000 = 7800 XP),
--    а награда за квест от эпохи не зависела. Последняя эпоха требовала
--    примерно в 36 раз больше квестов, чем первая: игра не ускорялась,
--    а замедлялась на каждом шаге.
--
-- 2. ЦЕНЫ ЛАГЕРЯ росли сами по себе. Полный лагерь всех шести эпох стоил
--    84 230 золота, а доход составлял около сотни в день: это стена примерно
--    на два года игры. Развитие вставало уже на второй эпохе, потому что
--    эволюция требует полностью отстроенный лагерь.
--
-- 3. ЦЕНЫ УСЛУГ были константами. Зелье энергии стоило 50 золота всегда:
--    в Каменном веке это 4–6 квестов, в Космической эре — треть квеста.
--
-- 4. НАГРАДУ ЗА КВЕСТ писали три разных источника: ручной конструктор,
--    активация пресета и ИИ. Проверить их было нечем.
--
-- ЧТО ДЕЛАЕТ МИГРАЦИЯ
--
--   * era_config: пороги подобраны так, чтобы эпоха занимала 20–35 квестов;
--   * camp_building_effects: цена лагеря привязана к доходу эпохи
--     (полный лагерь ≈ 1.2–1.3 дохода эпохи + награда за вход в неё);
--   * era_economy (новая таблица): коридор награды за квест и цены услуг
--     по эпохам — единственное место, где эти числа заданы;
--   * buy_consumable и restore_streak читают цены из era_economy;
--   * goal_slot_prices: 150 / 400 / 900;
--   * league_tiers: пороги под новую шкалу опыта + множитель награды;
--   * clamp_quest_rewards: триггер, который приводит ЛЮБУЮ награду за квест
--     в коридор эпохи владельца цели. Это единственное место, которое видит
--     все три источника наград сразу.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- Файл можно применять повторно: все изменения — upsert или create or replace.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Пороги эпох и награда за переход
-- ---------------------------------------------------------------------------
insert into public.era_config
  (era_id, display_order, xp_required, gold_bonus, increases_max_energy, name)
values
  ('stone_age',   1,  120,    0, false, 'Каменный век'),
  ('bronze_age',  2,  240,  100, false, 'Бронзовый век'),
  ('iron_age',    3,  480,  250, true,  'Железный век'),
  ('middle_ages', 4,  900,  500, false, 'Средневековье'),
  ('modern_age',  5, 1600,  900, true,  'Индустриальная эпоха'),
  ('space_age',   6, 2800, 1500, true,  'Космическая эпоха')
on conflict (era_id) do update set
  display_order        = excluded.display_order,
  xp_required          = excluded.xp_required,
  gold_bonus           = excluded.gold_bonus,
  increases_max_energy = excluded.increases_max_energy,
  name                 = excluded.name;

-- ---------------------------------------------------------------------------
-- 2. Цены лагеря
-- ---------------------------------------------------------------------------
-- Бонусы построек не меняются, меняются только цены: они должны быть
-- посильны из дохода своей эпохи.
insert into public.camp_building_effects
  (era_id, unlock_level, name, price, shields, max_energy, instant_energy, gold_bonus, xp_bonus)
values
  ('stone_age',   2, 'Кострище',            30,   1, 0, 0, 0.00, 0.00),
  ('stone_age',   3, 'Мастерская кремня',   50,   0, 0, 0, 0.00, 0.05),
  ('stone_age',   4, 'Шаманский тотем',     80,   0, 0, 0, 0.10, 0.00),
  ('stone_age',   5, 'Хижина вождя',        120,  0, 1, 1, 0.00, 0.00),

  ('bronze_age',  2, 'Медный рудник',       90,   0, 0, 0, 0.10, 0.00),
  ('bronze_age',  3, 'Гончарный склад',     140,  1, 0, 0, 0.00, 0.00),
  ('bronze_age',  4, 'Бронзовая кузница',   200,  0, 0, 0, 0.00, 0.10),
  ('bronze_age',  5, 'Дворец правителя',    290,  0, 1, 1, 0.00, 0.00),

  ('iron_age',    2, 'Плавильня железа',    190,  0, 0, 0, 0.15, 0.00),
  ('iron_age',    3, 'Частокол легиона',    290,  2, 0, 0, 0.00, 0.00),
  ('iron_age',    4, 'Оружейный арсенал',   410,  0, 0, 0, 0.00, 0.15),
  ('iron_age',    5, 'Цитадель легиона',    600,  0, 1, 1, 0.00, 0.00),

  ('middle_ages', 2, 'Торговая площадь',    380,  0, 0, 0, 0.20, 0.00),
  ('middle_ages', 3, 'Башня алхимиков',     560,  0, 0, 2, 0.00, 0.00),
  ('middle_ages', 4, 'Рыцарский орден',     780,  0, 0, 0, 0.00, 0.20),
  ('middle_ages', 5, 'Кафедральный собор',  1100, 0, 1, 1, 0.00, 0.00),

  ('modern_age',  2, 'Паровая фабрика',     640,  0, 0, 0, 0.25, 0.00),
  ('modern_age',  3, 'Телеграфная вышка',   950,  0, 0, 0, 0.00, 0.25),
  ('modern_age',  4, 'Железная дорога',     1350, 3, 0, 0, 0.00, 0.00),
  ('modern_age',  5, 'Академия наук',       1900, 0, 2, 2, 0.00, 0.00),

  ('space_age',   2, 'Солнечная ферма',     1100, 0, 0, 0, 0.30, 0.00),
  ('space_age',   3, 'Орбитальный лифт',    1650, 3, 0, 0, 0.00, 0.00),
  ('space_age',   4, 'Спутниковый ЦУП',     2300, 0, 0, 0, 0.00, 0.30),
  ('space_age',   5, 'Космодром Альфа',     3200, 0, 2, 2, 0.00, 0.00)
on conflict (era_id, unlock_level) do update set
  name           = excluded.name,
  price          = excluded.price,
  shields        = excluded.shields,
  max_energy     = excluded.max_energy,
  instant_energy = excluded.instant_energy,
  gold_bonus     = excluded.gold_bonus,
  xp_bonus       = excluded.xp_bonus;

-- ---------------------------------------------------------------------------
-- 3. Экономика эпохи: коридор награды за квест и цены услуг
-- ---------------------------------------------------------------------------
create table if not exists public.era_economy (
  era_id               text primary key,
  xp_min               integer not null,
  xp_max               integer not null,
  gold_min             integer not null,
  gold_max             integer not null,
  energy_potion_price  integer not null,
  shield_price         integer not null,
  streak_restore_price integer not null,

  constraint era_economy_ranges check (
    xp_min > 0 and xp_max >= xp_min and gold_min > 0 and gold_max >= gold_min
  ),
  constraint era_economy_prices check (
    energy_potion_price > 0 and shield_price > 0 and streak_restore_price > 0
  )
);

insert into public.era_economy
  (era_id, xp_min, xp_max, gold_min, gold_max,
   energy_potion_price, shield_price, streak_restore_price)
values
  ('stone_age', 4, 7, 8, 14, 80, 45, 65),
  ('bronze_age', 7, 12, 14, 24, 130, 75, 115),
  ('iron_age', 13, 20, 25, 40, 220, 130, 190),
  ('middle_ages', 22, 34, 42, 65, 355, 210, 320),
  ('modern_age', 38, 58, 70, 105, 575, 350, 520),
  ('space_age', 65, 95, 115, 165, 900, 560, 840)
on conflict (era_id) do update set
  xp_min               = excluded.xp_min,
  xp_max               = excluded.xp_max,
  gold_min             = excluded.gold_min,
  gold_max             = excluded.gold_max,
  energy_potion_price  = excluded.energy_potion_price,
  shield_price         = excluded.shield_price,
  streak_restore_price = excluded.streak_restore_price;

-- Справочник баланса: клиент читает цены из конфига, доступ к таблице не нужен.
alter table public.era_economy enable row level security;
drop policy if exists era_economy_no_client_access on public.era_economy;
create policy era_economy_no_client_access on public.era_economy
  for select using (false);

-- ---------------------------------------------------------------------------
-- 4. Цены слотов целей
-- ---------------------------------------------------------------------------
insert into public.goal_slot_prices (level, price)
values (2, 150), (3, 400), (4, 900)
on conflict (level) do update set price = excluded.price;

-- ---------------------------------------------------------------------------
-- 5. Лиги: пороги под новую шкалу опыта и множитель награды
-- ---------------------------------------------------------------------------
-- Полное прохождение игры теперь даёт около 6100 опыта, поэтому прежние
-- пороги (до 20 000) стали недостижимы.
alter table public.league_tiers
  add column if not exists reward_multiplier numeric not null default 1;

alter table public.league_tiers
  drop constraint if exists league_tiers_reward_multiplier_positive;
alter table public.league_tiers
  add constraint league_tiers_reward_multiplier_positive check (reward_multiplier > 0);

insert into public.league_tiers (id, tier_order, name, min_total_xp, reward_multiplier)
values
  ('bronze',   1, 'Бронзовая лига',    0,    1.0),
  ('silver',   2, 'Серебряная лига',   400,  1.5),
  ('gold',     3, 'Золотая лига',      1000, 2.0),
  ('platinum', 4, 'Платиновая лига',   2000, 3.0),
  ('emerald',  5, 'Изумрудная лига',   3500, 4.0),
  ('diamond',  6, 'Алмазная лига',     5500, 5.0)
on conflict (id) do update set
  tier_order        = excluded.tier_order,
  name              = excluded.name,
  min_total_xp      = excluded.min_total_xp,
  reward_multiplier = excluded.reward_multiplier;

-- ---------------------------------------------------------------------------
-- 6. Триггер: награда за квест обязана попадать в коридор эпохи
-- ---------------------------------------------------------------------------
-- Единственное место, которое видит все три источника наград сразу: ручной
-- конструктор, активацию пресета и генерацию ИИ. Коридор задан в era_economy,
-- относительный разброс внутри коридора сохраняется — подрезается только то,
-- что вышло за рамки.
create or replace function public.clamp_quest_rewards()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_era  text;
  v_econ public.era_economy%rowtype;
begin
  select p.current_era::text
    into v_era
    from public.goals g
    join public.profiles p on p.id = g.user_id
   where g.id::text = new.goal_id::text;

  if v_era is null then
    return new;
  end if;

  select * into v_econ from public.era_economy e where e.era_id = v_era;
  if not found then
    return new;
  end if;

  new.xp_reward := least(
    greatest(coalesce(new.xp_reward, v_econ.xp_min), v_econ.xp_min),
    v_econ.xp_max
  );
  new.gold_reward := least(
    greatest(coalesce(new.gold_reward, v_econ.gold_min), v_econ.gold_min),
    v_econ.gold_max
  );

  return new;
end;
$$;

drop trigger if exists clamp_quest_rewards_trigger on public.quests;
create trigger clamp_quest_rewards_trigger
  before insert or update of xp_reward, gold_reward on public.quests
  for each row execute function public.clamp_quest_rewards();

-- ---------------------------------------------------------------------------
-- 7. Функции, которые теперь читают цены из era_economy
-- ---------------------------------------------------------------------------

create or replace function public.buy_consumable(p_kind text, p_count integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Цены больше не константы: они зависят от эпохи игрока и читаются
  -- из era_economy ниже, после загрузки профиля.
  c_energy_amount  constant integer := 3;
  c_max_shields    constant integer := 5;

  v_user_id     uuid;
  v_profile     profiles%rowtype;
  v_kind        text;
  v_count       integer;
  v_useful      integer;
  v_energy_price integer;
  v_shield_price integer;
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

  -- Цена зависит от эпохи: в Каменном веке зелье стоит 25, в Космической
  -- эре 280. Раньше цена была одна на всю игру — в начале разорение,
  -- в конце мелочь.
  select e.energy_potion_price, e.shield_price
    into v_energy_price, v_shield_price
    from public.era_economy e
   where e.era_id = v_profile.current_era::text;
  if v_energy_price is null or v_shield_price is null then
    raise exception 'SHOP_NO_ECONOMY' using errcode = 'invalid_parameter_value';
  end if;

  if v_kind = 'energy' then
    v_unit_price := v_energy_price;
    v_useful := greatest(1,
      ((greatest(coalesce(v_profile.max_energy, 5) - coalesce(v_profile.energy, 0), 0)
        + c_energy_amount - 1) / c_energy_amount));
  else
    v_unit_price := v_shield_price;
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

create or replace function public.restore_streak()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Цена спасения серии зависит от эпохи и читается ниже из era_economy.
  v_price   integer;
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

  select e.streak_restore_price
    into v_price
    from public.era_economy e
   where e.era_id = v_profile.current_era::text;
  if v_price is null then
    raise exception 'STREAK_NO_ECONOMY' using errcode = 'invalid_parameter_value';
  end if;

  -- Спасать можно только стрик, который реально в упадке.
  if v_profile.is_decayed is not true then
    raise exception 'STREAK_NOT_DECAYED' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.gold, 0) < v_price then
    raise exception 'STREAK_NOT_ENOUGH_GOLD' using errcode = 'invalid_parameter_value';
  end if;

  v_new_gold := coalesce(v_profile.gold, 0) - v_price;

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
    'paid', v_price,
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

create or replace function public.settle_league_season()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid;
  v_season    public.league_seasons%rowtype;
  v_row       record;
  v_awarded   integer;
  v_seasons   integer := 0;
  v_paid      integer := 0;
  v_award_id  uuid;
  v_place     integer;
  v_gold      integer;
  v_tier_id   text;
  v_tier_name text;
  v_my_award  jsonb := null;
begin
  if auth.uid() is null then
    raise exception 'LEAGUE_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_uid := auth.uid();

  -- Закрываем все истёкшие сезоны по порядку.
  for v_season in
    select * from public.league_seasons
    where settled_at is null and ends_at <= now()
    order by ends_at
    for update
  loop
    for v_row in
      with ranked as (
        select p.id as user_id,
               public.league_tier_for_xp(p.total_xp) as tier_id,
               row_number() over (
                 partition by public.league_tier_for_xp(p.total_xp)
                 order by coalesce(p.season_xp, 0) desc, p.id
               ) as place
        from public.profiles p
        where coalesce(p.season_xp, 0) > 0
      )
      -- Награда умножается на множитель уровня лиги: 300 золота в
      -- Бронзовой и 1500 в Алмазной. Без этого награда была бы заметна
      -- в начале игры и незаметна в конце.
      select r.user_id, r.tier_id, r.place,
             round(lr.gold * t.reward_multiplier)::int as gold
      from ranked r
      join public.league_rewards lr on lr.place = r.place
      join public.league_tiers t on t.id = r.tier_id
      where r.place <= 3
    loop
      insert into public.league_awards (season_id, user_id, tier_id, place, gold)
      values (v_season.id, v_row.user_id, v_row.tier_id, v_row.place, v_row.gold)
      on conflict (season_id, user_id) do nothing;

      get diagnostics v_awarded = row_count;
      if v_awarded > 0 then
        update public.profiles
           set gold = coalesce(gold, 0) + v_row.gold
         where id = v_row.user_id;
        v_paid := v_paid + 1;
      end if;
    end loop;

    -- Сезонный опыт обнуляется: новый сезон начинается с нуля.
    update public.profiles set season_xp = 0 where coalesce(season_xp, 0) <> 0;

    update public.league_seasons set settled_at = now() where id = v_season.id;
    v_seasons := v_seasons + 1;

    insert into public.league_seasons (started_at, ends_at)
    values (now(), now() + interval '7 days');
  end loop;

  -- Открытый сезон должен существовать всегда.
  perform public.open_league_season();

  -- Награда текущего игрока, о которой он ещё не уведомлён.
  select a.id, a.place, a.gold, a.tier_id, coalesce(t.name, a.tier_id)
    into v_award_id, v_place, v_gold, v_tier_id, v_tier_name
  from public.league_awards a
  left join public.league_tiers t on t.id = a.tier_id
  where a.user_id = v_uid and a.notified_at is null
  order by a.awarded_at desc
  limit 1;

  if v_award_id is not null then
    update public.league_awards set notified_at = now() where id = v_award_id;
    v_my_award := jsonb_build_object(
      'place', v_place,
      'gold', v_gold,
      'tier_id', v_tier_id,
      'tier_name', v_tier_name
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'settled_seasons', v_seasons,
    'awards_paid', v_paid,
    'my_award', v_my_award
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7.1 Множитель серии больше не растёт без предела
-- ---------------------------------------------------------------------------
-- Рост на 0.5% в день без ограничения означал, что через полгода серии
-- награды удваиваются. Для игры это плохо вдвойне: любая цена в магазине
-- становится мелочью, а покупка энергии — выгодной, из-за чего пропадает
-- смысл суточного лимита.
create or replace function public.complete_quest_atomic(
  p_user_id uuid,
  p_quest_id text,
  p_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
DECLARE
    v_profile profiles%ROWTYPE;
    v_quest quests%ROWTYPE;
    v_session focus_sessions%ROWTYPE;
    v_camp_xp_bonus NUMERIC := 0.0;
    v_camp_gold_bonus NUMERIC := 0.0;
    v_earned_xp INT;
    v_earned_gold INT;
    v_new_energy INT;
    v_new_streak INT;
    v_new_multiplier NUMERIC;
    v_today DATE := NOW()::date;
    v_uid TEXT;
BEGIN
    v_uid := p_user_id::text;

    -- Идентификатор игрока приходит параметром исторически: это самая старая
    -- функция схемы. Обязательно сверяем его с текущей сессией, иначе любой
    -- зарегистрированный игрок может сдать квест за другого, зная его id.
    -- Так же сделано в redeem_promo_code.
    IF auth.uid() IS NULL OR auth.uid()::text <> v_uid THEN
        RAISE EXCEPTION 'QUEST_UNAUTHORIZED' using errcode = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_profile
    FROM profiles
    WHERE id::text = v_uid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF coalesce(v_profile.energy, 0) <= 0 THEN
        RAISE EXCEPTION 'Not enough energy';
    END IF;

    SELECT q.* INTO v_quest
    FROM quests q
    JOIN goals g ON g.id::text = q.goal_id::text
    WHERE q.id::text = p_quest_id::text
      AND g.user_id::text = v_uid
    FOR UPDATE OF q;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quest not found';
    END IF;

    IF v_quest.is_completed THEN
        RAISE EXCEPTION 'Quest already completed';
    END IF;

    -- Квест с таймером сдаётся только через серверную сессию фокуса.
    IF coalesce(v_quest.is_timer_based, false) THEN
        IF p_session_id IS NULL THEN
            RAISE EXCEPTION 'QUEST_TIMER_NOT_STARTED';
        END IF;

        SELECT * INTO v_session
        FROM public.focus_sessions
        WHERE id = p_session_id
          AND user_id = v_uid::uuid
          AND quest_id = v_quest.id
          AND completed_at IS NULL
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'QUEST_TIMER_NOT_STARTED';
        END IF;

        IF now() < v_session.started_at + make_interval(secs => v_session.required_seconds) THEN
            RAISE EXCEPTION 'QUEST_TIMER_NOT_ELAPSED';
        END IF;

        UPDATE public.focus_sessions
        SET completed_at = now()
        WHERE id = v_session.id;
    END IF;

    SELECT b.gold_bonus, b.xp_bonus
      INTO v_camp_gold_bonus, v_camp_xp_bonus
      FROM public.camp_bonuses(v_profile.current_era::text, v_profile.camp_level) b;

    v_earned_xp := ROUND(
        v_quest.xp_reward::numeric
        * v_profile.streak_multiplier::numeric
        * (1.0 + v_camp_xp_bonus)
    );
    v_earned_gold := ROUND(
        v_quest.gold_reward::numeric
        * v_profile.streak_multiplier::numeric
        * (1.0 + v_camp_gold_bonus)
    );
    v_new_energy := v_profile.energy - 1;

    -- Множитель серии ограничен: без предела он растёт бесконечно, и любая
    -- цена зелья энергии рано или поздно становится выгодной — лимит
    -- энергии перестаёт ограничивать игру (миграция 022).
    IF v_profile.last_active_date IS DISTINCT FROM v_today THEN
        v_new_streak     := v_profile.streak_count + 1;
        v_new_multiplier := least(v_profile.streak_multiplier + 0.005, 1.5);
    ELSE
        v_new_streak     := v_profile.streak_count;
        v_new_multiplier := v_profile.streak_multiplier;
    END IF;

    UPDATE quests
    SET is_completed = TRUE, completed_at = NOW()
    WHERE id::text = p_quest_id::text;

    UPDATE profiles
    SET xp                = v_profile.xp + v_earned_xp,
        total_xp          = coalesce(v_profile.total_xp, 0) + v_earned_xp,
        season_xp         = coalesce(v_profile.season_xp, 0) + v_earned_xp,
        gold              = v_profile.gold + v_earned_gold,
        energy            = v_new_energy,
        streak_count      = v_new_streak,
        streak_multiplier = v_new_multiplier,
        last_active_date  = v_today,
        is_decayed        = FALSE
    WHERE id::text = v_uid;

    RETURN jsonb_build_object(
        'success', true,
        'xp_reward', v_quest.xp_reward,
        'gold_reward', v_quest.gold_reward,
        'earned_xp', v_earned_xp,
        'earned_gold', v_earned_gold,
        'energy_left', v_new_energy,
        'camp_gold_bonus', v_camp_gold_bonus,
        'camp_xp_bonus', v_camp_xp_bonus,
        'gold', v_profile.gold + v_earned_gold,
        'xp', v_profile.xp + v_earned_xp,
        'total_xp', coalesce(v_profile.total_xp, 0) + v_earned_xp,
        'season_xp', coalesce(v_profile.season_xp, 0) + v_earned_xp,
        'energy', v_new_energy,
        'max_energy', v_profile.max_energy,
        'shields_left', coalesce(v_profile.shields_left, 0),
        'streak_count', v_new_streak,
        'streak_multiplier', v_new_multiplier
    );
END;
$function$;

revoke all on function public.complete_quest_atomic(uuid, text, uuid) from public, anon;
grant execute on function public.complete_quest_atomic(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Права на новые функции
-- ---------------------------------------------------------------------------
revoke all on function public.clamp_quest_rewards() from public, anon;
grant execute on function public.clamp_quest_rewards() to authenticated;

revoke all on function public.buy_consumable(text, integer) from public, anon;
grant execute on function public.buy_consumable(text, integer) to authenticated;

revoke all on function public.restore_streak() from public, anon;
grant execute on function public.restore_streak() to authenticated;

revoke all on function public.settle_league_season() from public, anon;
grant execute on function public.settle_league_season() to authenticated;

commit;

-- ============================================================================
-- ПРОВЕРКА
--
-- 1) Справочники:
--   select era_id, xp_required, gold_bonus from public.era_config order by display_order;
--   select era_id, price from public.camp_building_effects order by era_id, unlock_level;
--   select * from public.era_economy order by era_id;
--   select level, price from public.goal_slot_prices order by level;
--   select id, min_total_xp, reward_multiplier from public.league_tiers order by tier_order;
--
-- 2) Полная стоимость лагеря по эпохам (ожидаем 280 / 720 / 1490 / 2820 / 4840 / 8250):
--   select era_id, sum(price) from public.camp_building_effects
--    group by era_id order by min(unlock_level) desc;
--
-- 3) Коридор награды работает. Вставьте квест с заведомо дикой наградой и
--    посмотрите, что сохранилось (не забудьте rollback):
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   insert into public.quests (goal_id, title, xp_reward, gold_reward)
--   select g.id, 'проверка', 99999, 99999 from public.goals g
--    join public.profiles p on p.id = g.user_id
--   where p.id = '<uuid>' limit 1;
--   select title, xp_reward, gold_reward from public.quests where title = 'проверка';
-- rollback;
-- Ожидаемо: награда подрезана до xp_max и gold_max эпохи игрока.
-- ============================================================================

-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 006: бонусы лагеря — один источник правды
-- ============================================================================
-- ЧТО ИСПРАВЛЯЕТСЯ
--
-- В complete_quest_atomic бонусы построек считались жёсткой цепочкой IF по
-- эпохе и уровню лагеря. Те же бонусы есть в приложении (game_config.dart), и
-- они уже разошлись: для modern_age сервер давал +25% XP с уровня 3, а клиент
-- с уровня 4. Плюс клиент умножал ответ сервера на бонусы ещё раз, то есть
-- награда начислялась с двойным бонусом лагеря.
--
-- РЕШЕНИЕ
--
-- Единственный источник правды — таблица camp_building_effects. Из неё читает
-- complete_quest_atomic. Клиент больше не считает бонусы: он получает готовую
-- награду и новое состояние профиля из ответа сервера.
--
-- Дублирование настроек в этой таблице намеренное (см. game_config.dart):
-- сервер обязан проверять цены и эффекты сам, иначе клиент пришлёт свои.
-- Расхождение ловит тест test/server_config_sync_test.dart.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Таблица эффектов построек
-- ---------------------------------------------------------------------------
create table if not exists public.camp_building_effects (
  era_id          text    not null,
  unlock_level    integer not null,          -- уровень лагеря, на котором строится
  name            text    not null,
  price           integer not null,
  shields         integer not null default 0,
  max_energy      integer not null default 0,
  instant_energy  integer not null default 0,
  gold_bonus      numeric not null default 0,
  xp_bonus        numeric not null default 0,

  constraint camp_building_effects_pk primary key (era_id, unlock_level),
  constraint camp_building_effects_unlock check (unlock_level between 2 and 5),
  constraint camp_building_effects_non_negative check (
    price >= 0 and shields >= 0 and max_energy >= 0
    and instant_energy >= 0 and gold_bonus >= 0 and xp_bonus >= 0
  )
);

-- Заполняем/обновляем все 24 постройки. Значения сверены с game_config.dart.
insert into public.camp_building_effects
  (era_id, unlock_level, name, price, shields, max_energy, instant_energy, gold_bonus, xp_bonus)
values
  ('stone_age',   2, 'Кострище',            40,    1, 0, 0, 0.00, 0.00),
  ('stone_age',   3, 'Мастерская кремня',   70,    0, 0, 0, 0.00, 0.05),
  ('stone_age',   4, 'Шаманский тотем',     110,   0, 0, 0, 0.10, 0.00),
  ('stone_age',   5, 'Хижина вождя',        160,   0, 1, 1, 0.00, 0.00),

  ('bronze_age',  2, 'Медный рудник',       250,   0, 0, 0, 0.10, 0.00),
  ('bronze_age',  3, 'Гончарный склад',     450,   1, 0, 0, 0.00, 0.00),
  ('bronze_age',  4, 'Бронзовая кузница',   700,   0, 0, 0, 0.00, 0.10),
  ('bronze_age',  5, 'Дворец правителя',    1000,  0, 1, 1, 0.00, 0.00),

  ('iron_age',    2, 'Плавильня железа',    500,   0, 0, 0, 0.15, 0.00),
  ('iron_age',    3, 'Частокол легиона',    850,   2, 0, 0, 0.00, 0.00),
  ('iron_age',    4, 'Оружейный арсенал',   1300,  0, 0, 0, 0.00, 0.15),
  ('iron_age',    5, 'Цитадель легиона',    2000,  0, 1, 1, 0.00, 0.00),

  ('middle_ages', 2, 'Торговая площадь',    1000,  0, 0, 0, 0.20, 0.00),
  ('middle_ages', 3, 'Башня алхимиков',     1700,  0, 0, 2, 0.00, 0.00),
  ('middle_ages', 4, 'Рыцарский орден',     2600,  0, 0, 0, 0.00, 0.20),
  ('middle_ages', 5, 'Кафедральный собор',  4000,  0, 1, 1, 0.00, 0.00),

  ('modern_age',  2, 'Паровая фабрика',     2500,  0, 0, 0, 0.25, 0.00),
  ('modern_age',  3, 'Телеграфная вышка',   4000,  0, 0, 0, 0.00, 0.25),
  ('modern_age',  4, 'Железная дорога',     6000,  3, 0, 0, 0.00, 0.00),
  ('modern_age',  5, 'Академия наук',       10000, 0, 2, 2, 0.00, 0.00),

  ('space_age',   2, 'Солнечная ферма',     5000,  0, 0, 0, 0.30, 0.00),
  ('space_age',   3, 'Орбитальный лифт',    8000,  3, 0, 0, 0.00, 0.00),
  ('space_age',   4, 'Спутниковый ЦУП',     12000, 0, 0, 0, 0.00, 0.30),
  ('space_age',   5, 'Космодром Альфа',     20000, 0, 2, 2, 0.00, 0.00)
on conflict (era_id, unlock_level) do update set
  name           = excluded.name,
  price          = excluded.price,
  shields        = excluded.shields,
  max_energy     = excluded.max_energy,
  instant_energy = excluded.instant_energy,
  gold_bonus     = excluded.gold_bonus,
  xp_bonus       = excluded.xp_bonus;

-- ---------------------------------------------------------------------------
-- 2. Суммарные бонусы лагеря для эпохи и уровня
-- ---------------------------------------------------------------------------
create or replace function public.camp_bonuses(p_era_id text, p_camp_level integer)
returns table (gold_bonus numeric, xp_bonus numeric)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(sum(e.gold_bonus), 0)::numeric,
    coalesce(sum(e.xp_bonus), 0)::numeric
  from public.camp_building_effects e
  where e.era_id = p_era_id
    and e.unlock_level <= greatest(coalesce(p_camp_level, 1), 1);
$$;

-- ---------------------------------------------------------------------------
-- 3. Сдача квеста: та же логика, но бонусы из таблицы и полный ответ
-- ---------------------------------------------------------------------------
-- Изменения против прежней версии:
--   * бонусы лагеря читаются из camp_building_effects, а не из цепочки IF;
--   * проверяется владелец квеста, иначе можно было сдать чужой квест, зная
--     только его id;
--   * ответ возвращает полное состояние профиля, чтобы клиент не досчитывал
--     ничего сам (раньше он угадывал стрик и множитель локально).
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
    SELECT q.* INTO v_quest
    FROM quests q
    JOIN goals g ON g.id = q.goal_id
    WHERE q.id = p_quest_id AND g.user_id = p_user_id
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

    -- Стрик: правило одно и то же здесь и в магазине, шаг +0.005 в день.
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

revoke all on function public.complete_quest_atomic(uuid, text) from public;
grant execute on function public.complete_quest_atomic(uuid, text) to authenticated;

commit;

-- ============================================================================
-- Проверка после применения — бонусы должны совпасть с прежними для этих эпох
-- (кроме modern_age, где прежнее правило расходилось с конфигом приложения):
--   select * from public.camp_bonuses('stone_age', 5);    -- 0.10 золота, 0.05 XP
--   select * from public.camp_bonuses('modern_age', 4);   -- 0.25 золота, 0.25 XP
--   select count(*) from public.camp_building_effects;    -- 24
-- ============================================================================

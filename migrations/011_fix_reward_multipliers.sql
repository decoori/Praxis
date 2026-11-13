-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 011: награда с учётом множителей
-- ============================================================================
-- ЧТО ИСПРАВЛЯЕТСЯ
--
-- 010 починила сдачу квеста, но награда начислялась без множителей: при
-- integer * numeric ROUND() давал голый номинал квеста, хотя в ответе лежали
-- streak_multiplier и camp_*_bonus. Игрок получал меньше, чем задумано.
--
-- РЕШЕНИЕ
--
-- Оба множителя приводятся к numeric явно, формула считается как задумано:
--     earned = round(xp_reward::numeric * streak * (1 + camp_bonus))
-- В ответ добавлены базовые xp_reward/gold_reward — чтобы проверять награду
-- по явным числам, а не косвенно.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

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
    v_today DATE := NOW()::date;
    v_uid TEXT;
BEGIN
    v_uid := p_user_id::text;

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

    -- Квест обязан принадлежать цели этого игрока.
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

    -- Бонусы лагеря: единственный источник — camp_building_effects.
    SELECT b.gold_bonus, b.xp_bonus
      INTO v_camp_gold_bonus, v_camp_xp_bonus
      FROM public.camp_bonuses(v_profile.current_era::text, v_profile.camp_level) b;

    -- Все множители приводятся к numeric явно: иначе integer * numeric при
    -- округлении даёт неверный результат.
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

    IF v_profile.last_active_date IS DISTINCT FROM v_today THEN
        v_new_streak     := v_profile.streak_count + 1;
        v_new_multiplier := v_profile.streak_multiplier + 0.005;
    ELSE
        v_new_streak     := v_profile.streak_count;
        v_new_multiplier := v_profile.streak_multiplier;
    END IF;

    UPDATE quests
    SET is_completed = TRUE, completed_at = NOW()
    WHERE id::text = p_quest_id::text;

    UPDATE profiles
    SET xp                = v_profile.xp + v_earned_xp,
        gold              = v_profile.gold + v_earned_gold,
        energy            = v_new_energy,
        streak_count      = v_new_streak,
        streak_multiplier = v_new_multiplier,
        last_active_date  = v_today,
        is_decayed        = FALSE
    WHERE id::text = v_uid;

    RETURN jsonb_build_object(
        'success', true,
        -- Базовые значения для проверки формулы.
        'xp_reward', v_quest.xp_reward,
        'gold_reward', v_quest.gold_reward,
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

commit;

-- ============================================================================
-- Проверка: вызовите в SQL Editor (подставив свои id), затем сверьте формулу.
--   begin;
--     select set_config('request.jwt.claims',
--       '{"sub":"<ваш-uuid>","role":"authenticated"}', true);
--     select public.complete_quest_atomic('<ваш-uuid>'::uuid, '<quest-id>');
--   rollback;
--
--   earned_xp должен быть round(xp_reward * streak_multiplier * (1 + camp_xp_bonus)).
-- ============================================================================

-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 021: сдачу квеста нельзя вызвать за другого
-- ============================================================================
-- ЧТО НАШЛОСЬ (конечный тест приложения)
--
-- complete_quest_atomic принимает id игрока ПАРАМЕТРОМ и нигде не сверяет его
-- с auth.uid(). Все остальные функции проекта либо берут игрока из сессии,
-- либо, как redeem_promo_code, сравнивают параметр с auth.uid() и отказывают
-- при расхождении. Эта функция была исключением.
--
-- ЧЕМ ЭТО ГРОЗИТ
--
-- Вызвать функцию может любой зарегистрированный игрок (анонимно нельзя:
-- execute выдан только роли authenticated). Зная id другого игрока и id его
-- квеста, он может сдать квест за него: списать чужую энергию, отметить квест
-- выполненным, испортить серию. Награда при этом уйдёт владельцу, то есть это
-- вредительство, а не кража.
--
-- Насколько легко это провернуть: id игроков публичны (таблица profiles
-- читается по политике select using(true) — это нужно таблице лидеров), но
-- id квестов защищены RLS и чужим не видны. Поэтому на практике нужен
-- угаданный uuid квеста. Дыра всё равно настоящая: правило «действуй только
-- за себя» должно обеспечиваться сервером, а не тем, что id трудно угадать.
--
-- ЧТО ДЕЛАЕТ МИГРАЦИЯ
--
-- Добавляет проверку сессии. Клиент менять не нужно: он уже отправляет
-- p_user_id = supabase.auth.currentUser.id.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;
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

commit;

-- ============================================================================
-- ПРОВЕРКА
--
-- 1) Свой квест сдаётся как раньше (подставьте свои uuid и id квеста):
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<ваш-uuid>","role":"authenticated"}', true);
--   select public.complete_quest_atomic('<ваш-uuid>'::uuid, '<quest-id>');
-- rollback;
--
-- 2) За другого игрока — отказ:
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<ваш-uuid>","role":"authenticated"}', true);
--   select public.complete_quest_atomic('<чужой-uuid>'::uuid, '<любой-quest-id>');
-- rollback;
-- Ожидаемо: QUEST_UNAUTHORIZED.
-- ============================================================================
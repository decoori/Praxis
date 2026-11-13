-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 017: серверная проверка таймера фокуса
-- ============================================================================
-- ДЫРА, КОТОРУЮ ЭТО ЗАКРЫВАЕТ
--
-- Квест с таймером («25 минут непрерывной практики») можно было сдать мгновенно:
-- complete_quest_atomic не знала ни о какой длительности, а таймер шёл только
-- на клиенте. Достаточно было вызвать RPC прямым запросом — награда начислялась
-- сразу.
--
-- ПОЧЕМУ НЕЛЬЗЯ ПРОСТО ПЕРЕДАТЬ «СКОЛЬКО ПРОШЛО» С КЛИЕНТА
--
-- Клиент может прислать любое число. Проверка «пришло >= длительности» ничего
-- не даёт: подделанный клиент пришлёт нужное значение. Поэтому фиксируем время
-- старта НА СЕРВЕРЕ:
--
--   * start_focus_session(quest_id) — записывает момент старта и требуемое
--     время, возвращает идентификатор сессии;
--   * complete_quest_atomic(..., p_session_id) — для квестов с таймером требует
--     незавершённую сессию этого игрока по этому квесту и проверяет, что с
--     момента старта прошло не меньше требуемого времени.
--
-- ЧТО ЭТО ДАЁТ И ЧЕГО НЕ ДАЁТ
--
-- Закрывает: мгновенную сдачу квеста с таймером.
-- Не закрывает и не пытается: «сидеть и ничего не делать» нужное время. Это
-- то же самое, что сегодня делает добросовестный клиент, и измерение внимания
-- вне задачи этой миграции.
--
-- ВНИМАНИЕ, СОВМЕСТИМОСТЬ: после применения старые сборки приложения не смогут
-- сдавать квесты с таймером — они не начинают сессию и получат
-- QUEST_TIMER_NOT_STARTED. Приложение нужно пересобрать.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Таблица сессий фокуса
-- ---------------------------------------------------------------------------
create table if not exists public.focus_sessions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null,
  quest_id         uuid not null references public.quests (id) on delete cascade,
  started_at       timestamptz not null default now(),
  required_seconds integer not null,
  completed_at     timestamptz,

  constraint focus_sessions_required_positive check (required_seconds > 0)
);

create index if not exists focus_sessions_user_quest_idx
  on public.focus_sessions (user_id, quest_id);

-- Клиент к таблице доступа не имеет: и старт, и проверку делают функции.
alter table public.focus_sessions enable row level security;
drop policy if exists focus_sessions_no_client_access on public.focus_sessions;
create policy focus_sessions_no_client_access on public.focus_sessions
  for select using (false);

-- ---------------------------------------------------------------------------
-- 2. Старт сессии фокуса
-- ---------------------------------------------------------------------------
create or replace function public.start_focus_session(p_quest_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id  uuid;
  v_quest    quests%rowtype;
  v_required integer;
  v_started  timestamptz := now();
  v_id       uuid;
begin
  if auth.uid() is null then
    raise exception 'FOCUS_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  select q.* into v_quest
  from public.quests q
  join public.goals g on g.id::text = q.goal_id::text
  where q.id::text = p_quest_id::text
    and g.user_id = v_user_id;

  if not found then
    raise exception 'FOCUS_QUEST_NOT_FOUND' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_quest.is_completed, false) then
    raise exception 'FOCUS_QUEST_COMPLETED' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_quest.is_timer_based, false) is not true then
    raise exception 'FOCUS_NOT_TIMER_QUEST' using errcode = 'invalid_parameter_value';
  end if;

  v_required := greatest(coalesce(v_quest.timer_duration_minutes, 25), 1) * 60;

  -- Прежние незавершённые сессии по этому квесту убираем: активной может быть
  -- только одна, иначе игрок накопил бы «готовые» сессии заранее.
  delete from public.focus_sessions
   where user_id = v_user_id
     and quest_id = v_quest.id
     and completed_at is null;

  insert into public.focus_sessions (user_id, quest_id, started_at, required_seconds)
  values (v_user_id, v_quest.id, v_started, v_required)
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'session_id', v_id,
    'required_seconds', v_required,
    'started_at', v_started,
    'ready_at', v_started + make_interval(secs => v_required)
  );
end;
$$;

revoke all on function public.start_focus_session(text) from public, anon;
grant execute on function public.start_focus_session(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Сдача квеста с проверкой сессии
-- ---------------------------------------------------------------------------
-- Сигнатура меняется: добавляется p_session_id со значением по умолчанию,
-- чтобы уже собранные клиенты, которые его не передают, могли сдавать квесты
-- БЕЗ таймера. Старую двухпараметрическую версию удаляем явно — иначе в базе
-- остались бы две функции и PostgREST не смог бы выбрать нужную.
drop function if exists public.complete_quest_atomic(uuid, text);

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

        -- Главная проверка: с момента старта на сервере должно пройти
        -- требуемое время. Клиент не может ни подделать, ни сократить его.
        IF now() < v_session.started_at + make_interval(secs => v_session.required_seconds) THEN
            RAISE EXCEPTION 'QUEST_TIMER_NOT_ELAPSED';
        END IF;

        UPDATE public.focus_sessions
        SET completed_at = now()
        WHERE id = v_session.id;
    END IF;

    -- Бонусы лагеря: единственный источник — camp_building_effects.
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
-- Проверка (подставив свой uuid и id квеста с таймером).
--
-- 1) Сессия стартует, но сдать сразу нельзя:
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   select public.start_focus_session('<quest-id>');   -- вернёт session_id
--   select public.complete_quest_atomic('<uuid>'::uuid, '<quest-id>',
--          '<session_id>'::uuid);                      -- ожидаем QUEST_TIMER_NOT_ELAPSED
-- rollback;
--
-- 2) Без сессии квест с таймером не сдаётся:
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   select public.complete_quest_atomic('<uuid>'::uuid, '<quest-id>');
-- rollback;
-- Ожидаемо: QUEST_TIMER_NOT_STARTED.
--
-- 3) Квест БЕЗ таймера сдаётся как раньше, сессия не нужна.
-- ============================================================================

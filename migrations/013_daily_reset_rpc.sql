-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 013: суточный пересчёт на сервере
-- ============================================================================
-- ЧТО ЗАКРЫВАЕТСЯ
--
-- Самый важный из оставшихся прямых записей: клиент при каждой загрузке
-- пересчитывал энергию, щиты, стрик и флаг упадка и писал их в profiles
-- АБСОЛЮТНЫМИ значениями:
--     update profiles set energy = <с клиента>, shields_left = <с клиента>, ...
-- Через прямой запрос к API их можно было выставить любыми.
--
-- РЕШЕНИЕ
--
-- Вся логика перенесена в apply_daily_reset(). Функция идемпотентна: повторный
-- вызов в тот же день возвращает changed=false и ничего не меняет.
--
-- Логика повторяет прежнюю клиентскую ОДИН В ОДИН:
--   * энергии восстанавливается до максимума;
--   * при пропуске одного дня (daysDiff = 1) щиты и стрик не трогаются;
--   * при пропуске больше одного дня щиты списываются по одному за пропущенный
--     день; если щитов не хватило — стрик либо замораживается (is_decayed),
--     либо обнуляется, в зависимости от того, был ли он уже заморожен;
--   * якорь last_active_date сдвигается на «вчера», чтобы пропущенные дни
--     не посчитались дважды.
--
-- ЕДИНСТВЕННОЕ ОТСТУПЛЕНИЕ от прежнего кода: при shields_left = NULL клиент
-- подставлял 3 и записывал это как реальные щиты. Здесь NULL считается нулём —
-- чтобы не выдавать щиты за счёт пустого значения.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

create or replace function public.apply_daily_reset()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_profile profiles%rowtype;
  v_today   date := now()::date;
  v_last    date;
  v_days    integer;
  v_shields integer;
  v_streak  integer;
  v_mult    numeric;
  v_decayed boolean;
  v_anchor  date;
begin
  if auth.uid() is null then
    raise exception 'DAILY_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_user_id := auth.uid();

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then
    raise exception 'DAILY_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  v_last := v_profile.last_active_date;

  -- Даты ещё нет — пересчитывать нечего.
  if v_last is null then
    return jsonb_build_object('changed', false, 'reason', 'no_last_active_date');
  end if;

  v_days := v_today - v_last;

  -- Тот же день или дата в будущем — ничего не меняем.
  if v_days < 1 then
    return jsonb_build_object('changed', false, 'reason', 'same_day');
  end if;

  v_shields := coalesce(v_profile.shields_left, 0);
  v_streak  := coalesce(v_profile.streak_count, 0);
  v_mult    := coalesce(v_profile.streak_multiplier, 1.0);
  v_decayed := coalesce(v_profile.is_decayed, false);
  v_anchor  := v_last;

  if v_days > 1 then
    declare
      v_missed     integer := v_days - 1;
      v_unshielded integer;
    begin
      -- Якорь сдвигаем на «вчера»: сегодняшний день ещё может стать активным
      -- после сдачи квеста, а уже учтённые пропуски не должны считаться снова.
      v_anchor := v_today - 1;

      if v_shields >= v_missed then
        v_shields := v_shields - v_missed;
      else
        v_unshielded := v_missed - v_shields;
        v_shields := 0;

        if v_decayed then
          -- Был заморожен и снова пропуск: серия сгорает.
          v_streak  := 0;
          v_mult    := 1.0;
          v_decayed := false;
        elsif v_unshielded = 1 then
          -- Ровно один незакрытый день: серия замораживается.
          v_decayed := true;
        else
          v_streak  := 0;
          v_mult    := 1.0;
          v_decayed := false;
        end if;
      end if;
    end;
  end if;

  update public.profiles p
     set energy            = coalesce(p.max_energy, 5),
         shields_left      = v_shields,
         streak_count      = v_streak,
         streak_multiplier = v_mult,
         is_decayed        = v_decayed,
         last_active_date  = v_anchor
   where p.id = v_user_id
   returning p.gold, p.xp, p.energy, p.max_energy, coalesce(p.shields_left, 0),
             p.streak_count, p.streak_multiplier, p.is_decayed, p.last_active_date
   into v_profile.gold, v_profile.xp, v_profile.energy, v_profile.max_energy,
        v_profile.shields_left, v_profile.streak_count, v_profile.streak_multiplier,
        v_profile.is_decayed, v_anchor;

  return jsonb_build_object(
    'changed', true,
    'days_missed', v_days - 1,
    'gold', v_profile.gold,
    'xp', v_profile.xp,
    'energy', v_profile.energy,
    'max_energy', v_profile.max_energy,
    'shields_left', v_profile.shields_left,
    'streak_count', v_profile.streak_count,
    'streak_multiplier', v_profile.streak_multiplier,
    'is_decayed', v_profile.is_decayed,
    'last_active_date', v_anchor::text
  );
end;
$$;

revoke all on function public.apply_daily_reset() from public, anon;
grant execute on function public.apply_daily_reset() to authenticated;

commit;

-- ============================================================================
-- Проверка (подставив свои id). Каждый блок с rollback — данные не меняются.
--
-- 1) Пропуск ОДНОГО дня без щитов: серия замораживается (is_decayed = true).
--    last_active_date = сегодня − 2 → daysDiff = 2, незакрытых дней = 1.
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   update public.profiles
--      set last_active_date = now()::date - 2, shields_left = 0,
--          streak_count = 5, is_decayed = false
--    where id = '<uuid>';
--   select public.apply_daily_reset();
-- rollback;
--
-- 2) Пропуск ТРЁХ дней без щитов: серия обнуляется (is_decayed = false).
--    last_active_date = сегодня − 4 → daysDiff = 4, незакрытых дней = 3.
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   update public.profiles
--      set last_active_date = now()::date - 4, shields_left = 0,
--          streak_count = 5, is_decayed = false
--    where id = '<uuid>';
--   select public.apply_daily_reset();
-- rollback;
--
-- 3) Щитов хватает на все пропуски: серия сохраняется.
--    last_active_date = сегодня − 3, shields_left = 5 → спишется 2 щита.
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   update public.profiles
--      set last_active_date = now()::date - 3, shields_left = 5,
--          streak_count = 5, is_decayed = false
--    where id = '<uuid>';
--   select public.apply_daily_reset();
-- rollback;
--
-- 4) Идемпотентность: второй вызов в тот же день возвращает changed=false.
--    Сначала один вызов меняет состояние, второй — уже нет.
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   update public.profiles set last_active_date = now()::date - 2 where id = '<uuid>';
--   select public.apply_daily_reset();   -- changed: true
--   select public.apply_daily_reset();   -- changed: false, reason: same_day
-- rollback;
-- ============================================================================

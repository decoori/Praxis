-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 014: apply_daily_reset без лишних записей
-- ============================================================================
-- ЧТО ИСПРАВЛЯЕТСЯ
--
-- В 013 функция выполняла UPDATE профиля при каждом вызове, когда с даты якоря
-- прошёл хотя бы один день — даже если менять было нечего. Поскольку клиент
-- вызывает её при каждой загрузке игры, это давало запись в строку профиля
-- на каждый вход, плюс неверный флаг changed=true.
--
-- Прежняя формулировка в шапке 013 («повторный вызов в тот же день возвращает
-- changed=false») была неточной: для v_days = 1 повторный вызов возвращал
-- changed=true, потому что якорь намеренно остаётся на «вчера» до сдачи
-- квеста.
--
-- НОВОЕ ПОВЕДЕНИЕ
--
-- Значения сначала считаются, потом сравниваются с текущими. Если ничего не
-- изменилось — запись не выполняется, возвращается changed=false с причиной
-- 'nothing_to_change'. Логика начисления при этом не изменилась ни на шаг:
-- расход щитов, заморозка и обнуление серии, сдвиг якоря — как в 013.
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
  v_energy  integer;
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

  if v_last is null then
    return jsonb_build_object('changed', false, 'reason', 'no_last_active_date');
  end if;

  v_days := v_today - v_last;

  -- Будущая дата или уже сегодняшний якорь — пересчитывать нечего.
  if v_days < 1 then
    return jsonb_build_object('changed', false, 'reason', 'same_day');
  end if;

  -- Считаем новые значения, ничего пока не записывая.
  v_energy  := coalesce(v_profile.max_energy, 5);
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
          v_streak  := 0;
          v_mult    := 1.0;
          v_decayed := false;
        elsif v_unshielded = 1 then
          v_decayed := true;
        else
          v_streak  := 0;
          v_mult    := 1.0;
          v_decayed := false;
        end if;
      end if;
    end;
  end if;

  -- Ничего не изменилось — не пишем строку и честно сообщаем об этом.
  -- Сравнения null-безопасные: пустые значения не должны выглядеть как разница.
  if v_energy  is not distinct from v_profile.energy
     and v_shields is not distinct from coalesce(v_profile.shields_left, 0)
     and v_streak  is not distinct from coalesce(v_profile.streak_count, 0)
     and v_mult    is not distinct from coalesce(v_profile.streak_multiplier, 1.0)
     and v_decayed is not distinct from coalesce(v_profile.is_decayed, false)
     and v_anchor  is not distinct from v_profile.last_active_date
  then
    return jsonb_build_object(
      'changed', false,
      'reason', 'nothing_to_change',
      'gold', v_profile.gold,
      'xp', v_profile.xp,
      'energy', v_energy,
      'max_energy', coalesce(v_profile.max_energy, 5),
      'shields_left', v_shields,
      'streak_count', v_streak,
      'streak_multiplier', v_mult,
      'is_decayed', v_decayed,
      'last_active_date', v_anchor::text
    );
  end if;

  update public.profiles p
     set energy            = v_energy,
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
-- ПРОВЕРКА ИДЕМПОТЕНТНОСТИ: два вызова в одной транзакции, результат — одной
-- строкой, чтобы экспорт CSV не терял первый вызов.
--
-- 1) Создать диагностическую обёртку:
-- create or replace function public.diag_daily_reset()
-- returns jsonb language plpgsql security definer set search_path = public as $$
-- declare r1 jsonb; r2 jsonb;
-- begin
--   r1 := public.apply_daily_reset();
--   r2 := public.apply_daily_reset();
--   return jsonb_build_object('first', r1, 'second', r2);
-- end $$;
--
-- 2) Вызвать (данные не меняются благодаря rollback):
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   update public.profiles set last_active_date = now()::date - 3, shields_left = 0
--    where id = '<uuid>';
--   select public.diag_daily_reset();
-- rollback;
--
-- ОЖИДАЕМО: first.changed = true (сработал расход щитов и обнуление серии),
--          second.changed = false, second.reason = 'nothing_to_change'.
--
-- 3) Убрать обёртку: drop function if exists public.diag_daily_reset();
-- ============================================================================

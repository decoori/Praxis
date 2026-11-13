-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 016: evolve_era возвращает current_era
-- ============================================================================
-- ЧТО ИСПРАВЛЯЕТСЯ
--
-- В 012 функция возвращала новую эпоху под ключом 'era':
--     'era', v_expected
-- А клиент читает состояние профиля под ключом 'current_era' (см.
-- _applyServerState в game_controller.dart). Из-за несовпадения ключей после
-- эволюции применялись gold, xp, energy, max_energy и camp_level, но НЕ эпоха.
--
-- КАК ЭТО ВЫГЛЯДЕЛО ДЛЯ ИГРОКА
--
--   * нажал «СОВЕРШИТЬ ЭВОЛЮЦИЮ» — в базе всё прошло: эпоха сменилась,
--     лагерь сброшен на 1, начислен бонус золота;
--   * но интерфейс продолжал показывать старую эпоху и цены построек старой
--     эпохи;
--   * при попытке построить лагерь сервер считал цену уже для НОВОЙ эпохи
--     (в бронзовом веке первая постройка стоит 250 против 40 в каменном),
--     и игрок получал «недостаточно золота», имея на руках 230.
--
-- РЕШЕНИЕ
--
-- Возвращаем и 'current_era' (ключ, который читает клиент), и 'era' для
-- совместимости с уже собранными версиями приложения.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

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

  -- Следующая эпоха определяется порядком, а не значением от клиента.
  select era_id into v_expected
  from public.era_config
  where display_order = v_cur.display_order + 1;

  if v_expected is null then
    raise exception 'EVOLVE_MAX_ERA' using errcode = 'invalid_parameter_value';
  end if;

  if btrim(coalesce(p_next_era, '')) <> v_expected then
    raise exception 'EVOLVE_WRONG_ERA' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.xp, 0) < v_cur.xp_required then
    raise exception 'EVOLVE_NOT_ENOUGH_XP' using errcode = 'invalid_parameter_value';
  end if;

  if coalesce(v_profile.camp_level, 1) < 5 then
    raise exception 'EVOLVE_CAMP_NOT_READY' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_next
  from public.era_config
  where era_id = v_expected;

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
         energy      = v_new_max,
         camp_level  = 1
   where p.id = v_user_id
   returning p.xp, p.gold, p.energy, p.max_energy, p.camp_level, p.current_era
   into v_new_xp, v_new_gold, v_profile.energy, v_new_max, v_profile.camp_level, v_profile.current_era;

  return jsonb_build_object(
    'ok', true,
    -- Ключ, который читает клиент для обновления состояния профиля.
    'current_era', v_expected,
    -- Оставлен для совместимости с уже собранными версиями приложения.
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

commit;

-- ============================================================================
-- Проверка: в ответе должны быть оба ключа.
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   update public.profiles
--      set xp = 5000, camp_level = 5, current_era = 'stone_age', gold = 0
--    where id = '<uuid>';
--   select public.evolve_era('bronze_age');
-- rollback;
-- Ожидаемо: "current_era":"bronze_age" и "era":"bronze_age" в одном объекте.
-- ============================================================================

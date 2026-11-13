-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 020: в зачёт лиги идут только активные
-- ============================================================================
-- ЗАЧЕМ
--
-- Проверка на живых данных показала расхождение: список лиги показывал
-- призовое место игроку, которому награда не положена. У второго тестового
-- аккаунта 0 опыта за сезон, но он стоял на 1 месте — при подведении итогов
-- settle_league_season награждает только игроков с season_xp > 0, потому что
-- иначе золото за топ-3 получали бы те, кто в сезоне вообще не играл.
--
-- Теперь место в таблице получают только игроки с опытом за сезон — те же
-- самые, кого награждает settle_league_season. Остальные участники лиги
-- видны в списке, но с пустым местом: в новом сезоне таблица не выглядит
-- сломанной, и при этом никому не обещают награду, которой не будет.
--
-- Режим «Союзники» НЕ меняется: это сравнение с друзьями, а не призовая
-- таблица, там места есть у всех.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- Файл можно применять повторно: он только заменяет функцию.
-- ============================================================================

begin;
create or replace function public.get_league_leaderboard(p_mode text default 'league')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me      uuid;
  v_profile  public.profiles%rowtype;
  v_tier     public.league_tiers%rowtype;
  v_next     public.league_tiers%rowtype;
  v_season   public.league_seasons%rowtype;
  v_rows     jsonb;
  v_my_place integer;
  v_rewards  jsonb;
begin
  if auth.uid() is null then
    raise exception 'LEAGUE_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;
  v_me := auth.uid();

  select * into v_profile from public.profiles where id = v_me;
  if not found then
    raise exception 'LEAGUE_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_tier
  from public.league_tiers
  where id = public.league_tier_for_xp(v_profile.total_xp);

  select * into v_next
  from public.league_tiers
  where tier_order = v_tier.tier_order + 1;

  perform public.open_league_season();

  select * into v_season
  from public.league_seasons
  where settled_at is null
  order by started_at desc
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.place), '[]'::jsonb)
    into v_rewards
  from (select place, gold from public.league_rewards order by place) r;

  if lower(coalesce(p_mode, 'league')) = 'friends' then
    -- ВНИМАНИЕ ПРО ТИПЫ: friendships.user_id и friend_id — это text, а auth.uid()
    -- возвращает uuid. Без явного приведения UNION и JOIN падают с ошибкой
    -- «UNION types text and uuid cannot be matched».
    with circle as (
      select f.friend_id as id
      from public.friendships f
      where f.user_id = v_me::text
      union
      select v_me::text
    ),
    ranked as (
      select p.id,
             p.username,
             p.user_tag,
             p.current_era::text as current_era,
             coalesce(p.streak_count, 0) as streak_count,
             p.avatar_id,
             coalesce(p.season_xp, 0) as season_xp,
             coalesce(p.total_xp, 0) as total_xp,
             row_number() over (order by coalesce(p.season_xp, 0) desc, p.id) as place
      from public.profiles p
      join circle c on c.id = p.id::text
    )
    select coalesce(jsonb_agg(to_jsonb(r) order by r.place), '[]'::jsonb),
           max(r.place) filter (where r.id = v_me)
      into v_rows, v_my_place
    from ranked r;
  else
    with ranked as (
      select p.id,
             p.username,
             p.user_tag,
             p.current_era::text as current_era,
             coalesce(p.streak_count, 0) as streak_count,
             p.avatar_id,
             coalesce(p.season_xp, 0) as season_xp,
             coalesce(p.total_xp, 0) as total_xp,
             -- Место получают только те, кто набрал опыт за сезон: ровно их
             -- награждает settle_league_season. У остальных место NULL.
             --
             -- Так список лиги никогда не бывает пустым (в новом сезоне
             -- видно, с кем соревнуешься), но и не обещает призовое место
             -- тому, кому золото не придёт.
             --
             -- partition by нужен, чтобы номера шли подряд только среди
             -- набравших опыт: без него игрок с нулём «съедал» бы номер
             -- и следующее место оказывалось бы 3 вместо 2.
             case when coalesce(p.season_xp, 0) > 0
                  then row_number() over (
                         partition by (coalesce(p.season_xp, 0) > 0)
                         order by coalesce(p.season_xp, 0) desc, p.id
                       )
                  else null
             end as place
      from public.profiles p
      where public.league_tier_for_xp(p.total_xp) = v_tier.id
    ),
    top_rows as (
      select * from ranked
      order by place nulls last, total_xp desc, id
      limit 50
    )
    select coalesce(
             jsonb_agg(to_jsonb(t) order by t.place nulls last, t.total_xp desc, t.id),
             '[]'::jsonb
           ),
           (select r.place from ranked r where r.id = v_me)
      into v_rows, v_my_place
    from top_rows t;
  end if;

  return jsonb_build_object(
    'ok', true,
    'mode', case when lower(coalesce(p_mode, 'league')) = 'friends' then 'friends' else 'league' end,
    'tier', jsonb_build_object(
      'id', v_tier.id,
      'name', v_tier.name,
      'tier_order', v_tier.tier_order,
      'min_total_xp', v_tier.min_total_xp
    ),
    'next_tier', case when v_next.id is null then null else jsonb_build_object(
      'name', v_next.name,
      'min_total_xp', v_next.min_total_xp
    ) end,
    'season_ends_at', v_season.ends_at,
    'rewards', v_rewards,
    'me', jsonb_build_object(
      'place', coalesce(v_my_place, 0),
      'season_xp', coalesce(v_profile.season_xp, 0),
      'total_xp', coalesce(v_profile.total_xp, 0)
    ),
    'rows', v_rows
  );
end;
$$;
revoke all on function public.get_league_leaderboard(text) from public, anon;
grant execute on function public.get_league_leaderboard(text) to authenticated;

commit;

-- ============================================================================
-- ПРОВЕРКА (блок с rollback — данные не меняются).
--
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   select jsonb_pretty(public.get_league_leaderboard('league'));
-- rollback;
-- Ожидаемо: в rows только игроки с season_xp > 0; me.place = 0, если у вас
-- ещё нет опыта за сезон.
-- ============================================================================
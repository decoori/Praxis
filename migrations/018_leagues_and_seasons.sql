-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 018: лиги, сезоны и награды за топ-3
-- ============================================================================
-- ЧТО ДЕЛАЕТ
--
-- Система рейтинга становится похожей на дуолинговскую:
--   * лига определяется накопленным опытом (league_tiers, пороги по total_xp);
--   * внутри своей лиги игроки соревнуются по опыту, набранному ЗА СЕЗОН;
--   * по итогам сезона (7 дней) топ-3 каждой лиги получают золото по месту;
--   * итоги подводятся при заходе игрока (settle_league_season), а не по
--     расписанию — расширение pg_cron не требуется.
--
-- ПОЧЕМУ ПОНАДОБИЛСЯ total_xp
--
-- Рейтинг сортировался по profiles.xp, но этот счётчик ТРАТИТСЯ на эволюцию
-- (xp = xp − порог эпохи). Получалось, что развивающийся игрок падает в
-- рейтинге ниже того, кто копит опыт и не эволюционирует. Поэтому введены:
--   * total_xp  — опыт за всё время, только растёт;
--   * season_xp — опыт за текущий сезон, сбрасывается при подведении итогов.
--
-- ОГРАНИЧЕНИЕ БЭКФИЛЛА: прошлый опыт восстановить нельзя — он нигде не
-- хранился отдельно от потраченного. Поэтому total_xp проставляется равным
-- текущему xp, то есть у тех, кто уже эволюционировал, история начинается
-- с текущего значения.
--
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Счётчики опыта
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists total_xp  integer not null default 0;
alter table public.profiles add column if not exists season_xp integer not null default 0;

-- Бэкфилл только для тех, у кого счётчик ещё пуст.
update public.profiles
   set total_xp = greatest(coalesce(xp, 0), 0)
 where coalesce(total_xp, 0) = 0
   and coalesce(xp, 0) > 0;

-- ---------------------------------------------------------------------------
-- 2. Справочник лиг: порог по опыту за всё время
-- ---------------------------------------------------------------------------
create table if not exists public.league_tiers (
  id           text primary key,
  tier_order   integer not null unique,
  name         text not null,
  min_total_xp integer not null,

  constraint league_tiers_min_non_negative check (min_total_xp >= 0)
);

insert into public.league_tiers (id, tier_order, name, min_total_xp)
values
  ('bronze',   1, 'Бронзовая лига',    0),
  ('silver',   2, 'Серебряная лига',   1000),
  ('gold',     3, 'Золотая лига',      2500),
  ('platinum', 4, 'Платиновая лига',   5000),
  ('emerald',  5, 'Изумрудная лига',   10000),
  ('diamond',  6, 'Алмазная лига',     20000)
on conflict (id) do update set
  tier_order   = excluded.tier_order,
  name         = excluded.name,
  min_total_xp = excluded.min_total_xp;

-- ---------------------------------------------------------------------------
-- 3. Награды за места
-- ---------------------------------------------------------------------------
create table if not exists public.league_rewards (
  place integer primary key,
  gold  integer not null,

  constraint league_rewards_place check (place between 1 and 3),
  constraint league_rewards_gold_positive check (gold > 0)
);

insert into public.league_rewards (place, gold)
values (1, 300), (2, 200), (3, 100)
on conflict (place) do update set gold = excluded.gold;

-- ---------------------------------------------------------------------------
-- 4. Сезоны и начисления
-- ---------------------------------------------------------------------------
create table if not exists public.league_seasons (
  id         uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  ends_at    timestamptz not null,
  settled_at timestamptz,

  constraint league_seasons_range check (ends_at > started_at)
);

create index if not exists league_seasons_open_idx
  on public.league_seasons (ends_at)
  where settled_at is null;

create table if not exists public.league_awards (
  id          uuid primary key default gen_random_uuid(),
  season_id   uuid not null references public.league_seasons (id) on delete cascade,
  user_id     uuid not null,
  tier_id     text not null,
  place       integer not null,
  gold        integer not null,
  awarded_at  timestamptz not null default now(),
  -- Когда игрок увидел уведомление о награде.
  notified_at timestamptz,

  -- Награда за сезон начисляется один раз: защита от повторного подведения.
  constraint league_awards_unique unique (season_id, user_id)
);

-- Справочники баланса и служебные таблицы клиенту читать не нужно:
-- всё приходит через функции ниже.
alter table public.league_tiers    enable row level security;
alter table public.league_rewards  enable row level security;
alter table public.league_seasons  enable row level security;
alter table public.league_awards   enable row level security;

drop policy if exists league_tiers_no_client   on public.league_tiers;
create policy league_tiers_no_client   on public.league_tiers   for select using (false);
drop policy if exists league_rewards_no_client on public.league_rewards;
create policy league_rewards_no_client on public.league_rewards for select using (false);
drop policy if exists league_seasons_no_client on public.league_seasons;
create policy league_seasons_no_client on public.league_seasons for select using (false);
drop policy if exists league_awards_no_client  on public.league_awards;
create policy league_awards_no_client  on public.league_awards  for select using (false);

-- ---------------------------------------------------------------------------
-- 5. Вспомогательные функции
-- ---------------------------------------------------------------------------
create or replace function public.league_tier_for_xp(p_total_xp integer)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select t.id
  from public.league_tiers t
  where t.min_total_xp <= greatest(coalesce(p_total_xp, 0), 0)
  order by t.min_total_xp desc
  limit 1;
$$;

-- Открытый сезон: если его нет — создаём на 7 дней.
create or replace function public.open_league_season()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select s.id into v_id
  from public.league_seasons s
  where s.settled_at is null
  order by s.started_at desc
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.league_seasons (started_at, ends_at)
  values (now(), now() + interval '7 days')
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Подведение итогов сезона (вызывается при заходе игрока)
-- ---------------------------------------------------------------------------
-- Функция идемпотентна: сезон помечается settled_at, а начисления защищены
-- уникальностью (season_id, user_id). Повторный вызов ничего не начислит.
--
-- Награды получает топ-3 КАЖДОЙ лиги — так у игроков нижних лиг тоже есть
-- за что соревноваться, как в Duolingo.
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
      select r.user_id, r.tier_id, r.place, lr.gold
      from ranked r
      join public.league_rewards lr on lr.place = r.place
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

revoke all on function public.settle_league_season() from public, anon;
grant execute on function public.settle_league_season() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Таблица лиги для интерфейса
-- ---------------------------------------------------------------------------
-- Возвращает всё, что нужно вкладке «Рейтинг»: мою лигу, границу следующей,
-- конец сезона, награды и список игроков моей лиги по сезонному опыту.
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
             row_number() over (order by coalesce(p.season_xp, 0) desc, p.id) as place
      from public.profiles p
      where public.league_tier_for_xp(p.total_xp) = v_tier.id
    ),
    top_rows as (
      select * from ranked order by place limit 50
    )
    select coalesce(jsonb_agg(to_jsonb(t) order by t.place), '[]'::jsonb),
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

-- ---------------------------------------------------------------------------
-- 8. Сдача квеста начисляет и счётчики лиг
-- ---------------------------------------------------------------------------
-- Единственное отличие от версии 017 — total_xp и season_xp в UPDATE и в
-- ответе. Логика награды, проверка владельца и сессия фокуса не менялись.
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
-- ПРОВЕРКА (каждый блок с rollback — данные не меняются).
--
-- 1) Справочники:
--   select * from public.league_tiers order by tier_order;   -- 6 лиг
--   select * from public.league_rewards order by place;      -- 3 награды
--   select public.league_tier_for_xp(0), public.league_tier_for_xp(1500);
--      -- bronze, silver
--
-- 2) Подведение итогов вручную: создаём просроченный сезон и сезонный опыт.
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   -- Открытый сезон обязан существовать: иначе просрочивать будет нечего
--   -- и функция честно вернёт settled_seasons = 0.
--   select public.open_league_season();
--   -- Двигаем И начало, И конец: если отодвинуть только конец, сработает
--   -- check (ends_at > started_at) — конец окажется раньше начала.
--   update public.league_seasons
--      set started_at = now() - interval '8 days',
--          ends_at    = now() - interval '1 hour'
--    where settled_at is null;
--   update public.profiles set season_xp = 500 where id = '<uuid>';
--   select public.settle_league_season();
--   select place, gold, tier_id from public.league_awards where user_id = '<uuid>';
--   select gold, season_xp, total_xp from public.profiles where id = '<uuid>';
-- rollback;
-- Ожидаемо: своя награда (place 1, gold 300), season_xp = 0, золото выросло.
--
-- 3) Таблица лиги:
-- begin;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   select jsonb_pretty(public.get_league_leaderboard('league'));
-- rollback;
-- ============================================================================

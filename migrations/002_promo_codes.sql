-- ============================================================================
-- PRAXIS / game_of_aim_app — миграция 002: система промокодов
-- ============================================================================
-- Применение: Supabase Dashboard → SQL Editor → вставить файл целиком → Run.
-- Зависит от миграции 001 (профиль игрока и его RLS-политики).
--
-- ВАЖНО про типы: в этой базе идентификаторы игрока в клиентских таблицах
-- хранятся как text (`friendships.user_id`, `preset_votes.user_id`), а
-- `auth.uid()` возвращает uuid. Поэтому здесь `promo_redemptions.user_id`
-- объявлен как text, и функция нормализует аргумент в text. Сравнение идёт
-- как `p_user_id = auth.uid()::text`. Внешнего ключа на auth.users нет —
-- так же, как в остальных таблицах базы.
--
-- Что даёт:
--   * таблица промокодов с наградами (золото, XP, энергия, щиты);
--   * таблица погашений — один код нельзя активировать дважды одним игроком;
--   * атомарная выдача награды в БД: накрутить код повторным запросом,
--     обойти лимиты или обнулить прогресс нельзя;
--   * награды и лимиты применяются на сервере, клиент только показывает итог.
--
-- Как создать код (пример):
--   insert into public.promo_codes (label, gold, xp, energy, shields, max_redemptions)
--   values ('praxis2026', 500, 100, 3, 1, 100);
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Таблицы
-- ---------------------------------------------------------------------------
create table if not exists public.promo_codes (
  id               uuid primary key default gen_random_uuid(),
  -- Именно это значение вводит игрок. Регистр не важен: храним в нижнем.
  label            text not null,
  description      text,
  gold             integer not null default 0,
  xp               integer not null default 0,
  energy           integer not null default 0,
  shields          integer not null default 0,
  -- Лимиты. null = без ограничения.
  max_redemptions  integer,
  max_per_user     integer not null default 1,
  redeemed_count   integer not null default 0,
  starts_at        timestamptz,
  expires_at       timestamptz,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),

  constraint promo_codes_label_lower   check (label = lower(label)),
  constraint promo_codes_label_format  check (label ~ '^[a-z0-9_-]{3,32}$'),
  constraint promo_codes_non_negative  check (
    gold >= 0 and xp >= 0 and energy >= 0 and shields >= 0
    and coalesce(max_redemptions, 0) >= 0
    and max_per_user >= 1
    and redeemed_count >= 0
  ),
  constraint promo_codes_has_reward    check (gold > 0 or xp > 0 or energy > 0 or shields > 0),
  constraint promo_codes_window        check (expires_at is null or starts_at is null or expires_at > starts_at)
);

create unique index if not exists promo_codes_label_key
  on public.promo_codes (label);

create table if not exists public.promo_redemptions (
  id          uuid primary key default gen_random_uuid(),
  code_id     uuid not null references public.promo_codes (id) on delete cascade,
  -- text, как и идентификаторы в остальных клиентских таблицах проекта.
  user_id     text not null,
  gold        integer not null default 0,
  xp          integer not null default 0,
  energy      integer not null default 0,
  shields     integer not null default 0,
  redeemed_at timestamptz not null default now()
);

-- Авторитетная защита от повторной активации: гонка двух запросов
-- упирается в уникальный индекс, а не в проверку в коде.
create unique index if not exists promo_redemptions_code_user_key
  on public.promo_redemptions (code_id, user_id);

create index if not exists promo_redemptions_user_idx
  on public.promo_redemptions (user_id, redeemed_at desc);

-- ---------------------------------------------------------------------------
-- 2. RLS: игрок видит только свои погашения и не может их подделать
-- ---------------------------------------------------------------------------
alter table public.promo_codes enable row level security;
alter table public.promo_redemptions enable row level security;

-- Список кодов игроку не нужен: ввод идёт по значению, подбор запрещён.
drop policy if exists promo_codes_no_client_access on public.promo_codes;
create policy promo_codes_no_client_access on public.promo_codes
  for select using (false);

-- Свои активации видны; вставлять и менять их клиент не может —
-- записи создаёт только функция redeem_promo_code (security definer).
drop policy if exists promo_redemptions_select_self on public.promo_redemptions;
create policy promo_redemptions_select_self on public.promo_redemptions
  for select using (user_id = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- 3. Атомарная активация кода
-- ---------------------------------------------------------------------------
-- ВАЖНО: функция требует авторизации, поэтому p_user_id обязан совпадать с
-- текущим игроком. Без этой проверки любой мог бы начислить награды чужому
-- аккаунту, зная только его id.
create or replace function public.redeem_promo_code(
  p_user_id text,
  p_label text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label       text;
  v_uid         text;
  v_code        public.promo_codes%rowtype;
  v_max_energy  integer;
  v_energy      integer;
  v_shields     integer;
  v_used        integer;
  v_energy_add  integer := 0;
  v_shields_add integer := 0;
  -- Итоговые значения профиля после начисления. Отдельные переменные нужны,
  -- чтобы не переиспользовать v_energy/v_shields и не путать «до» и «после».
  v_new_gold       integer := 0;
  v_new_xp         integer := 0;
  v_new_energy     integer := 0;
  v_new_max_energy integer := 0;
  v_new_shields    integer := 0;
begin
  -- 1. Игрок должен быть авторизован.
  if auth.uid() is null then
    raise exception 'PROMO_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;

  v_uid := auth.uid()::text;

  if p_user_id is null or btrim(p_user_id) <> v_uid then
    raise exception 'PROMO_UNAUTHORIZED' using errcode = 'insufficient_privilege';
  end if;

  -- 2. Нормализация ввода. upper() для ASCII-кода безопаснее lower():
  --    некоторые локали складывают регистр нестандартно.
  v_label := upper(btrim(coalesce(p_label, '')));
  if v_label = '' then
    raise exception 'PROMO_EMPTY' using errcode = 'invalid_parameter_value';
  end if;

  -- 3. Код ищем только по значению. Отдельные сообщения «не найден» и
  --    «отключён» не раскрываем: это позволило бы перебирать базу кодов.
  select * into v_code
  from public.promo_codes c
  where upper(c.label) = v_label
  for update;

  if not found then
    raise exception 'PROMO_INVALID' using errcode = 'invalid_parameter_value';
  end if;

  if not v_code.is_active then
    raise exception 'PROMO_INVALID' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.starts_at is not null and now() < v_code.starts_at then
    raise exception 'PROMO_NOT_STARTED' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.expires_at is not null and now() > v_code.expires_at then
    raise exception 'PROMO_EXPIRED' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.max_redemptions is not null
     and v_code.redeemed_count >= v_code.max_redemptions then
    raise exception 'PROMO_EXHAUSTED' using errcode = 'invalid_parameter_value';
  end if;

  -- 4. Сколько раз этот игрок уже активировал код.
  select count(*) into v_used
  from public.promo_redemptions r
  where r.code_id = v_code.id and r.user_id = v_uid;

  if v_used >= v_code.max_per_user then
    raise exception 'PROMO_ALREADY_USED' using errcode = 'invalid_parameter_value';
  end if;

  -- 5. Награды клампятся теми же правилами, что и магазин:
  --    энергия не выше максимума, щиты не выше 5. Иначе игрок копил бы
  --    энергию промокодами в обход магазина.
  select max_energy, energy, coalesce(shields_left, 0)
    into v_max_energy, v_energy, v_shields
  from public.profiles
  where id::text = v_uid
  for update;

  if not found then
    raise exception 'PROMO_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  if v_code.energy > 0 then
    v_energy_add := greatest(0, least(v_code.energy, v_max_energy - v_energy));
  end if;

  if v_code.shields > 0 then
    v_shields_add := greatest(0, least(v_code.shields, 5 - v_shields));
  end if;

  -- 6. Фиксируем погашение. Уникальный индекс (code_id, user_id) здесь
  --    работает как последний рубеж защиты от гонки.
  begin
    insert into public.promo_redemptions (code_id, user_id, gold, xp, energy, shields)
    values (v_code.id, v_uid, v_code.gold, v_code.xp, v_energy_add, v_shields_add);
  exception
    when unique_violation then
      raise exception 'PROMO_ALREADY_USED' using errcode = 'invalid_parameter_value';
  end;

  -- 7. Начисляем награды.
  update public.profiles p
     set gold         = coalesce(p.gold, 0) + v_code.gold,
         xp           = coalesce(p.xp, 0) + v_code.xp,
         energy       = least(coalesce(p.max_energy, 5), v_energy + v_energy_add),
         shields_left = least(5, v_shields + v_shields_add)
   where p.id::text = v_uid
   returning p.gold, p.xp, p.energy, p.max_energy, coalesce(p.shields_left, 0)
   into v_new_gold, v_new_xp, v_new_energy, v_new_max_energy, v_new_shields;

  -- Профиль блокировался выше через FOR UPDATE, поэтому сюда попасть нельзя.
  if not found then
    raise exception 'PROMO_NO_PROFILE' using errcode = 'invalid_parameter_value';
  end if;

  -- 8. Счётчик активаций кода (строка уже заблокирована через FOR UPDATE).
  update public.promo_codes c
     set redeemed_count = c.redeemed_count + 1
   where c.id = v_code.id;

  return jsonb_build_object(
    'ok', true,
    'code', v_code.label,
    'title', coalesce(v_code.description, v_code.label),
    'gold_added', v_code.gold,
    'xp_added', v_code.xp,
    'energy_added', v_energy_add,
    'shields_added', v_shields_add,
    'gold', v_new_gold,
    'xp', v_new_xp,
    'energy', v_new_energy,
    'max_energy', v_new_max_energy,
    'shields_left', v_new_shields
  );
end;
$$;

revoke all on function public.redeem_promo_code(text, text) from public;
grant execute on function public.redeem_promo_code(text, text) to authenticated;

commit;

-- ============================================================================
-- Проверка после применения:
--   -- код на 500 золота и 3 энергии, 3 активации, каждому игроку по одному разу
--   insert into public.promo_codes (label, description, gold, energy, max_redemptions)
--   values ('praxis2026', 'Стартовый набор', 500, 3, 3);
--
--   -- повторная активация тем же игроком должна вернуть PROMO_ALREADY_USED:
--   select public.redeem_promo_code(auth.uid()::text, 'PRAXIS2026');
-- ============================================================================

-- ============================================================================
-- World Cup Office Predictor 2026 — Schema
-- Supabase project: knodunjnsxelmpziupwk (supabase-amber-ball, eu-west-2)
--
-- Run this once in the Supabase SQL editor.
-- Then run seed.sql to populate teams + demo data.
-- ============================================================================

-- --------------------------------------------------------------------------
-- Extensions
-- --------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- --------------------------------------------------------------------------
-- Drop in reverse order (safe re-run)
-- --------------------------------------------------------------------------
drop view if exists public.leaderboard cascade;
drop function if exists public.recalc_match(uuid) cascade;
drop function if exists public.recalc_all_matches() cascade;
drop function if exists public.recalc_bracket() cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.is_match_locked(uuid) cascade;
drop function if exists public.is_bracket_locked() cascade;

drop table if exists public.bracket_actuals cascade;
drop table if exists public.bracket_picks cascade;
drop table if exists public.predictions cascade;
drop table if exists public.matches cascade;
drop table if exists public.teams cascade;
drop table if exists public.settings cascade;
drop table if exists public.profiles cascade;

-- --------------------------------------------------------------------------
-- profiles  (one row per auth.users row)
-- --------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text unique not null check (length(username) between 2 and 24),
  display_name  text not null,
  is_admin      boolean not null default false,
  initials      text generated always as (upper(substring(regexp_replace(display_name, '[^A-Za-z ]', '', 'g'), 1, 1)) ||
                                          coalesce(upper(substring(split_part(display_name, ' ', 2), 1, 1)), '')) stored,
  avatar_colour text not null default '#22c55e',
  created_at    timestamptz not null default now()
);

create index profiles_username_idx on public.profiles (username);

-- --------------------------------------------------------------------------
-- settings  (singleton-style key/value)
-- --------------------------------------------------------------------------
create table public.settings (
  key   text primary key,
  value jsonb not null
);

insert into public.settings(key, value) values
  ('tournament_name', '"World Cup 2026"'),
  ('bracket_locked_at', 'null'),         -- ISO timestamp once group stage starts
  ('tournament_started', 'false');

-- --------------------------------------------------------------------------
-- teams
-- --------------------------------------------------------------------------
create table public.teams (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null check (length(code) = 3),
  name        text not null,
  group_code  text not null check (group_code in ('A','B','C','D','E','F','G','H','I','J','K','L')),
  flag_emoji  text not null default '⚽',
  seed_rank   int  not null default 99
);

create index teams_group_idx on public.teams (group_code);

-- --------------------------------------------------------------------------
-- matches
-- --------------------------------------------------------------------------
create table public.matches (
  id           uuid primary key default gen_random_uuid(),
  match_no     int  unique not null,                       -- official match number 1..104
  round        text not null check (round in ('group','r32','r16','qf','sf','final','3rd')),
  group_code   text check (group_code in ('A','B','C','D','E','F','G','H','I','J','K','L') or group_code is null),
  home_team_id uuid references public.teams(id) on delete set null,
  away_team_id uuid references public.teams(id) on delete set null,
  kickoff_at   timestamptz not null,
  home_score   int,
  away_score   int,
  status       text not null default 'scheduled' check (status in ('scheduled','locked','final')),
  bracket_slot text,                                       -- e.g. 'R32-1' for knockout pairing
  notes        text
);

create index matches_kickoff_idx on public.matches (kickoff_at);
create index matches_round_idx   on public.matches (round);

-- --------------------------------------------------------------------------
-- predictions  (one per player per match)
-- --------------------------------------------------------------------------
create table public.predictions (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references public.profiles(id) on delete cascade,
  match_id    uuid not null references public.matches(id) on delete cascade,
  home_score  int  not null check (home_score between 0 and 20),
  away_score  int  not null check (away_score between 0 and 20),
  points      int  not null default 0,
  exact_hit   boolean not null default false,
  result_hit  boolean not null default false,
  updated_at  timestamptz not null default now(),
  unique (player_id, match_id)
);

create index predictions_player_idx on public.predictions (player_id);
create index predictions_match_idx  on public.predictions (match_id);

-- --------------------------------------------------------------------------
-- bracket_picks  (player's predicted teams per knockout stage)
-- --------------------------------------------------------------------------
create table public.bracket_picks (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.profiles(id) on delete cascade,
  round      text not null check (round in ('r32','r16','qf','sf','final','winner')),
  team_id    uuid not null references public.teams(id) on delete cascade,
  points     int  not null default 0,
  created_at timestamptz not null default now(),
  unique (player_id, round, team_id)
);

create index bracket_picks_player_idx on public.bracket_picks (player_id);

-- --------------------------------------------------------------------------
-- bracket_actuals  (admin marks who actually reached each round)
-- --------------------------------------------------------------------------
create table public.bracket_actuals (
  round        text not null check (round in ('r32','r16','qf','sf','final','winner')),
  team_id      uuid not null references public.teams(id) on delete cascade,
  confirmed_at timestamptz not null default now(),
  primary key (round, team_id)
);

-- ============================================================================
-- Helper functions
-- ============================================================================

-- is the current auth user an admin?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- is a given match past its kickoff (and therefore locked)?
create or replace function public.is_match_locked(p_match_id uuid)
returns boolean
language sql
stable
as $$
  select coalesce(
    (select status = 'final' or status = 'locked' or kickoff_at <= now()
       from public.matches where id = p_match_id),
    true);
$$;

-- is bracket entry locked (tournament has started)?
create or replace function public.is_bracket_locked()
returns boolean
language sql
stable
as $$
  select coalesce(
    (select (value)::text::boolean from public.settings where key = 'tournament_started'),
    false);
$$;

-- ============================================================================
-- Scoring engine
-- ============================================================================

-- Recalculate points for a single match's predictions.
-- Exact score = 3 pts.  Correct result (W/D/L) only = 1 pt.  Wrong = 0.
create or replace function public.recalc_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
begin
  select home_score, away_score, status into m from public.matches where id = p_match_id;
  if m.home_score is null or m.away_score is null then
    update public.predictions
      set points = 0, exact_hit = false, result_hit = false
      where match_id = p_match_id;
    return;
  end if;

  update public.predictions p set
    exact_hit  = (p.home_score = m.home_score and p.away_score = m.away_score),
    result_hit = (
      (p.home_score > p.away_score and m.home_score > m.away_score) or
      (p.home_score < p.away_score and m.home_score < m.away_score) or
      (p.home_score = p.away_score and m.home_score = m.away_score)
    ),
    points = case
      when (p.home_score = m.home_score and p.away_score = m.away_score) then 3
      when (
        (p.home_score > p.away_score and m.home_score > m.away_score) or
        (p.home_score < p.away_score and m.home_score < m.away_score) or
        (p.home_score = p.away_score and m.home_score = m.away_score)
      ) then 1
      else 0
    end,
    updated_at = now()
  where p.match_id = p_match_id;
end;
$$;

create or replace function public.recalc_all_matches()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in select id from public.matches where home_score is not null and away_score is not null loop
    perform public.recalc_match(r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Recalculate every bracket_pick from current bracket_actuals
-- Award 1 pt per round per correct team reached.
create or replace function public.recalc_bracket()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  update public.bracket_picks bp set points = 0;
  update public.bracket_picks bp set points = 1
    where exists (select 1 from public.bracket_actuals ba
                   where ba.round = bp.round and ba.team_id = bp.team_id);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ============================================================================
-- Leaderboard view
-- ============================================================================
create or replace view public.leaderboard as
with match_stats as (
  select
    pr.player_id,
    coalesce(sum(pr.points), 0)                    as match_points,
    coalesce(sum(case when pr.exact_hit then 1 else 0 end), 0)  as exact_scores,
    coalesce(sum(case when pr.result_hit then 1 else 0 end), 0) as correct_results
  from public.predictions pr
  join public.matches m on m.id = pr.match_id and m.status = 'final'
  group by pr.player_id
),
bracket_stats as (
  select bp.player_id, coalesce(sum(bp.points), 0) as bracket_points
  from public.bracket_picks bp group by bp.player_id
)
select
  p.id,
  p.username,
  p.display_name,
  p.initials,
  p.avatar_colour,
  coalesce(ms.match_points,    0) as match_points,
  coalesce(ms.exact_scores,    0) as exact_scores,
  coalesce(ms.correct_results, 0) as correct_results,
  coalesce(bs.bracket_points,  0) as bracket_points,
  coalesce(ms.match_points, 0) + coalesce(bs.bracket_points, 0) as total_points,
  rank() over (
    order by
      coalesce(ms.match_points, 0) + coalesce(bs.bracket_points, 0) desc,
      coalesce(ms.exact_scores, 0)    desc,
      coalesce(ms.correct_results, 0) desc,
      coalesce(bs.bracket_points, 0)  desc
  ) as rank
from public.profiles p
left join match_stats   ms on ms.player_id = p.id
left join bracket_stats bs on bs.player_id = p.id
where p.is_admin = false;

-- ============================================================================
-- Row Level Security
-- ============================================================================

alter table public.profiles        enable row level security;
alter table public.teams           enable row level security;
alter table public.matches         enable row level security;
alter table public.predictions     enable row level security;
alter table public.bracket_picks   enable row level security;
alter table public.bracket_actuals enable row level security;
alter table public.settings        enable row level security;

-- profiles: everyone sees usernames + display names (needed for leaderboard);
-- only the user can update their own profile; only admins can write any.
create policy profiles_read on public.profiles for select using (true);
create policy profiles_update_self on public.profiles for update using (id = auth.uid());
create policy profiles_admin_all   on public.profiles for all   using (public.is_admin()) with check (public.is_admin());

-- teams, matches, bracket_actuals, settings: read = all; write = admin only.
create policy teams_read   on public.teams   for select using (true);
create policy teams_admin  on public.teams   for all using (public.is_admin()) with check (public.is_admin());

create policy matches_read  on public.matches for select using (true);
create policy matches_admin on public.matches for all using (public.is_admin()) with check (public.is_admin());

create policy ba_read  on public.bracket_actuals for select using (true);
create policy ba_admin on public.bracket_actuals for all using (public.is_admin()) with check (public.is_admin());

create policy settings_read  on public.settings for select using (true);
create policy settings_admin on public.settings for all using (public.is_admin()) with check (public.is_admin());

-- predictions: any signed-in user reads all (so leaderboards/profile views work);
-- but write only own + only when match not locked.
create policy predictions_read on public.predictions for select using (auth.role() = 'authenticated');

create policy predictions_insert_self
  on public.predictions for insert
  with check (player_id = auth.uid() and not public.is_match_locked(match_id));

create policy predictions_update_self
  on public.predictions for update
  using (player_id = auth.uid() and not public.is_match_locked(match_id))
  with check (player_id = auth.uid() and not public.is_match_locked(match_id));

create policy predictions_delete_self
  on public.predictions for delete
  using (player_id = auth.uid() and not public.is_match_locked(match_id));

create policy predictions_admin on public.predictions for all using (public.is_admin()) with check (public.is_admin());

-- bracket_picks: read all; write own only while bracket not locked.
create policy bracket_read on public.bracket_picks for select using (auth.role() = 'authenticated');

create policy bracket_insert_self
  on public.bracket_picks for insert
  with check (player_id = auth.uid() and not public.is_bracket_locked());

create policy bracket_update_self
  on public.bracket_picks for update
  using (player_id = auth.uid() and not public.is_bracket_locked())
  with check (player_id = auth.uid() and not public.is_bracket_locked());

create policy bracket_delete_self
  on public.bracket_picks for delete
  using (player_id = auth.uid() and not public.is_bracket_locked());

create policy bracket_admin on public.bracket_picks for all using (public.is_admin()) with check (public.is_admin());

-- Grant the leaderboard view to anon + authenticated (RLS still applies to base tables)
grant select on public.leaderboard to anon, authenticated;

-- ============================================================================
-- Admin: create a player (auth.users + profile) in one call.
--   Username  -> synthetic email (`<username>@wcop.local`)
--   PIN       -> 6 digit string, used as password (padded internally for safety)
-- Callable only by an admin profile, or with no profiles yet (bootstrap).
-- ============================================================================
create or replace function public.admin_create_player(
  p_username     text,
  p_pin          text,
  p_display_name text,
  p_is_admin     boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email   text;
  v_user_id uuid;
  v_existing int;
begin
  if length(p_pin) < 4 then
    raise exception 'PIN must be at least 4 digits';
  end if;
  if length(p_username) < 2 then
    raise exception 'Username too short';
  end if;

  -- Allow first call (bootstrap) or admin caller.
  select count(*) into v_existing from public.profiles;
  if v_existing > 0 and not public.is_admin() then
    raise exception 'Only admins can create players';
  end if;

  v_email := lower(p_username) || '@wcop.local';
  v_user_id := gen_random_uuid();

  insert into auth.users (
    id, instance_id, email, encrypted_password,
    email_confirmed_at, aud, role,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  )
  values (
    v_user_id, '00000000-0000-0000-0000-000000000000',
    v_email, crypt(p_pin || '-wcop2026', gen_salt('bf')),
    now(), 'authenticated', 'authenticated',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', p_username, 'display_name', p_display_name),
    now(), now(), '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  )
  values (
    gen_random_uuid(), v_user_id, v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email', now(), now(), now()
  );

  insert into public.profiles (id, username, display_name, is_admin)
  values (v_user_id, p_username, p_display_name, p_is_admin);

  return v_user_id;
end;
$$;

revoke all on function public.admin_create_player(text,text,text,boolean) from public;
grant execute on function public.admin_create_player(text,text,text,boolean) to authenticated, anon;

-- Reset a player's PIN (admin only)
create or replace function public.admin_reset_pin(p_username text, p_new_pin text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if length(p_new_pin) < 4 then raise exception 'PIN too short'; end if;
  v_email := lower(p_username) || '@wcop.local';
  update auth.users
    set encrypted_password = crypt(p_new_pin || '-wcop2026', gen_salt('bf')),
        updated_at = now()
    where email = v_email;
  return found;
end;
$$;
revoke all on function public.admin_reset_pin(text,text) from public;
grant execute on function public.admin_reset_pin(text,text) to authenticated;

-- Delete a player (auth.users + profile cascades)
create or replace function public.admin_delete_player(p_username text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_email text;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  v_email := lower(p_username) || '@wcop.local';
  delete from auth.users where email = v_email;
  return found;
end;
$$;
revoke all on function public.admin_delete_player(text) from public;
grant execute on function public.admin_delete_player(text) to authenticated;

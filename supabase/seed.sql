-- ============================================================================
-- World Cup Office Predictor 2026 — Seed data
-- Run AFTER schema.sql.
--
-- This populates:
--   * 48 placeholder teams across 12 groups (A–L)
--   * 72 group-stage fixtures (each group: 6 round-robin matches)
--   * Demo admin + 5 demo players
--   * Sample finished results for the first matchday so leaderboard is non-empty
--
-- Replace team names / kickoff times when official 2026 fixtures are published.
-- Reset everything: see "Reset" section at bottom.
-- ============================================================================

begin;

-- --------------------------------------------------------------------------
-- TEAMS  (the actual 48 qualifiers from the FIFA World Cup 2026 final draw,
-- held in Washington DC on 5 December 2025)
-- --------------------------------------------------------------------------
insert into public.teams (code, name, group_code, flag_emoji, seed_rank) values
  -- Group A
  ('MEX','Mexico',                  'A','🇲🇽',1),
  ('KOR','South Korea',             'A','🇰🇷',2),
  ('CZE','Czechia',                 'A','🇨🇿',3),
  ('RSA','South Africa',            'A','🇿🇦',4),
  -- Group B
  ('CAN','Canada',                  'B','🇨🇦',1),
  ('SUI','Switzerland',             'B','🇨🇭',2),
  ('BIH','Bosnia and Herzegovina',  'B','🇧🇦',3),
  ('QAT','Qatar',                   'B','🇶🇦',4),
  -- Group C
  ('BRA','Brazil',                  'C','🇧🇷',1),
  ('MAR','Morocco',                 'C','🇲🇦',2),
  ('SCO','Scotland',                'C','🏴',3),
  ('HAI','Haiti',                   'C','🇭🇹',4),
  -- Group D
  ('USA','United States',           'D','🇺🇸',1),
  ('TUR','Türkiye',                  'D','🇹🇷',2),
  ('AUS','Australia',               'D','🇦🇺',3),
  ('PAR','Paraguay',                'D','🇵🇾',4),
  -- Group E
  ('GER','Germany',                 'E','🇩🇪',1),
  ('ECU','Ecuador',                 'E','🇪🇨',2),
  ('CIV','Côte d''Ivoire',          'E','🇨🇮',3),
  ('CUW','Curaçao',                 'E','🇨🇼',4),
  -- Group F
  ('NED','Netherlands',             'F','🇳🇱',1),
  ('JPN','Japan',                   'F','🇯🇵',2),
  ('SWE','Sweden',                  'F','🇸🇪',3),
  ('TUN','Tunisia',                 'F','🇹🇳',4),
  -- Group G
  ('BEL','Belgium',                 'G','🇧🇪',1),
  ('IRN','Iran',                    'G','🇮🇷',2),
  ('EGY','Egypt',                   'G','🇪🇬',3),
  ('NZL','New Zealand',             'G','🇳🇿',4),
  -- Group H
  ('ESP','Spain',                   'H','🇪🇸',1),
  ('URU','Uruguay',                 'H','🇺🇾',2),
  ('SAU','Saudi Arabia',            'H','🇸🇦',3),
  ('CPV','Cabo Verde',              'H','🇨🇻',4),
  -- Group I
  ('FRA','France',                  'I','🇫🇷',1),
  ('NOR','Norway',                  'I','🇳🇴',2),
  ('SEN','Senegal',                 'I','🇸🇳',3),
  ('IRQ','Iraq',                    'I','🇮🇶',4),
  -- Group J
  ('ARG','Argentina',               'J','🇦🇷',1),
  ('AUT','Austria',                 'J','🇦🇹',2),
  ('ALG','Algeria',                 'J','🇩🇿',3),
  ('JOR','Jordan',                  'J','🇯🇴',4),
  -- Group K
  ('POR','Portugal',                'K','🇵🇹',1),
  ('COL','Colombia',                'K','🇨🇴',2),
  ('UZB','Uzbekistan',              'K','🇺🇿',3),
  ('COD','DR Congo',                'K','🇨🇩',4),
  -- Group L
  ('ENG','England',                 'L','🏴',1),
  ('CRO','Croatia',                 'L','🇭🇷',2),
  ('GHA','Ghana',                   'L','🇬🇭',3),
  ('PAN','Panama',                  'L','🇵🇦',4);

-- --------------------------------------------------------------------------
-- GROUP FIXTURES  (round-robin per group: 6 matches × 12 groups = 72)
-- Generated procedurally so we don't have to hand-write 72 inserts.
-- Kickoff times are placeholders starting 2026-06-11 18:00 BST, +3h each.
-- --------------------------------------------------------------------------
do $$
declare
  g record;
  t_a uuid; t_b uuid; t_c uuid; t_d uuid;
  base_ts timestamptz := '2026-06-11 17:00:00+00';
  match_no int := 0;
begin
  for g in select distinct group_code from public.teams order by group_code loop
    -- get the four teams of this group ordered by seed
    select id into t_a from public.teams where group_code = g.group_code and seed_rank = 1;
    select id into t_b from public.teams where group_code = g.group_code and seed_rank = 2;
    select id into t_c from public.teams where group_code = g.group_code and seed_rank = 3;
    select id into t_d from public.teams where group_code = g.group_code and seed_rank = 4;

    -- Matchday 1: A vs B, C vs D
    match_no := match_no + 1;
    insert into public.matches (match_no, round, group_code, home_team_id, away_team_id, kickoff_at)
      values (match_no, 'group', g.group_code, t_a, t_b, base_ts + (match_no * interval '4 hours'));
    match_no := match_no + 1;
    insert into public.matches (match_no, round, group_code, home_team_id, away_team_id, kickoff_at)
      values (match_no, 'group', g.group_code, t_c, t_d, base_ts + (match_no * interval '4 hours'));

    -- Matchday 2: A vs C, B vs D
    match_no := match_no + 1;
    insert into public.matches (match_no, round, group_code, home_team_id, away_team_id, kickoff_at)
      values (match_no, 'group', g.group_code, t_a, t_c, base_ts + (match_no * interval '4 hours') + interval '5 days');
    match_no := match_no + 1;
    insert into public.matches (match_no, round, group_code, home_team_id, away_team_id, kickoff_at)
      values (match_no, 'group', g.group_code, t_b, t_d, base_ts + (match_no * interval '4 hours') + interval '5 days');

    -- Matchday 3: A vs D, B vs C
    match_no := match_no + 1;
    insert into public.matches (match_no, round, group_code, home_team_id, away_team_id, kickoff_at)
      values (match_no, 'group', g.group_code, t_a, t_d, base_ts + (match_no * interval '4 hours') + interval '10 days');
    match_no := match_no + 1;
    insert into public.matches (match_no, round, group_code, home_team_id, away_team_id, kickoff_at)
      values (match_no, 'group', g.group_code, t_b, t_c, base_ts + (match_no * interval '4 hours') + interval '10 days');
  end loop;
end $$;

-- --------------------------------------------------------------------------
-- Knockout placeholder rows (admin fills home/away once group stage ends)
-- 32 R32 + 16 R16 + 8 QF + 4 SF + 1 Final + 1 third-place = 62 placeholder rows
-- For simplicity we only create R32 and downstream skeleton; home/away NULL.
-- --------------------------------------------------------------------------
do $$
declare
  base_ts timestamptz := '2026-06-30 17:00:00+00';
  i int;
  next_no int;
begin
  select coalesce(max(match_no),0) into next_no from public.matches;
  for i in 1..32 loop
    next_no := next_no + 1;
    insert into public.matches (match_no, round, kickoff_at, bracket_slot)
      values (next_no, 'r32', base_ts + (i * interval '4 hours'), 'R32-' || i);
  end loop;
  for i in 1..16 loop
    next_no := next_no + 1;
    insert into public.matches (match_no, round, kickoff_at, bracket_slot)
      values (next_no, 'r16', base_ts + interval '5 days' + (i * interval '4 hours'), 'R16-' || i);
  end loop;
  for i in 1..8 loop
    next_no := next_no + 1;
    insert into public.matches (match_no, round, kickoff_at, bracket_slot)
      values (next_no, 'qf', base_ts + interval '12 days' + (i * interval '4 hours'), 'QF-' || i);
  end loop;
  for i in 1..4 loop
    next_no := next_no + 1;
    insert into public.matches (match_no, round, kickoff_at, bracket_slot)
      values (next_no, 'sf', base_ts + interval '20 days' + (i * interval '4 hours'), 'SF-' || i);
  end loop;
  next_no := next_no + 1;
  insert into public.matches (match_no, round, kickoff_at, bracket_slot)
    values (next_no, '3rd', '2026-07-18 18:00:00+00', '3rd');
  next_no := next_no + 1;
  insert into public.matches (match_no, round, kickoff_at, bracket_slot)
    values (next_no, 'final', '2026-07-19 18:00:00+00', 'Final');
end $$;

-- --------------------------------------------------------------------------
-- DEMO USERS
--   admin    / PIN 262626  (admin)
--   alice    / PIN 111111
--   bob      / PIN 222222
--   carla    / PIN 333333
--   danny    / PIN 444444
--   ellie    / PIN 555555
-- Login email mapping: <username>@wcop.local
-- --------------------------------------------------------------------------
select public.admin_create_player('admin','262626','Tournament Admin', true);
select public.admin_create_player('alice','111111','Alice Andersen', false);
select public.admin_create_player('bob',  '222222','Bob Brennan',    false);
select public.admin_create_player('carla','333333','Carla Costa',    false);
select public.admin_create_player('danny','444444','Danny Davies',   false);
select public.admin_create_player('ellie','555555','Ellie Ellis',    false);

-- --------------------------------------------------------------------------
-- SAMPLE RESULTS  — first 3 group matches finalised so leaderboard is live
-- --------------------------------------------------------------------------
update public.matches set home_score = 2, away_score = 1, status = 'final' where match_no = 1;
update public.matches set home_score = 0, away_score = 0, status = 'final' where match_no = 2;
update public.matches set home_score = 3, away_score = 2, status = 'final' where match_no = 3;

-- --------------------------------------------------------------------------
-- SAMPLE PREDICTIONS — give demo players a mix of right/wrong picks
-- Use display_name to look up player ids cleanly.
-- --------------------------------------------------------------------------
do $$
declare
  alice uuid; bob uuid; carla uuid; danny uuid; ellie uuid;
  m1 uuid; m2 uuid; m3 uuid;
begin
  select id into alice from public.profiles where username = 'alice';
  select id into bob   from public.profiles where username = 'bob';
  select id into carla from public.profiles where username = 'carla';
  select id into danny from public.profiles where username = 'danny';
  select id into ellie from public.profiles where username = 'ellie';
  if alice is null or bob is null then return; end if;
  select id into m1 from public.matches where match_no = 1;
  select id into m2 from public.matches where match_no = 2;
  select id into m3 from public.matches where match_no = 3;

  insert into public.predictions (player_id, match_id, home_score, away_score) values
    (alice, m1, 2, 1),  -- exact
    (alice, m2, 0, 0),  -- exact
    (alice, m3, 2, 1),  -- correct result
    (bob,   m1, 1, 0),  -- correct result
    (bob,   m2, 1, 1),  -- correct result (draw)
    (bob,   m3, 0, 2),  -- wrong
    (carla, m1, 3, 0),  -- correct result
    (carla, m2, 2, 0),  -- wrong (no draw)
    (carla, m3, 3, 2),  -- exact
    (danny, m1, 0, 1),  -- wrong
    (danny, m2, 0, 0),  -- exact
    (danny, m3, 1, 1),  -- wrong (draw, actual was home win)
    (ellie, m1, 1, 1),  -- wrong (draw vs home win)
    (ellie, m2, 2, 2),  -- correct result (draw)
    (ellie, m3, 2, 1);  -- correct result
end $$;

-- recalc points for the three finished matches
select public.recalc_match(id) from public.matches where status = 'final';

-- --------------------------------------------------------------------------
-- SAMPLE BRACKET PICKS for one player (Alice) so screens demo nicely
-- --------------------------------------------------------------------------
do $$
declare alice uuid;
begin
  select id into alice from public.profiles where username = 'alice';
  if alice is null then return; end if;
  -- pick 8 teams to reach R32 (in real use a player picks 32)
  insert into public.bracket_picks (player_id, round, team_id)
    select alice, 'r32', id from public.teams where seed_rank = 1 order by group_code limit 8;
  -- pick 4 teams for R16, 2 for QF, 1 each for SF/Final/Winner
  insert into public.bracket_picks (player_id, round, team_id)
    select alice, 'r16', id from public.teams where code in ('USA','BRA','ARG','FRA');
  insert into public.bracket_picks (player_id, round, team_id)
    select alice, 'qf',  id from public.teams where code in ('BRA','ARG');
  insert into public.bracket_picks (player_id, round, team_id)
    select alice, 'sf',  id from public.teams where code in ('BRA');
  insert into public.bracket_picks (player_id, round, team_id)
    select alice, 'final',  id from public.teams where code in ('BRA');
  insert into public.bracket_picks (player_id, round, team_id)
    select alice, 'winner', id from public.teams where code in ('BRA');
end $$;

commit;

-- ============================================================================
-- Reset everything (uncomment + run, then re-run schema.sql + seed.sql):
--   delete from auth.users where email like '%@wcop.local';
--   truncate public.predictions, public.bracket_picks, public.bracket_actuals,
--            public.matches, public.teams restart identity cascade;
-- ============================================================================

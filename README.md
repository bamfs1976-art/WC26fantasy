# World Cup Office Predictor 2026

A simple single-page web app for a private FIFA World Cup 2026 office prediction pool. Up to 40 players each predict every match score and a full knockout bracket, then compete on a live leaderboard.

- Single-file `index.html` (vanilla JS, no build step)
- Supabase backend (Postgres + Auth + RLS)
- Deploy with Netlify Drop in one drag
- Scoring runs in Postgres functions, leaderboard is a SQL view

---

## What's in this repo

```
worldcup2026/
  index.html             # the whole app (drag this to Netlify Drop)
  supabase/
    schema.sql           # tables, RLS, scoring functions, leaderboard view
    seed.sql             # 48 teams, 96 fixtures, demo users, sample results
  README.md              # this file
  .claude/launch.json    # local preview helper (not deployed)
```

---

## Setup (15 minutes)

### 1. Create a Supabase project

You can reuse the existing `supabase-amber-ball` project (`knodunjnsxelmpziupwk`, `eu-west-2`) or create a new one. The schema is self-contained — no shared tables.

### 2. Run the schema and seed

In the Supabase SQL editor, run **`supabase/schema.sql`** first. Then run **`supabase/seed.sql`**.

Verify in the Table Editor:

| Table              | Expected rows |
|--------------------|---------------|
| `teams`            | 48            |
| `matches`          | 134 (72 group + 32 R32 + 16 R16 + 8 QF + 4 SF + 1 third-place + 1 final) |
| `profiles`         | 6 (1 admin + 5 demo)  |
| `predictions`      | 15 (sample)   |
| `bracket_picks`    | 17 (Alice's sample bracket: 8 R32 + 4 R16 + 2 QF + 1 SF + 1 Final + 1 Winner) |

### 3. Configure the app

Open `index.html` and find this block near the top of the script:

```js
const SUPABASE_URL  = window.WCOP_SUPABASE_URL  || 'https://knodunjnsxelmpziupwk.supabase.co';
const SUPABASE_ANON = window.WCOP_SUPABASE_ANON || 'REPLACE_WITH_YOUR_ANON_KEY';
```

Replace `REPLACE_WITH_YOUR_ANON_KEY` with the **anon public key** from
Supabase → Project Settings → API. (Anon key only. Never paste the service role key.)

### 4. Authentication settings in Supabase

In Supabase Authentication settings:

- **Disable** "Enable email confirmations" (we use synthetic emails; nobody owns the inbox)
- **Disable** "Enable signups" (admins create accounts; players can't self-register)
- Leave password length at the default (≥ 6). PINs are padded server-side, so even 4-digit PINs work.

### 5. Deploy

Drag `index.html` to https://app.netlify.com/drop. That's it — Netlify gives you an HTTPS URL you can share with the office.

### 6. Log in

Default admin: **`admin`** / PIN **`262626`**. Change the PIN immediately:

- Sign in as `admin`
- Go to Admin → Players → click "Reset PIN" next to the admin row

---

## Demo accounts

Seed data includes these accounts so the app feels alive on first load:

| Username | PIN    | Role  |
|----------|--------|-------|
| admin    | 262626 | Admin |
| alice    | 111111 | Player |
| bob      | 222222 | Player |
| carla    | 333333 | Player |
| danny    | 444444 | Player |
| ellie    | 555555 | Player |

Delete or rename these in Admin → Players before going live.

---

## Admin guide

### Add a player

1. Sign in as admin → click **Admin** in the nav
2. **Players** tab → fill in username (lowercase, no spaces), PIN (4–8 digits), display name → **Create**
3. Tell the player their username and PIN. They go to your Netlify URL and sign in.

To bulk-add: just repeat the form. Up to 40 accounts takes ~5 minutes.

### Update teams or fixtures

The seed has 48 placeholder teams in groups A–L and a generated round-robin
group schedule. Update them once the real 2026 draw and fixture list are published:

- Admin → **Teams** tab → edit any cell inline (name, code, group, flag, seed)
- Admin → **Fixtures** tab → set home/away teams and kickoff time for each match

Kickoff times are stored in UTC. The UI displays them in the user's local timezone.

### Enter a match result

1. Admin → **Results** tab
2. Find the match (use the match number — it's the official 1..104)
3. Enter home and away scores → **Save**
4. The app calls `recalc_match()` immediately. Leaderboard updates instantly.

### Lock the bracket

Players can edit bracket picks until you lock the tournament. Once the first
match kicks off, do this:

1. Admin → **Tools** tab → **Lock bracket entry**

If you locked too early, the same screen has **Unlock bracket**.

### Mark bracket-round actuals

After a knockout round finishes (say the Round of 32 ends), tell the app which
teams *actually* progressed so player picks can be scored:

1. Admin → **Bracket** tab
2. For each round (R32, R16, QF, SF, Final, Champion), tick the teams that
   reached that round
3. Admin → **Tools** tab → **Recalculate bracket points**

The leaderboard's "Bracket" column updates immediately.

### Recalculate everything

If you change scoring rules or fix a bad result, Admin → **Tools** has:

- **Recalculate all match points** — re-runs `recalc_match()` on every finished match
- **Recalculate bracket points** — re-runs `recalc_bracket()` from current actuals

### Reset for a new tournament

Admin → **Tools** → Danger zone:

- **Clear all predictions** — removes every prediction. Players will need to re-enter.
- **Clear all results** — sets every match back to "scheduled". Predictions remain.

To reset *everything* including users, run the snippet at the bottom of
`seed.sql` in the Supabase SQL editor.

---

## Scoring rules

### Match predictions
- **Exact score**: 3 points (not 3 + 1 — exact is the full prize)
- **Correct result only** (W / D / L matches actual): 1 point
- **Wrong**: 0 points

### Bracket predictions
For each round, you score **1 point per team you predicted to reach that round
that actually did reach it**. Round-reached, not path-dependent — you still get
the point for picking Brazil in the semis even if you had them beating the
wrong opponent in the quarters.

Max bracket points:

| Round         | Picks | Max pts |
|---------------|-------|---------|
| R32 (qualifiers) | 32 | 32 |
| R16           | 16    | 16 |
| Quarter-finals | 8    | 8 |
| Semi-finals   | 4     | 4 |
| Final         | 2     | 2 |
| Champion      | 1     | 1 |
| **Total**     |       | **63** |

### Tiebreakers
1. Most exact scores
2. Most correct results
3. Most bracket points

After all three, players share the rank.

---

## Architecture notes

### Auth
We use Supabase Auth with synthetic emails. A player's email is
`<username>@wcop.local` and password is `<pin>-wcop2026`. The user never sees the
synthetic email. This gives us a real JWT, real RLS, and password hashing for
free — no custom session table.

### RLS in one paragraph
- Reads: anyone authenticated can read teams, matches, the leaderboard view,
  and other players' predictions (for transparency)
- Writes: a player can only insert/update their own predictions, and only
  while the match isn't locked. Same for bracket picks before tournament start.
- `is_admin()` is a stable function that checks `profiles.is_admin = true` for
  the current auth.uid(). Admin policies allow full access to all tables.

### Lock at kickoff
A match is "locked" when `kickoff_at <= now()` OR `status IN ('locked','final')`.
Both client (UI hides inputs) and server (`is_match_locked()` in RLS policy
WITH CHECK) enforce this — clients can't bypass by editing the DOM.

### Scoring engine
- `recalc_match(uuid)` recomputes points for one match's predictions. Called
  automatically when admin enters a result.
- `recalc_all_matches()` and `recalc_bracket()` are admin tools for full
  rebuilds.
- Leaderboard is a SQL view — no manual cache. Tiebreakers are in the
  `ORDER BY` of the `rank() over (...)`.

### Why a single HTML file?
Forty office players using the app for ~5 weeks is not a SaaS. One file is:

- One thing to deploy (drag to Netlify Drop)
- Zero build dependencies, zero supply-chain risk
- Trivial to read, fork, or fix
- Loads in <200kB total

If you need to scale or add many more features, this is easy to port to Vite +
React later — the schema and scoring functions don't change.

---

## Known issues / heads-ups

- **Flag emojis on Windows desktop** render as the two-letter regional indicator pair (e.g. "MX" instead of 🇲🇽). Mac, iOS, Android, and most modern browsers render them correctly. If your office is heavy on Windows desktop and you want real flags, bundle [Twemoji](https://twemoji.maxcdn.com/) — but that adds ~250kB.
- **Match kickoff times in the seed are placeholders** starting 2026-06-11. Replace them with real fixture times once published (Admin → Fixtures).
- **Best-3rd-placed-team logic** is not derived automatically — the admin types in the 32 actual R32 qualifiers via Admin → Bracket. The scoring rule doesn't need group-table math, so this is fine.
- **PINs are case-insensitive** at the username level (we lowercase before forming the synthetic email). PIN itself is case-sensitive, but it's digits.
- **Session persistence** uses Supabase's default localStorage. The token is a short-lived JWT so the exposure window is small, but if your security policy forbids any auth storage in localStorage, set `persistSession: false` in the `createClient` call.

---

## Security checklist (already applied)

- CSP meta tag restricts scripts to self + jsDelivr (Supabase CDN), connect to Supabase only
- Anon key is the public anon key (intended for client use); service role key is never in the client
- All Supabase tables have RLS enabled with explicit policies
- Inputs are validated client-side AND constrained server-side via column CHECK constraints
- DOM rendering uses `textContent` for user-supplied strings (no `innerHTML` injection)
- No secrets in this repo — anon key is plugged in at deploy time
- HTTPS enforced by Netlify

---

## Local development

Just open `index.html` in a browser. Or run a static server:

```
python -m http.server 5179 --directory D:/worldcup2026
```

Then visit http://localhost:5179.

---

## Licence

Internal use. Not for redistribution.

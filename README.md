# HERO//HQ

Portrait, offline-first incremental superhero-agency game running on a reusable,
game-neutral Godot framework. One rookie hero stopping street crime grows into a
coordinated citywide agency while the player builds, trains and automates teams.

- **Engine:** Godot **4.7.2** stable, GDScript, `gl_compatibility` renderer
- **Target:** Android first, portrait, 360×640 logical canvas with safe-area insets
- **Status:** Milestone **M1.2 (long-term curve + Command Rebirth)** complete — see [docs/CHANGELOG.md](docs/CHANGELOG.md)
- **Design source of truth:** `HERO_HQ_MASTER_CODEX.md` (see *Design document* below)

## Run it

```bash
# open in the editor
godot --editor --path .

# run the game (portrait window)
godot --path .

# headless test suite (exits nonzero on failure)
godot --headless --path . -s res://tests/run_tests.gd

# validate every content pack
godot --headless --path . -s res://tooling/validate_packs.gd

# watch the whole loop play out, no display needed
godot --headless --path . -s res://tooling/demo_loop.gd

# measure the progression curve a greedy player actually experiences
godot --headless --path . -s res://tooling/balance_report.gd

# play seven days with rebirth, and fail if any wait exceeds the boredom budget
godot --headless --path . -s res://tooling/long_run_report.gd
```

Downloads for the pinned engine: <https://godotengine.org/download/linux/>.
No Android SDK, ad SDK or billing credentials are needed for anything above.

## Play the loop

The M1 loop is playable from a fresh save, and the curve is tuned rather than
improvised. Volt starts at **rating 70** — `(power 5 + speed 5 + skill 4) × 5` —
with 50 Credits, which is enough for one training session and no more.

1. **Missions** lists six tasks. Each card shows stage, category, duration and
   rating gate, plus what it pays. `Deploy` is disabled with the blocking reason
   printed on the card (rating too low, no free hero).
2. The ladder is paced so a new tier opens roughly every couple of minutes, and
   each tier is worth about **1.5× the credits per minute** of the one before it:

   | Task | Gate | Time | Pays | Rate |
   |---|---|---|---|---|
   | Alley Patrol | 60 | 20 s | 18 Credits | 54/min |
   | Break-In Response | 80 | 30 s | 45 Credits | 90/min |
   | Drone Swarm | 100 | 45 s | 95 Credits + 1 Intel | 128/min |
   | Rooftop Pursuit | 120 | 60 s | 190 Credits + 2 Intel | 192/min |
   | Convoy Ambush | 140 | 90 s | 430 Credits + 4 Intel | 289/min |
   | Citywide Siege | 160 | 120 s | 900 Credits + 8 Intel | 454/min |

3. **Heroes** shows rating, level, XP bar and `Train` (25 Credits for +40 XP,
   cost ×1.4 per level). Volt gains +20 rating per level, so each level unlocks
   exactly one new tier — 70 at level 1, 90 at level 2, and so on.
4. A deployed card moves to **Active operations** with a live countdown. When it
   reaches zero the task pays out, the hero is freed and the result is logged on
   the HQ tab.
5. Close the app mid-task and reopen it later: the same settlement call finishes
   the task on launch, capped at the pack's 8-hour allowance.

Measured with `tooling/balance_report.gd`, a greedy first session reaches the six
tiers at roughly **0:00, 0:40, 2:10, 5:10, 8:10 and 11:10**, and levels then keep
slowing (15:10, 21:10, 29:10, 41:10, 59:10). That shape is deliberate: quick first
win, a visible power spike per tier, and a decaying cadence after the content runs
out — see the balance note in [docs/CHANGELOG.md](docs/CHANGELOG.md).

### Rebirth: the long-term loop

Six tasks cannot carry a week on their own, so the loop above is a *run*. Once the
save has earned **4,000 Credits lifetime** and Volt reaches **level 7**, the
**Upgrades** tab offers a Command Rebirth: the run resets (level, training,
Credits, assignments) and the save banks chips that permanently multiply every
payout by `1 + 0.05 × chips`. Chips are derived from lifetime earnings with a
sub-linear exponent, so each rebirth needs several times the previous progress to
double — runs lengthen instead of collapsing into a reset treadmill.

Measured over seven days with `tooling/long_run_report.gd`: 205 rebirths, runs
growing from ~17 minutes to ~1 hour, ×11.40 on payouts, and **no single wait over
14 minutes**. The formulas, the sweep behind them and the tuning knobs are in
[docs/BALANCE.md](docs/BALANCE.md).

Everything above is driven by pack data (`games/hero_hq/data/*.json`), not by
code in `framework/`.

## Layout

```text
project.godot              entry point, portrait/stretch/orientation settings
framework/                 shared, game-neutral engine (never names a title)
  core/                    game_state, clock, simulation, agent_rules, prestige, save
  content/                 pack loader, pack object, pack validator + content checks
  ui/                      theme tokens, text formatting, portrait shell, resource bar
    screens/               task board, roster screen, rebirth screen
    components/            resource bar widget
games/hero_hq/             HERO//HQ content pack — game #1
  manifest.json            5 tabs, credits/intel, 8h offline cap, data paths
  data/                    roles, starter agents + tuning, task ladder, progression
  locale/en.json           every player-facing string
  ui/theme.json            palette as generic theme tokens
  scenes/                  app composition root + operations-network drawing
tests/                     headless runner, test_case harness, suites
tooling/validate_packs.gd  CLI pack validator (CI gate)
tooling/demo_loop.gd       headless walkthrough of the loop
tooling/balance_report.gd  greedy pacing simulation + curve report
tooling/long_run_report.gd 7-day rebirth model + boredom-budget check
```

**Dependency direction:** `games/* -> framework/*`. The framework never imports a
pack, never references title-specific ids, and `tests/game_packs/test_hero_hq.gd`
fails the build if that rule is broken.

## What works and what does not

Working now: the M1 loop above end to end — deploy, settle (online and offline),
earn, level up, train, save, resume — on validated pack data, with an invalid pack
rendering a readable error screen instead of crashing.

Not implemented yet: recruitment, squads/teams, upgrades (the Upgrades tab now
hosts rebirth), automation, focus, monetization (M6), Android export and device
testing (M7). The Teams tab still shows a placeholder rather than pretending to
have live logic.

## Non-negotiable product rules

- No banner, interstitial, native, app-open, forced or auto-triggered ads, ever.
  Only a player-initiated, player-confirmed rewarded ad may exist, at M6.
- Nothing is gated behind an ad or a purchase.
- Core play, saves and simulation work fully offline.
- Every game built on this framework inherits the same ad rule.

## Design document

The authoritative specification is `HERO_HQ_MASTER_CODEX.md`, which the spec says
must live at the repository root. It is **not committed yet** — the copy supplied
arrived as a chat attachment and was not available as a file in the workspace. Add
it at the root (or `docs/`) so the single-document rule holds; nothing in the code
depends on it.

## Setup for a fresh checkout

```bash
godot --headless --path . --import   # build import caches once
godot --headless --path . -s res://tests/run_tests.gd
```

# HERO//HQ

Portrait, offline-first incremental superhero-agency game running on a reusable,
game-neutral Godot framework. One rookie hero stopping street crime grows into a
coordinated citywide agency while the player builds, trains and automates teams.

- **Engine:** Godot **4.7.2** stable, GDScript, `gl_compatibility` renderer
- **Target:** Android first, portrait, 360×640 logical canvas with safe-area insets
- **Status:** **v1 loop complete** (M1.5) — fresh save to rebirth, played end to end; see [docs/CHANGELOG.md](docs/CHANGELOG.md)
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

# play the whole game through the real UI, then restore your save
godot --headless --path . -s res://tooling/playthrough_demo.gd

# capture every tab to PNG at 360x640 (windowed, restores your save)
godot --path . --resolution 360x640 -s res://tooling/ui_capture.gd
```

Downloads for the pinned engine: <https://godotengine.org/download/linux/>.
No Android SDK, ad SDK or billing credentials are needed for anything above.

## Play the loop

The v1 loop is playable from a fresh save, and the curve is tuned rather than
improvised. Volt starts at **rating 70** — `(power 5 + speed 5 + skill 4) × 5` —
with 50 Credits, which is enough for one training session and no more.

1. **HQ** always names one concrete next step — deploy, train, recruit, research,
   rebirth — derived from the live save, so a new player is never left guessing.
   It re-arms itself after every Command Rebirth.
2. **Missions** lists all fifteen operations: twelve solo jobs and three squad
   jobs, gates from **60 to 185**, durations from 20 seconds to 4 minutes, and
   payouts from 18 to 2,400 Credits plus Intel. Each card shows stage, category,
   duration and gate, and `Deploy` is disabled with the blocking reason printed
   on it (rating too low, no free hero, missing role).
3. **Heroes** shows rating, level, XP bar and `Train` (25 Credits for +40 XP,
   cost ×1.4 per level). The starter gains +20 rating per level, so early levels
   open new tiers quickly. Recruitment draws from 200 named slots, costs 50
   Credits with ×1.03 growth, and has a **role picker**: choose Tech and the next
   affordable hire is a Tech, instead of hoping the pool rolls one.
4. A deployed operation moves to **Active operations** with a live countdown.
   When it reaches zero it pays out, the heroes are freed and the result is
   logged on the HQ tab.
5. **Teams** previews every squad operation against the current roster — members,
   individual and average ratings against the gate, missing roles, and the exact
   blocking reason — and saves one lineup per operation.
6. Close the app mid-operation and reopen it later: the same settlement call
   finishes it on launch, capped at the pack's 8-hour allowance.

Measured with `tooling/balance_report.gd`, one greedy agent — the model recruits
nobody, so this is a lower bound — plays **2 hours**, completes **68**
operations, reaches **level 13** and earns **51,871 Credits**.

### Rebirth: the long-term loop

One ladder cannot carry a week on its own, so the loop above is a *run*. Once the
save has earned **4,000 Credits lifetime** and Volt reaches **level 7**, the
**Upgrades** tab offers a Command Rebirth: levels, training, Credits and running
operations reset, the roster is kept and rewound to its base ratings, and the
save banks chips that permanently multiply every payout by `1 + 0.05 × chips`.
Research ranks also survive, so each run starts from a stronger baseline. Chips
are derived from lifetime earnings with a sub-linear exponent, so each rebirth
needs several times the previous progress to double — runs lengthen instead of
collapsing into a reset treadmill.

Measured over seven days with `tooling/long_run_report.gd`: 207 rebirths, runs
growing from ~15 minutes to ~1 hour, ×11.45 on payouts, and **no single wait over
14 minutes**. The formulas, the sweep behind them and the tuning knobs are in
[docs/BALANCE.md](docs/BALANCE.md).

Everything above is driven by pack data (`games/hero_hq/data/*.json`), not by
code in `framework/`.

## Layout

```text
project.godot              entry point, portrait/stretch/orientation settings
framework/                 shared, game-neutral engine (never names a title)
  core/                    game_state, clock, simulation, agent_rules,
                           recruitment, research, squads, prestige, save
  content/                 pack loader, pack object, pack validator + content checks
  ui/                      theme tokens, text formatting, portrait shell, resource bar
    screens/               task board, roster, team and rebirth screens
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
tooling/playthrough_demo.gd  real-UI playthrough, fresh save to rebirth
tooling/ui_capture.gd      windowed PNG capture of every tab
```

**Dependency direction:** `games/* -> framework/*`. The framework never imports a
pack, never references title-specific ids, and `tests/game_packs/test_hero_hq.gd`
fails the build if that rule is broken.

## What works and what does not

Working now: the loop end to end — deploy, settle (online and offline), earn,
level up, train, recruit, research, rebirth, save, resume — on validated pack
data, with an invalid pack rendering a readable error screen instead of crashing.
Recruitment can target a role, HQ names the next objective, and Upgrades spends
Intel on payout and training research plus an automation rank that repeats the
last operation once per completion. The Teams tab previews every squad operation
against the current roster: the members, their individual and average ratings
against the gate, any missing role, and the exact blocking reason when it cannot
deploy. A lineup can be saved per operation, updated after training, or cleared
to return to auto-selection.

Not implemented yet: manual per-slot team building, the remaining automation and
focus layers, monetization (M6), Android export and device testing (M7).

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

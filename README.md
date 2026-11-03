# HERO//HQ

Portrait, offline-first incremental superhero-agency game running on a reusable,
game-neutral Godot framework. One rookie hero stopping street crime grows into a
coordinated citywide agency while the player builds, trains and automates teams.

- **Engine:** Godot **4.7.2** stable, GDScript, `gl_compatibility` renderer
- **Target:** Android first, portrait, 360×640 logical canvas with safe-area insets
- **Status:** Milestone **M1 (single-hero loop)** complete — see [docs/CHANGELOG.md](docs/CHANGELOG.md)
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
```

Downloads for the pinned engine: <https://godotengine.org/download/linux/>.
No Android SDK, ad SDK or billing credentials are needed for anything above.

## Play the loop

The M1 loop is playable from a fresh save in about four minutes:

1. **Missions** lists every task the pack declares. Each card shows stage,
   category, duration and rating gate, plus what it pays. `Deploy` is disabled
   with the blocking reason on the card (rating too low, no free hero).
2. Volt starts at **rating 70** — `(power 5 + speed 5 + skill 4) × 5`. Alley
   Patrol (20 s, 18 Credits, 24 XP) clears its gate of 60; Break-In Response
   (45 s, 70) does too; Drone Swarm (80) and Rooftop Pursuit (90) do not.
3. A deployed card moves to **Active operations** with a live countdown. When it
   reaches zero the task pays out, the hero is freed and the result is logged on
   the HQ tab.
4. **Heroes** shows rating, level, XP bar and `Train` (25 Credits for +30 XP,
   cost ×1.5 per level). At 60 XP Volt reaches level 2, and the Striker growth
   curve (+1 power, +2 speed, +1 skill) takes the rating to 90 — which unlocks
   Rooftop Pursuit.
5. Close the app mid-task and reopen it later: the same settlement call finishes
   the task on launch, capped at the pack's 8-hour allowance.

Everything above is driven by pack data (`games/hero_hq/data/*.json`), not by
code in `framework/`.

## Layout

```text
project.godot              entry point, portrait/stretch/orientation settings
framework/                 shared, game-neutral engine (never names a title)
  core/                    game_state, clock, simulation, agent_rules, save
  content/                 pack loader, pack object, pack validator + content checks
  ui/                      theme tokens, text formatting, portrait shell, resource bar
    screens/               task board, roster screen
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
```

**Dependency direction:** `games/* -> framework/*`. The framework never imports a
pack, never references title-specific ids, and `tests/game_packs/test_hero_hq.gd`
fails the build if that rule is broken.

## What works and what does not

Working now: the M1 loop above end to end — deploy, settle (online and offline),
earn, level up, train, save, resume — on validated pack data, with an invalid pack
rendering a readable error screen instead of crashing.

Not implemented yet: recruitment, squads/teams, upgrades, automation, focus,
monetization (M6), Android export and device testing (M7). The Teams and Upgrades
tabs still show a placeholder rather than pretending to have live logic.

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

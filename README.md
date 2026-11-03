# HERO//HQ

Portrait, offline-first incremental superhero-agency game running on a reusable,
game-neutral Godot framework. One rookie hero stopping street crime grows into a
coordinated citywide agency while the player builds, trains and automates teams.

- **Engine:** Godot **4.7.2** stable, GDScript, `gl_compatibility` renderer
- **Target:** Android first, portrait, 360×640 logical canvas with safe-area insets
- **Status:** Milestone **M0 (project foundation)** complete — see [docs/CHANGELOG.md](docs/CHANGELOG.md)
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
```

Downloads for the pinned engine: <https://godotengine.org/download/linux/>.
No Android SDK, ad SDK or billing credentials are needed for anything above.

## Layout

```text
project.godot              entry point, portrait/stretch/orientation settings
framework/                 shared, game-neutral engine (never names a title)
  core/                    game_state, clock, simulation, save
  content/                 pack loader, pack object, pack validator
  ui/                      theme tokens, portrait screen shell, resource bar
games/hero_hq/             HERO//HQ content pack — game #1
  manifest.json            5 tabs, credits/intel, 8h offline cap, data paths
  data/                    roles, starter agents, task catalogue, progression
  locale/en.json           every player-facing string
  ui/theme.json            palette as generic theme tokens
  scenes/                  app composition root + operations-network drawing
tests/                     headless runner, test_case harness, suites
tooling/validate_packs.gd  CLI pack validator (CI gate)
```

**Dependency direction:** `games/* -> framework/*`. The framework never imports a
pack, never references title-specific ids, and `res://tests/game_packs/test_hero_hq.gd`
fails the build if that rule is broken.

## What M0 does and does not do

Working now: the project opens and runs, the HERO//HQ pack is validated on load,
the themed portrait shell renders resources from restored state, all five tabs
build from pack data, saves are atomic and scoped to `game_id`, and the same
`Simulation.simulate_delta` path handles online and post-absence time.

Not implemented yet (M1–M7): missions, training, recruitment, teams, upgrades,
automation, offline earnings, monetization, Android export. Tabs other than HQ
show a placeholder so no screen pretends to have live logic.

## Non-negotiable product rules

- No banner, interstitial, native, app-open, forced or auto-triggered ads, ever.
  Only a player-initiated, player-confirmed rewarded ad may exist, at M6.
- Nothing is gated behind an ad or a purchase.
- Core play, saves and simulation work fully offline.
- Every game built on this framework inherits the same ad rule.

## Design document

The authoritative specification is `HERO_HQ_MASTER_CODEX.md`, which the spec says
must live at the repository root. It is **not committed yet** — the copy supplied
for this milestone arrived as a chat attachment and was not available as a file
here. Add it at the root (or `docs/`) so the single-document rule holds; nothing
in the code depends on it.

## Setup for a fresh checkout

```bash
godot --headless --path . --import   # build import caches once
godot --headless --path . -s res://tests/run_tests.gd
```

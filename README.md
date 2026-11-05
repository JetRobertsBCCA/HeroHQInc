# HERO//HQ

Portrait, offline-first incremental superhero-agency game running on a reusable,
game-neutral Godot framework. One rookie hero stopping street crime grows into a
coordinated citywide agency while the player builds, trains and automates teams.

- **Engine:** Godot **4.7.2** stable, GDScript, `gl_compatibility` renderer
- **Target:** Android first, portrait, 360×640 logical canvas with safe-area insets
- **Status:** **v1 core loop complete** (M1.12) + **M1.21 hero traits** + **M1.22 portrait Operations Network schematic** — fresh save to rebirth with manual squad lineups, Focus, traits and offline settlement, played end to end; debug APK verified on an Android 35 emulator (see [docs/ANDROID.md](docs/ANDROID.md)). Focus, the live network and the trait cards are headless/capture-verified but the network and trait passes have not had a new device pass; remaining MVP gaps are listed below.
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

# play the whole game through the real UI with no grants, then restore your save
godot --headless --path . -s res://tooling/playthrough_demo.gd

# capture every tab to PNG at 360x640 (windowed, restores your save)
godot --path . --resolution 360x640 -s res://tooling/ui_capture.gd

# capture the network working / reduced-motion / completed / idle states
godot --path . --resolution 360x640 -s res://tooling/network_capture.gd

# capture HQ fresh / active-solo / active-squad / reduced-motion first viewports
godot --path . --resolution 360x640 -s res://tooling/hq_viewport_capture.gd

# capture the Mission board in fresh, active, Auto Patrol live/paused and locked states at 360x640
godot --path . --resolution 360x640 -s res://tooling/missions_viewport_capture.gd -- --tag=after

# capture the Heroes two-offer screen fresh and midgame at 360x640
godot --path . --resolution 360x640 -s res://tooling/heroes_viewport_capture.gd -- --tag=after
```

Downloads for the pinned engine: <https://godotengine.org/download/linux/>.
No Android SDK, ad SDK or billing credentials are needed for anything above.

## Android

The repository carries an Android debug preset. With the toolchain from
[docs/ANDROID.md](docs/ANDROID.md):

```bash
godot --headless --path . --export-debug "Android" build/hero_hq.apk
adb install -r build/hero_hq.apk
```

Verified on an Android 35 x86_64 emulator (Pixel 6 AVD, host GPU), not yet on a
physical phone: install and launch, fresh-save onboarding, first mission and
payout, all five tabs, force-stop/relaunch persistence, recruitment, a research
purchase and a two-step rebirth. The two-offer Heroes screen has only been
verified in windowed 360×640 captures so far, not in an emulator pass. Seeded offline saves
settled a due operation once across force-stop/relaunch, instant training
persisted, and persisted auto-repeat re-armed after settlement while closed;
squad automation kept its exact lineup across reloads. A live banner on Missions
and Teams explains a blocked rule by slot, job, rating or role, offers Retry for
an immediate recheck, and clears when the rule starts. Use
`-gpu host`; the software renderer cannot link Godot's canvas shader and shows a
black screen.
The M1.12 Focus card and the M1.22 operations-network visuals have not yet
been included in an emulator or phone pass.

## Play the loop

The v1 loop is playable from a fresh save, and the curve is tuned rather than
improvised. Volt starts at **rating 70** — `(power 5 + speed 5 + skill 4) × 5` —
with 50 Credits, which is enough for one training session and no more.

1. **HQ** always names one concrete next step — deploy, train, recruit, research,
   rebirth — derived from the live save, so a new player is never left guessing.
   It re-arms itself after every Command Rebirth.
2. **Missions** is a compact operation board. Ready operations sit above locked
   ones; every row carries a category glyph and accent, stage, duration, payout,
   role gate and an explicit `RATING` versus `GATE` readiness line. `Deploy` is
   disabled on locked rows, which say `LOCKED` and the bottleneck (rating, no
   free hero or missing role). A running operation gets an in-place progress bar
   that updates on the existing one-second tick, not a tween.
3. **Heroes** shows rating, level, XP bar and `Train` (25 Credits for +40 XP,
   cost ×1.4 per level). The starter gains +20 rating per level, so early levels
   open new tiers quickly. Recruitment shows **two persistent offers** with
   distinct roles, ratings, tiers, attributes and exact Credit prices. Each card
   states what the hire adds ("Adds a new Tech role", "Adds Support #2"), so the
   choice is informed rather than a blind draw. The pair is deterministic from
   200 named slots, survives reloads, and refreshes only after a hire or a
   Command Level increase: there is no paid reroll. Missing Tech/Support and
   squad roles are prioritized, a same-price higher-rating card is re-paired to
   preserve a real cost-versus-quality choice, and prices start at 50 Credits
   with ×1.03 growth per standing hero.
4. A deployed operation moves to **Live operations** with a countdown and an
   in-place progress bar. When it reaches zero it pays out, the heroes are freed
   and the result is logged on the HQ tab. HQ's **Operations Network** now draws
   a portrait agency map: a bottom HQ hub, Street/City/National destination
   stations with lock/next labels, and active routes labelled with the numbered
   operation, crew, percent and projected payout. Small bright dispatch/return
   dots and short trails follow those routes; completion substitutes the actual
   `COMPLETE` payout at the destination. The `MISSIONS` header cue stays visible
   for the next manual action. A brief `COMPLETE` line and restrained HQ pulse
   report the paid reward. The saved `Reduce motion: on` control stops the
   five-hertz pulse and redraw loop while leaving the progress text live. The
   two live rows use 15 px operation/time text and 14 px crew, percent and status
   text; the map header and motion toggle are 14 px.
5. **Focus** on HQ shows the 5/5 bank, the next regeneration and one pulse button
   per running operation. Each button prints the exact projected saving before
   spending — 15% of remaining time, capped at 30 seconds solo and 90 seconds
   squad — and a 10-second per-operation cooldown blocks repeat taps.
6. **Teams** gives every squad operation one slot per required hero. Tapping a
   slot opens an inline roster list; a hero already in another slot or currently
   deployed is shown disabled, so duplicates and activity locks cannot be
   chosen. `Save squad` stores the lineup (it survives reloads), `Clear` removes
   it, and `Deploy` still enforces roles and the rating gate with the exact
   reason on screen.
7. Close the app mid-operation and reopen it later: the same settlement call
   finishes it on launch, capped at the pack's 8-hour allowance. If the
   automation rank is owned, the remembered operation is re-armed once after
   that settlement. Missions and Teams show its live state: `Waiting` while an
   operation runs, or `Paused` with the exact slot, job, rating or role that is
   blocking it. Training or recruiting retries a recovered rule immediately;
   a paused rule also offers Retry to recheck without waiting for settlement.

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

The loop is driven by pack data (`games/hero_hq/data/*.json`), while HERO//HQ-specific
rules such as Focus live in `games/hero_hq/`, not in `framework/`.

## Layout

```text
project.godot              entry point, portrait/stretch/orientation settings
export_presets.cfg        Android debug preset (arm64 + x86_64, immersive)
framework/                 shared, game-neutral engine (never names a title)
  core/                    game_state, clock, simulation, agent_rules,
                           recruitment, research, squads, prestige, save
  content/                 pack loader, pack object, pack validator + content checks
  ui/                      theme tokens, text formatting, portrait shell, resource bar,
                           touch scrolling
    screens/               task board, roster, team and rebirth screens
    components/            resource bar and Auto Patrol card
games/hero_hq/             HERO//HQ content pack — game #1
  manifest.json            5 tabs, credits/intel, 8h offline cap, data paths
  data/                    roles, starter agents + tuning, traits, task ladder, progression
  rules/focus.gd           HERO//HQ Focus rules and persisted state
  locale/en.json           every player-facing string
  ui/theme.json            palette as generic theme tokens
  scenes/                  app composition root + Focus card + operations-network drawing
tests/                     headless runner, test_case harness, suites
tooling/validate_packs.gd  CLI pack validator (CI gate)
tooling/demo_loop.gd       headless walkthrough of the loop
tooling/balance_report.gd  greedy pacing simulation + curve report
tooling/long_run_report.gd 7-day rebirth model + boredom-budget check
tooling/playthrough_demo.gd  real-UI playthrough, fresh save to rebirth, no grants
tooling/ui_capture.gd      windowed PNG capture of every tab
tooling/network_capture.gd  controlled network state captures
tooling/missions_viewport_capture.gd  strict Missions fresh/active/patrol/paused/locked/national capture
tooling/heroes_viewport_capture.gd   strict Heroes two-offer fresh/midgame capture
```

**Dependency direction:** `games/* -> framework/*`. The framework never imports a
pack, never references title-specific ids, and `tests/game_packs/test_hero_hq.gd`
fails the build if that rule is broken.

## What works and what does not

Working now: the loop end to end — deploy, settle (online and offline), earn,
level up, train, recruit, research, rebirth, save, resume — on validated pack
data, with an invalid pack rendering a readable error screen instead of crashing.
Recruitment shows two persistent, gate-aware offers with exact prices, HQ names the next objective, and Upgrades spends
Intel on payout and training research plus a 30-Intel squad auto-repeat rank
that repeats a saved squad operation once per completion, including after a
relaunch. A separate 2-Intel Auto Patrol repeats one solo operation only after
the player has chosen a hero and an eligible operation and pressed Enable; its
Missions card shows the live or paused reason and can be paused without
cancelling work already running. A squad keeps its exact saved lineup and waits
rather than substituting a missing or busy member. A live banner explains why a
configured squad rule cannot start, offers Retry for a paused rule, and clears
as soon as one of its inputs changes. The Teams tab
previews every squad operation against the current roster: the members, their individual and average ratings
against the gate, any missing role, and the exact blocking reason when it cannot
deploy. A lineup can be saved per operation, updated after training, or cleared
to return to auto-selection.

Every hero now carries one data-backed trait. Volt starts with Tactical Mind;
each recruit derives a stable trait from its pool slot, and both the roster row
and both offer cards show the name and exact effect. Ten launch traits cover
training XP, solo pace, Credits, Intel, task XP, squad/role/category rating and
automatic rewards. Modifiers are additive and filter by solo/squad, category,
role, resource or automatic work. Automatic deployments rank available heroes
by the trait-adjusted rating for the operation, and Teams shows that same task
rating in its drafts and slot list. Older saves backfill a missing trait without
a save-schema migration.

The HQ Focus card projects every pulse before the tap; its bank, spent points,
deadlines and per-operation cooldowns survive a save round trip. HQ's Operations
Network now mirrors live solo and squad assignments instead of drawing the
roster: numbered satellites, moving crew tokens, mission progress at a glance,
a brief completion/reward pulse, and a persistent reduced-motion toggle.
Non-colour labels (`LIVE`, `READY`, `STANDBY`, `COMPLETE`), percentages and
shapes keep idle, working and completed states distinct without the palette.

Command Levels are now live. Level 2 asks for 3 agents, 6 completed operations
and 500 lifetime Credits; level 3 asks for 4 agents, 12 completed operations,
1,500 lifetime Credits and a Tech or Support hero, then unlocks Citywide
Defense. HQ shows the current level, the next milestone, live requirement
progress and the stage it unlocks. City operations stay visible but disabled
with a required/current Command Level reason until the milestone is met. Levels
are derived from existing saved totals, so older profiles need no migration; a
City operation already running when the gate arrives still settles. The visible
Tech/Support offers and Street operations are enough to reach level 3 without
Intel. The current deterministic fresh-save route with no grants reaches City at
5:40 in-game with 32 dispatches, 41 completed operations, 1,513 lifetime
Credits, 4 agents and 4 roles; that route found no deadlock, with a longest
completion gap of 40 seconds.

The separate real-UI no-grant check, `tooling/playthrough_demo.gd`, now starts
with the pack's 50 Credits and 0 Intel, hires Tech through the visible 50-Credit
card at 0:40, earns Support and Vanguard from refreshed visible offers, and
reaches City at 6:10 with 47 dispatches, 47 completed operations, 1,650 lifetime
Credits, 4 agents and 4 roles. It then trains the Tech to 110, clears Signal
Pursuit, buys payout research, raises Volt to level 7 and completes the
two-step rebirth; the run restores the player's save and reports PASS. It
presses the real board, offer, training, research, team and rebirth controls and
never grants Credits or calls the hidden role-targeted recruit API.

Level 4 asks for 5 agents, 40 completed operations, 3,500 lifetime Credits,
heroes in 4 roles and one completed squad operation, then unlocks National
Response. It derives from existing saved totals, needs no Intel or currently
locked National job, and gates all four National operations through the same
stage rule in direct deploys, Missions, Teams and auto-repeat. A no-grant route
reaches City at 5:40 and National at 9:20 in-game: 3:40 later, 57 dispatches,
76 completed operations, 3,796 lifetime Credits, 5 agents in 5 roles and one
completed squad, with a longest completion gap of 40 seconds and no deadlock. A National
operation already running on an older save still settles normally.

Before the offer redesign, Auto Patrol became affordable only at 8:40 after 64
manual dispatches. It now becomes affordable at the first Break-In Response
Intel payout: at **2:10**, after **10 manual dispatches** and 7 operations. Its
**2-Intel** branch is bought and enabled immediately, before the first squad.
The selected non-squad hero is still finishing a deployed operation, so the card
shows the paused reason; the first automatic cycle starts at **2:20** and
completes at **2:40**, after 12 manual dispatches. The route still reaches
National at 9:20 with **57 manual dispatches**, 76 completed operations, 3,796
lifetime Credits, 5 agents in 5 roles and one squad; the National gate is
unchanged. A nine-hour return then applies exactly 28,800 seconds: 1,439 away
patrol starts, 1,442 operations complete in the away pass alongside the other
in-flight jobs, 26,160 Credits are earned, and a second settlement pays nothing.
Squad auto-repeat retains its separate 30-Intel branch and exact lineup
behavior.

City now has a role-shaped second tier: Convoy Ambush is the Support's
high-rating solo, while Joint Raid is the better use of a Support and Striker
together. The current no-grant route completes the first Joint Raid at 7:50;
the 15-operation ladder and Street gate are unchanged.

Not implemented yet: command milestones beyond National Response, team
autopilot with its wait reasons, team mastery,
synergies and named team slots, specializations, legendaries, agency contracts, and
an offline earnings report. Monetization (M6) and physical-device Android testing
remain out of scope for this pass. The debug build runs on an emulator; release
signing, an app icon and a phone run remain.

The newer owner decisions intentionally override several codex launch numbers:
the build keeps its **15-operation ladder** (12 solo, 3 squad), **2–3-hero
squads**, **instant paid training** and the existing prestige layer, rather than
the codex's 10 solo / 8 team missions, fixed three-hero teams, timed training and
reserved Legacy Data. Those are deliberate product differences, not missing
Focus work. The codex's Focus training pulse is also inapplicable while training
is instant; mission pulses are implemented.

## Non-negotiable product rules

- No banner, interstitial, native, app-open, forced or auto-triggered ads, ever.
  Only a player-initiated, player-confirmed rewarded ad may exist, at M6.
- Nothing is gated behind an ad or a purchase.
- Core play, saves and simulation work fully offline.
- Every game built on this framework inherits the same ad rule.

## Design document

The authoritative specification lives at `HERO_HQ_MASTER_CODEX.md`
(version 1.2, 101,715 bytes, SHA-256
`69ce6d284ae66d8ad14a428847a4064d1c9e51e43dc773373418a24e85533077`). It is the
single product-context document; source code, tests, game-pack JSON and this
changelog remain development artifacts. Where the codex and a newer owner
decision differ, the newer decision wins and the difference is recorded here and
in [docs/CHANGELOG.md](docs/CHANGELOG.md).

## Setup for a fresh checkout

```bash
godot --headless --editor --path . --quit   # build editor/import caches once
godot --headless --path . -s res://tests/run_tests.gd
```

The first command also refreshes `.godot/global_script_class_cache.cfg`; without
it, a fresh checkout can fail to resolve newly added `class_name` scripts.

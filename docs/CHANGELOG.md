# Changelog

All work on HERO//HQ and the shared framework. Milestones follow Part D of the
design specification.

## M1.17 — Mission operation board (2026-11-05)

Status: complete; windowed 360×640 fresh/active/locked captures and headless checks.

### What was wrong

Missions was a long stack of nearly identical 140px panels. Active work was a
thin strip above the list, ready and locked jobs were mixed together, and the
role gate, Command Level gate and blocking reason were buried in an 11px detail
line or at the bottom of a disabled card. On a portrait phone the next useful
operation took several rows of reading to find.

### What changed

- `TaskBoard` now separates **Live operations**, **Ready now** and **Locked**
  groups. The board header carries ready/locked counts, and each group is sorted
  by its rating gate.
- Every available row uses a compact 110px card: a category glyph and 4px accent
  stripe, title and payout across the top, a stage/category/time/role-gate meta
  line, and a readiness line with the current rating and required gate. Locked
  rows keep a disabled `Locked` action; the 48px action sits in a footer beside
  the reason instead of squeezing the title.
- Category glyphs and palette tokens come from the order of
  `progression.categories`, not from title ids, so the shared widget stays
  game-neutral. The glyphs are simple printable symbols (`◆ + # * !`).
- Running rows now show the assigned heroes, payout, countdown, a 6px progress
  bar and a percentage derived from `started_utc`/`ends_utc`. `tick()` updates
  the bar and countdown only, once per second. There is no tween or continuous
  animation; the existing reduced-motion preference is untouched.
- The rewrite retains the existing auto-repeat banner, its Retry signal and the
  `blocked_reason` API. Stage-locked City operations still use
  `CommandProgression.stage_lock_text`, so their Command Level explanation stays
  visible on the board.
- `tooling/missions_viewport_capture.gd` boots the real app at 360×640, backs up
  and restores the save, captures fresh/active/locked states, and fails unless
  the live row, progress bar, visible cards, disabled lock action and 48px touch
  targets pass.
- Two focused cases cover the ready/locked split and in-place progress with the
  existing countdown. The total suite is now **138 tests**.

### Evidence

- Before: `ui_shots/missions_before_original.png` (the canonical old card stack).
- After: `ui_shots/missions_after_fresh.png`, `ui_shots/missions_after_active.png`,
  `ui_shots/missions_after_locked.png`; `ui_shots/missions.png` is the active
  state.
- Measured at 360×640: content slot **344×456**, available rows **110px**, live
  row **106px**, action buttons **48px**. Fresh shows 1 ready and 14 locked;
  active shows 3 ready and 12 locked with the live operation at **50% / 0:10**;
  locked is scrolled to y=160 with the first blocked rows and reasons visible.
- The locked capture includes City jobs whose two-line status names the Command
  Level gate, confirming the merge kept the newer progression behavior.

### Checks

- **138/138** headless tests pass, including the existing auto-repeat and
  blocked-reason coverage plus the two new Mission cases.
- Validator `OK hero_hq`, 1 pack checked, 0 invalid.
- Strict capture exits **0** with `MISSION_CAPTURE_OK`; all three images are
  360×640, the ready card and live card are visible, and the live progress bar is
  in flight.

### Known limitations

- The captures are windowed 360×640, not a new Android/emulator or physical
  phone pass. No formal playtest was started.
- No content, deploy, lock, reward or settlement rules changed.

## M1.16 — HQ first-viewport hierarchy (2026-11-05)

Status: development verification complete with 360×640 windowed captures; no
formal reviewer playtest or new Android device pass was started.

### What was wrong

At 360×640 the HQ column ordered Next objective → Command progress → Operations
Network. The first screen was mostly guidance: the network started at y=393 on
a fresh save, and at y=418 with one live job its first progress row ended at
y=628. With two live jobs the first row ended at y=561, one pixel past the
content edge at y=560. The live agency state was below the fold at the moment it
mattered most.

### What changed

- The Operations Network now leads the HQ column directly under the header. The
  next objective and compact Command progress follow below it.
- The objective is a compact strip: the heading and Step share a row, and the
  13px objective is capped at two lines.
- Command progress keeps its milestone and requirement rows, but the heading and
  next milestone share a row and the rows use 12px text with tighter spacing.
  The max-level card keeps its unlock and later-milestone copy.
- The network keeps its grid, HQ node, numbered satellites, links, travelling
  tokens, completion pulse, row text and 44px motion toggle. Its map band shrank
  from 108 to 82px, rows from 62 to 56px, and padding/gaps tightened. No new
  animation was added.
- No simulation, rewards, tabs or touch semantics changed.

### Viewport evidence

The content slot ends at y=560 in every capture; coordinates below are global.

| State | Before network / row | After first / second row | Objective bottom | Command bottom |
|---|---:|---:|---:|---:|
| Fresh | 393 / — | — / — | 421 | 518 |
| Active solo | 418 / 628 (cut) | 336 / — | 442 | 539 |
| Active squad | 351 / 561 (cut) | 336 / 392 | 469 | 553 |
| Reduced motion | 351 / 561 (cut) | 336 / 392 | 469 | 553 |

All four required states keep the next objective and complete Command card above
the fold. Every active state keeps its first live row; the two-row squad case
also keeps its second row (network bottom 400) visible. The 44px motion toggle
and 48px tab buttons retain their touch heights. Reduced motion was restored from the saved
preference and reported `reduced=true` with the animation timer stopped.

The completion capture still names the finished job and its reward in the
network header (`Alley Patrol COMPLETE  +18 Credits`) while the empty map shows
“No active operations / Deploy from Missions.” No extra motion was added.

Captures are written to `ui_shots/` by the reproducible
`tooling/hq_viewport_capture.gd` harness; that directory stays gitignored.

### Checks

- Godot headless suite: **136/136 passed**, including the new hierarchy check
  proving the live network leads the objective and Command column.
- Box geometry from the capture harness: all `objective_fits=true` and
  `command_fits=true`; both active rows fit in the squad state.
- `tooling/validate_packs.gd`: `OK hero_hq`, 1 pack checked, 0 invalid.
- No formal reviewer playtest or new Android device pass was started.

## M1.15 — City role choices and the first squad (2026-11-05)

Status: development verification complete headlessly; no formal reviewer
playtest or new Android device pass was started.

### What was wrong

The first City slice had a universal repeat. Convoy Ambush paid 430 Credits and
4 Intel in 90 seconds (4.78 Credits/s, 0.044 Intel/s) with no role gate. Joint
Raid paid 560 and 5 in 120 seconds (4.67, 0.042) and occupied a Striker and a
Support. A Support trained to 145 could therefore run Convoy alone for more of
both rewards than the two-hero raid. The route confirmed the effect: City was
reachable at 4:40 and the squad at 5:20, but Convoy was the Support's best
assignment and the team had no economic reason to form.

### What changed

- Convoy Ambush now requires a Support hero, keeping its 140 rating, 90-second
  duration and 430 Credits / 4 Intel payout. It is the Support's high-rating
  solo rather than a universal 140-rated job.
- Joint Raid keeps its two-hero, rating-130 Striker + Support gate. It now takes
  100 seconds and pays 850 Credits / 8 Intel: 8.5 Credits/s and 0.08 Intel/s,
  above the best Support-plus-Striker solo pair (Convoy + Rooftop at 7.94
  Credits/s and 0.078 Intel/s).
- Pack content version is 4. The Street gate, Command Level 3 unlock and the
  15-operation ladder are unchanged; no operation was added or removed.
- Vanguard/Hazmat remains the narrowest role window. The model's Vanguard
  reaches 130 to clear it, where Rooftop already pays more, so Hazmat is a
  first-clear target rather than a repeat. That observation is recorded for the
  deferred playtest rather than changed here.

### Route check

A deterministic fresh-save model followed the M1.14 Street route to City at 4:40
(37 dispatches, 1,549 lifetime Credits), then used ordinary targeted recruitment
and paid training with no grants. It recruited the next Tech (rating 100, 328
Credits) and Mystic (rating 95, 141 Credits) at City entry, trained the Support
to 145, the starter Striker to 130, the Vanguard to 130, the Tech to 120 and the
Mystic to 175, and bought the first payout and training research ranks when Intel
allowed (7:35 and 9:35).

| Operation | Reachable | First clear |
|---|---:|---:|
| Drone Swarm | 4:40 | 5:25 |
| Signal Pursuit | 5:20 | 6:35 |
| Hazmat Breach | 6:35 | 8:15 |
| Rooftop Pursuit | 4:40 | 7:35 |
| Medivac Escort | 4:40 | 9:05 |
| Joint Raid | 5:20 | 7:35 |
| Convoy Ambush | 5:20 | 10:35 |
| Ward Collapse | 7:35 | 9:30 |

“Reachable” means a legal composition existed, not that the hero was idle. The
first squad was reachable at 5:20 but both roles were finishing earlier work, so
it dispatched at 5:55 and completed at 7:35 (100 seconds; 51 total dispatches,
14 after City entry). All eight City firsts completed at 10:35, with 71 total
dispatches (34 after entry; 24 to City operations and 10 Street fallbacks).
There was no idle stall. The longest gap between reaches was 1:15, from Signal
Pursuit at 5:20 to Hazmat Breach at 6:35.

The resulting choices are role-shaped. Convoy is the Support's best solo, but
Raid is better when a Striker is free. Signal Pursuit is the Tech's best legal
repeat (3.57 Credits/s), Ward Collapse the Mystic's (4.27), and Rooftop Pursuit
the Striker's (3.17). Hazmat remains a bridge before Rooftop opens. No single
operation is both the best solo for every role and the best use of the pair.

### Checks

- Godot headless suite: **135/135 passed** (two new city-content cases).
- The new checks prove Convoy rejects a rating-eligible non-Support, Joint Raid
  keeps its two-hero/rating-130 Striker + Support gate and is reachable at
  125 + 145, and Raid's Credits/s and Intel/s both exceed Convoy + Rooftop.
- `tooling/validate_packs.gd`: `OK hero_hq`, 1 pack checked, 0 invalid.
- No formal reviewer playtest was started.

## M1.14 — Command Levels and the City unlock (2026-11-05)

Status: complete headlessly and in 360×640 windowed captures; no formal reviewer
playtest or new Android device pass was started.

### What was wrong

`progression.json` declared levels 1 and 2, but nothing evaluated their
requirements or derived a level from state. City operations were gated only by
rating, so the Street-to-City milestone did not exist in play. HQ had no view of
the next milestone, and Research was the next objective even though its Intel
source was the still-locked City stage.

### What changed

- `CommandProgression` derives contiguous levels from existing saved state:
  roster size, completed operations, lifetime earnings and owned roles. No
  command-level field or save-schema migration was added; an older profile is
  evaluated from the totals it already has.
- Level 3 (attainable from Street play and targeted recruitment) requires four
  agents, twelve completed operations, 1,500 lifetime Credits and a Tech or
  Support hero. It unlocks Citywide Defense. Level 2 remains three agents, six
  operations and 500 lifetime Credits.
- `Simulation.evaluate_assignment` now checks the operation's stage before role,
  rating or count gates. A locked City operation returns `stage_locked` with the
  required and current Command Level, so direct deploys, auto-repeat and every UI
  path share one rule. Settlement does not re-check the gate: a City assignment
  already running in an older save still finishes and pays normally.
- HQ gains a Command Level card showing the current level, next milestone,
  live per-requirement progress, `Unlocks: Citywide Defense` at level 2, and the
  completed unlock at level 3. The next-objective card now points to Command
  Level 3 before Research, removing the dead-end Research instruction.
- Missions and Teams show the localized stage-lock reason; the auto-repeat
  banner reports it too when a remembered operation is in a locked stage.
- Locale adds level 3 plus milestone, requirement, unlock and stage-lock copy.
  Pack content version is 3; save schema remains 1.
- National Response is deliberately outside this slice and has no command-level
  gate yet; later milestones still show the explicit `later update` state.

### Route check

A deterministic model drove a fresh save through the real simulation with no
grants: recruit the next two candidates, train the starter to level 2 with three
25-Credit sessions, then take the better-rated Tech/Support candidate for the
level 3 role requirement, dispatching every idle agent to its best legal Street
operation. It reached level 2 at 2:40 in-game (17 operations, 691 lifetime
Credits) and level 3/City at 4:40 (33 operations, 1,549 lifetime Credits). The
route used 33 dispatches: 18 Alley Patrol, 11 Stakeout and 4 Break-In Response;
Alley was first useful at 0:00, Stakeout at 0:40, and Break-In at 2:40. No agent
sat idle, and the lifetime-Credit gate, not the operation count, set the pace,
so the approved level requirements and Street rewards were left unchanged.
Break-In's window is narrow: the rating-85 Striker always prefers Stakeout, and
only the later Support hire used Break-In; that is noted for the deferred
playtest rather than changed in this slice.

### Checks

- Godot headless suite: **133/133 passed** (eight new progression cases).
  Coverage includes fresh level 1 and City refusal, level-2 requirements,
  Tech/Support recovery, a Street-only route to level 3 with zero Intel, a
  pre-command-level save, an in-flight legacy City assignment, the fresh HQ card
  and mission reason, and an existing level-3 save restoring the City unlock.
- `tooling/validate_packs.gd`: `OK hero_hq`, 1 pack checked, 0 invalid.
- 360×640 windowed captures: the HQ Command Level 1 card (next level 2), the HQ
  Command Level 2 card (next level 3 with the Tech/Support row), the locked Drone
  Swarm row in Missions and the locked Joint Raid row in Teams. All four
  requirement rows, the Tech/Support requirement label and the full `Citywide
  Defense requires Command Level 3 (current 2).` reason were legible; no clipped
  text or overlapping controls.
- No formal reviewer playtest was started.

## M1.13 — Live operations network (2026-11-05)

Status: complete headlessly and in 360×640 windowed captures; no new Android
device pass.

### What was wrong

The HQ network was a static roster diagram: every agent became an evenly spaced
satellite whether idle, solo or in a squad. It showed no live assignment, no
progress, no completion, no reduced-motion control, and it did not redraw as a
job advanced. Section 11.3 asks for the opposite: a central operation display
with hero/team activity, readable state, subtle mission motion and an efficient
reduced-motion path.

### What changed

- `HeroNetworkPanel` now maps only running assignments onto numbered satellites:
  a diamond for solo work, a three-dot cluster for a squad, a progress arc around
  each node, crew tokens travelling from HQ, and hollow outer dots for idle
  heroes. The central HQ node and grid stay flat and palette-driven.
- Each operation also gets a compact text row: number, name, solo/squad and crew,
  time left, percent complete and a progress bar. The header reports `N LIVE` /
  `N READY`, or `STANDBY` when idle. Colour is supplemental; the labels, shapes,
  counts and percentages carry the state without it.
- Owner readability review at native 360×640: the two active rows now reserve
  62 px each, with a 15 px operation/time line and a 14 px crew/percent/status
  line. The map header, card title and reduced-motion control are 14 px; the
  full-width bar is 4 px. The idle message is split into two 14 px lines so it
  cannot clip. The two-row panel is 282 px high inside the existing HQ touch
  scroller, and the bottom tab bar remains fixed.
- `app.gd` feeds the panel a small snapshot (`activities`, `idle_count`,
  `completion`) rather than giving the view mutable state. A normal tick updates
  the panel in place, so no scene nodes are rebuilt for progress.
- A completed task arms a 2.4-second completion feed with the operation name and
  paid reward. The map header changes to a check plus `… COMPLETE` and the reward,
  while one restrained success ring expands once around HQ. This survives the HQ
  rebuild that follows settlement.
- Verification caught a completion-only gap: after the last operation left the
  map, the pulse had no active work to keep the redraw timer alive. The motion
  gate now also honors the 2.4-second completion feed, with an App-level
  regression assertion.
- The network card adds a 44 px flat `Reduce motion: off/on` toggle. The choice is
  saved under `extensions["hero_hq.ui"]`, restored on boot, and stops the 5 Hz
  animation timer. Reduced mode draws static tokens and a static completion ring;
  the one-second app tick still updates progress text.
- The draw path is deliberately bounded: no shaders, no per-frame scene churn,
  about twenty grid lines, at most three numbered map nodes plus `+N more`, and
  at most eight idle dots (the header keeps the real count). The timer runs only
  while the panel is visible, has active work or a completion pulse, and the
  preference is full motion.
- `tooling/network_capture.gd` reproduces working, reduced-motion, completion and
  idle frames at 360×640 from a throwaway profile and manual clock.
- Locale adds network status, idle, overflow, motion and solo copy.

### Checks

- Godot headless suite: **125/125 passed** (four new App-level network cases).
  They cover solo + squad feed data, progress advancing with the deadline, the
  completion/reward feed and one normal payout, the reduced-motion round trip,
  and the idle ready count.
- `tooling/validate_packs.gd`: `OK hero_hq`, 1 pack checked, 0 invalid.
- Windowed 360×640 capture: `motion_running=true`; two frames 0.35 s apart
  changed 61 sampled pixels; `Reduce motion: on` set `timer_running=false`;
  completion showed `Alley Patrol COMPLETE` and `+18 Credits`; idle showed
  `STANDBY` and `4 READY`.
- Re-captured after the readability pass: working shows `2 LIVE` / `1 READY`,
  `01 Alley Patrol` at `0:06` / `70%`, and `02 Joint Raid` at `1:00` / `50%`;
  idle shows the two-line 14 px message; reduced-motion shows the 14 px toggle
  with `timer_running=false`; completion still fits its 14 px header. All
  captures are 360×640, the two rows have no clipping or overlap, and the
  bottom tab bar is visible.
- Direct before/after pair uses the same 7-agent, one-Alley-Patrol state:
  `ui_shots/network_before.png` and `ui_shots/network_after_single.png`.
  The controlled two-operation pair is `ui_shots/network_after_working.png`.
- `tooling/playthrough_demo.gd`: **PASS in-game playthrough**.
- `git diff --check`: clean.

### Known limitations

- The visual slice is verified in a 360×640 desktop window, not on a phone or
  emulator. Its layout at other aspect ratios and touch feel remain unverified.
- Abstract draw-only tokens are intentional: the codex excludes character
  animation, and no image assets were added.
- The map shows three active operations; overflow is counted in a `+N more`
  line. The completion header shows the latest completion, while every event
  still appears in Recent operations.
- Reduced motion affects this network only. There is no global accessibility
  settings screen yet, and no text-size setting.
- The map's numbered badges and `HQ` mark are 10 px decorative labels; the
  readable rows repeat the operation numbers and all operation/status text is
  14–15 px.

## M1.12 — Focus and v1.2 gameplay audit (2026-11-04)

Status: complete headlessly; no new Android device pass.

### What was wrong

The codex makes Focus a signature active-acceleration mechanic, and the pack
already declared it, but nothing loaded, validated, simulated, rendered or tested
it. The v1.2 codex was also supplied out of tree, so the repository could not
serve as its own product-context source of truth.

### What changed

- `HERO_HQ_MASTER_CODEX.md` is now at the repository root: v1.2, 101,715 bytes,
  SHA-256 `69ce6d284ae66d8ad14a428847a4064d1c9e51e43dc773373418a24e85533077`.
- `HeroFocus` (`games/hero_hq/rules/focus.gd`) owns the bank under
  `extensions["hero_hq.focus"]`: 5/5 start, +1 per 60 real seconds including while
  closed, backwards-clock safety, and 15% of current remaining time per pulse.
  Solo pulses cap at 30 seconds, squad pulses at 90, each assignment has a
  10-second cooldown, and a pulse never leaves less than one second on the clock.
  The bank, timestamps, shortened deadline and cooldown all survive a save.
- `HeroFocusCard` adds the HQ control. It shows the bank and next regeneration,
  one button per running assignment, the exact projected saving before spending,
  and a disabled reason for cooldown, empty bank, finished operation or too little
  time. The composition root settles Focus at launch and each tick, applies only
  successful pulses, saves, and logs the result.
- The pack contract now loads and validates `focus` tuning. A malformed pack
  fails validation instead of silently disabling the mechanic.
- Added five Focus rule cases, an App-level projection/tap/persistence case, the
  pack assertions and a negative pack-validation case. Also added a concurrent
  two-operation settlement/reload case, so independent jobs settle exactly once
  even when one completes before a save and the other after it.
- Locale copy covers Focus status, pulse, cooldown, empty bank, unavailable and
  refusal reasons.

### Gameplay audit against v1.2

Implemented and covered: the core deploy/settle/earn/train/recruit/research/
rebirth loop; atomic saves and offline settlement capped at 8 hours; manual squad
lineups; role-targeted recruitment; the current 15-operation ladder; Focus; and
the single-rank repeat-last-operation automation.

Deliberate newer-owner differences from the codex, preserved rather than
silently reverted: 15 operations instead of 10 solo + 8 team; 2–3-hero squads
instead of fixed three-hero teams; instant paid training instead of 1 XP/second
timed training; and the existing Command Rebirth prestige layer instead of
reserving Legacy Data. Focus's training pulse is inapplicable while training is
instant.

Remaining gameplay gaps, highest priority first:

1. Command Levels are implemented through the City unlock; later milestones and
   National Response gating remain.
2. Team depth: no named team slots, composition synergies or category mastery.
3. Automation is one remembered last operation, not configured Auto Patrol /
   team autopilot rules with slots and visible wait reasons.
4. No offline earnings report; absence settlement happens but the player only sees
   the existing settlement status line and event log.
5. Content depth: traits, specializations, legendaries, contracts, first-clear
   rewards and the codex's 22-upgrade catalogue are absent.
6. Mission strategies (Fast Response / Careful Approach), speed-based duration
   and class/skill reward modifiers are absent.
7. Recruitment uses direct role-targeted hires rather than two revealed candidate
   offers; the current flow is intentional in the build but is a codex difference.

### Checks

- Godot headless suite: **121/121 passed**.
- `tooling/validate_packs.gd`: `OK hero_hq`, 1 pack checked, 0 invalid.
- `tooling/playthrough_demo.gd`: **PASS in-game playthrough**.
- `git diff --check`: clean.

### Known limitations

- The Focus card has no Android emulator or physical-phone pass yet. The last
  device pass was M1.7 and predates Focus.
- Focus is HQ-only; Missions and Teams do not duplicate the pulse controls.
- The codex audit excludes store, ads/billing and physical-phone release work.
- A fresh checkout may need `godot --headless --editor --path . --quit` before
  tests so the global class cache registers newly added `class_name` scripts.

## M1.11 — Retry a paused auto-repeat (2026-11-04)

Status: complete; headless and Android 35 emulator verified, with the successful
manual Retry tap covered headlessly (see the device gap below).

### What was wrong

M1.10 made a blocked auto-repeat rule explain itself, but the player could only
wait. There was no action to force a fresh eligibility check after fixing a
blocker, and the paused card offered nothing to press. A rule that recovered
through training, recruitment, launch or settlement was usually restarted by an
automatic trigger, but that trigger was implicit and gave no feedback about the
manual path.

### What changed

- `AutoRepeatBanner` now renders a full-width **Retry** button while a rule is
  paused. It is hidden when the rule is armed or already waiting, so the button
  never claims an action is available when there is nothing to retry.
- `TaskBoard` and `TeamScreen` forward `auto_repeat_retry_requested`; the game
  app handles it by calling the same guarded `AutoRepeat.resume`, saving, and
  rebuilding the current tab.
- Retry re-evaluates live rating, roles, slots, assignments and saved lineup. It
  never settles a task, pays a reward, assigns directly or rewrites the lineup.
  A refusal keeps the rule and its current reason; a second request while the
  replacement is running refuses as `Waiting`.
- The visible copy comes from `ui.auto_repeat_retry`, with a game-neutral
  fallback in the shared banner.

### Checks

- 112/112 tests (110 before), validator `OK hero_hq`, `playthrough_demo.gd` PASS,
  `git diff --check` clean.
- Two new core cases: a missing member refuses Retry without changing Credits,
  tasks or assignments, then a recovered member starts exactly one job with the
  saved lineup; a locked slot refuses Retry without adding a second assignment.
- Screen coverage asserts the button is visible only while paused, forwards one
  request, keeps the same reason after a refused retry, hides while armed, and
  hides once the replacement is running.
- App-level bootstrap coverage boots the real composition root against an
  isolated profile slot. It verifies the shell and timer, the Missions and Teams
  Retry listeners, and that a blocked tap refreshes the tab without changing
  state. A controlled recovered state then presses Retry and proves exactly one
  assignment, no upfront payment, no second job from a second request, and one
  completion payout/count.
- Android 35 x86_64, controlled saves, host clock untouched:
  - Solo rating block: 500 Credits / Lv 3 / 240 XP / rating 110 / no assignments
    showed `Paused · Rooftop Pursuit`, `Available rating 110 / 120`, and Retry.
    Tapping Retry left the save unchanged: 500 Credits / 0 tasks / no
    assignments / Lv 3 / 240 XP, and the same banner remained.
  - One Train (49 Credits) took the save to 451 Credits / Lv 4 / 0 XP / rating
    130. The existing automatic retry then started `task_1` `s_rooftop`; Missions
    showed `Waiting · Rooftop Pursuit`, and Retry disappeared.
  - Locked slot: 500 Credits / 0 tasks, Support on `task_1` Alley Patrol, rule
    `[Volt, Support]` for Joint Raid showed `Paused · Joint Raid` / `Slot 2:
    Support is locked to Alley Patrol.` and Retry. Tapping Retry left only
    `task_1` running, with 500 Credits / 0 tasks, the rule and the Support lock
    intact; no `task_2` was created.

### Known limitations

- Emulator only; physical phone, release signing and icon remain.
- The successful manual Retry tap is not reachable in ordinary emulator UI.
  Training, recruitment, settlement and launch all run the existing automatic
  retry in the same event that makes the rule eligible, so it starts before the
  player can reach the button. The App-level headless test now boots the real
  composition root and covers the successful tap, one-job cap and no-payout
  behaviour; the device pass covers the visible button, a refused retry and
  blocked-to-recovered through the automatic path.
- Retry cannot cancel the operation holding a slot or change a saved lineup. It
  only rechecks the current state, so the same reason remains until that state
  changes.
- The button is on Missions and Teams only, matching the status card.
- Role, count, duplicate and removed-operation retry messages are covered
  headlessly rather than individually on the emulator.

## M1.10 — Auto-repeat blockers are visible (2026-11-04)

Status: complete; headless and Android 35 emulator verified.

### What was wrong

Auto-repeat could keep a rule for a missing, busy, under-rated or role-incomplete
lineup, but the game showed nothing: the player saw an idle screen and had to
guess why the remembered operation never started. A solo rule that failed its
rating gate was worse — resume discarded it, so there was no state left to
explain. Eligibility results also lacked the slot, role and rating context the
UI needed for a specific message.

### What changed

- `AutoRepeat.status()` returns a side-effect-free snapshot of the configured
  rule: ready, waiting for a running operation, or paused with a `Simulation`
  error code, current rating, required rating, blocked slots and missing roles.
- Recoverable solo and squad failures keep the rule. Only a missing research
  effect or an operation removed from the pack clears it, so a stale reason
  cannot remain forever.
- `AutoRepeatBanner` renders the snapshot on Missions and Teams. It names the
  operation, saved slot and locking job; messages are pack locale strings, so
  the shared framework stays title-neutral.
- A rule whose own replacement is running reads as `Waiting`, not `Paused`,
  even though that job locks both saved squad slots. A genuine lock elsewhere
  still names the operation holding the member.
- `App` retries after training and recruitment as well as launch and settlement,
  so a recovered rating gate starts the rule immediately instead of waiting for
  another completion.
- `Simulation` eligibility results now carry `slot_index`, `agent_id`,
  `assignment_id`, `role_id`, `duplicate`, and required/given agent counts.

### Checks

- 108/108 tests (103 before), validator `OK hero_hq`, `playthrough_demo.gd` PASS.
- New headless coverage: solo rating block and recovery, missing-member status
  and slot, active-job lock, role/count refusals, removed operation, and banner
  refresh/clear on both Missions and Teams.
- Android 35 x86_64, controlled saves, host clock untouched:
  - Solo rating: 500 Credits / Lv 3 / 240 XP / rating 110 showed
    `Paused · Rooftop Pursuit` and `Available rating 110 / 120`. One Train
    (49 Credits) reached Lv 4 / rating 130; the rule immediately deployed
    `task_1` `s_rooftop`, and the banner changed to
    `Waiting · Rooftop Pursuit / Starts when Rooftop Pursuit finishes.` The
    disk save was 451 Credits / Lv 4 / 0 XP / one assignment.
  - Locked slot: 500 Credits with Support on `task_1` Alley Patrol showed
    `Paused · Joint Raid / Slot 2: Support is locked to Alley Patrol.` When
    Alley Patrol finished naturally (18 Credits / 8 XP / 1 task), the rule
    re-armed `task_2` Joint Raid on the saved lineup. The banner changed to
    `Waiting · Joint Raid / Starts when Joint Raid finishes.` Save: 518 Credits
    / 1 task / both agents on `task_2`.
  - Missing member: the rule named `[Volt, Support]` but only Volt and a reserve
    were on the roster. Teams showed `Paused · Joint Raid / Slot 2: the saved
    hero is no longer on the roster.` No assignment was created, no reserve was
    substituted, and the rule stayed on disk with 500 Credits / 0 tasks.

### Known limitations

- Emulator only; physical phone, release signing and icon remain.
- Device checks cover rating, missing member, a lock clearing by completion and
  the rule's own running job. Role, count and removed-operation messages are
  covered headlessly.
- A missing member is a controlled save case; normal gameplay has no roster
  removal, so this is a legacy/corrupt-save recovery path.
- Recovery is automatic on training, recruitment, launch or settlement. M1.11
  adds an explicit Retry control for a paused rule.
- The status card is shown on Missions and Teams; HQ and Heroes do not duplicate
  it.

## M1.9 — Squad auto-repeat preserves its lineup (2026-11-04)

Status: complete; headless and Android 35 emulator verified.

### What was wrong

Auto-repeat persisted only the task id and resumed through `Simulation.deploy`,
which auto-selects the strongest free agents. A squad therefore did not replay
the lineup the player deployed: a stronger reserve could be substituted, or the
rule could fail even though the saved squad was eligible.

### What changed

- `AutoRepeat` rules now store the deployed `agent_ids` for a squad. Resume
  validates that exact lineup and schedules it with `Simulation.assign_task`;
  solo tasks still use the one-agent auto-select path.
- A missing, busy, under-rated or role-incomplete lineup refuses the re-arm. The
  rule is kept for a later retry, and the refusal changes neither rewards nor
  the task count.
- `App` passes the deployed lineup into the rule on squad deploy. Rebirth already
  called `AutoRepeat.forget`; the device pass now covers that path too.
- Four headless cases: the lineup survives save/load, resume uses the saved
  lineup instead of a stronger auto-pick, and missing/busy members refuse
  without a second payout.

### Checks

- 103/103 tests (99 before), validator `OK hero_hq`, `playthrough_demo.gd` PASS.
- Android 35 x86_64, controlled saves, host clock untouched:
  - UI-created rule: Teams deploy of the saved `[Volt, Support]` raid created
    `task_1` and a rule carrying both ids; a force-stop/relaunch kept the
    assignment, both activity locks and the reserve Support free. Making that
    job due and relaunching paid 560 Credits + 5 Intel / 26 XP each once, then
    re-armed `task_2` with `[Volt, Support]`; a quick reload kept 1560 / 5 /
    one task and did not pay again.
  - Seeded end-to-end: 1000 Credits plus a past-due raid, rule and manual preset.
    Launch: 1560 / 5 / 1 task, `task_2` on `[Volt, Support]`, stronger reserve
    free. Reload unchanged. A 125 s closed absence paid again to 2120 / 10 /
    2 tasks and re-armed `task_3` with the same lineup.
  - Missing member: Support was removed from the roster while the rule named
    `[Volt, Support]`. Settlement paid once (1560 / 5 / 1), then no re-arm, no
    substitution of the available reserve, and the rule stayed for a retry; a
    reload stayed at 1560 / 5 / 1.
  - Busy member: Support was active on another job while the rule named
    `[Volt, Support]`. Settlement paid the due raid once (1560 / 5 / 1), the
    other job stayed active, no re-arm occurred, and a reload did not pay again.
  - Rebirth: with a rule, an active job and chips available, the two-step
    Rebirth banked 4 chips, reset agents to level 1 and Credits to 50, cleared
    the assignment and the automation rule, and preserved the squad preset and
    research rank.

### Known limitations

- Emulator only; physical phone, release signing and icon remain.
- Timed training still does not exist in v1.
- A missing or busy lineup kept its rule without alerting the player; M1.10 adds
  the live status banner and retry path.

## M1.8 — Offline progression and persisted auto-repeat (2026-11-04)

Status: complete; headless and Android 35 emulator verified.

### What was wrong

The operations loop already settled a job on launch, but the automation rank it
sold was memory-only: the task chosen on deploy lived in `App._auto_task_id`, and
a force-stop/relaunch forgot it. Launch settlement also never ran the auto-repeat
path, so a job that finished while the app was closed was never replaced.

### What changed

- `AutoRepeat` (`framework/core/auto_repeat.gd`) is the game-neutral automation
  helper. It stores the remembered task in `GameState.automation_rules` under a
  `repeat_task` rule, so the choice is part of the save. `resume()` deploys at
  most one replacement, only when the research is owned and no job is running;
  a locked rule or a task the roster can no longer field is dropped.
- `App` re-arms automation after launch settlement and before the shell is built,
  remembers the task on solo/squad deploy, and forgets it on rebirth.
- Four headless cases cover rule persistence through save/load, a single
  replacement after settlement plus the busy refusal, a missing research rank,
  and an under-rated task being forgotten.
- README and `docs/ANDROID.md` record the device checks and the remaining limits.

### Checks

- 99/99 tests (95 before), validator `OK hero_hq`, `playthrough_demo.gd` PASS.
- Android 35 x86_64 emulator, controlled saves with relative `ends_utc` values
  (host clock untouched):
  - Solo mission: seed 1000 Credits, Alley Patrol 10 s past due, 40 s since the
    last settlement. Launch: 1018 Credits, 1 task, 8 XP, assignment cleared,
    Volt available, `last_settled_utc` advanced. A second force-stop/relaunch
    kept 1018 / 1 / 8.
  - Training (instant in v1, so there is no in-progress timer): 1000 → 975
    Credits and 0 → 40 XP; reload unchanged. Two more sessions reached Lv 2
    (925 Credits, 0 XP, power 6 / speed 7 / skill 5); another reload unchanged.
  - Auto-repeat: seed 1000 Credits, one past-due Alley Patrol, `ops_automation`
    and a remembered `s_alley`. Launch settled it and re-armed `task_2`
    (1018 / 1 task / 8 XP). Killing the app for 25 s and relaunching settled
    `task_2` and re-armed `task_3` (1036 / 2 / 16). A quick relaunch did not
    double-pay (1036 / 2, `task_3`). Leaving it open settled `task_3` and
    re-armed `task_4` (1054 / 3 / 24); the next relaunch settled `task_4` once
    and re-armed `task_5` (1072 / 4 / 32). The rule survived every cycle.

### Known limitations

- Emulator only; no physical phone, release signing or icon yet.
- Timed training does not exist in v1, so the "training in progress" case has no
  state to exercise.
- Squad auto-repeat was not separately repeated at M1.8; M1.9 covers it and
  fixes lineup persistence.

## M1.7 — Manual team lineups (2026-11-04)

Status: complete; headless and Android 35 emulator verified.

### What was wrong

Teams previewed the strongest available set and could only save that suggestion.
There was no way to put a specific hero in a specific squad operation, so the
squad half of the game played itself.

### What changed

- `TeamScreen` keeps a draft lineup per operation, one picker per required agent.
  A draft seeds from the saved preset, or from auto-selection when none exists,
  so the tab still opens with a usable suggestion.
- Tapping a slot opens an inline chooser under it: `Empty` plus the roster sorted
  by rating. Agents already in another slot and deployed agents stay visible but
  disabled, and both the slot and the card say `deployed`. The card explains an
  incomplete lineup (`Fill every slot to deploy`), a missing role, a deployed
  agent or a low rating, using the same evaluation the deploy path runs.
- `Save squad` writes the draft only when every slot is filled and unique; an
  incomplete row disables both Save and Deploy. `Clear` removes the preset and
  re-seeds the suggestion.
- The chooser is inline rather than an `OptionButton` popup: on-device testing
  showed popup item taps landing on the row above, opening the wrong slot's menu.
  Deploy, Save and Clear also became full-width rows because three buttons side
  by side were too cramped to hit once Clear appeared.
- `TouchScroll` now also swallows the mouse release Godot emulates from a touch.
  Scrolling moves the control under the finger, so before this a drag that ended
  on a slot still opened that slot's chooser.
- Locale keys `ui.squad_slot`, `ui.slot_empty`, `ui.slot_busy` and
  `ui.blocked_squad_incomplete`; the Teams hint now says to tap a slot.
- Three headless cases: slot editing with duplicate refusal and a deployed
  draft, empty-slot reason plus save/reload, and a deployed agent disabling its
  choice with the right reason. The playthrough demo now edits slots, refuses a
  duplicate, empties and refills a slot, saves a manual lineup, and asserts the
  preset survives rebirth and a reload.

### Checks

- 95/95 tests, validator `OK hero_hq`, `playthrough_demo.gd` PASS.
- Android 35 x86_64 emulator with a seeded three-agent roster: emptied a slot
  (reason shown, Deploy and Save disabled), refilled it, saved it as
  `[hero_volt, op_0100]`, deployed it (assignment `task_2`, both agents
  `assigned`), saw `Hero already deployed`, and confirmed the preset and lock
  survived a relaunch. A deliberately non-default lineup
  `[hero_volt, op_0101]` then saved and survived a force-stop/relaunch.

### Known limitations

- Emulator only; release signing, an app icon and a physical phone run remain.
- One saved lineup per operation; named multi-preset teams are not part of v1.

## M1.6 — Android export and emulator pass (2026-11-04)

Status: complete on an emulator. Not verified on a physical phone.

### What was wrong

There was no Android export preset, and no phone had ever run the game. Setting
up the toolchain and driving the debug build on Android 35 surfaced four defects
that desktop testing could not:

- `ScrollContainer` ignores touch drags, so content below the fold — including
  the Rebirth button on Upgrades — was unreachable on a phone.
- Blocked-reason labels on Missions, Heroes (training) and Teams sat beside their
  button in an HBox. A wrapping label has zero minimum width there, so it
  rendered as a one-character-wide vertical column and stretched the button to
  hundreds of pixels tall.
- Research said "Not enough Credits" for a purchase priced in Intel.
- A squad that was one hero short reported "No free hero for this task".

### What changed

- `export_presets.cfg`: Android debug preset, arm64-v8a + x86_64, immersive
  fullscreen, tests/tooling/docs excluded. No longer gitignored.
- `framework/ui/touch_scroll.gd`: a neutral `ScrollContainer` that translates
  finger drags into `scroll_vertical`, handles them before the GUI (so it works
  over buttons), and swallows the release only after a real drag so a scroll
  cannot press the control it started on. Used by all five scrolling screens.
- Reasons moved to their own full-width lines in `TaskBoard`, `RosterScreen` and
  `TeamScreen`; the agent-count reason now carries the required hero count; the
  insufficient-resource reason formats the actual resource name.
- `docs/ANDROID.md` records the toolchain, commands, emulator caveats and the
  verified checklist.

### Checks

- 92/92 tests; validator `OK hero_hq`; `playthrough_demo.gd` PASS; windowed
  capture of all five tabs unchanged apart from the corrected reasons.
- Debug APK builds, installs and runs on an Android 35 x86_64 emulator (Pixel 6
  AVD, `-gpu host`). Verified there: onboarding, first mission and payout, all
  five tabs, force-stop/relaunch persistence, role-targeted Tech hire, research
  purchase, and a two-step rebirth (4 chips, resources reset, roster kept at
  base ratings, research kept).
- Emulator-only caveat: SwiftShader cannot link Godot's canvas shader (261
  fragment uniform vectors) and renders black; `-gpu host` is required.

### Known limitations of this pass

- No physical phone, no release signing, no app icon.
- The rebirth check used a hand-seeded save; the rest was played through the UI.
- Ads and billing remain untouched by design.

## M1.5 — Playable v1: guidance, role hiring, honest checks (2026-11-04)

Status: complete. Content version stays 2; no new operations or tuning blocks.

### What was wrong

Three defects could end a run instead of slowing it:

- Role-gated operations (Signal Pursuit needs a Tech, Joint Raid needs Support)
  could stall the ladder. Recruits were drawn uniformly from a 200-slot pool, so
  a player could hire twenty agents and never roll the one role the next
  operation demanded.
- A fresh save explained nothing. HQ drew a network and a status row; the only
  instruction was implicit in whichever button happened to look enabled.
- Research ranks in Upgrades stayed tappable when Intel could not pay for them,
  so a tap did nothing and said nothing.

The end-to-end demo had two blind spots of its own: it hired randomly until a
Tech appeared, so it never exercised the picker, and a runtime error inside the
playthrough still printed PASS because the failure list stayed empty.

### What changed

- `Recruitment.recruit` takes an optional role id. A targeted hire scans forward
  from the next unclaimed slot and **skips** slots that do not match, so the
  player trades breadth for certainty rather than paying twice. A pool with no
  such role returns `role_unavailable` instead of silently spending.
- `RosterScreen` gains a role picker (`Any role` plus every declared role); the
  choice travels with `recruit_requested(role_id)` and the offer, price and
  blocked reason follow it.
- `app.gd` derives a five-step **Next objective** card from live state — deploy,
  train to level 2, recruit a second operative, buy a research rank, rebirth —
  so HQ always names one thing to do next. It re-arms after a rebirth.
- `PrestigeScreen` disables a research rank it cannot pay for and prints why.
- `tooling/playthrough_demo.gd` hires its Tech through the picker, asserts one
  hire is enough, checks the objective advances and re-arms after rebirth, and
  fails when the run does not reach the end.
- `tooling/balance_report.gd` considers only operations the roster can staff;
  filtering on rating alone had it pick a squad job with no roles available and
  stop at 2:00 of a two-hour horizon.

### Checks

- 92/92 tests (three new: targeted hire, every declared role targetable, picker
  signal carries the role).
- `playthrough_demo.gd` PASS from a deleted profile — a genuine fresh save —
  through the role gate, research, rebirth and a save/reload.
- `balance_report.gd`: 2:01 h, 68 operations, level 13, 51,871 Credits earned.
- `long_run_report.gd` PASS: 207 runs, ×11.45, longest single wait 14m 00s.
- Validator `OK hero_hq`; windowed capture of all five tabs at 360×640.

### Known limitations

- No Android export preset, keystore or device run: the loop is verified in a
  360×640 desktop window, not on a phone.
- Teams deploys auto-selected squads plus one saved lineup per operation;
  choosing members slot by slot is not built.
- Ads and billing remain untouched by design.

## M1.4 — Saved squad lineups (2026-11-04)

Status: complete. No content change.

### What changed

- `framework/core/squads.gd`: one saved lineup per operation, stored on the
  already-serialized `GameState.squads` map as `squad_<task_id>`. Saving checks
  the ids are non-empty, unique and on the roster; removal is idempotent.
- `TeamScreen` prefers the saved lineup over auto-selection, marks it `Saved`,
  and adds `Save squad` / `Update squad` / `Clear` controls. Deployment carries
  the chosen agent ids into `Simulation.assign_task`, so a lineup that has since
  become busy or under-rated is refused with the usual blocking reason.
- `app.gd` saves immediately when a lineup changes and deploys the squad through
  the explicit-member path.

### Checks

- 89/89 tests (five preset tests and the save/clear screen test are new).
- `playthrough_demo.gd` PASS; windowed capture of all five tabs; validator OK.

## M1.3 — Playable UI pass and squad screen (2026-11-04)

Status: complete. No content change.

### What was wrong

The game window drew only its header and tab bar. `ScreenShell` sized itself
with `set_anchors_preset`, which preserves a control's current (zero) size, so
the content slot was 0 px tall and every screen that passed its headless tests
drew nothing. Switching to `set_anchors_and_offsets_preset` then centred the
column at its minimum size, because that helper defaults to minimum-size mode
rather than fill.

The shell also treated the desktop monitor's Windows safe area as a phone notch:
a `(1080, 472)` inset on a 2560×1440 display scaled into the 360×640 window
produced 151 px left and 209 px top margins.

### What changed

- `framework/ui/ui_layout.gd`: `UILayout.fill` sets full-rect anchors and zeroes
the offsets, which is what filling a parent actually requires.
- `ScreenShell`, `TaskBoard`, `RosterScreen`, `PrestigeScreen` and the app root
  use it. Safe-area insets apply only when the window spans the display (phone
  or fullscreen), so a desktop window gets none.
- Research rows keep a non-wrapping rank label; a wrapping label in an HBox has
  zero minimum width and was squeezed into a one-character column.
- `framework/ui/screens/team_screen.gd`: the Teams tab lists every multi-agent
  operation with its required roles, the auto-selected squad with individual
  ratings, the squad average against the gate, missing roles and the blocking
  reason. Deployment uses the same `Simulation.deploy` path as Missions.
- `tooling/ui_capture.gd`: windowed capture of every tab at 360×640, with the
  player's save backed up and restored, for visual checks the headless suite
  cannot make.

### Checks

- Windowed capture at 360×640 on the RTX 4060: all five tabs render.
- `playthrough_demo.gd` PASS; 83/83 tests; validator `OK hero_hq`.

## M1.2.1 — Roster survives rebirth, in-game playthrough (2026-11-04)

Status: complete. No content change.

### What was wrong

`docs/BALANCE.md` promised that a rebirth keeps the roster at pack base values,
but `Prestige._reset_run` cleared `state.agents` and reseeded only the starters.
Every recruited hero — up to 240 of them, each bought with Credits — vanished on
rebirth, which made the collection layer pointless in a loop that rebirths often.

### What changed

- `AgentRules.reset_progress` rewinds an agent to level one with base attributes,
  no XP and no assignment. Growth is linear per level, so subtracting the same
  growth per level restores the exact starting attributes without storing a
  second copy.
- `Prestige._reset_run` rewinds every existing agent instead of clearing the
  roster, then reseeds any missing starter. Chips, rebirth count and lifetime
  totals are untouched, as before.
- `tooling/playthrough_demo.gd` boots the real app scene and plays it through the
  real UI — Missions, Heroes and Upgrades tabs, Deploy, Train, Recruit, Research
  and the two-step Rebirth — faking only the clock. It snapshots and restores the
  player's save, so a failed demo cannot damage real progress.

Checks: `playthrough_demo.gd` PASS, 81/81 tests, validator `OK hero_hq`.

## M1.2 — Long-term curve and Command Rebirth (2026-11-03)

Status: complete and measured. Content version stays 2 (additive `prestige` block).

### What was wrong

Content v2 runs out of ladder after ~11 minutes and then waits grow roughly 1.4×
per level forever: 15, 21, 29, 41, 59 minutes, then hours. A first session is fine
and a first week is not. The fix is the genre-standard one — a rebirth layer — but
it has to be built so the meta-currency cannot outrun the cost curve.

### Research used

- Prestige payouts should be sub-linear in progress (square root for Realm Grinder,
  cube root for Cookie Clicker): each doubling then costs roughly 4× (resp. 8×) the
  earnings — Pecorella, *The Math of Idle Games, Part III*.
  <https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii>
- The first prestige must land inside the first sitting and waits should lengthen
  as engagement decays — Guan, *Idle Game Design Principles*.
  <https://ericguan.substack.com/p/idle-game-design-principles>
- Resets should read as a soft chapter: the player keeps the permanent bank and
  loses only what is meant to be rebuilt.
  <https://dropletidle.com/pages/blog/guide-to-idle-game-prestige-mechanics/>

### What changed

- `framework/core/prestige.gd`: pack-driven rebirth math. Chips are a function of
  **lifetime** earnings (`chips = floor(gain_factor · (lifetime/scale)^exponent)`)
  and the multiplier is `1 + bonus_per_chip · chips`.
- Chips are recomputed, not awarded per run. The first implementation banked on
  reset, and the seven-day model showed the multiplier reaching **×6424** — a run that
  earned more could be reset repeatedly to double-dip. Lifetime-derived chips made
  the bank monotone and the same progress can never pay twice.
- `Simulation._complete_assignment` multiplies every payout by the multiplier and
  tracks run earnings; `Prestige.rebirth` clears resources, assignments, levels
  and run earnings while keeping chips, rebirth count and lifetime totals, and
  resets the settlement stamp so no time is paid twice.
- `framework/ui/screens/prestige_screen.gd`: live chips, multiplier, lifetime
  progress toward the next chip, and a two-step confirm so a tap cannot wipe a
  run. Wired to the Upgrades tab.
- Pack data: `prestige` block (`threshold_amount 4000`, `scale 1000`,
  `exponent 0.45`, `gain_factor 2`, `bonus_per_chip 0.05`, `min_level 7`); content
  checks validate the block when present, like `leveling` and `training`.
- `tooling/long_run_report.gd`: seven days of the real simulation with a rebirth
  policy; fails when any single level-up wait exceeds 30 minutes.
- Docs: `docs/BALANCE.md` records the formulas, the curve and the sweep behind
  `exponent 0.45`.
- Tests: **64** (up from 54): payout formula, no-double-dip invariant, both gates,
  reset contract, boosted payouts, save round-trip, panel arming behaviour.

### Measured result (7-day model)

205 rebirths, average run 49m 10s (17m 10s at the start, ~1h 05m by run 200),
208 chips banked for **×11.40** on every payout, and a longest single wait of
**14m 00s** — inside the 30-minute budget. `exponent 0.5` produced 459 resets at
22 minutes each (a treadmill); `0.4` stretched the worst wait to 42 minutes.

### Known limitations of this pass

- Content is still six tasks. Rebirth deepens the existing ladder (level 15–16 by
  day 7) but adds no new tiers; more tasks and squads are the next content axis.
- Intel still has no sink, so it rides along as score rather than a resource.
- The model's policy rebirths at the earliest worthwhile moment, which is a lower
  bound on human run length; it measures waits, not enjoyment.

## M1.1 — Power-curve tuning (2026-11-03)

Status: complete and measured. Content version bumped to 2.

### What was wrong

`tooling/balance_report.gd` simulates a greedy player against the real pack. Run
against the first M1 numbers it showed three defects:

- 250 starting Credits bought two level-ups instantly, so three of the four tasks
  were unlocked at **t = 0** and the player never touched the early tiers.
- Income per minute was nearly flat across tiers (54, 60, 61, 86/min), so a new
  unlock was not a power spike worth chasing.
- Levels accelerated instead of slowing: task XP (24–110) dwarfed the XP curve
  (thresholds rising by only 40), so the curve inverted.

### Research used

- Idle-game cost curves are exponential while rewards are linear; when costs
  outrun rewards too early it feels bad, and manual per-upgrade tuning does not
  scale — Gabriel Padinha, *Balancing Tips: How We Managed Math on Idle Idol*.
  <https://www.gamedeveloper.com/design/balancing-tips-how-we-managed-math-on-idle-idol>
- Growth must stay multiplicative to stay perceptible (Weber–Fechner): each step
  should read as a visible multiple of the last, with cost growing slightly faster
  than reward to slow the pace. First sessions run 15–60 minutes of active play,
  and optimal wait times lengthen as engagement decays — Eric Guan, *Idle Game
  Design Principles* <https://ericguan.substack.com/p/idle-game-design-principles>
- Progression should be deliberately "bumpy" with slow and fast stretches, and
  the model is a rough feel-check, not a prediction — Anthony Pecorella,
  *The Math of Idle Games, Part III*.
  <https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii>

### What changed

- Starting Credits **250 → 50**: one training session, no free levels.
- Task ladder **4 → 6 tiers** with gates 60/80/100/120/140/160, one gate per
  level (+20 rating from the Striker growth curve).
- Income per minute now steps **1.4–1.7× per tier** (54 → 90 → 128 → 192 → 289 →
  454), so every unlock is a felt upgrade.
- Task XP cut to a trickle (8–30) and the XP curve raised to `base 120, +80/level`,
  making **training the power source and tasks the income source** rather than the
  other way round.
- Training gives **+40 XP for 25 Credits at ×1.4 cost growth** (was +30 at ×1.5),
  which keeps cost growth ahead of reward growth without stalling.
- Measured result: tiers unlock at 0:00, 0:40, 2:10, 5:10, 8:10, 11:10; levels then
  slow to 15:10, 21:10, 29:10, 41:10, 59:10.

### Known limitations of this pass

- Intel has no sink yet, so it is included in the rate model at face value. That is
  a proxy, not a finished economy; M4 upgrades are where it should be spent.
- The ladder still ends after ~11 minutes with nothing new to unlock. Levels keep
  going, but new content (recruitment, squads) is M2–M3 work.
- The report models one greedy agent, not humans. It catches walls and inverted
  curves; it cannot judge whether the game is *fun*.

## M1 — Single-hero functional loop (2026-11-03)

Status: complete, gate met in a headless environment. No Android, ad or billing
work exists at M1.

### Delivered

- [x] `framework/core/agent_rules.gd`: neutral rating (`5 × sum of attributes`),
      XP curve read from the pack, and level-ups that apply the agent's role
      growth curve. No attribute name is hardcoded.
- [x] Assignment lifecycle in `Simulation`: `evaluate_assignment` (task exists,
      agent count, agents exist, availability, required roles, rating gate),
      `assign_task`, deterministic `auto_select_agents` (required roles first,
      then rating, then id) and a one-call `deploy` for the UI.
- [x] Settlement in `simulate_delta`: assignments whose deadline has passed are
      completed in `(ends_utc, assignment_id)` order — rewards paid once,
      lifetime stats recorded, task XP granted to each assigned agent, level-ups
      applied, agents freed, and a `task_completed` event plus any `level_up`
      events returned. Online ticks and launch-time absence use this one call.
- [x] Paid training: cost derived from pack tuning with `cost_growth` escalation,
      affordability check, XP grant and level-ups. `train_agent` returns a
      structured result instead of mutating silently.
- [x] `framework/ui/screens/task_board.gd`: active operations with live
      countdowns, one card per declared task, deploy button disabled with the
      pack's own reason string, 48px minimum tap targets, one-second `tick()`
      that updates only countdown labels.
- [x] `framework/ui/screens/roster_screen.gd`: rating, level, XP progress bar and
      training control per agent; hidden entirely when a pack declares no
      training rules.
- [x] `framework/ui/text_format.gd` for amounts, durations and reward strings.
- [x] App wiring: a single 1-second `Timer` settles time and refreshes the shell,
      HQ logs the last four results, deploys and training save immediately, and
      progress is saved periodically while idle.
- [x] Restore guard: a save that restores without a roster is reseeded from pack
      data, so an old or incomplete save can never leave the player unable to act.
- [x] Content: four-step task ladder (20 s / 45 s / 90 s / 150 s, rating gates
      60/70/80/90, 18–210 Credits plus Intel at the top end), `leveling` and
      `training` tuning blocks, and locale strings for every new label.
- [x] Validator: optional `leveling`/`training` blocks are checked when present
      (positive XP base, non-negative growth, `cost_growth >= 1`, training must
      spend a declared resource) and task `xp` must be finite and non-negative.
      Packs that omit the blocks keep the framework defaults and stay valid.
- [x] Tests: **54** (up from 31), adding task lifecycle, settlement and cap,
      training, save round-trip with a running assignment, roster healing, and
      headless screen tests for both new screens.
- [x] `tooling/demo_loop.gd`: deterministic headless walkthrough of the loop.

### Decisions recorded in this milestone

- **Rating formula:** `5 × sum(attributes)`, which puts the starter at 70 and keeps
  ratings small integers. A squad's rating is the mean of its members, so M3 squads
  work without changing the gate semantics.
- **Task XP** is granted in full to each assigned agent. With one agent in M1 this
  is unambiguous; M3 revisits whether a squad splits or duplicates XP.
- **Training is instant** (no timer) in M1. Timed training arrives with the
  automation milestone rather than being half-built now.
- **No cancel button.** M1 has no cancel requirement; adding one would need a
  refund policy that is not specified yet.
- **Save schema stays v1.** `stats` is additive and defaults to `{}` on load, so M0
  saves load unchanged; no migration path is needed yet.
- **Offline and online share one completion rule**; there is deliberately no
  separate "offline earnings" formula that could drift from live play.

### Known limitations / not done at M1

- No recruitment, squads, upgrades, automation, focus or command-level progression
  screen: the ladder is declared in data but not yet enforced or rewarded.
- Android export, device testing, ad SDKs and Play Billing are untouched (M6–M7).
- `HERO_HQ_MASTER_CODEX.md` is still not in the repository (supplied as a chat
  attachment).
- Screenshots could not be produced in the CI-style sandbox: it has no X server and
  no root to install one, so all verification is headless.

Next recommended milestone: **M2 — recruitment and roster depth.**

## M0 — Repository / project foundation (2026-11-03)

Status: complete, gate met in a headless environment. Not yet verified on Android
(no Android export or SDK work exists at M0).

### Delivered

- [x] Godot 4.7.2 GDScript project: portrait 360×640 canvas, `canvas_items` stretch
      with `expand` aspect, portrait orientation, `gl_compatibility` renderer,
      touch-from-mouse for desktop testing.
- [x] `framework/` and `games/hero_hq/` structure with a game-neutral shared module
      set: `game_state`, `clock`, `simulation`, `save`, `pack`, `pack_loader`,
      `pack_validator`, `theme_tokens`, `screen_shell`, `resource_bar`.
- [x] Pluggable clock (`Clock`, `Clock.Manual`) so no simulation code reads wall time
      directly and tests are deterministic.
- [x] `game_id`-scoped save paths with atomic temp-file commit, previous-profile
      backup, backup recovery, and refusal of foreign/newer saves.
- [x] `GamePackLoader` + `PackValidator` with stable error codes: required manifest
      fields, schema version, id syntax, path-escape rejection, unique ids,
      resolved locale keys, theme tokens as hex, task/role/stage/category/resource
      reference checks, mechanically bounded numbers, requirement types.
- [x] HERO//HQ pack: manifest (5 tabs, credits/intel, 8h offline cap), 5 classes,
      starter hero from data, Alley Patrol task, 3 sectors + 5 categories, theme
      palette, full English locale.
- [x] App scene: loads and validates the pack, restores or creates state, settles
      absence through the shared simulation path, saves, then builds the themed
      shell with pack-driven tabs and an HQ placeholder that draws an operations
      network from live roster data. Invalid packs render a readable error screen
      instead of crashing.
- [x] Headless test runner (`tests/run_tests.gd`) with a dependency-free assertion
      harness and 31 tests over simulation, saves, pack validation, pack loading,
      theming, the tab shell, and framework neutrality.
- [x] `tooling/validate_packs.gd` CI gate; README with run instructions.

### Decisions recorded in this milestone

- **Engine pinned** to 4.7.2 stable (current stable as of this date).
- **Save schema v1**, first version, so there is no migration path yet. The
  `newer_schema` / `unsupported_schema` guards already exist for when schema 2 lands.
- **Starter hero attributes** `power 5 / speed 5 / skill 4` at level 1. The spec's
  rating formula (10·power + 4·skill + 2·level) yields 68, clearing Alley Patrol's
  minimum of 60, so the opening mission is reachable without a balance change. The
  rating formula itself is not implemented at M0 (it is M1 work).
- **Offline settlement** is wired end to end but has nothing to settle yet: M0
  advances the settlement stamp and applies the pack's 8h cap, and later systems
  (training, tasks, arbitration) will add events to the same call.
- **Component scenes built in code.** Part C lists `framework/ui/components/*.tscn`;
  the reusable widgets are `.gd` classes composing built-in Control nodes instead,
  which keeps the shared UI diffable and avoids hand-authored scene files. Behaviour
  and ownership boundaries are unchanged.

### Known limitations / not done at M0

- Android export, device testing, ad SDKs and Play Billing are untouched (M6–M7).
- `HERO_HQ_MASTER_CODEX.md` is not in the repository yet; it was supplied as a chat
  attachment, not as a file in this workspace.
- Only one task definition is committed; the remaining nine solo and eight team
  operations are M1–M3 content.
- HQ is a placeholder: it shows real roster and resource state but cannot dispatch.
- No accessibility/reduced-motion pass and no numeric compaction yet (M5).

Next recommended milestone: **M1 — single-hero functional loop.**

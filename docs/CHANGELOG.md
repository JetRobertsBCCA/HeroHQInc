# Changelog

All work on HERO//HQ and the shared framework. Milestones follow Part D of the
design specification.

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

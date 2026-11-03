# Changelog

All work on HERO//HQ and the shared framework. Milestones follow Part D of the
design specification.

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
      harness and 24 tests over simulation, saves, pack validation, pack loading,
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

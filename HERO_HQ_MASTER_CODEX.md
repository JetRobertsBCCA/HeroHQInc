# HERO//HQ — Unified Game Design & Codex Development Specification

**Version:** 1.2 — Single-document edition  
**Date:** November 3, 2026  
**Purpose:** One self-contained specification for implementing HERO//HQ on a reusable incremental-game framework using Codex and Godot 4.x.  
**Status:** Design / implementation handoff; not an existing runnable Godot project.

> **ONE DOCUMENT RULE:** This file is the only design/handoff document Codex needs to read to begin. It consolidates the operating instructions, complete game design, reusable framework architecture, milestone checklist, future theme roadmap, and illustrative content-pack fixtures. You may create source-code files, game data, automated tests, and change notes as part of development; do not require a second design-specification file for context.
>
> **HARD MONETIZATION REQUIREMENT:** Never display popup, interstitial, banner, native feed, app-open, automatic, forced, or unsolicited advertisements. The only permitted format is an explicit **player-initiated, player-confirmed rewarded ad** giving a small optional bonus. No ad or purchase is required to play, progress, recruit, train, deploy, or automate. This rule applies to HERO//HQ **and every future game using the framework**.

## Contents and source-of-truth order

- **Section 0:** Start Here — how to hand this file to Codex and the exact initial command.
- **Part A:** Codex Operating Rules — technical decisions, behavior and delivery contract.
- **Part B:** HERO//HQ Game Design — scope, missions, heroes, teams, balancing, UI, economy and monetization.
- **Part C:** Reusable Framework Engineering Contract — abstraction boundaries, generic data model, hooks, validation, testing.
- **Part D:** Implementation Milestones — ordered M0–M7 tasks and acceptance gates.
- **Part E:** Future Theme Roadmap — 30 possible follow-up titles and reuse mappings; **none authorized for implementation now**.
- **Part F:** Reference Theme-Pack Fixtures — illustrative JSON that demonstrates two game configurations in a single document.

**Interpretation priority:** (1) hard product restrictions above and any newer owner decisions, (2) Part B for gameplay and MVP scope, (3) Part C for architecture and data contracts, (4) Part A for Codex behavior, (5) Part D for execution order and verification, (6) Part F as **non-production illustrative samples**, and (7) Part E as ideas only. If there is a contradiction, preserve the higher-priority requirement and report it instead of quietly changing scope.

**Locked launch scope:** Android-first, portrait, offline-first; three playable sectors, five classes, ten solo missions, eight team operations, three launch legendaries, earned manual-to-automatic progression, optional rewarded ads only, and direct-priced optional nonconsumable purchases. The full five-sector/cosmic/prestige vision is **post-launch** unless the owner changes this decision.

---

## Section 0 — Start Here: Codex Quick Start

1. Create or open a Godot 4.x GDScript repository. Place this document at the repository root as `HERO_HQ_MASTER_CODEX.md` (or copy it into `docs/` and adjust the Codex prompt path accordingly).
2. Hand Codex **this file only**. Codex should read it completely and implement **M0 only** first.
3. Organize code as `framework/` plus `games/hero_hq/` and tests as directed below. Names, roles, missions, currencies and theme colors belong to game data rather than framework source code.
4. Use a tiny `paranormal_fixture` pack as the required **M2 test fixture**, not a second game release.
5. Keep real AdMob/Google Play Billing integration until M6. Mock interfaces in editor first. No ad format other than rewarded ads may enter the product.
6. At the end of each milestone, report actual changed files, actual tests and results, run instructions, known limitations, and the next recommended milestone. Do not claim that an unperformed Android, ad SDK, or purchase test passed.

### Exact first prompt for Codex

> Read `HERO_HQ_MASTER_CODEX.md` completely. This single document is the full product and engineering specification for HERO//HQ and its reusable game-neutral incremental framework. Implement **Milestone M0 only** from Part D. Use Godot 4.x and GDScript. Build a runnable portrait app shell, load a basic HERO//HQ content pack, create the shared framework architecture, implement pack validation and game-ID-isolated saves, and establish a headless test runner. Keep superhero-specific text, mechanics, palette and assets outside shared framework code. Do not integrate real ads or billing in M0. Run all available checks; report exact changed files, commands/tests/results, setup steps, and blockers. Stop at the M0 acceptance gate rather than starting M1.

### Updating the specification later

When the owner changes a feature, edit the relevant part **in this same file** and update the version at the top. Avoid letting duplicates of the handoff become competing sources of truth. Source code, tests, game-pack JSON, changelog, and platform integration notes are development artifacts, not alternative design documents.

---


## Part A — Codex Operating Rules

### Start here
Read Part B — HERO//HQ Game Design Specification, Part C — Reusable Framework Engineering Contract, then Part D — Implementation Milestones. Refer to Part E — Future Theme Roadmap for future concepts, but do not implement them during HERO//HQ development. Implement **only the next uncompleted milestone**, unless the owner asks otherwise. The GDD is the product source of truth.

### Non-negotiable product constraints
- Android-first, Godot 4.x, GDScript, portrait, offline-first, dark/neon UI.
- No live combat, 3D models or character animation. Mission outcomes are deterministic, eligibility-driven timers.
- Mixed recruitment: visible candidate choice for procedural heroes, earned handcrafted legendaries.
- Manual hero/team assignments followed by unlockable auto solo dispatch, team repeat and offline settlement.
- **Ads:** absolutely no banner, interstitial, popup, forced, native feed or app-open advertising. Never show an unsolicited ad prompt. ONLY opt-in rewarded ads initiated by tapping an explicit reward action. Ads must not gate play.
- All purchases are optional direct-priced nonconsumables at launch. Do not add a subscription, paid loot box, premium currency or paywall.
- Gameplay must work in the Godot editor using mocked platform providers without Android credentials.
- **HERO//HQ is game pack #1.** Keep shared generic systems game-neutral. `framework/` must not reference `hero`, `Volt`, `striker`, `Credit`, mission names, or import `games/hero_hq/`; game-specific values, labels, palette, and mechanics belong to the game pack.
- Build only one game now: Paranormal Property Inspectors is a tiny headless *test fixture*, not an approved second game.
- Game saves, purchase SKUs, entitlement state and ad claims must be namespaced by stable game ID. Ads remain rewarded-only in every derived game.

### Coding approach
1. Inspect repo, version and existing tests before editing.
2. Maintain clear separation: generic domain rules/state/simulation, per-game pack content/rules, shared UI components, per-game scenes and platform billing/ads. Follow Part C — Reusable Framework Engineering Contract.
3. Put tunable values in JSON/resources, not scattered through UI scripts.
4. Implement deterministic simulation, pack validation and per-game save migration before expanding content.
5. Use typed GDScript where practical; keep scripts concise and easy to review.
6. Write headless tests for all economy, eligibility, time, automated dispatch and monetization logic.
7. Handle SDK absence, denied consent, no network, app resume and malformed saves without crashing.
8. Use only original/licensed assets, pinned dependencies and safe ignored credentials.
9. If an existing mechanism is working and tested, preserve it when adding new features.
10. At M2, run a minimal second pack through the unchanged engine and demonstrate that swapping pack data changes roles, tasks, currencies and palette without source replacement.
11. Avoid speculative abstraction or a plugin ecosystem. Shared primitives plus explicit limited extensions suffice.

### Definition of a milestone delivery
- Project opens/runs in editor.
- Exact behavior in backlog is implemented, not a visual mockup posing as live logic.
- Unit/headless test runner and pack validation pass or failures are reported.
- Changelog or implementation notes updated.
- Manual verification instructions included.
- Summary contains: completed work, changed files, commands/tests actually run, limitations, next recommended task.

### Suggested commands
Adapt to actual installed Godot executable and environment:

```bash
godot --headless --path . --quit
godot --headless --path . -s res://tests/run_tests.gd
```

Do not say an Android build, rewarded-ad playback or purchases have been verified without real emulator/device/test-track evidence. Keep `docs/PLATFORM_INTEGRATION.md` current with actual selected plugin versions and required platform setup.

### Decision protocol
When unclear, prefer the simplest interpretation that preserves game rules. Do not expand scope without approval. For platform policy/version questions, verify current official documentation. If product decisions conflict, stop and surface the conflict with a recommended resolution instead of silently substituting behavior.

---


## Part B — HERO//HQ Game Design Specification

**Version:** 1.1 · **Status:** implementation-ready reusable-framework baseline · **Date:** 2026-11-03  
**Primary reader:** Codex coding agent and human project owner  
**Product:** Free-to-play, offline-first, portrait mobile incremental superhero-agency management game  
**Target:** Android first (Google Play), iOS later · **Engine:** Godot 4.x, GDScript · **Working title:** HERO//HQ  
**Architecture:** HERO//HQ is the first game built on a reusable, game-neutral incremental management framework.

> **Authority:** Part B is the source of truth for release scope, game rules, UI behavior, and monetization constraints. The other parts of this same document define operating instructions, framework boundaries, implementation order, and future ideas. If anything here conflicts with a future owner decision, update this document before implementing the new behavior.
>
> **Absolutely non-negotiable:** The game must NEVER show popup, interstitial, banner, app-open, forced, or auto-triggered ads. The ONLY ads allowed are rewarded ads that a player deliberately chooses inside the optional Support Protocols interface. No surprise prompts, and no ads in the onboarding flow. No part of ordinary gameplay requires an ad or purchase.

---

### 1. Product vision

A minimalist neon-on-black idle/incremental superhero management game. The player starts with one hero, trains heroes, deploys them to short solo jobs, recruits more heroes, forms three-person teams, and assigns those teams to bigger operations. As the agency grows, the player buys automation that handles recurring missions and training while offline. Heroes have classes, traits, modest statistical differences, and optional specializations. The appeal is optimizing a growing network of heroes, not controlling their combat.

**Design pillars:** (1) satisfying incremental progression; (2) simple, legible portrait UI; (3) individual heroes remain useful after stronger heroes arrive; (4) teams unlock distinct strategic content, not simply better payouts; (5) manual management graduates into player-configured automation; (6) offline-first, no server dependency for normal play; (7) ethical, voluntary monetization.

**Visual reference:** https://play.google.com/store/apps/details?id=com.studioadept.computer — use its density, black backdrop, neon indicators, compact panels, and central process visualization as *inspiration only*. Create wholly original UI, branding, layouts, icons, code and assets. Do not copy trade dress, assets or exact screens.

**Player fantasy:** One rookie hero stopping street crimes grows into a coordinated citywide agency. Longer-term updates expand to global/cosmic threats.

**Session design:** 2–10 minutes for routine management; the simulation keeps working as allowed offline. No tap-spamming required.

**Multi-game product strategy:** Implement reusable mechanics once, then configure distinct games through independent content packs and optional small game-specific mechanic modules. Do **not** let a hypothetical future game delay delivery of HERO//HQ. The second-pack test is a technical fixture, not a second commercial product. See Part C — Reusable Framework Engineering Contract and Part E — Future Theme Roadmap.

---

### 2. Locked decisions, scope and boundaries

| Question | Decision |
|---|---|
| Mission completion | Hybrid: timers/idle gains + optional active acceleration |
| Recruitment | Procedural ordinary heroes + handcrafted legendary heroes |
| Management | Players initially dispatch manually; progressively unlock precise automation |
| Combat | No rendered combat; deterministic eligibility and timed success |
| Multiplayer | No, not at launch |
| Network | Core gameplay works without a network; ads/IAP require services |
| Ads | User-initiated rewarded ads only; 3 total rewards/day shared across reward types |
| Store | Direct-priced, one-time products; no paid loot boxes or subscriptions at launch |
| Primary platform | Android, portrait, phones first |
| Development language | GDScript; avoid C# unless owner authorizes change |
| UI | Built-in Godot Control nodes, reusable themed components; no heavy art pipeline |
| Reusability | Common simulation, persistence, UI components and opt-in rewarded-ad platform adapters are game-neutral; HERO//HQ mechanics/content live in a game pack |

#### 2.1 Commercial MVP (must ship)

- Three progression sectors: **Street Level**, **Citywide Defense**, **National Response**.
- Five hero classes; procedural generated recruits with names, rarity and one trait.
- Ten solo mission definitions and eight team operation definitions, allocated across three sectors and variants.
- Three-member teams; maximum **three** simultaneously owned team slots at launch (expand to five in later content).
- At least 20 purchasable upgrade types, including meaningful manual-to-auto unlocks; upgrade catalogue defined as data.
- Training and mission XP, offline calculations, local save/backup/migration.
- Ten common traits, five class specializations with two branches each (10 total), and **three** launch legendary heroes. Eight legendaries are the eventual content target.
- Original central operations-network display and functional five-tab UI.
- Focus-based active acceleration, daily contracts, basic team mastery.
- Optional Support Protocols rewarded-ad feature and nonconsumable cosmetics/Commander License; show real store only when validated on platform.
- Consent, privacy/data disclosures, accessibility, QA, Android testing, Play release preparation.

#### 2.2 Post-launch / not part of commercial MVP

Global Crisis, Cosmic Defense, additional legendary heroes, fourth-member squads, 5 team slots, Agency Ascension/prestige, weekly supervillain rotation, advanced live events, cloud save, leaderboards, iOS. Architecture should allow these without rewriting core systems, but **do not implement them speculatively** during the MVP.

#### 2.3.1 Reuse boundary for MVP

- The reusable framework must support different **agents**, **jobs**, **squads**, **training**, **facilities**, **currencies**, **upgrades**, **mission types**, **automation policies**, **offline progression**, **UI skins**, and **optional purchase/reward entitlements**, without embedding superhero terminology in framework code.
- Hero names, classes, mission catalogues, icon mappings, synergies, tuning, story sectors, theme palette, first-session tutorials and mission-specific rules belong to the HERO//HQ content pack and game-specific rule modules.
- Reuse is proven by loading a small **Paranormal Property Inspectors** smoke-test content pack in the editor using the same framework; it need not be balanced, polished or released.
- Do not turn every distinction into an abstraction. Prefer shared primitives plus a small optional extension hook for truly unique systems; ship HERO//HQ on schedule.

#### 2.3 Explicit exclusions

No battles/character animations, equipment inventories, open world, user accounts, PvP, guilds, forced online connection, ads for basic income access, timers intentionally made tedious to sell accelerators, paid random recruits, premium currency, subscription, or AI-generated runtime content.

---

### 3. First-session progression

1. Begin in Sector 1 with **one starter Striker**, starter name `Volt`, hero level 1, 250 Credits, one training slot, two solo dispatch slots, and no team. A very short tutorial highlights **Deploy** on Alley Patrol.
2. The first 20-second Alley Patrol completes successfully. Credits and hero XP are granted automatically; the player sees a calm green completion toast and a resource increase.
3. Show **Train Volt**. Training produces 1 XP/second before bonuses and occupies the hero, so the player makes a real assignment decision.
4. Unlock **Recruit**. Each recruitment offer reveals two non-legendary candidates; the player chooses one (no blind paid draw). For the tutorial, guarantee candidate options that enable progression (never strand the player without a required class).
5. Continue solo missions, purchase simple upgrades, recruit three total heroes, reach Command Level 2, and form **Team Alpha**.
6. Show a team-only operation with class/rating requirements and a visible higher payout. The first team mission is a key milestone.
7. Unlock **Auto Patrol** after completing a first team operation and a research purchase. Let the player configure only a single repetitive solo mission at first.
8. Introduce Intel, team mastery, specializations, and team auto-repeat gradually.
9. Reveal Support Protocols **only as a quiet section of HQ/Store navigation after the player understands missions**; never auto-open ad interface or prompt to watch an ad.

**Initial pacing goals, subject to testing:** First completion <30 sec; second hero by 3–5 min; first team by 15–25 min; first automation around 30–45 min; second team 60–90 min. These are tuning goals, not baked-in timers.

---

### 4. Domain rules and state invariants

#### 4.1 Hero status and assignment

A hero has exactly one active activity: `available`, `training`, `solo_mission`, or `team_mission`. Team membership is an affiliation, *not* an activity. A hero may be a team member and still train or run solo missions when that team is not dispatched, unless reserved for team auto-dispatch.

**Invariants:**
- A hero cannot be assigned to multiple activities at once.
- A mission can start only when all assigned heroes exist, are available, satisfy the requirements, and a deployment slot is free.
- A team operation cannot start with a duplicate hero ID.
- Completed missions pay once, even across save/load, reconnect, app suspension or retry.
- If a mission ends, its heroes return to available status before automation can assign them again.
- Offline simulation observes the exact same eligibility, locks and slot constraints as online play.
- No ad, purchase or remote SDK failure may block core play.

#### 4.2 Classes

| Class ID | UI name | Purpose | Key mission fit |
|---|---|---|---|
| `vanguard` | Vanguard | Power/defense | Disaster and defense |
| `striker` | Striker | Speed/offense | Crime and raids |
| `tech` | Tech | Intelligence/efficiency | Hacking, robots, sabotage |
| `support` | Support | Recovery/training | Rescue, recovery, medical |
| `mystic` | Mystic | Unusual powers | Paranormal/dimensional |

#### 4.3 Attributes and hero rating

All heroes have `power`, `speed`, `skill` (positive integers), `level`, `xp`, class, rarity, trait, specialization and rank. The default rating formula is:

```text
HeroRating = 10 * power + 4 * skill + 2 * level
```

Speed affects timer duration, not displayed rating. Class/trait/matchup bonuses affect eligibility or resulting rewards as specified. **Display the final effective rating when deploying**, so requirements are never mysterious.

Define class-specific level-up growth in `data/class_growth.json`, data-driven, e.g. Striker earns more Speed on average; Vanguard more Power. For reproducibility, generate growth deterministically from hero seed + level rather than rerolling on load.

#### 4.4 Mission eligibility, timing and success

The initial implementation is **deterministic**: eligible missions complete successfully after their timers finish; ineligible ones cannot launch. Do not implement random failure rates, injuries or death. Their absence makes offline simulation easy to understand.

```text
HeroEffectiveDurationSeconds = max(10, BaseSeconds / (1 + speed * 0.035 + speed_upgrades))
TeamSpeed = arithmetic_mean(speed of assigned heroes)
TeamEffectiveDurationSeconds = max(20, BaseSeconds / (1 + TeamSpeed * 0.025 + team_speed_upgrades))

SoloCredits = floor(BaseCredits * (1 + skill * 0.015) * credit_modifiers)
TeamCredits = floor(BaseCredits * (1 + MeanSkill * 0.015) * credit_modifiers)
MissionXPPerHero = max(5, floor(BaseCredits * (solo ? 0.30 : 0.12)))
```

`credit_modifiers` combines documented trait/upgrade/strategy bonuses multiplicatively, and is always visible in the mission summary. Do **not** let team/solo duration reductions make sub-10-second infinite farming possible. For mission length, timers in the data catalogue are *base* durations before hero/upgrade factors.

#### 4.5 Recruitment

- Ordinary candidate tiers: Standard 65%, Advanced 27%, Elite 8%, subject to playtesting.
- Every offer presents two revealed candidates; player selects one and pays Credits only on confirmation. Upgrades can increase the choice pool.
- Starting recruitment price: `round(150 * 1.35 ^ total_nonstarter_recruits_purchased)`; use a big-number-safe representation when growth exceeds normal integer comfort.
- Player cannot recruit beyond roster capacity. Do not randomly overwrite or discard a hero.
- Ensure the first few recruitment offers include viable candidates for the first team mission; afterward use deterministic seeded sampling.
- No purchasing randomness for real money; legendary heroes earned through achievements/special operations.

**Launch legendary heroes** (earned, not purchasable random drops): Volt Prime (Striker, team speed), Bastion Zero (Vanguard, boss rating), Ghostline (Tech, technology Intel). Additional five later.

**Common trait pool:** Quick Learner (+15% training XP), Night Watch (+10% patrol Credits), Tactical Mind (+8% team rating), Sprinter (+12% solo speed), Investigator (+10% Intel yield), Crowd Favorite (+10% Credits), Team Player (+8% team mastery), Unbreakable (+10% defense rating), Arcane Talent (+10% Mystic mission rating), Efficient (+8% auto-mission rewards). Traits are additive within their named category and are then combined in the modifier pipeline.

#### 4.6 Training and specializations

- One free training slot; each assigned hero gains `1 XP / second` before upgrades.
- `XPToNextLevel = ceil(40 * 1.22 ^ (level - 1))`, per-level required XP. XP overflows into the next level automatically.
- Training consumes an assignment slot. Leveling during training never stops training unless the configured level target is reached.
- Missions also award XP automatically to participating heroes.
- At level 10 each hero may choose one of two specialization branches for its class; five ranks, respec via Credits. Keep all benefits as data-driven modifiers.

| Class | Branch A | Branch B |
|---|---|---|
| Vanguard | Fortress — defensive rating | Guardian — rescue rewards |
| Striker | Assault — combat rating | Blitz — mission speed |
| Tech | Hacker — technology efficiency | Engineer — Intel reward |
| Support | Medic — rescue efficiency | Mentor — training XP |
| Mystic | Arcanist — paranormal rating | Seer — uncommon reward efficiency |

#### 4.7 Teams and mastery

- A team is a named slot with **three unique hero IDs**, mission priorities, auto-repeat setting, and category mastery.
- Initial team size 3 only. Four-member teams are post-launch.
- Team rating: `sum(HeroRating) * (1 + rating_bonus_total)`, rounded down.
- Team can only deploy when all assigned members are available. Teams cannot share a hero *at the same time*, but players may edit team compositions while idle; if a change would conflict with an active mission, disable it until completion.
- Apply the **best one** named composition synergy plus one diversity bonus if eligible. Cap combined rating synergy bonus at +30%, avoiding double-counting.

| Composition | Bonus |
|---|---|
| 3 Strikers | +15% team operation speed |
| Vanguard + Striker + Support | +15% team rating |
| Tech + Tech + Mystic | +20% technology Credits |
| 3 different classes | +8% team rating (diversity bonus) |
| Vanguard + Support + Mystic | +15% rescue Credits |
| Striker + Tech + Mystic | +12% Intel |

- Five mission categories: Crime, Rescue, Technology, Paranormal, Catastrophe.
- Team mastery levels 0–10 by category, +2% category Credits per level, cap +20%.
- Mastery belongs to the **team slot** and remains when idle members are swapped. Mastery gained only from completed team missions of that category.

---

### 5. Mission catalogue (seed data)

**Ratings are initial tuning targets.** Load from data, validate requirements, and adjust in balance passes. Each mission belongs to a sector; later sectors may use tier-scaled variants without bespoke artwork.

#### 5.1 Solo missions

| ID | Sector | Mission | Base sec | Credits | Min rating | Class rule |
|---|---|---|---:|---:|---:|---|
| `s_alley` | Street | Alley Patrol | 20 | 18 | 60 | none |
| `s_pet` | Street | Pet Rescue | 30 | 24 | 70 | none |
| `s_robbery` | Street | Stop a Robbery | 45 | 35 | 85 | none |
| `s_drone` | Street | Recover Lost Drone | 60 | 45 | 100 | Tech bonus, not required |
| `s_transit` | Street | Transit Emergency | 90 | 65 | 115 | Vanguard bonus, not required |
| `s_warehouse` | City | Warehouse Raid | 120 | 100 | 130 | none |
| `s_android` | City | Rogue Android | 180 | 150 | 155 | Tech required |
| `s_museum` | City | Museum Break-In | 240 | 195 | 180 | Mystic bonus, not required |
| `s_grid` | National | Power Grid Sabotage | 360 | 300 | 205 | Tech required |
| `s_mutant` | National | Mutant Outbreak | 480 | 450 | 240 | Support required |

#### 5.2 Team missions

All require a full team of 3 unless marked otherwise. Tier/rating numbers are summed team thresholds after composition bonuses. Requirements are checked before dispatch.

| ID | Sector | Operation | Base sec | Credits | Intel | Min team rating | Class rule |
|---|---|---|---:|---:|---:|---:|---|
| `t_bank` | Street | Bank Siege | 180 | 300 | 0 | 250 | none |
| `t_hostage` | City | Hostage Crisis | 300 | 450 | 1 | 300 | Support required |
| `t_gang` | City | Powered Gang | 360 | 650 | 1 | 350 | none |
| `t_cyber` | City | Cyber Attack | 480 | 950 | 2 | 410 | Tech required |
| `t_chemical` | National | Chemical Catastrophe | 600 | 1300 | 3 | 480 | Vanguard + Support |
| `t_machine` | National | Armored War Machine | 900 | 1950 | 4 | 540 | Vanguard + Tech |
| `t_breach` | National | Dimensional Breach | 1200 | 3000 | 6 | 630 | Mystic + Support |
| `t_nemesis` | National | Nemesis Showdown | 1800 | 4500 | 10 | 720 | none, milestone unlocked |

**First-clear rewards:** Mission definitions may include one-time bonus Credits or Intel, recorded by unique mission ID. The gameplay event log stores completed mission instance IDs for exactly-once settlement.

**Important progression safeguard:** A player must never be locked out of advancement because an essential class is unavailable; recruiter guarantees, visible class requirements, and affordable roster expansion handle this.

---

### 6. Active gameplay: Focus and optional strategy

- Focus starts at 5 / 5; regenerate 1 every 60 real seconds up to cap, including offline.
- Player may spend 1 Focus on a running mission to reduce **15% of current remaining time**, capped at 30 seconds solo / 90 seconds team. At least 10 seconds between pulses on a single mission; no reduction can complete the mission below its minimum allowed remaining time of 1 second.
- Player may spend 1 Focus on an actively training hero to grant 30 seconds' worth of that hero's current training XP rate.
- No tapping loop, daily stamina barrier, or sale of Focus in MVP.
- Mission strategy options: Standard (1.0x time, 1.0x Credits), Fast Response (0.85x time, 0.9x Credits), Careful Approach (1.15x time, 1.1x Credits). A strategy is chosen at dispatch and locked for that mission, including offline.
- Focus actions produce a minor neon pulse animation. A button displays the actual projected time saved before confirmation.

---

### 7. Unlocks, progression and upgrade economy

**Three MVP sectors:** Street Level → Citywide Defense → National Response. Each introduces more difficult solo missions, team-only operations, new research and additional team capacity.

**Command Level:** A milestone grade controlled by explicit objectives, not XP farming. Example milestones:
- Level 1: starting HQ.
- Level 2: own 3 heroes, complete 6 solo jobs, have 500 lifetime Credits earned. Unlock team formation.
- Level 3: complete Bank Siege, own a Tech or Support hero, purchase 3 HQ upgrades. Unlock Auto Patrol and Citywide missions.
- Level 4: complete 3 Citywide team missions; unlock additional team slot and team auto-repeat research.
- Level 5: complete Cyber Attack and reach total HQ research spend target; unlock National Response.
- Level 6: complete Nemesis Showdown; complete commercial-MVP campaign; show future sectors as clearly labeled 'Coming in an update', not pseudo-locked monetization teasers.

**Currencies:** Credits (main resource); Intel (team and advanced mission research). Legacy Data remains a reserved field for the later prestige system, not an active MVP resource.

**Upgrade pricing convention:** For Credit-funded ranks, `floor(base_cost * 1.65 ^ current_rank)`; purchases are atomic. Intel upgrades have explicit per-rank costs from data. Show current level, next effect, cost, prerequisite, cap.

#### 7.1 MVP upgrade catalogue (at least these 22)

| ID | Label | Per-rank effect | Max level | Primary cost |
|---|---|---|---:|---|
| `train_speed` | Fitness Facility | +10% training XP/s | 10 | Credits |
| `mission_xp` | Instructor AI | +5% XP from missions | 10 | Credits |
| `train_slots` | Parallel Training Pods | +1 training slot | 3 | Credits |
| `recruit_discount` | Recruitment Outreach | -4% recruit cost | 8 | Credits |
| `talent_scout` | Talent Scouts | Better tier odds; normalize total | 5 | Intel |
| `roster_cap` | Hero Housing | +4 roster capacity | 7 | Credits |
| `candidate_count` | Candidate Database | +1 candidate in offers | 2 | Intel |
| `solo_slots` | Dispatch Stations | +1 simultaneous solo channel | 6 | Credits |
| `solo_speed` | City Navigation | +4% solo speed | 10 | Credits |
| `solo_credits` | Public Relations | +6% solo Credits | 10 | Credits |
| `solo_intel` | Evidence Network | +10% solo Intel opportunities | 5 | Intel |
| `focus_capacity` | Rapid Response | +1 max Focus | 5 | Credits |
| `team_slots` | Team Charter | +1 team slot | 2 | Credits + prerequisite |
| `team_rating` | Tactical Link | +3% team rating | 10 | Credits |
| `team_mastery` | Bond Protocol | +10% team mastery XP | 5 | Intel |
| `team_credits` | Advanced Operations | +6% team Credits | 10 | Credits |
| `team_speed` | Field Logistics | +5% team speed | 10 | Credits |
| `auto_patrol` | Auto Patrol | Enables one solo automatic channel | 1 | Intel |
| `auto_dispatch_slots` | Dispatch Algorithms | +1 automatic solo channel | 6 | Credits + Intel |
| `team_autopilot` | Team Autopilot | +1 automated team | 3 | Intel |
| `offline_cap` | Offline Logistics | +2 h offline cap | 4 | Intel |
| `central_command` | Central Command | +5% all Credits | 10 | Credits + Intel |

Later add Mentor Program, Training Scheduler, Specialization Lab, squad expansion, Synergy Matrix, Smart Orders, Duty Scheduler, Threat Scanner, Research Archives, Heroic Reputation and Legacy Terminal. Keep catalogue extensible to all 33 planned types.

**Baseline offline cap:** 8 hours; Offline Logistics increases to max 16 hours in MVP. **No paid-only offline cap**.

---

### 8. Automation (earned progression)

#### 8.1 Unlock stages

1. **Manual:** player picks training, recruits, mission and team deployments.
2. **Auto Patrol:** configure *one* eligible solo mission for one channel; it repeats while a suitable available hero exists.
3. **Dispatch Algorithms:** additional auto-solo channels; choose a permitted class, mission category and priority.
4. **Team Autopilot:** configure an existing team to auto-repeat a specific eligible team operation; unlock additional auto-team slots over time.
5. **Smart Orders** (post-launch): choose best Credits/min, best Intel/min, best XP, fastest, category, or fixed mission.
6. **Duty Scheduler** (post-launch): automatically rotate trainees until target level.

#### 8.2 Rules

- The player explicitly enables and configures each automation rule.
- `preferred_mission_id`, `allowed_hero_ids`, `reserved_for_team`, `enabled`, and priority are persistent.
- Automatic action may start only when heroes and channels are idle, requirements pass and region is unlocked.
- If the selected mission is temporarily ineligible, the automation waits silently; it does not borrow unavailable heroes or change the target unexpectedly.
- Order of arbitration when multiple automations want the same hero: **active mission completion → reserved team auto-dispatch → solo auto-dispatch → manual training queue**. No existing mission is interrupted.
- Automation must behave deterministically for given state, seed and elapsed time.
- UI always shows which automation rule is waiting and why; e.g. 'Waiting for Tech hero'.
- Manual missions may use available, unreserved heroes. A reserved team member may be manually overridden only after a clear local confirmation (not a monetary prompt).

---

### 9. Offline progression and deterministic simulation

Offline progress is not a simple flat Credit reward. It is the same simulation advanced over elapsed time. **This is one of the highest-risk engineering areas and must receive its own tests.**

#### 9.1 Clock model

- Store a UTC last-settlement timestamp in seconds (and schema version) at every save/suspend.
- Use a monotonic timer while the app runs, and wall-clock UTC only to calculate elapsed time after resume. Convert elapsed seconds once to an authoritative `simulate_delta(seconds)` input.
- Clamp offline elapsed to `min(max(now - last_settlement, 0), offline_cap_seconds)` and record that cap was applied.
- If device time moves backward or jumps unexpectedly, do not create negative progress or gigantic rewards; explain the fallback in tests.
- Show the player an offline summary on app return **only if** offline progress occurred (this is a game summary, not an ad or offer popup).

#### 9.2 Simulation model

Implement discrete-event or batch processing; never loop once per simulated second for long absences.

At any simulated event boundary:
1. Determine the next scheduled training level-up, mission completion, Focus regeneration cap, or offline window end.
2. Advance shared time to that event.
3. Award training XP and Focus regeneration for the elapsed interval.
4. Settle all missions that finish at this exact timestamp, each once, applying **snapshotted launch modifiers** (so buying an upgrade later cannot retroactively change a mission reward).
5. Release hero and channel locks; update stats, team mastery and milestones.
6. Run automation arbitration in fixed priority order, and schedule newly started missions if eligible.
7. Continue until offline window ends or a defined safe event bound; if bound hit, finish using a mathematically equivalent batch path or report a tested safe fallback—do not silently overpay.

**No double reward on restart:** record immutable active mission instance IDs, completed IDs or a bounded settlement ledger; apply settlement and save atomically as one state transition.

#### 9.3 Offline edge cases to test

- One mission completes during app closure and pays once.
- Several automated cycles finish and pay exact expected totals.
- A hero is not assigned to both solo and team work.
- One hero reaches multiple levels while training offline.
- Save/load mid-mission preserves remaining time.
- Unlock/upgrade changes do not rewrite already-running mission rewards.
- Negative elapsed time does not subtract or generate currency.
- Offline cap works and never includes ad-earned bonuses without a claimed reward.
- Device reboot, app kill and stale save do not duplicate settlements.
- Purchase, refund and ad SDK outages do not affect offline gameplay.

---

### 10. Monetization (hard product requirements)

#### 10.1 Absolute advertising contract

**Never create, configure or display any banner, native feed ad, interstitial, app-open ad, forced video, auto-triggered rewarded ad, or unsolicited opt-in ad prompt.** No ad after launch, mission completion, hero recruitment, return from idle, or navigation.

The *only* valid ad entry point is a deliberate tap on a clearly labeled **Watch Ad** button in `HQ > Support Protocols` (or a direct, user-selected entry from Store); the user then confirms. No autoplay. The reward and any daily limit must be disclosed before the user chooses.

Rewarded placement is not visible or enabled before consent/age compliance and SDK readiness. If unavailable, calmly say `Reward currently unavailable` with no interruption. Ad viewing is never required to complete any unlock or daily quest.

#### 10.2 Reward catalogue and shared cap

A maximum of **3 successful rewarded claims per UTC day, total**, across all reward types and the Commander License claim method. Day resets at 00:00 UTC; show countdown in local device time. Do not offer an extra paid way around the cap.

| Reward ID | Effect | MVP implementation |
|---|---|---|
| `credit_boost` | +50% Credits on one selected eligible active/next mission | Store one-use modifier bound to a mission instance, expires after successful completion |
| `training_surge` | +25% training XP for the next 30 minutes | Active time-based global modifier, persists across saves/offline |
| `rapid_response` | Reduce an active mission's remaining time by 25%, max 90 seconds, never below 1 sec | Apply after verified reward; choose the target mission before ad starts |

**Avoid stacking exploit:** one `credit_boost` per mission; training-surge duration cannot stack (refresh to max 30 minutes); other upgrades can affect normal calculations. A reward is granted once per valid reward callback and persisted before visible confirmation. No reward on load error, user dismissal before eligibility, or failed playback.

**Rewarded ad state machine:** `IDLE -> USER_SELECTED -> USER_CONFIRMED -> LOADING -> SHOWING -> REWARD_EARNED -> APPLIED`, with recoverable `FAILED` and `CANCELLED`. Use SDK earned-reward callback, NOT merely the ad-dismissed callback. A unique pending request ID must prevent double grants if callbacks arrive twice. Store pending and granted reward IDs so app suspend/restart is handled safely. Ad SDK may differ between test/production; abstract it.

#### 10.3 Commander License

Proposed **$5.99 USD** *nonconsumable*, localized display price provided by Google Play Billing (never fake/store a hardcoded purchase price inside the actual purchase button). Benefits:
- Claim **the same three daily Support Protocol bonuses** without watching ads; never more total claims.
- One exclusive violet-and-gold HQ theme.
- Exclusive badge/emblems.
- Additional **saved automation presets** only; core automation behavior available to everyone.

No subscriptions, popups inviting purchase, premium-only legendaries, advantage multipliers outside the shared daily rewards, or removal of fabricated barriers.

#### 10.4 Other nonconsumable products

- `theme_cyber_blue`: proposed $1.99; palette/node styling.
- `theme_villain_red`: proposed $1.99.
- Optional launch cosmetics pack with direct-price bundles, subject to testing. Avoid combining overlap with Commander License in a misleading way; clearly disclose what is already owned.
- Optional Founder's Pack is **deferred** from commercial MVP unless its contents and refund behavior are independently verified. Simpler store is better.

#### 10.5 Billing requirements

Use a `BillingProvider` adapter with a fake editor implementation and production Play Billing implementation. Use Godot's first-party Android Play Billing plugin compatible with the selected Godot 4 version. Before sale, verify exact currently supported plugin version/API and platform billing requirements.

- Purchase flow starts **only** after player presses Buy in Store.
- Verify completed purchases; `PENDING` is not ownership.
- Acknowledge completed nonconsumable purchases; restore entitlements on reinstall / same Play account.
- Persist a local entitlement cache, but **do not treat a locally editable flag as sole proof of purchase**. Production plan should use Google Play purchase verification from a small secure backend when possible; if opting for client-only verification initially, document its limitations and use the platform purchase query/acknowledgement APIs robustly.
- Reflect refunds/revocations; no repeat grant on duplicate callbacks. Real-money transactions must be tested through a Google Play test track, not only an editor mock.
- If offline, existing valid cached entitlements remain usable; purchases require connection, and the game otherwise works normally.

#### 10.6 Ads, consent and privacy

Build a `RewardedAdsProvider` facade (`MockRewardedAdsProvider`, `AndroidRewardedAdsProvider`). Use test ad IDs in development. Ensure the release build only serves approved production IDs. Honor consent/region/age requirements and deliver a privacy policy/Data safety disclosures reflecting actual analytics/advertising SDK behavior. Do not ship marketing trackers simply because a plugin supplies them by default. Use no push alerts advertising boosts.

#### 10.7 Analytics (minimal and privacy-aware)

Track only aggregated, purpose-limited events where allowed: `session_started`, `tutorial_step_completed`, `hero_recruited`, `training_started`, `mission_completed`, `team_created`, `automation_unlocked`, `ad_selected`, `reward_granted`, `purchase_started`, `purchase_completed`, `store_viewed`, `sector_unlocked`. Keep an adapter that can be disabled; no hidden user-account requirement.

---

### 11. UI/UX and art implementation

#### 11.1 Design tokens

| Token | Hex | Use |
|---|---|---|
| background | `#080C13` | Full-screen canvas |
| panel | `#111B29` | Cards |
| border | `#253749` | Dividers |
| text | `#E5EEF8` | Primary |
| muted | `#90A5BA` | Metadata |
| solo_cyan | `#00E5F5` | Solo missions/selection |
| team_purple | `#D98EFA` | Team operations |
| success_green | `#83EAAF` | Training/success |
| credit_gold | `#F7C854` | Credits |
| warning_red | `#FF6585` | Constraints/warnings |

Prefer crisp flat iconography, simple shapes/lines, animated bar fills and subtle pulses. Neon should not mean entire bright backgrounds; preserve dark negative space for legibility. Avoid animated character portraits or sophisticated illustrations.

#### 11.2 Five primary tabs

1. **HQ**: top resource bar, Command Level, animated operations network, active mission summary, current milestones; quiet link to Support Protocols.
2. **Heroes**: scroll roster, recruit, training slots/XP, hero detail, trait/specialization and availability.
3. **Missions**: filters by Solo/Team/Sector, requirements, projected time, rewards, dispatch status.
4. **Teams**: create/edit team, choose 3 members, synergy display, category mastery, assign/auto-repeat.
5. **Upgrades**: organized by Training, Recruitment, Solo, Teams, Automation and Global; each card has cost, max, prerequisites, current/next effect. Store reachable via normal navigation, not overlay promotion.

#### 11.3 Central operations network

One Control with background grid and a pool of 2D nodes/lines using `_draw()` (or cheap Line2D nodes). Center = HQ; satellite nodes = current hero and team activity. Color-coded by status; subtle pulsing on missions; expanding number of nodes as capacity grows. It is informational and decorative, **not the only way to control the game**. Efficient redraw; reduced-motion setting turns off pulsing. No 3D shaders required.

#### 11.4 Responsive/mobile requirements

- Primary layout 360–430 logical px wide in portrait; support taller/smaller phones and system safe areas.
- Regular text ~14–16 logical px where possible, major tap targets at least 44–48 px, never rely only on color for status.
- Scroll the tab content; keep the most important resources and bottom tab bar accessible.
- Show compact numeral notation (`1.2K`, `3.4M`) with full value on tap/tooltip where appropriate.
- All buttons have visible disabled reasons; keyboard/desktop support allows rapid editor testing.
- Save confirmation is unobtrusive. Tutorial uses local highlights, not monetization offers.

#### 11.5 UI examples / statuses

- Hero card: `VOLT · STRIKER · LV 14 · TRAINING · XP 720/1000`.
- Mission card: `CYBER ATTACK · TEAM 3 · TECH REQUIRED · 08:00 BASE · 950 CR + 2 INTEL`.
- Automation status: `Team Alpha: waiting for Tech hero`.
- Reward link: `Support Protocols · 2 of 3 daily bonuses available` (never flashing, no nag icon).

---

### 12. Reusable framework, theme packs and project architecture

**Source of truth:** Part C — Reusable Framework Engineering Contract specifies stable interfaces, pack schema, test fixtures, game isolation and extension points. The general framework has **no HERO//HQ-specific strings, classes, characters, currency names, reward values or mission definitions**. HERO//HQ is the first packaged implementation of this framework, not a monolithic app to clone later.

#### 12.1 Three-layer architecture

1. **Shared incremental framework** (`framework/`): deterministic scheduler, state commands, generic agent/task/team assignment, XP/training, recruitment choices, resource accounting, upgrades/modifiers, unlock conditions, automation, save migrations, reusable UI primitives, mock/Android platform adapters, optional monetization gates and test helpers.
2. **Per-game content pack** (`games/hero_hq/`): declarative IDs and values for classes, traits, generated names, missions, team recipes, advancement, upgrade definitions, localizations, icons, colors, tutorial, entitlements, and store SKUs.
3. **Optional game-specific modules** (`games/hero_hq/rules/`, `games/hero_hq/scenes/`): HERO//HQ team synergy and Focus features, specialized headquarters network, or future game-specific mechanics. These communicate with shared rules via an explicit narrow interface; no shared engine edits for a content-only change.

Use dependency direction `app -> game pack / framework`, and `game-specific extension -> framework API`; **never import a named game or its content from framework code**. UI sends commands to the simulation; content and saves carry stable IDs, not scene references.

Recommended repository structure:

```text
incremental-games/
  project.godot                    # builds/runs the HERO//HQ entrypoint first
  HERO_HQ_MASTER_CODEX.md         # single authoritative design and Codex handoff
  README.md                       # generated run/build instructions
  docs/
    BALANCE_NOTES.md              # generated balancing notes
    CHANGELOG.md                  # generated implementation record
    PLATFORM_INTEGRATION.md       # generated SDK/version/setup notes
  framework/
    core/{game_state,commands,clock,simulation,save,events}.gd
    systems/{agents,recruitment,training,tasks,teams,upgrades,progression,automation}.gd
    content/{pack_loader,pack_validator,requirements,modifiers}.gd
    ui/components/{agent_card,task_card,resource_bar,upgrade_card,progress_bar}.tscn
    ui/{theme_tokens,screen_shell,screen_controller}.gd
    platform/{billing_provider,rewarded_ads_provider,analytics_provider}.gd
    platform/mock/{mock_billing,mock_rewarded_ads,mock_analytics}.gd
  games/
    hero_hq/
      manifest.json
      data/{roles,agents,names,traits,legendary,missions,upgrades,progression,synergies,rewards,store}.json
      locale/en.json
      ui/theme.json
      rules/{hero_synergy,focus}.gd
      scenes/{app,hq,heroes,missions,teams,upgrades,store}.tscn
      assets/                         # original, separately licensed per-game assets
    paranormal_fixture/
      manifest.json
      data/{roles,agents,missions,upgrades,progression}.json
      locale/en.json
      ui/theme.json
      # test-only minimal content pack, not a second release
  tests/
    run_tests.gd
    framework/{simulation,save,resources,requirements,automation,monetization}.gd
    game_packs/{hero_hq,paranormal_fixture,pack_validation}.gd
  tooling/
    validate_packs.gd
```

Codex may improve filenames/directories where needed for Godot import rules, but must preserve these ownership boundaries and keep the documentation current. Add no plugin framework or external generic-game package just to solve this—plain GDScript modules are enough.

#### 12.2 Content-pack contract and sample IDs

A pack has a stable `game_id`, a pack schema version, selected optional mechanics, default locale, display labels, UI tokens and file paths. Roles, missions, upgrades, and entities each have **stable machine-readable IDs** and localized labels. Numbers (XP rates, Credit rewards, costs, timers, caps) live in data. See Part C — Reusable Framework Engineering Contract for the precise expected examples, validation, and variation rules.

Illustrative mapping:

| Shared framework concept | HERO//HQ | Paranormal Property Inspectors |
|---|---|---|
| Agent | Hero | Inspector |
| Agent role | Vanguard / Tech / Mystic | Medium / Technician / Warden |
| Solo task | Stop a Robbery | Survey a Haunted Apartment |
| Group | Team | Investigation Crew |
| Group operation | Dimensional Breach | Cleanse a Cursed Hospital |
| Training | Hero Training | Certification / Field Training |
| Upgrade facility | Dispatch Station | Case Dispatch Office |
| Main currency | Credits | Service Fees |
| Rare currency | Intel | Evidence |
| Progression stage | Sector | Haunting Grade |

The **game rules** behind the HERO//HQ roster and missions remain those described in §§3–11. The mapping changes labels/content, not their values or balance. Future games must add a genuine signature mechanic where it improves their identity rather than being only a cosmetic reskin.

#### 12.3 Save-state contract and migration

Store a `game_id`, `save_schema_version`, `pack_content_version`, state and timestamps in a **per-game** save path (for example `user://saves/hero_hq/profile.json`). Never load a save across game IDs. Use neutral state keys for reusable concepts (`agents`, `squads`, `assignments`, `resources`, `upgrades`, `automation_rules`); game-specific state is namespaced under `extensions.<module_id>`. Stable IDs ensure that a character called Volt remains the same saved agent after a UI rename.

Conceptual example (not production JSON schema):

```json
{
  "game_id": "hero_hq",
  "save_schema_version": 1,
  "pack_content_version": 1,
  "last_settled_utc": 0,
  "resources": {"credits": 250, "intel": 0},
  "agents": {"hero_volt": {"id": "hero_volt", "role_id": "striker", "level": 1, "xp": 0, "activity": "available"}},
  "squads": {},
  "assignments": {},
  "upgrades": {},
  "automation_rules": [],
  "granted_reward_request_ids": [],
  "extensions": {"hero_hq.focus": {"current": 5}}
}
```

Replace illustrative timestamp zero with actual UTC at profile creation. Save atomically with backup and schema migration; settle all simulation actions as one idempotent state transition. Content update migrations and save-schema migrations are separate: handle removed/renamed content IDs using explicit mappings, never silently reassign a save to another game.

Purchased entitlements and rewarded-ad claims are also isolated to the respective game/product namespace; no automatic account linking or cross-title player data sharing. The shared platform integration code must enforce the absolute ad constraints in §10 for **every** future game built from this framework.

#### 12.4 Pack validation and reuse acceptance

In debug/test builds validate all required pack definitions: manifest schema, unique `game_id` and IDs, legal resource/role references, valid missions and prerequisites, achievable first progression, locale keys, valid icons/tokens, finite nonnegative upgrade caps, and store SKU uniqueness within the build.

The proof of reuse is **not** duplicating the HERO//HQ source tree and searching/replacing strings. It is running the **unchanged** framework with a second minimal pack that alters agent roles, mission list, resources, text and palette. A headless fixture test should perform recruit → train → solo task → form group → group task → offline settlement; a small theme-preview UI test should load the second palette without a code edit in `framework/`.

**Scope limit:** The test fixture can contain 2–3 roles, two solo tasks, one group operation and one upgrade; it is not a commercial game. Keep it maintained throughout milestone tests so accidental hardcoding is caught immediately.

Do not commit API secrets, Play signing keys, production credentials or private user data. Use pinned dependencies and documented commercial asset licenses.

---

### 13. Technical integration requirements

- Use GDScript and Godot Control UI. Android build requires working SDK, export template, signing and release AAB flow.
- Keep Android SDK integrations in `platform/` adapters. In editor, mock rewarded-ad and billing providers must simulate success, cancellation, failure and duplicate callback behavior without real-money flows.
- Select/pin a current stable Godot 4.x release supported by required Android plugins, before writing much code. Do not assume APIs from old Godot releases.
- Use actual device testing for resume/suspend, background behavior, screen safe area, billing and rewarded ad callbacks.
- Tests should run without a graphical desktop, e.g. `godot --headless --path . -s res://tests/run_tests.gd` with an appropriate SceneTree-based runner; make this command reliable rather than assuming the sample path itself proves functionality.
- Avoid expensive per-frame polling of every mission. Schedule timer completion events or drive UI bars from target timestamps with lightweight refresh.
- Target stable 60 FPS on representative Android hardware; simulation cost bounded and no unnecessary network traffic. Accessibility and battery impact outrank decorative animation.

**Official documentation to check at implementation time:**
- Godot Android export: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
- Godot first-party Android IAP: https://docs.godotengine.org/en/stable/tutorials/platform/android/android_in_app_purchases.html
- Google Play Billing: https://developer.android.com/google/play/billing/integrate
- AdMob rewarded ads: https://developers.google.com/admob/android/rewarded

Platform SDKs and policies change. Verify actual versions, requirement changes, consent guidance, and Google Play target API before release; keep specifics in `docs/PLATFORM_INTEGRATION.md` rather than treating dated guesses as specifications.

---

### 14. QA, performance, telemetry and release gates

#### 14.1 Automated tests are required for

- HERO//HQ hero rating and level-up threshold calculations; generic agent/task math tested without game strings.
- Candidate generation reproducibility with a fixed seed.
- Recruitment cost, roster caps, duplicate rejection.
- Mission eligibility: positive, negative and mixed-class cases.
- No hero double-booking and no duplicate mission settlement.
- Team synergy priority and maximum caps.
- Team mastery progression.
- Focus regeneration and pulse bounds.
- Automation selecting only eligible and unreserved heroes.
- Online `simulate_delta` equivalence to offline resume.
- Rewarded claim global cap: 3/day, across all reward types and Commander claims; day boundary.
- Ad cancellation/failure earns nothing; callback twice awards once.
- Paid entitlement restoration and revoked/pending cases.
- Save/load, backup recovery and schema migration, including game-ID isolation and content-ID mapping.
- At least 100 simulated runs of first 60 minutes without getting stuck on impossible class requirements or hard currency dead ends.
- Pack validator rejects missing references, duplicate IDs, unsupported mechanics and unsatisfiable early progression.
- Paranormal fixture smoke test uses unchanged shared framework for recruit/train/solo/group/offline; theme tokens load without edits to shared UI components.
- Changing only mission rewards and localized labels in a pack requires no modifications under `framework/`.

#### 14.2 Manual Android acceptance

- Cold start, rotate/interrupt (still portrait), suspend/resume, device reboot and low-memory process death.
- Ads stay absent until deliberate player-initiated reward flow; no overlays, banners, startup video or accidental SDK ad placements.
- Offline mode still allows training/missions/save; clearly shows ads/purchases unavailable without internet.
- Tap targets and readable layouts on narrow and tall phones.
- Purchase tester account sees restored nonconsumable, including reinstall; refund test removes entitlement after valid verification.
- Privacy and consent screens behave as legally/platform required without converting into ad solicitation.

#### 14.3 Playtest metrics (targets, not guaranteed forecasts)

- First mission completed <30 sec; recruit #2 by ~3–5 minutes; first team by ~15–25 min.
- Day-1 retention initial internal target 30%; Day-7 target 10%; revise based on data.
- Most players can create a team without external guidance.
- Premium product is optional; testers can reach the same gameplay content free.
- Track ad offer-to-completion, rewarded completion integrity, purchase success/failure/restore, and support complaints.

#### 14.4 Release checklist

- An actual playable Android AAB (not just Godot editor preview).
- Signing credentials safely managed and not committed.
- Correct package identity, store listing, app icon, screenshots, content rating and legal policy pages.
- Test-only ad identifiers removed; production identifiers reviewed.
- Purchase product IDs and localized prices read from Play APIs; no fake confirmation.
- Play Billing verification, acknowledgement and entitlement restore tested.
- Closed test run and Google Play release eligibility confirmed for developer account.
- Privacy/Data safety answers match actual SDK/network behavior.
- Offline progress, cap, and save recovery validated.
- All non-negotiable ad rules pass regression tests.

---

### 15. Implementation milestones and delivery contract

Codex must work in **small, demonstrable vertical slices**, not attempt an entire commercial game in one pass. For exact tasks and acceptance checks, see Part D — Implementation Milestones. Every milestone should end with a launchable editor build, automated tests, a change log entry, and a short report of what works and what remains.

| Milestone | Demo requirement | Exit gate |
|---|---|---|
| M0 Project bootstrap | App launches via HERO//HQ pack, shared UI shell | Godot project loads; pack validator and headless tests run |
| M1 One-hero vertical slice | Train/deploy/earn/upgrade/save | Offline result deterministic, mission awards once |
| M2 Recruitment and roster | Generate/select candidates, train more heroes; second pack smoke fixture | Roster cap, class rules and engine reuse validated |
| M3 Teams | Form Team Alpha, deploy eligible 3-hero operation | Locks, synergies, mastery validated |
| M4 Automation and sectors | Auto Patrol, team repeat, 3 sector unlocks | Offline/online simulation equivalence |
| M5 Full UI/content | Five tabs, network, content data, contracts, legendaries | Usability pass, responsive Android UI |
| M6 Monetization | Only chosen rewarded ads, Commander License, themes | Real test-track callbacks; no forced ads |
| M7 Release polish | Crash recovery, accessibility, balance, Android AAB | Release checklist passes |

#### 15.1 Codex working rules

- Treat this document as the source of truth. Do not invent new monetization methods, unapproved gameplay systems, or surprising UI.
- Before major implementation, inspect repo, existing files and current Godot version; state any assumptions or blockers in the milestone report.
- Implement one milestone at a time, preferring the simplest maintainable solution.
- Data-driven content: changing a mission reward or theme label must not require editing shared framework or UI code. See Part C — Reusable Framework Engineering Contract.
- Favor small composable functions; use type hints and clear naming in GDScript.
- Include headless tests for game calculations; do not report 'working' if tests were not run.
- Provide concrete commands to open/run/test Android build and describe what needs manual setup.
- Do not claim to have checked device/Play purchase/ad behavior without an actual device/test-track verification.
- When a question can be answered with a conservative, compatible implementation choice, use it and document it; ask the owner only for materially blocking product decisions.
- At the end of each milestone provide: changes, files modified, tests run/results, known issues, next milestone, and a short manual validation walkthrough.

---

### 16. Multi-game roadmap and theme reuse (future, not MVP)

**HERO//HQ is commercial title #1; framework is the reusable foundation.** Candidate follow-up themes are described in Part E — Future Theme Roadmap, with their distinct gameplay identities and a practical translation of agents/jobs/squads/currencies. Strong initial candidates: Paranormal Property Inspectors, Cryptid Conservation Agency, Temporal Repair Division, Miniature Civilization Caretakers and Library of Living Books. A total of 30 ideas are summarized below and detailed there for future selection, **not** for implementation during HERO//HQ's M0–M7.

**New-game rule:** create a new `games/<game_id>/` pack; configure labels, roles, task definitions, costs, currencies, progression, UI skin and legally distinct art; add only a small optional rule module if a real signature mechanic requires it. Do not copy the entire HERO//HQ source tree, alter shared simulation rules just to fit a theme, share saves/products between titles, or release a pure reskin. Validate the pack, run framework tests, tune its economy independently, and apply the same ad restrictions.

#### 16.1 Candidate themes (future products, not MVP)

The 30 themes to consider are listed here for a standalone GDD reference; unique mechanics, suggested mappings and top-five priorities are in Part E — Future Theme Roadmap. All require independent validation before commercialization.

**1–10:** Paranormal Property Inspectors · Cryptid Conservation Agency · Afterlife Postal Service · Curse Removal Bureau · Monster Witness Protection · Haunted Artifact Reclamation · Dream Repair Corporation · Reaper’s Administration · Supernatural Building Maintenance · Forgotten Gods Agency

**11–20:** Temporal Repair Division · Microbot Repair Collective · Interdimensional Customs · Abandoned Satellite Recovery · Alien Ecosystem Restoration · Rogue AI Rehabilitation Center · Pocket Universe Surveyors · Space Weather Authority · Galactic Translation Bureau · Reality Glitch Technicians

**21–30:** Miniature Civilization Caretakers · Library of Living Books · Underground Fungal Network · Lost and Found Department · Mythological Insurance Agency · Secret Door Inspectors · Toy Restoration Society · Underworld Transit Authority · Ancient Language Recovery Institute · Department of Impossible Weather

#### 16.2 HERO//HQ expansion map (not MVP work)

1. Global Crisis and Cosmic Defense sectors; expanded mission catalogue and new HQ network rings.
2. Five team slots, optional fourth-member advanced operations, and more synergies.
3. Additional five handcrafted legendary heroes, earnable through sector milestones.
4. Agency Ascension prestige with Legacy Data: Credit/HQ reset, keep earned heroes and team mastery, permanent research, tier-scaled threats.
5. Weekly returning supervillain contracts with class-specific goals; no forced daily login streaks.
6. Seasonal cosmetic themes and improved operations animations; no game-breaking paid units.

**Success criterion:** The launch build should already be fun and complete enough for repeat play, while these expansions remain possible through content data and systems architecture.

---

### 17. Definition of done

Commercial MVP is done only when a new player can open the Android game, complete a tutorial, recruit and train multiple heroes, form and deploy teams, unlock increasingly powerful upgrades, run configured solo and team automation while offline, earn and spend Credits/Intel, finish three sectors, and optionally claim **user-initiated** rewarded bonuses or buy permanent cosmetics/license—with **zero** forced, popup, banner or automatic advertising and reliable save/billing behavior.

Every nonessential visual effect, store feature or new content idea is subordinate to a stable, enjoyable, battery-efficient core loop. Framework reuse is successful when a new game can be created mainly by authoring a new content pack, *without weakening HERO//HQ quality or delaying its release*.

---


## Part C — Reusable Framework Engineering Contract

**Audience:** Codex and future game designers. This section is the architecture companion to Part B in the same document.

### 1. Purpose and boundaries

Build **one reliable Godot 4.x / GDScript simulation framework**, with HERO//HQ as the first shipped title. A new game's initial prototype should be possible by changing a content pack and optional narrow game-specific rules, not by duplicating/replacing the framework source. Building a fully general visual game creator is **out of scope**.

**Do reuse:** game state/commands, deterministic simulation, generic agents and squads, jobs, training, recruitment choices, modifiers, upgrades, unlock prerequisites, offline scheduler, autosave/migration, UI controls, accessibility defaults, telemetry interfaces and opt-in ad/billing adapters.

**Do not force reuse:** distinctive story, layout art, signature mechanics, hero class-specific tactics, mascot visuals, event fiction, title-specific sales catalogues. These belong to individual games. Future games must offer differentiated mechanics beyond changes of nouns and colors.

### 2. Layer ownership (enforce dependency direction)

| Layer | Path | Owns | Must not depend on |
|---|---|---|---|
| Engine | `framework/core`, `framework/systems` | Generic state, math, transactions, schedule and assignment | Any specific game pack, scenes, SDKs |
| Pack loading | `framework/content` | Manifest parsing, validation, dependency resolution, ID lookup | Specific roles such as `striker` |
| Shared UI | `framework/ui` | Reusable labeled cards, bars, generic lists, styling tokens | HERO//HQ strings, art, specialized HUD |
| Platform | `framework/platform` | Interfaces, mock implementations, Android adapters | Any specific store product/bonus name |
| Per-game pack | `games/<game_id>/data`, `locale`, `ui` | Content, rules configuration, economy values, localized text | OS/SDK internals |
| Game-specific rules/UI | `games/<game_id>/rules`, `scenes` | Unique hook code and customized screens | Internals of unrelated game packs |

**Direction:** `game composition -> pack + framework` and `pack extensions -> public framework interfaces`. `framework -> games/hero_hq` is prohibited. Dependency cycles are prohibited.

### 3. Shared domain vocabulary

Use generic engine names; map them to the player's fantasy through localization.

| Framework | HERO//HQ labels | Paranormal inspector labels |
|---|---|---|
| `Agent` | Hero | Inspector |
| `Role` | Class | Discipline |
| `Squad` | Team | Crew |
| `Task` | Mission | Case |
| `SoloTask` | Solo Mission | Site Survey |
| `SquadTask` | Team Operation | Group Investigation |
| `Training` | Hero Training | Certification |
| `Upgrade` | HQ Research | Office Upgrade |
| `Stage` | Sector | Haunting Grade |
| `Resource` | Credits / Intel | Service Fees / Evidence |
| `Trait` | Hero Trait | Inspector Quirk |
| `Automator` | Auto Dispatch | Case Scheduler |

`Agent`, `Squad`, etc. are conceptual names; in Godot prefer concise files/classes, not inheritance trees.

#### Public engine operations (recommended command shapes)

- `load_pack(pack_id) -> validated_pack | error`
- `new_state(pack_id, seed, utc_timestamp) -> game_state`
- `apply_command(state, command) -> {state, events, error}`; operations include `recruit_agent`, `assign_training`, `start_task`, `create_squad`, `buy_upgrade`, `set_automation`, `apply_focus_or_extension_action`.
- `simulate_delta(state, elapsed_seconds, pack) -> {state, events}`; shared for online and offline, with fixed seed and deterministic event order.
- `save_state(state)` / `load_state(game_id)` with schema migrations and backup.
- `get_view_model(state, pack, screen_id)` for UI; UI never mutates domain objects directly.

Commands should return explicit typed or dictionary results with error codes (`insufficient_funds`, `agent_unavailable`, `task_locked`, `missing_role`, etc.). All command validation and reward settlement happen inside the engine.

Godot has no required plugin API design here. Implement as simple, testable GDScript objects and resources. Define hook contracts once a real use case exists.

### 4. Content-pack files and versioned manifest

Each game pack should contain:

```text
games/<game_id>/
  manifest.json
  data/roles.json
  data/agents.json               # starter agents, procedural generation settings
  data/names.json
  data/traits.json
  data/missions.json             # solo + squad tasks
  data/upgrades.json
  data/progression.json
  data/synergies.json            # optional
  data/rewards.json              # optional rewarded bonuses
  data/store.json                # only when billing is present
  locale/en.json
  ui/theme.json
  rules/                          # optional scripts implementing a narrow documented hook
  scenes/                         # specific HUD screens and title-specific visualizations
  assets/
```

Manifest sketch:

```json
{
  "pack_schema_version": 1,
  "game_id": "hero_hq",
  "content_version": 1,
  "display_name_key": "game.title",
  "default_locale": "en",
  "entry_scene": "res://games/hero_hq/scenes/app.tscn",
  "mechanics": ["agents", "training", "recruitment", "squads", "timed_tasks", "automation", "focus"],
  "resources": ["credits", "intel"],
  "max_offline_seconds": 28800,
  "data_paths": {
    "roles": "data/roles.json",
    "agents": "data/agents.json",
    "missions": "data/missions.json",
    "upgrades": "data/upgrades.json",
    "progression": "data/progression.json"
  },
  "locale_path": "locale/en.json",
  "theme_path": "ui/theme.json"
}
```

**Contract:** Relative paths resolve inside the pack only. A pack may not escape its root. IDs are lowercase snake_case, unique within their type; references are always by ID (never list index or display label). Arrays must have stable ordering where simulation priority matters. The pack schema and save schema are **different version numbers**. At runtime, validate against the actual implemented schema; examples in this handoff are illustrative until Codex formalizes them.

#### Example content (one task)

```json
{
  "id": "s_alley",
  "name_key": "tasks.s_alley",
  "kind": "solo",
  "stage_id": "street",
  "category_id": "crime",
  "base_seconds": 20,
  "required_agent_count": 1,
  "minimum_rating": 60,
  "required_role_ids": [],
  "rewards": {"credits": 18}
}
```

A future game's inspection case can use the same structure with `name_key: cases.apartment`, category `haunting`, and resource `fees`; do not add special-case code for the word *mission*.

#### Data-driven modifiers and progression

- Prefer generic modifiers (`flat`, `additive_percent`, `multiplicative_percent`, `speed`, `reward`, `xp`, `rating`) with category/source/role filters.
- Validate modifier targets and caps; execute ordering consistently. Core formulas and scaling caps remain configurable where mathematically safe.
- Progression requirements are declarative where possible (`own_agents`, `complete_task`, `earn_resource_lifetime`, `buy_upgrade`). A unique game may add a named custom predicate via a limited hook.
- Recruitment policies expose choice count, role probabilities, costs, traits and starting characters via pack data.
- The engine has no assumptions about exactly five classes, Credits being the primary currency, three-person crews, five stages, or having a prestige system.

### 5. Engine extension hooks (minimal and deliberate)

Only use custom modules when configurable requirements/modifiers are insufficient:

- `get_additional_task_eligibility(state, task, assignees) -> errors[]`
- `get_additional_modifiers(state, task, assignees) -> modifiers[]`
- `on_task_settled(state, completed_task) -> declarative_commands[]`
- `get_custom_screen_data(state) -> dictionary`

Examples: HERO//HQ has Focus and named superhero team synergies; Cryptid Conservation might add creature wellbeing; Temporal Repair might add paradox risk. Extensions must not directly write currencies, bypass transactions, show ads, or mutate save IDs. Hook outputs enter the shared validation and transaction pipeline. If a hook is unnecessary, use no hook.

**Anti-overengineering:** Build a first implementation of the smallest interface required by the current HERO//HQ feature. Do not code all example future systems.

### 6. Reusable UI theming without cloning the HQ screen

UI theme tokens are pack data: background/panel/text/accent/warning colors, typography identifiers, spacing presets, shape/border style, and optional icon style. Use shared reusable widgets for generic list/card/bar behavior, with labels from the pack locale.

Different games can have different top-level compositions: HERO//HQ has its operations grid, Paranormal Inspectors might have a haunted blueprint, and Microbot Repair might have a circuit board. Reuse the engine and UI building blocks, **not** an obligatory identical central visualization or layout.

**Accessibility:** Contrast, tap sizes, readable text, non-color status indicators and reduced-motion support are shared requirements.

### 7. Per-game save/monetization isolation

- Save path: `user://saves/<game_id>/profile.json`; atomic write, backup, migrations. Never silently import a differently identified game's save.
- Save metadata: `game_id`, `save_schema_version`, `pack_content_version`, `last_settled_utc`, stable content IDs, optional namespaced `extensions` state.
- Each Android store app has its own package name, signing/release configuration and platform SKU catalogue. Even with shared provider code, ownership is not automatically shared across apps.
- Reward request IDs are unique and scoped to the game. Daily successful reward cap in HERO//HQ is **three per UTC day**; other games can configure their own bonuses/caps, but none may show unsolicited ads.
- **Universal hard rule:** No popup, banner, interstitial, app-open, autoplay, or forced ads in any derived game. Only explicitly selected/confirmed rewarded ads. Never add a provider method for other ad formats to the game-facing interface.
- Core gameplay, save, recruiting, training and scheduling must run offline. Billing/ads are optional platform adapters and cannot be imported by core simulation code.

### 8. Pack validation and quality gates

At development startup and in CI:

1. Manifest is syntactically valid, schema-supported, with unique stable game ID.
2. All `data_paths` exist within the pack root; referenced roles, tasks, stages, currencies, locale keys and asset IDs exist.
3. Progression dependencies can be satisfied; first-session starter recruits/classes cannot dead-end an unlock.
4. Costs, timers, XP and caps are finite/nonnegative and meet task-specific minimums. Upgrade max ranks are bounded.
5. No duplicate IDs or dangling references. Missing optional feature definitions degrade predictably.
6. State saved under one `game_id` is rejected by another. Pack updates preserve saves using explicit content ID migration mappings.
7. All cross-cutting safety invariants hold: no double assignment, no double settlement, no unearned rewarded bonus, no mandatory ad to progress.

#### Minimal second-pack proof (do at M2, not full game development)

Create a tiny test-only pack called `paranormal_fixture` with **2–3 inspector roles**, **two solo cases**, **one crew case**, and **one upgrade**. Execute the same engine operations as HERO//HQ, with its own palette and resource IDs. In headless tests:

- Load HERO//HQ pack and complete starter solo mission; reload state.
- Load paranormal fixture and recruit an inspector, train, complete a solo case, form a crew, complete a group case and settle offline.
- Assert that no engine code was changed to switch packs; only `game_id` and pack path changed.
- Change a fixture case reward, resource label and theme accent; confirm corresponding runtime values change without editing `framework/`.
- Confirm saved progress, reward claims, entitlements and content IDs do not leak from one game to another.

This is the **acceptance test for framework reusability**, not an instruction to develop or publish another title.

### 9. How Codex should create a new game when authorized

1. Copy only a **pack template** into `games/<new_game_id>/`; never copy `framework/` or rewrite it for theme names.
2. Define theme-specific player fantasy and one differentiated mechanic before writing code.
3. Author resources/roles, agents, training, squad rules, tasks, stages, upgrades, unlocks, mission rewards, monetization config, locale and visual theme.
4. Validate pack; generate preview UI; run shared simulation tests and save-migration tests.
5. Add a small named extension only if the game cannot be expressed through documented modifiers and requirements.
6. Build a title-specific shell/central visualization using reusable UI primitives.
7. Balance offline and active economy in seeded simulations; check no impossible locks.
8. Make a separate Android app/package and test billing/ad/consent policies on its own track.

**Success measure:** The next game achieves a playable prototype mostly through pack authoring and new visual content while shared framework tests remain unchanged and green.

---


## Part D — Implementation Milestones

**Instruction:** Complete sequentially. Mark tasks `[x]` as verified, not merely coded. Each milestone is a small vertical slice that must be runnable and tested before starting the next.

### Architecture constraint for every milestone

HERO//HQ must be an installable/configurable game on top of a **shared game-neutral incremental framework**, not a cloned monolith. Follow Part C — Reusable Framework Engineering Contract in this document. Never hardcode named roles, jobs, currencies, upgrade numbers, palettes or monetization products inside `framework/`. The simple Paranormal Property Inspectors pack is a **test fixture only**; do not build or ship a second commercial game under this backlog.

### M0 — Repository/project foundation
- [ ] Initialize Godot 4.x GDScript project; portrait viewport, stretch mode, safe areas, dark neon theme.
- [ ] Create `framework/` and `games/hero_hq/` structure from GDD §12 and Framework Spec; implement a simple HQ placeholder and bottom tab bar composed from game-specific theme values.
- [ ] Establish pure generic simulation/state module, pluggable clock and `game_id`-scoped save path; no SDK dependency in domain scripts.
- [ ] Create a headless test runner, first smoke test, `GamePackLoader` and basic pack validator; build HERO//HQ scene from a minimal manifest/theme/role/task definition.
- [ ] Add README with launch commands and `docs/CHANGELOG.md`.

**Gate:** Editor opens, HERO//HQ pack loads, main scene and themed tab nav work, headless pack-validation/smoke tests pass. No hardcoded title-specific content inside shared modules.

### M1 — Single-hero functional loop (highest priority)
- [ ] Load initial `Volt` hero, attributes, XP, rating, starter Credits and two solo channels from HERO//HQ pack data.
- [ ] Add Alley Patrol and Stop a Robbery definitions; eligibility, timers, rewards and XP.
- [ ] Add one training slot, XP accumulation and automatic level-up.
- [ ] Implement Focus regeneration and one optional pulse action.
- [ ] Make Credits and XP persist via atomic versioned save and backup.
- [ ] Implement deterministic offline settlement of manual active missions and training in the shared framework, preserving `game_id` and pack version.
- [ ] Show functional live values in HQ (not hardcoded UI mock values).

**Gate:** Train/deploy/earn/save/reopen; no lost/duplicate payout; offline 5-min scenario matches expected.

### M2 — Recruitment, classes, solo catalogue
- [ ] Implement all 5 classes and class growth tables.
- [ ] Generate deterministic 2-candidate ordinary recruit offers; rarity odds/traits, seeded names.
- [ ] Charge Credit cost only upon selecting/confirming recruit; enforce capacity.
- [ ] Implement 10 solo missions and sector availability gating.
- [ ] Build Heroes and Missions tabs and hero detail card.
- [ ] Implement starter recruit guarantees needed for team progression.
- [ ] Add first training/recruit/solo upgrades and validation rules.
- [ ] Add a **minimal** Paranormal Property Inspectors test pack (2–3 roles, 2 solo jobs, 1 crew job, 1 upgrade); no release-ready UI/content.
- [ ] Add headless smoke test loading both packs sequentially without modifying `framework/`: hire/recruit, train, complete solo job, build crew/team, complete group job, settle offline; assert separate game IDs, saves, display labels and palettes.
- [ ] Run a content-only modification test: change a fixture job reward and theme name; ensure engine code remains unchanged.

**Gate:** Reach 3 heroes naturally; no dead-end class combinations; all costs, timings and requirements correct. Second game pack smoke test passes with unchanged shared framework and isolated state.

### M3 — Teams and team missions
- [ ] Team roster editor; unique 3-hero assignments, rename team.
- [ ] Implement team rating, class requirement checking, synergies and reserved hero status.
- [ ] Implement all 8 team operations, rewards, Intel and first-clear flags.
- [ ] Implement team mastery for five categories.
- [ ] Build Teams tab and display detailed ineligibility reasons.

**Gate:** Form Team Alpha, complete Bank Siege, train one member later; no double assignment or double payout.

### M4 — Automated idle gameplay + progression
- [ ] Implement Command Level milestones and sector unlocks through National Response.
- [ ] Auto Patrol: fixed-mission solo channel repeat with player config.
- [ ] Auto Team: fixed-mission team repeat with player config.
- [ ] Implement offline discrete-event simulation for repeated automated missions and training.
- [ ] Implement up to 8h base offline cap and upgrade cap to 16h.
- [ ] Add 22 upgrade types with prerequisites/rank limits.
- [ ] Add offline earnings report and automation wait-reason UI.

**Gate:** Three-hour offline test pays exact expected amount; automated teams and solo slots respect hero locks; game can reach sector 3.

### M5 — Presentation, content and first playable campaign
- [ ] Build complete five-tab UI with responsive Control nodes and touch-sized targets.
- [ ] Draw original low-cost central HQ network with dynamic state-driven nodes in HERO//HQ-specific scene; shared UI card components use pack theme tokens.
- [ ] Implement the 10 specialization branches and first 3 earnable legendaries.
- [ ] Add daily agency contracts (no ad quests), tutorial and milestone achievements.
- [ ] Add optional reduced motion and text clarity/accessibility pass.
- [ ] Polish saved states, compact numbers, sound toggle, offline report.
- [ ] Complete first campaign at Nemesis Showdown and show post-launch sector roadmap non-intrusively.

**Gate:** New tester can play from first mission to campaign clear, understand automation and complete all systems without purchasing.

### M6 — Ethical monetization integrations
- [ ] Implement shared interface + mock `RewardedAdsProvider`, `BillingProvider` and analytics adapter; product identifiers and reward catalogue come from active game pack.
- [ ] Support Protocols visible only as normal in-app navigation; no ads except deliberate user tap + confirmation.
- [ ] Implement credit boost, training surge, rapid response and **shared 3/day successful reward cap**.
- [ ] Add persisted idempotent earned-reward workflow; callbacks cannot double-credit; skip/failure grants nothing.
- [ ] Implement HERO//HQ Commander License entitlement in the HERO//HQ pack and its **same** daily claim count, theme and extra saved presets; generic entitlement validation remains in framework.
- [ ] Implement two cosmetics and localized store price display.
- [ ] Integrate actual current Android rewarded SDK and Godot/Play Billing; pin versions and document setup.
- [ ] Test purchases pending/completed/acknowledged/restored/refunded using Play test track.
- [ ] Finish region/privacy/consent and Data safety review.

**Gate:** Every reward flow is explicitly user-initiated; cancel leaves gameplay intact; no forced ads anywhere; end-to-end test-track purchases work and restore.

### M7 — Closed testing + launch quality
- [ ] Android phone tests (small/tall screen, accessibility, suspend, airplane mode, reboot).
- [ ] Automated balancing: 100+ seeded runs first 60 minutes, 24-hour idle economy stress.
- [ ] Check payment failure/restore, SDK unavailable, privacy consent, ads disabled, game-specific SKU entitlement isolation and pack/schema migrations.
- [ ] Use release keys safely; verify Android AAB, Play Console setup and current policy.
- [ ] Record first-week retention and early tutorial bottlenecks (privacy-compliant).
- [ ] Update README, GDD balance appendix and release notes.

**Gate:** All non-negotiable policies pass; game playable free; store items real/valid; releases survive save migrations and offline recovery.

### Reusability readiness checklist (required before M7 release)
- [ ] Core `framework/` imports no `games/hero_hq` file or title-specific string.
- [ ] Pack contains roles, labels, mission definitions, tunable math, skins, unlocks and store SKU namespace.
- [ ] Two packs can launch through the same framework in editor/test mode without search-and-replace or copying engine code.
- [ ] Save/claim/entitlement state is isolated by `game_id`; duplicate IDs and invalid pack refs fail validation cleanly.
- [ ] A content-only edit changes fixture task rewards and visual theme while all framework tests continue passing.
- [ ] Documentation explains how to create a third pack and where unique mechanics extensions belong.

### Order for a Codex agent
Start at **M0** only. After completing its gate, report precisely what changed and wait for owner to approve the next milestone if they are reviewing manually. Do not attempt M0–M7 in one generated code dump. Keep each completed milestone shippable in the Godot editor.

---


## Part E — Future Theme Roadmap

**Status:** Inspiration and possible future products ONLY. None of these themes is approved for implementation as part of HERO//HQ M0–M7. Competition and market demand have not been independently validated.

### Principles

All 30 can share agents/roles, individual jobs, multi-agent operations, training, progression, automation, offline processing, upgrades, save handling and voluntary rewarded-ad providers. **Each should add at least one distinct signature mechanic** and have its own identity, economy, visual theme, release application and store entitlements. Avoid shipping a series of near-identical reskins.

| # | Potential title/theme | Shared-loop mapping | Unique mechanic to explore |
|---:|---|---|---|
| 1 | Paranormal Property Inspectors | Inspectors → surveys → investigation crews → haunted sites | Diagnose haunting categories, then pick containment methods |
| 2 | Cryptid Conservation Agency | Trackers → field surveys → capture/recovery teams | Welfare and habitat compatibility for rescued creatures |
| 3 | Afterlife Postal Service | Couriers → deliveries → escort squads | Routes across increasingly unstable spirit territories |
| 4 | Curse Removal Bureau | Exorcists → minor cleansings → ritual teams | Identify multi-part curse conditions before lifting them |
| 5 | Monster Witness Protection | Relocation officers → assignments → security teams | Disguise integrity and secrecy risk |
| 6 | Haunted Artifact Reclamation | Collectors → retrieval jobs → containment squads | Vault safety and interacting artifact traits |
| 7 | Dream Repair Corporation | Dreamwalkers → nightmare jobs → shared-dream teams | Repair dream stability and memory fragments |
| 8 | Reaper's Administration | Reapers → soul cases → processing teams | Department routing/queue backlog |
| 9 | Supernatural Building Maintenance | Technicians → faults → major repair crews | Building systems with interacting failures |
| 10 | Forgotten Gods Agency | Minor deities → favors → divine teams | Domain influence and faith synergy |
| 11 | Temporal Repair Division | Time agents → anomalies → paradox teams | Timeline divergence/paradox pressure |
| 12 | Microbot Repair Collective | Microbots → repairs → swarms | Swarm specialization and circuit/component coverage |
| 13 | Interdimensional Customs | Inspectors → border cases → incident teams | Species/contraband compatibility and inspection profiles |
| 14 | Abandoned Satellite Recovery | Operators → salvage sorties → orbital crews | Debris trajectories and module salvage decisions |
| 15 | Alien Ecosystem Restoration | Scientists → ecosystem tasks → field expeditions | Interdependent food chains and habitat stability |
| 16 | Rogue AI Rehabilitation Center | AI therapists → diagnostics → recovery teams | Personality/behavior patterns and rehabilitation fit |
| 17 | Pocket Universe Surveyors | Researchers → surveys → exploration teams | Universe stability clocks and exploration risk |
| 18 | Space Weather Authority | Forecasters → warnings → crisis teams | Forecast uncertainty and response windows |
| 19 | Galactic Translation Bureau | Linguists → translations → language teams | Unlockable grammar fragments/language trees |
| 20 | Reality Glitch Technicians | Debuggers → incidents → repair squads | Chained bug dependencies and patches |
| 21 | Miniature Civilization Caretakers | Caretakers → interventions → maintenance teams | Population/ecosystem feedback between tiny civilizations |
| 22 | Library of Living Books | Archivists → page fixes → story expedition teams | Narrative continuity and divergent storylines |
| 23 | Underground Fungal Network | Mycologists → growth jobs → colony groups | Nutrient network and colony adjacency |
| 24 | Lost and Found Department | Finders → searches → recovery teams | Clue chains and item provenance |
| 25 | Mythological Insurance Agency | Adjusters → claims → investigation teams | Risk pricing and claim validity |
| 26 | Secret Door Inspectors | Explorers → inspections → doorway teams | Discover and classify unstable destination rules |
| 27 | Toy Restoration Society | Restorers → repairs → expedition groups | Toy personality and restoration parts matching |
| 28 | Underworld Transit Authority | Conductors → service jobs → emergency crews | Transit network routing and delay management |
| 29 | Ancient Language Recovery Institute | Scholars → inscriptions → deciphering teams | Language-family knowledge accumulation |
| 30 | Department of Impossible Weather | Forecasters → anomalies → intervention teams | Bizarre weather interactions and regional mitigation |

### First five candidates to prototype *after* HERO//HQ

1. **Paranormal Property Inspectors:** Closest to HERO//HQ's existing deployment mechanics, ideal for demonstrating real code reuse. Design shift: investigations reveal a haunting type before choosing a response crew. UI: haunted blueprint + teal/violet scanlines.
2. **Cryptid Conservation Agency:** Strong collectible roster fantasy; add specimen habitats and welfare needs. UI: bioluminescent green field records and creature silhouettes.
3. **Temporal Repair Division:** Compatible with missions and classes; unique paradox-pressure meter. UI: cyan/orange fractured timeline diagram.
4. **Miniature Civilization Caretakers:** Greater systemic differentiation through linked population/food/weather production. UI: terrarium-like dashboard and tiny settlement nodes. This requires more nonshared mechanics.
5. **Library of Living Books:** Narrative-themed missions; branching book continuity. UI: dark parchment-neon pages and glowing story-thread connections.

### Translation examples

| HERO//HQ | Paranormal Inspectors | Temporal Repair | Cryptid Conservation |
|---|---|---|---|
| Hero | Inspector | Time Agent | Field Researcher |
| Class | Discipline | Temporal Specialty | Research Specialty |
| Solo Mission | Site Survey | Minor Anomaly | Track Sighting |
| Team Mission | Crew Exorcism | Timeline Stabilization | Conservation Expedition |
| Credits | Service Fees | Temporal Credits | Research Grants |
| Intel | Evidence | Chronal Data | Species Data |
| Team Mastery | Case Expertise | Era Expertise | Habitat Expertise |
| HQ Upgrade | Agency Facility | Timeline Control Center | Sanctuary Upgrade |
| Operations Network | Haunted City Map | Timeline Map | Habitat/Expedition Map |

### Release guardrail

A good new-theme prototype should prove its *unique mechanic* in a playable vertical slice before cosmetic packs or paid monetization are added. Each product inherits the universal **rewarded-ads-only** rule: no forced/pop-up/interstitial/banner/app-open ads or unsolicited prompts. HERO//HQ remains the sole active release target until the owner explicitly authorizes another game.

---


## Part F — Self-Contained Reference Game-Pack Fixtures

These are **illustrative partial JSON fixture definitions**, not a full playable data set or final schema. They make this handoff self-contained; Codex should create the appropriate files under `games/<game_id>/` from these samples, extend missing required data, validate against the actual implemented manifest schema, and keep the production HERO//HQ and test-only Paranormal packs in distinct namespaces. JSON paths shown here follow the small fixture archive; Codex may adapt them into the canonical `data/`, `locale/`, and `ui/` layout from Part C. Preserve fields and meanings in the process.

The Paranormal fixture exists *only* to prove that a different game uses the unchanged framework. Building Paranormal Property Inspectors as a commercial game is not part of this assignment.


### `example_packs/hero_hq/en.json`

```json
{
  "game.title": "HERO//HQ",
  "roles.striker": "Striker",
  "roles.tech": "Tech",
  "roles.support": "Support",
  "tasks.s_alley": "Alley Patrol",
  "resources.credits": "Credits",
  "resources.intel": "Intel"
}
```


### `example_packs/hero_hq/manifest.json`

```json
{
  "pack_schema_version": 1,
  "game_id": "hero_hq",
  "content_version": 1,
  "display_name_key": "game.title",
  "default_locale": "en",
  "mechanics": [
    "agents",
    "training",
    "recruitment",
    "squads",
    "timed_tasks",
    "automation",
    "focus"
  ],
  "resources": [
    "credits",
    "intel"
  ],
  "max_offline_seconds": 28800,
  "data_paths": {
    "roles": "roles.json",
    "missions": "missions.json"
  },
  "locale_path": "en.json",
  "theme_path": "theme.json"
}
```


### `example_packs/hero_hq/missions.json`

```json
[
  {
    "id": "s_alley",
    "name_key": "tasks.s_alley",
    "kind": "solo",
    "stage_id": "street",
    "category_id": "crime",
    "base_seconds": 20,
    "required_agent_count": 1,
    "minimum_rating": 60,
    "required_role_ids": [],
    "rewards": {
      "credits": 18
    }
  }
]
```


### `example_packs/hero_hq/roles.json`

```json
[
  {
    "id": "striker",
    "name_key": "roles.striker",
    "growth": {
      "power": 1,
      "speed": 2,
      "skill": 1
    }
  },
  {
    "id": "tech",
    "name_key": "roles.tech",
    "growth": {
      "power": 1,
      "speed": 1,
      "skill": 2
    }
  },
  {
    "id": "support",
    "name_key": "roles.support",
    "growth": {
      "power": 1,
      "speed": 1,
      "skill": 2
    }
  }
]
```


### `example_packs/hero_hq/theme.json`

```json
{
  "background": "#080C13",
  "panel": "#111B29",
  "primary_text": "#E5EEF8",
  "secondary_text": "#90A5BA",
  "accent": "#00E5F5",
  "warning": "#FF6585"
}
```


### `example_packs/paranormal_fixture/en.json`

```json
{
  "game.title": "Paranormal Property Inspectors — Test Fixture",
  "roles.medium": "Medium",
  "roles.technician": "Technician",
  "roles.warden": "Warden",
  "tasks.case_apartment": "Survey Haunted Apartment",
  "tasks.case_basement": "Inspect Cursed Basement",
  "tasks.crew_hospital": "Cleanse Abandoned Hospital",
  "upgrades.better_scanners": "Better Scanners",
  "resources.fees": "Service Fees",
  "resources.evidence": "Evidence"
}
```


### `example_packs/paranormal_fixture/manifest.json`

```json
{
  "pack_schema_version": 1,
  "game_id": "paranormal_fixture",
  "content_version": 1,
  "display_name_key": "game.title",
  "default_locale": "en",
  "mechanics": [
    "agents",
    "training",
    "recruitment",
    "squads",
    "timed_tasks",
    "automation"
  ],
  "resources": [
    "fees",
    "evidence"
  ],
  "max_offline_seconds": 28800,
  "data_paths": {
    "roles": "roles.json",
    "missions": "missions.json",
    "upgrades": "upgrades.json"
  },
  "locale_path": "en.json",
  "theme_path": "theme.json"
}
```


### `example_packs/paranormal_fixture/missions.json`

```json
[
  {
    "id": "case_apartment",
    "name_key": "tasks.case_apartment",
    "kind": "solo",
    "stage_id": "block_one",
    "category_id": "survey",
    "base_seconds": 20,
    "required_agent_count": 1,
    "minimum_rating": 50,
    "required_role_ids": [],
    "rewards": {
      "fees": 18
    }
  },
  {
    "id": "case_basement",
    "name_key": "tasks.case_basement",
    "kind": "solo",
    "stage_id": "block_one",
    "category_id": "survey",
    "base_seconds": 50,
    "required_agent_count": 1,
    "minimum_rating": 80,
    "required_role_ids": [
      "technician"
    ],
    "rewards": {
      "fees": 50
    }
  },
  {
    "id": "crew_hospital",
    "name_key": "tasks.crew_hospital",
    "kind": "squad",
    "stage_id": "block_one",
    "category_id": "containment",
    "base_seconds": 180,
    "required_agent_count": 3,
    "minimum_rating": 210,
    "required_role_ids": [
      "medium"
    ],
    "rewards": {
      "fees": 200,
      "evidence": 1
    }
  }
]
```


### `example_packs/paranormal_fixture/roles.json`

```json
[
  {
    "id": "medium",
    "name_key": "roles.medium",
    "growth": {
      "power": 1,
      "speed": 1,
      "skill": 2
    }
  },
  {
    "id": "technician",
    "name_key": "roles.technician",
    "growth": {
      "power": 1,
      "speed": 2,
      "skill": 1
    }
  },
  {
    "id": "warden",
    "name_key": "roles.warden",
    "growth": {
      "power": 2,
      "speed": 1,
      "skill": 1
    }
  }
]
```


### `example_packs/paranormal_fixture/theme.json`

```json
{
  "background": "#0C0914",
  "panel": "#1C1528",
  "primary_text": "#F0EAF8",
  "secondary_text": "#AAA0BA",
  "accent": "#C77DFF",
  "warning": "#FF7596"
}
```


### `example_packs/paranormal_fixture/upgrades.json`

```json
[
  {
    "id": "better_scanners",
    "name_key": "upgrades.better_scanners",
    "max_level": 5,
    "base_cost": {
      "fees": 100
    },
    "modifiers": [
      {
        "target": "task_speed",
        "scope": "solo",
        "additive_percent_per_level": 5
      }
    ]
  }
]
```


---

## Final Delivery Gate

Codex should begin at **M0**, then progress only when each milestone's acceptance criteria are met. Verify that the game can be played without internet access or purchases, that only explicitly requested rewarded ads can ever play, and that a second game's pack works with the same unmodified shared framework. Do not implement or publish the other 30 themes without explicit authorization.

**Owner-facing handoff:** This file is the single authoritative product specification. Keep it available to the coding agent and update it in place as design decisions change.

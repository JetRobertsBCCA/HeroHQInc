# Balance: the long-term curve and rebirth

This document is the reference for every pacing number in HERO//HQ. Values are
measured with `tooling/balance_report.gd` (first hours) and
`tooling/long_run_report.gd` (days, with rebirth). If a number here disagrees
with a tool run, the tool is right and this file is stale.

## 1. The core loop, as formulas

One agent trains to gain levels; levels unlock harder tasks; tasks pay the
Credits that pay for training.

| Quantity | Formula | Hero HQ values |
| --- | --- | --- |
| Training cost | `C(L) = C0 · r_c^(L-1)` | `C0 = 25`, `r_c = 1.4` |
| XP for next level | `X(L) = X0 + X_inc·(L-1)` | `X0 = 120`, `X_inc = 80` |
| XP per training session | `x_p` | `40` |
| Task payout | `I_k` (per task) | 60 → 900 Credits |
| Payout multiplier | `M = 1 + b·chips` | `b = 0.05` |
| Time to next level | `T(L) = X(L)·C(L) / (x_p·I_min)` | see below |

The important term is `T(L) ∝ X(L)·r_c^L / I`. Income only grows when a new task
tier unlocks, and there is one tier per level. So while tiers last, income and
cost grow together and waits stay flat; **the moment the last tier is reached,
income freezes while cost keeps multiplying by 1.4 per level.** That is the wall
every idle game hits, and it is the reason a rebirth layer exists.

Measured with content v2 (first run): task unlocks at 0:40, 2:10, 5:10, 8:10 and
11:10, levels at 0:40, 2:10, 5:10, 8:10, 11:10, 15:10, 21:10, 29:10, 41:10 and
59:10. Waits grow ~1.4× per level after the ladder ends — roughly 1.5, 2, 3, 4.5,
7, 10, 18 minutes. That is a fine first session and an unplayable week.

## 2. Rebirth: the long-term engine

A rebirth ("Command Rebirth" in the UI) trades the current run for chips that
permanently multiply every payout.

```
chips  = floor(gain_factor · (run_earnings / scale)^exponent)
M      = 1 + bonus_per_chip · total_chips
```

Hero HQ values: `threshold_amount 4000`, `scale 1000`, `exponent 0.45`,
`gain_factor 2`, `bonus_per_chip 0.05`, `min_level 7`.

Chips are recomputed from lifetime earnings rather than awarded per run, so a
reset can never be double-dipped: two resets on the same progress pay the same
bank, and the only way to earn more is to earn more. Solving the formula for a
chip target also gives the progress bar its denominator:
`lifetime = scale · ((chips / gain_factor) ^ (1 / exponent))`.

Why these shapes:

- **Fractional exponent, not linear.** With `exponent = 0.5`, doubling the chips
  on offer needs *four times* the run earnings. Chips therefore grow like a
  square root while costs grow exponentially, so no single rebirth ever trivialises
  the ladder — each run still has a shape, and prestiging repeatedly without
  pushing deeper stops paying. (Cookie Clicker uses a cube root for the same
  reason; Realm Grinder and AdVenture Capitalist use squares.)
- **Linear per-chip bonus.** Additive within the banked total keeps early chips
  exciting and prevents runaway compounding; `+5%` per chip means the first
  rebirth (4 chips) is a visible `+20%` on every payout.
- **A threshold, not "rebirth whenever".** 4000 run Credits is reachable around
  the end of the first ladder, so the first rebirth lands after the player has
  seen the whole loop (~15 minutes), not before they understand it.
- **A level gate.** Requiring level 7 means the reset cannot be used to skip the
  part of the game that teaches training.

What resets: level, XP, attributes, Credits, current assignments, run earnings.
What survives: chips, rebirth count, lifetime stats, lifetime earnings, and the
roster itself (agents are re-seeded at their pack base values, so a future
recruitment layer keeps its unlocks).

## 3. Why this stays interesting

The wall is not removed — it is *scheduled*. The curve is tuned so that:

1. Within a run, waits rise gently for the first ~6 levels, then steeply.
2. The steep part begins right where the rebirth payout becomes meaningful, so
   the "this is slowing down" feeling and the "I can reset for a real gain"
   feeling arrive together.
3. Each rebirth shortens the re-climb: at `M = 1.4` the same ladder costs ~29%
   less time, and the player pushes past their previous best before the next
   wall.

Two guardrails keep a slow stretch from becoming a boring one:

- **The reset is never hidden.** The Upgrades tab shows the live payout, the
  requirement bar and the next multiplier at all times, so a stalled run always
  has a legible next action.
- **The reset is never accidental.** The button arms on the first tap and
  commits on the second.

### Measured long-run shape

`tooling/long_run_report.gd` plays the real simulation for seven days with a
player who rebirths as soon as a chip is available and the run is at least 15
minutes old. That policy is a *lower bound* on run length — a patient player
waits longer — and it is the harshest schedule to keep waits short on.

| Measure | Result |
| --- | --- |
| Rebirths in 7 days | 205 |
| Average run | 49m 10s (17m 10s at the start, ~1h 05m by run 200) |
| Chips banked by day 7 | 208 (×11.40 on every payout) |
| Longest single level-up wait | **14m 00s** (run 105, level 15) |
| Level reached per run | 7 at first, 15–16 by day 7 |

The shape is what the design asks for: the first session resets inside half an
hour, runs lengthen by roughly 4× over the week, and the deepest wall never
crosses the 30-minute boredom budget. Sweeps that raised `exponent` to 0.5
collapsed the loop into a 22-minute reset treadmill (459 runs), and lowering it
to 0.4 stretched the worst wait to 42 minutes — hence 0.45.

## 4. Tuning knobs

| Knob | Where | Effect |
| --- | --- | --- |
| `threshold_amount` | manifest `prestige` | How long the first run lasts |
| `exponent` | manifest `prestige` | How hard later runs must push for the next chip |
| `bonus_per_chip` | manifest `prestige` | How fast a re-climb gets |
| `scale` / `gain_factor` | manifest `prestige` | Absolute payout size |
| `cost_growth` | agents.json `training` | Slope of the wall inside a run |
| `xp_per_session` | agents.json `training` | Overall session length |

Rule of thumb from the model: if the longest single wait in a run passes ~30
minutes, either the rebirth payout at that point is too small (`scale` too high)
or the tier ladder ends too early relative to `cost_growth`.

## 5. Sources

- Anthony Pecorella, *The Math of Idle Games, Part III* — prestige currencies,
  square/cube-root payouts, and why sub-linear prestige scaling preserves pacing.
  https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii
- Anthony Pecorella, *Balancing Tips: How We Managed Math on Idle Idol* —
  session-length targets and measured first-session curves.
  https://www.gamedeveloper.com/design/balancing-tips-how-we-managed-math-on-idle-idol
- Eric Guan, *Idle Game Design Principles* — early-game generosity, decaying
  session frequency, and why the first prestige must be reachable in one sitting.
  https://ericguan.substack.com/p/idle-game-design-principles
- *A Gentle Guide to Idle Game Prestige Mechanics* — reset timing, what players
  expect to keep, and the "soft chapter" framing of a reset.
  https://dropletidle.com/pages/blog/guide-to-idle-game-prestige-mechanics/
- Cookie Clicker wiki, *Ascension* — cube-root heavenly chips as a worked example.
  https://cookieclicker.wiki.gg/wiki/Ascension

class_name Prestige
extends RefCounted
## Rebirth ("prestige") math: how many chips a save is worth, what the permanent
## multiplier is, and exactly what a run reset clears.
##
## Neutral and pack-driven. The pack declares the economy:
##   {"resource_id": "<id>", "threshold_amount": 4000, "scale": 1000,
##    "exponent": 0.5, "gain_factor": 2, "bonus_per_chip": 0.05, "min_level": 7}
##
## Chips are a function of *lifetime* earnings, not an award per run. A rebirth
## therefore cannot double-dip: resetting twice on the same progress pays the
## same bank, so the only way forward is to earn more. The fractional exponent
## keeps that bank sub-linear, which is what stops the multiplier from outrunning
## the cost curve. Derivation and tuning targets live in docs/BALANCE.md.

const DEFAULT_EXPONENT := 0.5
const DEFAULT_BONUS_PER_CHIP := 0.05
const DEFAULT_GAIN_FACTOR := 2.0
const MIN_EXPONENT := 0.05
const MAX_EXPONENT := 1.0


static func enabled(pack: GamePack) -> bool:
	return not pack.prestige.is_empty()


static func resource_id(pack: GamePack) -> String:
	if not enabled(pack):
		return ""
	var declared := str(pack.prestige.get("resource_id", ""))
	if not declared.is_empty():
		return declared
	var resources := pack.declared_resources()
	if resources.is_empty():
		return ""
	return str(resources[0])


static func exponent(pack: GamePack) -> float:
	return clampf(
		float(pack.prestige.get("exponent", DEFAULT_EXPONENT)), MIN_EXPONENT, MAX_EXPONENT
	)


static func gain_factor(pack: GamePack) -> float:
	return maxf(float(pack.prestige.get("gain_factor", DEFAULT_GAIN_FACTOR)), 0.0)


static func scale(pack: GamePack) -> float:
	return maxf(float(pack.prestige.get("scale", 1000.0)), 1.0)


static func bonus_per_chip(pack: GamePack) -> float:
	return maxf(float(pack.prestige.get("bonus_per_chip", DEFAULT_BONUS_PER_CHIP)), 0.0)


## All-time earnings of the prestige resource. Lifetime totals never reset, so
## this is the one number a rebirth bank is derived from.
static func lifetime_earnings(state: GameState, pack: GamePack) -> float:
	var earned: Dictionary = state.stats.get("earned", {})
	return maxf(float(earned.get(resource_id(pack), 0.0)), 0.0)


## Chips a given lifetime total is worth.
static func chips_for(lifetime: float, pack: GamePack) -> int:
	if not enabled(pack) or lifetime <= 0.0:
		return 0
	return int(floor(gain_factor(pack) * pow(lifetime / scale(pack), exponent(pack))))


## Chips this save is currently worth, whether or not they are banked yet.
static func gain(state: GameState, pack: GamePack) -> int:
	return chips_for(lifetime_earnings(state, pack), pack)


## Chips a rebirth would add right now.
static func pending(state: GameState, pack: GamePack) -> int:
	return maxi(gain(state, pack) - state.prestige_chips(), 0)


## Lifetime earnings needed to reach the next chip above what is already earned.
static func next_chip_at(state: GameState, pack: GamePack) -> float:
	var target := float(gain(state, pack) + 1)
	var factor := maxf(gain_factor(pack), 0.0001)
	return scale(pack) * pow(target / factor, 1.0 / exponent(pack))


## Permanent reward multiplier from chips already banked.
static func multiplier(state: GameState, pack: GamePack) -> float:
	return 1.0 + bonus_per_chip(pack) * float(state.prestige_chips())


static func threshold_amount(pack: GamePack) -> float:
	return maxf(float(pack.prestige.get("threshold_amount", 0.0)), 0.0)


static func min_level(pack: GamePack) -> int:
	return maxi(int(pack.prestige.get("min_level", 1)), 1)


static func highest_level(state: GameState) -> int:
	var best := 1
	for agent_id in state.agents.keys():
		var agent: Variant = state.agents[agent_id]
		if agent is Dictionary:
			best = maxi(best, int((agent as Dictionary).get("level", 1)))
	return best


## Returns {ok, code, gain, chips, multiplier, lifetime, required_amount,
## level, required_level, next_chip_at}. `code` is stable so the UI can localise
## the reason a rebirth is unavailable.
static func eligibility(state: GameState, pack: GamePack) -> Dictionary:
	var lifetime := lifetime_earnings(state, pack)
	var level := highest_level(state)
	var adding := pending(state, pack)
	var result := {
		"ok": false,
		"code": "",
		"gain": adding,
		"chips": state.prestige_chips(),
		"multiplier": multiplier(state, pack),
		"lifetime": lifetime,
		"required_amount": threshold_amount(pack),
		"level": level,
		"required_level": min_level(pack),
		"next_chip_at": next_chip_at(state, pack),
	}
	if not enabled(pack):
		result["code"] = "prestige_unavailable"
		return result
	if lifetime + 0.0001 < threshold_amount(pack):
		result["code"] = "prestige_earnings_short"
		return result
	if adding <= 0:
		result["code"] = "prestige_no_pending"
		return result
	if level < min_level(pack):
		result["code"] = "prestige_level_short"
		return result
	result["ok"] = true
	return result


## Banks every chip the lifetime total is worth and starts a fresh run. Lifetime
## totals survive, which is what makes the bank monotone.
static func rebirth(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	var check := eligibility(state, pack)
	if not check.get("ok", false):
		return check
	var banked := gain(state, pack)
	var added := maxi(banked - state.prestige_chips(), 0)
	state.prestige["chips"] = banked
	state.prestige["count"] = int(state.prestige.get("count", 0)) + 1
	state.prestige["run_earnings"] = 0.0
	_reset_run(state, pack, utc_now)
	return {
		"ok": true,
		"code": "",
		"gained": added,
		"chips": banked,
		"count": int(state.prestige.get("count", 0)),
		"multiplier": multiplier(state, pack),
	}


static func _reset_run(state: GameState, pack: GamePack, utc_now: int) -> void:
	state.resources = pack.starting_resources.duplicate(true)
	state.assignments.clear()
	# The roster is a collection, not run progress: every recruited agent survives
	# and is rewound to its base shape. Starter agents are reseeded only if missing.
	for agent_id in state.agents.keys():
		var agent: Variant = state.agents[agent_id]
		if agent is Dictionary:
			AgentRules.reset_progress(agent as Dictionary, pack)
	Simulation.seed_missing_starter_agents(state, pack)
	state.stats["run_tasks_completed"] = 0
	# Reset the settlement stamp so time before the rebirth is not paid twice.
	state.last_settled_utc = int(utc_now)

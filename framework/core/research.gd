class_name Research
extends RefCounted
## Permanent research ranks: the second meta layer.
##
## A pack declares branches and what each rank does:
##   {"resource_id": "<id>", "branches": [
##     {"id": "...", "label_key": "...", "max_rank": 5,
##      "base_cost": 15, "cost_growth": 1.6,
##      "effect": "reward_multiplier", "per_rank": 0.06}]}
##
## Ranks live in `GameState.upgrades`, so they survive a rebirth: that is what
## makes this a meta layer rather than another run upgrade. The currency is
## usually a secondary resource the run throws off, which gives that resource a
## sink instead of leaving it as score.
##
## Neutral: no title ids and no attribute names. Effects are named generically
## and applied by the simulation only through the helpers here.

const EFFECT_REWARD := "reward_multiplier"
const EFFECT_TRAINING := "training_discount"
const EFFECT_AUTO_REPEAT := "auto_repeat"
const SUPPORTED_EFFECTS := [EFFECT_REWARD, EFFECT_TRAINING, EFFECT_AUTO_REPEAT]

const ERROR_UNAVAILABLE := "research_unavailable"
const ERROR_UNKNOWN := "research_unknown"
const ERROR_MAX_RANK := "research_max_rank"
const ERROR_INSUFFICIENT := "insufficient_resource"

## A discount may never make training free; below this it stops mattering.
const MIN_TRAINING_MULTIPLIER := 0.2


static func enabled(pack: GamePack) -> bool:
	return not pack.research.is_empty()


static func resource_id(pack: GamePack) -> String:
	if not enabled(pack):
		return ""
	var declared := str(pack.research.get("resource_id", ""))
	if not declared.is_empty():
		return declared
	var resources := pack.declared_resources()
	if resources.is_empty():
		return ""
	return str(resources[0])


static func branches(pack: GamePack) -> Array:
	var declared: Variant = pack.research.get("branches", [])
	if declared is Array:
		return declared
	return []


static func branch(pack: GamePack, branch_id: String) -> Dictionary:
	for raw in branches(pack):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == branch_id:
			return raw
	return {}


static func max_rank(pack: GamePack, branch_id: String) -> int:
	return maxi(int(branch(pack, branch_id).get("max_rank", 0)), 0)


static func rank(state: GameState, branch_id: String) -> int:
	return maxi(int(state.upgrades.get(branch_id, 0)), 0)


## Cost of the next rank, or -1 when the branch is unknown or already maxed.
static func cost(state: GameState, pack: GamePack, branch_id: String) -> int:
	var rules := branch(pack, branch_id)
	if rules.is_empty():
		return -1
	var current := rank(state, branch_id)
	if current >= max_rank(pack, branch_id):
		return -1
	var base := maxf(float(rules.get("base_cost", 0.0)), 0.0)
	var growth := maxf(float(rules.get("cost_growth", 1.0)), 1.0)
	return maxi(int(ceilf(base * pow(growth, float(current)))), 1)


## Sum of `per_rank` across every purchased rank with this effect.
static func effect_total(state: GameState, pack: GamePack, effect: String) -> float:
	var total := 0.0
	for raw in branches(pack):
		if not (raw is Dictionary):
			continue
		var rules: Dictionary = raw
		if str(rules.get("effect", "")) != effect:
			continue
		var current := rank(state, str(rules.get("id", "")))
		if current <= 0:
			continue
		total += float(rules.get("per_rank", 0.0)) * float(current)
	return total


## Permanent multiplier on every task payout.
static func reward_multiplier(state: GameState, pack: GamePack) -> float:
	return 1.0 + maxf(effect_total(state, pack, EFFECT_REWARD), 0.0)


## Multiplier applied to training cost.
static func training_multiplier(state: GameState, pack: GamePack) -> float:
	return clampf(
		1.0 - maxf(effect_total(state, pack, EFFECT_TRAINING), 0.0),
		MIN_TRAINING_MULTIPLIER,
		1.0
	)


## True once at least one rank of a branch carrying this effect is bought.
static func unlocked(state: GameState, pack: GamePack, effect: String) -> bool:
	return effect_total(state, pack, effect) > 0.0


## Spends the pack's research resource and raises the branch by one rank.
## Returns {ok, code, rank, cost, resource_id, effect}.
static func buy(state: GameState, pack: GamePack, branch_id: String) -> Dictionary:
	if not enabled(pack):
		return _problem(ERROR_UNAVAILABLE, "This pack declares no research.")
	var rules := branch(pack, branch_id)
	if rules.is_empty():
		return _problem(ERROR_UNKNOWN, "Research '%s' is not part of this pack." % branch_id)
	var current := rank(state, branch_id)
	if current >= max_rank(pack, branch_id):
		return _problem(ERROR_MAX_RANK, "Research '%s' is already at maximum rank." % branch_id)
	var resource := resource_id(pack)
	var price := cost(state, pack, branch_id)
	if state.resource(resource) + 0.0001 < float(price):
		return _problem(
			ERROR_INSUFFICIENT,
			"Research '%s' costs %d %s, only %.0f available." % [
				branch_id, price, resource, state.resource(resource),
			],
		)
	state.resources[resource] = state.resource(resource) - float(price)
	state.upgrades[branch_id] = current + 1
	return {
		"ok": true,
		"code": "",
		"rank": current + 1,
		"cost": price,
		"resource_id": resource,
		"effect": str(rules.get("effect", "")),
	}


static func _problem(code: String, details: String) -> Dictionary:
	return {"ok": false, "code": code, "details": details, "rank": 0, "cost": -1}

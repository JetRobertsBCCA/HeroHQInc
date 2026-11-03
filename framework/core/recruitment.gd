class_name Recruitment
extends RefCounted
## Deterministic recruit pool: every slot has a stable, repeatable identity.
##
## A pack declares a pool instead of hundreds of hand-written records:
##   "recruit_pool": {
##     "resource_id": "<id>",
##     "named_count": 200,
##     "base_cost": 60, "cost_growth": 1.03,
##     "given_names": [...], "call_signs": [...],
##     "filler_name_format": "Reserve Operative %d",
##     "tiers": [{"id": "standard", "weight": 65, "cost_multiplier": 1.0,
##                "attribute_base": 4, "attribute_spread": 2}]}
##
## Slot `i` is generated from (game_id, i) alone, so the same recruit looks the
## same after a restart, on another device, or in a test. Only the price depends
## on state: it grows with roster size, so breadth stays a long-term goal rather
## than a first-session giveaway.
##
## Neutral: no title ids. Roles, attributes, names and tiers are all pack data.

const ERROR_UNAVAILABLE := "recruitment_unavailable"
const ERROR_ROSTER_FULL := "roster_full"
const ERROR_INSUFFICIENT := "insufficient_resource"

const DEFAULT_FILLER_FORMAT := "Reserve Operative %d"
const DEFAULT_BASE_COST := 50.0
const DEFAULT_COST_GROWTH := 1.05
const MAX_CANDIDATE_SCAN := 500


static func enabled(pack: GamePack) -> bool:
	return not pool(pack).is_empty()


static func pool(pack: GamePack) -> Dictionary:
	return pack.recruit_pool


static func named_count(pack: GamePack) -> int:
	return maxi(int(pool(pack).get("named_count", 0)), 0)


static func capacity(pack: GamePack) -> int:
	return maxi(pack.roster_capacity, 0)


## Resource the pool is bought with: declared in the pool, else the pack's first.
static func resource_id(pack: GamePack) -> String:
	var declared := str(pool(pack).get("resource_id", ""))
	if not declared.is_empty():
		return declared
	var resources := pack.declared_resources()
	if resources.is_empty():
		return ""
	return str(resources[0])


static func tier_rules(pack: GamePack) -> Array:
	var declared: Variant = pool(pack).get("tiers", [])
	if declared is Array:
		return declared
	return []


## Attribute names are whatever the pack's roles grow, sorted for determinism.
static func attribute_names(pack: GamePack) -> Array:
	var names: Array = []
	var role_ids: Array = pack.roles.keys()
	role_ids.sort()
	for raw_id in role_ids:
		var growth: Variant = pack.role(str(raw_id)).get("growth", {})
		if not (growth is Dictionary):
			continue
		for key in (growth as Dictionary).keys():
			var text := str(key)
			if not names.has(text):
				names.append(text)
	names.sort()
	return names


## The recruit in slot `index`, independent of any save state.
static func candidate(pack: GamePack, index: int) -> Dictionary:
	if not enabled(pack):
		return {}
	var slot := maxi(index, 0)
	var config := pool(pack)
	var rng := _seed(pack.game_id, slot)
	var tiers := tier_rules(pack)
	var tier: Dictionary = {}
	if not tiers.is_empty():
		rng = _next(rng)
		var position := _weighted_index(tiers, rng % 1000)
		if tiers[position] is Dictionary:
			tier = tiers[position]
	var role_ids: Array = pack.roles.keys()
	role_ids.sort()
	var role_id := ""
	if not role_ids.is_empty():
		rng = _next(rng)
		role_id = str(role_ids[rng % role_ids.size()])

	var attributes: Dictionary = {}
	var base := maxi(int(tier.get("attribute_base", 4)), 1)
	var spread := maxi(int(tier.get("attribute_spread", 0)), 0)
	for attribute in attribute_names(pack):
		if spread > 0:
			rng = _next(rng)
			attributes[attribute] = base + (rng % (spread + 1))
		else:
			attributes[attribute] = base

	return {
		"index": slot,
		"id": "op_%04d" % (slot + 1),
		"name": _candidate_name(config, slot),
		"role_id": role_id,
		"tier_id": str(tier.get("id", "")),
		"tier_multiplier": maxf(float(tier.get("cost_multiplier", 1.0)), 0.0),
		"attributes": attributes,
		"rating": int(roundf(AgentRules.rating_value({"attributes": attributes}))),
		"named": slot < named_count(pack),
	}


## Price of slot `index` for the current roster size.
static func cost(state: GameState, pack: GamePack, index: int) -> int:
	var rules := candidate(pack, index)
	if rules.is_empty():
		return -1
	var config := pool(pack)
	var base := maxf(float(config.get("base_cost", DEFAULT_BASE_COST)), 0.0)
	var growth := maxf(float(config.get("cost_growth", DEFAULT_COST_GROWTH)), 1.0)
	# The first recruit costs the base price; growth applies to the roster that
	# is already standing, not to the one being filled.
	var raw := base * pow(growth, float(maxi(state.agents.size() - 1, 0)))
	raw *= maxf(float(rules.get("tier_multiplier", 1.0)), 0.0)
	return maxi(int(ceilf(raw)), 1)


static func next_index(state: GameState) -> int:
	var section: Variant = state.extensions.get("recruitment", {})
	if section is Dictionary:
		return maxi(int((section as Dictionary).get("next_index", 0)), 0)
	return 0


## The slot the next recruit would claim, with its current price.
static func next_candidate(state: GameState, pack: GamePack) -> Dictionary:
	var index := next_index(state)
	var rules := candidate(pack, index)
	if rules.is_empty():
		return {}
	rules["cost"] = cost(state, pack, index)
	return rules


## Spends the pool's resource and adds the next recruit to the roster.
## Returns {ok, code, details, agent_id, name, cost, resource_id, rating, tier_id}.
static func recruit(state: GameState, pack: GamePack) -> Dictionary:
	if not enabled(pack):
		return _problem(ERROR_UNAVAILABLE, "This pack declares no recruit pool.")
	if state.agents.size() >= capacity(pack):
		return _problem(ERROR_ROSTER_FULL, "The roster is full at %d." % capacity(pack))
	var index := next_index(state)
	var rules := candidate(pack, index)
	if rules.is_empty():
		return _problem(ERROR_UNAVAILABLE, "No recruit is available.")
	var price := cost(state, pack, index)
	var resource := resource_id(pack)
	if state.resource(resource) + 0.0001 < float(price):
		return _problem(
			ERROR_INSUFFICIENT,
			"%s costs %d %s, only %.0f available." % [
				str(rules["name"]), price, resource, state.resource(resource),
			],
		)

	# A hand-edited save can already hold the id this slot would claim; skip
	# forward deterministically instead of overwriting an existing agent.
	var scanned := 0
	while state.agents.has(str(rules["id"])) and scanned < MAX_CANDIDATE_SCAN:
		index += 1
		scanned += 1
		rules = candidate(pack, index)
		price = cost(state, pack, index)
	if state.agents.has(str(rules["id"])):
		return _problem(ERROR_ROSTER_FULL, "The roster holds every available recruit.")

	state.resources[resource] = state.resource(resource) - float(price)
	state.agents[str(rules["id"])] = {
		"id": rules["id"],
		"name": rules["name"],
		"name_key": "",
		"role_id": rules["role_id"],
		"tier_id": rules["tier_id"],
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": (rules["attributes"] as Dictionary).duplicate(true),
	}
	var section: Dictionary = state.extensions.get("recruitment", {})
	section["next_index"] = index + 1
	state.extensions["recruitment"] = section
	return {
		"ok": true,
		"code": "",
		"details": "",
		"agent_id": rules["id"],
		"name": rules["name"],
		"cost": price,
		"resource_id": resource,
		"rating": rules["rating"],
		"tier_id": rules["tier_id"],
	}


static func _candidate_name(config: Dictionary, index: int) -> String:
	var named := maxi(int(config.get("named_count", 0)), 0)
	if index < named:
		var given := _strings(config.get("given_names", []))
		var signs := _strings(config.get("call_signs", []))
		if not given.is_empty() and not signs.is_empty():
			var given_index := int(index / signs.size()) % given.size()
			return "%s \"%s\"" % [given[given_index], signs[index % signs.size()]]
		if not given.is_empty():
			return "%s %d" % [given[index % given.size()], int(index / given.size()) + 1]
	var format := str(config.get("filler_name_format", DEFAULT_FILLER_FORMAT))
	return format % (index + 1)


static func _strings(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for entry in value:
			var text := str(entry)
			if not text.is_empty():
				result.append(text)
	return result


static func _weighted_index(tiers: Array, roll: int) -> int:
	var total := 0
	for raw in tiers:
		if raw is Dictionary:
			total += maxi(int((raw as Dictionary).get("weight", 0)), 0)
	if total <= 0:
		return 0
	var target := roll % total
	var running := 0
	for i in tiers.size():
		if not (tiers[i] is Dictionary):
			continue
		running += maxi(int((tiers[i] as Dictionary).get("weight", 0)), 0)
		if target < running:
			return i
	return tiers.size() - 1


## FNV-1a over the pack id and the slot, so a slot is stable across runs.
static func _seed(text: String, index: int) -> int:
	var value := 2166136261
	for i in text.length():
		value = ((value ^ text.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	value = ((value ^ (index & 0xFFFF)) * 16777619) & 0xFFFFFFFF
	return value & 0xFFFFFFFF


static func _next(state: int) -> int:
	var value := state
	value ^= (value << 13) & 0xFFFFFFFF
	value ^= value >> 17
	value ^= (value << 5) & 0xFFFFFFFF
	return value & 0xFFFFFFFF


static func _problem(code: String, details: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"details": details,
		"agent_id": "",
		"name": "",
		"cost": -1,
		"rating": 0,
	}

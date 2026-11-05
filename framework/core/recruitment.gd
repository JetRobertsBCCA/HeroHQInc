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
const ERROR_ROLE_UNAVAILABLE := "role_unavailable"
const ERROR_OFFER_UNAVAILABLE := "offer_unavailable"

## The two visible offers are a player choice, not a paid reroll. They persist
## in `extensions.recruitment` and are replaced only by a hire or a Command
## Level increase (the one free progression event).
const OFFER_COUNT := 2
const SECTION_KEY := "recruitment"
const OFFERS_KEY := "offers"
const OFFER_LEVEL_KEY := "offer_level"

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
	var trait_id := ""
	var trait_ids := pack.trait_ids()
	if not trait_ids.is_empty():
		rng = _next(rng)
		trait_id = str(trait_ids[rng % trait_ids.size()])

	return {
		"index": slot,
		"id": "op_%04d" % (slot + 1),
		"name": _candidate_name(config, slot),
		"role_id": role_id,
		"tier_id": str(tier.get("id", "")),
		"tier_multiplier": maxf(float(tier.get("cost_multiplier", 1.0)), 0.0),
		"attributes": attributes,
		"rating": int(roundf(AgentRules.rating_value({"attributes": attributes}))),
		"trait_id": trait_id,
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
	return next_candidate_for_role(state, pack, "")


## The slot a role-targeted recruit would claim, with its current price.
## Returns {} when no slot of that role exists inside the scan window.
static func next_candidate_for_role(
	state: GameState, pack: GamePack, role_id: String
) -> Dictionary:
	var index := _find_slot(state, pack, role_id, next_index(state))
	if index < 0:
		return {}
	var rules := candidate(pack, index)
	if rules.is_empty():
		return {}
	rules["cost"] = cost(state, pack, index)
	return rules


## Returns the two persistent offers with their live price and roster fit.
## The pair is generated once and reused across every UI refresh and reload.
static func offers(state: GameState, pack: GamePack) -> Array:
	var result: Array = []
	for raw_slot in ensure_offers(state, pack):
		var offer := _offer_view(state, pack, int(raw_slot))
		if not offer.is_empty():
			result.append(offer)
	return result


## Normalizes stored offers for old saves and refreshes them only when the
## roster hires or the player reaches a new Command Level. Returns slot indices.
static func ensure_offers(state: GameState, pack: GamePack) -> Array:
	if not enabled(pack):
		return []
	var section := _section(state)
	var level := CommandProgression.current_level(state, pack)
	var slots := _valid_offer_slots(state, pack, section.get(OFFERS_KEY, []))
	var recorded := int(section.get(OFFER_LEVEL_KEY, -1))
	var changed := false
	if slots.size() != OFFER_COUNT:
		slots = _generate_offer_slots(state, pack, next_index(state))
		section[OFFERS_KEY] = slots
		section[OFFER_LEVEL_KEY] = level
		changed = true
	elif recorded < 0:
		# A partial save or a save from before offers existed: keep the pair
		# and start tracking progression from the current level.
		section[OFFER_LEVEL_KEY] = level
		changed = true
	elif level > recorded:
		# A Command Level gain is the one free progression refresh. The
		# replaced pair is consumed; no resource is paid for it.
		var start := maxi(next_index(state), _after_slots(slots))
		slots = _generate_offer_slots(state, pack, start)
		section["next_index"] = start
		section[OFFERS_KEY] = slots
		section[OFFER_LEVEL_KEY] = level
		changed = true
	elif level < recorded:
		# Rebirth can lower the level while the roster survives. Keep the
		# current pair, then track the next level-up normally.
		section[OFFER_LEVEL_KEY] = level
		changed = true
	if changed:
		state.extensions[SECTION_KEY] = section
	return slots


## Buys one of the two currently visible offers. A stale or invented id is
## refused without spending anything or refreshing the pair.
static func recruit_offer(state: GameState, pack: GamePack, offer_id: String) -> Dictionary:
	if offer_id.is_empty():
		return _problem(ERROR_OFFER_UNAVAILABLE, "No offer was selected.")
	var slot := -1
	for raw_slot in ensure_offers(state, pack):
		var rules := candidate(pack, int(raw_slot))
		if str(rules.get("id", "")) == offer_id:
			slot = int(raw_slot)
			break
	if slot < 0:
		return _problem(ERROR_OFFER_UNAVAILABLE, "That offer is no longer available.")
	var result := _buy_slot(state, pack, slot)
	if bool(result.get("ok", false)):
		_refresh_after_hire(state, pack, slot)
	return result


## Spends the pool's resource and adds the next recruit to the roster.
##
## An empty `role_id` means "any role". Otherwise the pool is scanned forward
## for the next slot of that role, and the slots passed over are skipped: the
## player trades breadth for certainty. Kept for tooling/tests; the screen uses
## `recruit_offer` so a player cannot scan or reroll invisibly.
static func recruit(state: GameState, pack: GamePack, role_id: String = "") -> Dictionary:
	if not enabled(pack):
		return _problem(ERROR_UNAVAILABLE, "This pack declares no recruit pool.")
	if state.agents.size() >= capacity(pack):
		return _problem(ERROR_ROSTER_FULL, "The roster is full at %d." % capacity(pack))
	if not role_id.is_empty() and not pack.roles.has(role_id):
		return _problem(ERROR_ROLE_UNAVAILABLE, "Role '%s' is not part of this pack." % role_id)
	var index := _find_slot(state, pack, role_id, next_index(state))
	if index < 0:
		return _problem(
			ERROR_ROLE_UNAVAILABLE if not role_id.is_empty() else ERROR_UNAVAILABLE,
			"No recruit of role '%s' is available." % role_id,
		)
	var result := _buy_slot(state, pack, index)
	if bool(result.get("ok", false)):
		_refresh_after_hire(state, pack, index)
	return result


static func _buy_slot(state: GameState, pack: GamePack, index: int) -> Dictionary:
	if not enabled(pack):
		return _problem(ERROR_UNAVAILABLE, "This pack declares no recruit pool.")
	if state.agents.size() >= capacity(pack):
		return _problem(ERROR_ROSTER_FULL, "The roster is full at %d." % capacity(pack))
	var rules := candidate(pack, index)
	if rules.is_empty() or state.agents.has(str(rules.get("id", ""))):
		return _problem(ERROR_OFFER_UNAVAILABLE, "That recruit is no longer available.")
	var price := cost(state, pack, index)
	var resource := resource_id(pack)
	if state.resource(resource) + 0.0001 < float(price):
		return _problem(
			ERROR_INSUFFICIENT,
			"%s costs %d %s, only %.0f available." % [
				str(rules["name"]), price, resource, state.resource(resource),
			],
		)
	state.resources[resource] = state.resource(resource) - float(price)
	state.agents[str(rules["id"])] = {
		"id": rules["id"],
		"name": rules["name"],
		"name_key": "",
		"role_id": rules["role_id"],
		"tier_id": rules["tier_id"],
		"trait_id": rules.get("trait_id", ""),
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": (rules["attributes"] as Dictionary).duplicate(true),
	}
	return {
		"ok": true,
		"code": "",
		"details": "",
		"agent_id": rules["id"],
		"offer_id": rules["id"],
		"name": rules["name"],
		"cost": price,
		"resource_id": resource,
		"rating": rules["rating"],
		"tier_id": rules["tier_id"],
		"trait_id": rules.get("trait_id", ""),
	}


static func _refresh_after_hire(state: GameState, pack: GamePack, slot: int) -> void:
	var section := _section(state)
	var start := slot + 1
	section["next_index"] = start
	section[OFFERS_KEY] = _generate_offer_slots(state, pack, start)
	section[OFFER_LEVEL_KEY] = CommandProgression.current_level(state, pack)
	state.extensions[SECTION_KEY] = section


static func _offer_view(state: GameState, pack: GamePack, slot: int) -> Dictionary:
	var rules := candidate(pack, slot)
	if rules.is_empty() or state.agents.has(str(rules.get("id", ""))):
		return {}
	rules = rules.duplicate(true)
	rules["slot"] = slot
	rules["cost"] = cost(state, pack, slot)
	var role_id := str(rules.get("role_id", ""))
	var role_count := _role_count(state, role_id)
	rules["role_count"] = role_count
	rules["new_role"] = role_count == 0
	return rules


static func _valid_offer_slots(
	state: GameState, pack: GamePack, raw_slots: Variant
) -> Array:
	var result: Array = []
	var used: Dictionary = {}
	var roles: Dictionary = {}
	if not (raw_slots is Array):
		return result
	for raw in raw_slots:
		var slot := int(raw)
		if slot < 0 or used.has(slot):
			continue
		var rules := candidate(pack, slot)
		if rules.is_empty() or state.agents.has(str(rules.get("id", ""))):
			continue
		var role_id := str(rules.get("role_id", ""))
		if roles.has(role_id):
			continue
		result.append(slot)
		used[slot] = true
		roles[role_id] = true
		if result.size() >= OFFER_COUNT:
			break
	return result


static func _generate_offer_slots(state: GameState, pack: GamePack, start: int) -> Array:
	var result: Array = []
	if not enabled(pack):
		return result
	var used_slots: Dictionary = {}
	var used_roles: Dictionary = {}
	var first := maxi(start, 0)
	for role_id in _priority_roles(state, pack):
		if result.size() >= OFFER_COUNT:
			break
		_append_offer_slot(
			state, pack, role_id, first, result, used_slots, used_roles
		)
	var role_ids := _sorted_roles(pack)
	for role_id in role_ids:
		if result.size() >= OFFER_COUNT:
			break
		if used_roles.has(role_id):
			continue
		_append_offer_slot(
			state, pack, role_id, first, result, used_slots, used_roles
		)
	# A pack with fewer than two roles cannot have two distinct roles. Fall back
	# to two slots so the screen still has a real choice.
	var scan := first
	var scanned := 0
	while result.size() < OFFER_COUNT and scanned < MAX_CANDIDATE_SCAN:
		var slot := scan
		var rules := candidate(pack, slot)
		if rules.is_empty():
			break
		if not used_slots.has(slot) and not state.agents.has(str(rules.get("id", ""))):
			result.append(slot)
			used_slots[slot] = true
		scan += 1
		scanned += 1
	# A same-price higher rating makes one card obviously worse. Keep the pair's
	# roles, but re-pair the stronger role with a higher-cost slot so the player
	# chooses between immediate quality and a cheaper price instead of a trap.
	if result.size() == OFFER_COUNT:
		_rebalance_tradeoff(state, pack, result, first, used_slots)
	return result


static func _rebalance_tradeoff(
	state: GameState,
	pack: GamePack,
	slots: Array,
	start: int,
	used_slots: Dictionary
) -> void:
	var first := candidate(pack, int(slots[0]))
	var second := candidate(pack, int(slots[1]))
	if first.is_empty() or second.is_empty():
		return
	var first_cost := cost(state, pack, int(slots[0]))
	var second_cost := cost(state, pack, int(slots[1]))
	var first_rating := int(first.get("rating", 0))
	var second_rating := int(second.get("rating", 0))
	var replace := -1
	var other_cost := 0
	var other_rating := 0
	if _headline_dominates(first_cost, first_rating, second_cost, second_rating):
		replace = 0
		other_cost = second_cost
		other_rating = second_rating
	elif _headline_dominates(second_cost, second_rating, first_cost, first_rating):
		replace = 1
		other_cost = first_cost
		other_rating = first_rating
	if replace < 0:
		return
	var chosen: Dictionary = first if replace == 0 else second
	var role_id := str(chosen.get("role_id", ""))
	var alternative := _find_tradeoff_slot(
		state,
		pack,
		role_id,
		start,
		used_slots,
		other_cost,
		other_rating,
	)
	if alternative >= 0:
		slots[replace] = alternative


## The next same-role slot that removes strict price/rating dominance while
## still differing from the other card. Used only when the pair is generated;
## a visible pair never rerolls itself.
static func _find_tradeoff_slot(
	state: GameState,
	pack: GamePack,
	role_id: String,
	start: int,
	used_slots: Dictionary,
	other_cost: int,
	other_rating: int
) -> int:
	var slot := maxi(start, 0)
	var scanned := 0
	while scanned < MAX_CANDIDATE_SCAN:
		var rules := candidate(pack, slot)
		if rules.is_empty():
			return -1
		if not used_slots.has(slot) \
			and not state.agents.has(str(rules.get("id", ""))) \
			and str(rules.get("role_id", "")) == role_id:
			var offer_cost := cost(state, pack, slot)
			var offer_rating := int(rules.get("rating", 0))
			var differs := offer_cost != other_cost or offer_rating != other_rating
			if differs \
				and not _headline_dominates(offer_cost, offer_rating, other_cost, other_rating) \
				and not _headline_dominates(other_cost, other_rating, offer_cost, offer_rating):
				return slot
		slot += 1
		scanned += 1
	return -1


static func _headline_dominates(
	cost_a: int, rating_a: int, cost_b: int, rating_b: int
) -> bool:
	return cost_a <= cost_b and rating_a >= rating_b and (cost_a < cost_b or rating_a > rating_b)


static func _append_offer_slot(
	state: GameState,
	pack: GamePack,
	role_id: String,
	start: int,
	result: Array,
	used_slots: Dictionary,
	used_roles: Dictionary
) -> void:
	if role_id.is_empty() or used_roles.has(role_id) or not pack.roles.has(role_id):
		return
	var slot := _find_role_slot(state, pack, role_id, start, used_slots)
	if slot < 0:
		return
	result.append(slot)
	used_slots[slot] = true
	used_roles[role_id] = true


static func _find_role_slot(
	state: GameState, pack: GamePack, role_id: String, start: int, used_slots: Dictionary
) -> int:
	var scanned := 0
	var slot := maxi(start, 0)
	while scanned < MAX_CANDIDATE_SCAN:
		var rules := candidate(pack, slot)
		if rules.is_empty():
			return -1
		if not used_slots.has(slot) \
			and not state.agents.has(str(rules.get("id", ""))) \
			and str(rules.get("role_id", "")) == role_id:
			return slot
		slot += 1
		scanned += 1
	return -1


static func _priority_roles(state: GameState, pack: GamePack) -> Array:
	var present := _roles_present(state)
	var result: Array = []
	# Critical role gates first: the City Tech/Support gate.
	for raw_level in CommandProgression.levels(pack):
		var level: Dictionary = raw_level
		var requirements: Variant = level.get("requirements", [])
		if not (requirements is Array):
			continue
		for raw_requirement in requirements:
			if not (raw_requirement is Dictionary):
				continue
			var requirement: Dictionary = raw_requirement
			if str(requirement.get("type", "")) != CommandProgression.TYPE_OWN_ROLE_ANY:
				continue
			var role_ids := _strings(requirement.get("role_ids", []))
			if _count_roles(state, role_ids) >= maxi(int(requirement.get("count", 1)), 1):
				continue
			for role_id in role_ids:
				_add_priority_role(result, role_id, pack)
	# Squad gates need their exact roles even when the command gate is satisfied.
	var task_ids: Array = pack.task_ids()
	for task_id in task_ids:
		var task := pack.task(str(task_id))
		if int(task.get("required_agent_count", 1)) <= 1:
			continue
		for raw_role in task.get("required_role_ids", []):
			var role_id := str(raw_role)
			if not present.has(role_id):
				_add_priority_role(result, role_id, pack)
	# Finally fill remaining distinct-role coverage.
	for raw_level in CommandProgression.levels(pack):
		var level: Dictionary = raw_level
		var requirements: Variant = level.get("requirements", [])
		if not (requirements is Array):
			continue
		for raw_requirement in requirements:
			if not (raw_requirement is Dictionary):
				continue
			var requirement: Dictionary = raw_requirement
			if str(requirement.get("type", "")) != CommandProgression.TYPE_OWN_DISTINCT_ROLES:
				continue
			var target := maxi(int(requirement.get("count", 1)), 1)
			if _count_distinct_roles(state) >= target:
				continue
			for role_id in _sorted_roles(pack):
				if not present.has(role_id):
					_add_priority_role(result, role_id, pack)
	return result


static func _add_priority_role(result: Array, role_id: String, pack: GamePack) -> void:
	if role_id.is_empty() or not pack.roles.has(role_id) or result.has(role_id):
		return
	result.append(role_id)


static func _roles_present(state: GameState) -> Dictionary:
	var roles: Dictionary = {}
	for raw in state.agents.values():
		if raw is Dictionary:
			var role_id := str((raw as Dictionary).get("role_id", ""))
			if not role_id.is_empty():
				roles[role_id] = true
	return roles


static func _count_distinct_roles(state: GameState) -> int:
	return _roles_present(state).size()


static func _count_roles(state: GameState, role_ids: Array) -> int:
	var count := 0
	for raw in state.agents.values():
		if raw is Dictionary and role_ids.has(str((raw as Dictionary).get("role_id", ""))):
			count += 1
	return count


static func _role_count(state: GameState, role_id: String) -> int:
	var count := 0
	for raw in state.agents.values():
		if raw is Dictionary and str((raw as Dictionary).get("role_id", "")) == role_id:
			count += 1
	return count


static func _sorted_roles(pack: GamePack) -> Array:
	var roles: Array = pack.roles.keys()
	roles.sort()
	return roles


static func _section(state: GameState) -> Dictionary:
	var raw: Variant = state.extensions.get(SECTION_KEY, {})
	if raw is Dictionary:
		return raw
	return {}


static func _after_slots(slots: Array) -> int:
	var after := 0
	for raw in slots:
		after = maxi(after, int(raw) + 1)
	return after


## First slot at or after `start` whose id is free and whose role matches.
## An empty role matches any slot; -1 means none was found in the scan window.
static func _find_slot(
	state: GameState, pack: GamePack, role_id: String, start: int
) -> int:
	var index := maxi(start, 0)
	var scanned := 0
	while scanned < MAX_CANDIDATE_SCAN:
		var rules := candidate(pack, index)
		if rules.is_empty():
			return -1
		if not state.agents.has(str(rules["id"])):
			if role_id.is_empty() or str(rules.get("role_id", "")) == role_id:
				return index
		index += 1
		scanned += 1
	return -1


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

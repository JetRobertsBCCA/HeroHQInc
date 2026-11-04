class_name AgentRules
extends RefCounted
## Game-neutral agent arithmetic: rating, XP curve and level-ups.
##
## Attribute names come from pack data (one pack calls them power/speed/skill,
## another can call them anything), so nothing here knows what an attribute
## means. Growth per level comes from the agent's role; the XP curve comes from
## the pack's `leveling` block.

## Rating points per attribute point. A fixed engine constant, not title data:
## it keeps ratings human-readable while attributes stay small integers.
const RATING_PER_POINT := 5.0

const DEFAULT_XP_BASE := 100.0
const DEFAULT_XP_PER_LEVEL := 50.0
const DEFAULT_ATTRIBUTE_GAIN := 1

## Guards against a corrupt XP value looping forever.
const MAX_LEVELS_PER_CALL := 500


static func attribute_total(agent: Dictionary) -> float:
	var total := 0.0
	var attributes: Variant = agent.get("attributes", null)
	if attributes is Dictionary:
		for key in (attributes as Dictionary).keys():
			var value := float((attributes as Dictionary)[key])
			if is_finite(value):
				total += value
	return total


static func rating_value(agent: Dictionary) -> float:
	return attribute_total(agent) * RATING_PER_POINT


static func rating(agent: Dictionary) -> int:
	return int(roundf(rating_value(agent)))


## XP needed to go from `level` to `level + 1`.
static func xp_threshold(leveling: Dictionary, level: int) -> float:
	var base := float(leveling.get("xp_base", DEFAULT_XP_BASE))
	var per_level := float(leveling.get("xp_per_level", DEFAULT_XP_PER_LEVEL))
	if not is_finite(base) or base <= 0.0:
		base = DEFAULT_XP_BASE
	if not is_finite(per_level) or per_level < 0.0:
		per_level = DEFAULT_XP_PER_LEVEL
	return maxf(base + per_level * float(maxi(level, 1) - 1), 1.0)


static func is_available(agent: Dictionary) -> bool:
	return str(agent.get("activity", "available")) == "available"


## Rewinds an agent to its level-one shape: base attributes, no XP, available.
##
## Growth is applied linearly per level, so subtracting the same growth per level
## gained restores the exact starting attributes without storing a second copy.
## Used by rebirth, where the roster survives but run progress must not.
static func reset_progress(agent: Dictionary, pack: GamePack) -> void:
	var level := maxi(int(agent.get("level", 1)), 1)
	var gained := level - 1
	var value: Variant = agent.get("attributes", {})
	if gained > 0 and value is Dictionary:
		var attributes: Dictionary = value
		var growth: Dictionary = pack.role(str(agent.get("role_id", ""))).get("growth", {})
		if growth.is_empty():
			var flat := int(pack.leveling.get("attribute_gain_per_level", DEFAULT_ATTRIBUTE_GAIN))
			for key in attributes.keys():
				attributes[key] = int(attributes[key]) - flat * gained
		else:
			for key in growth.keys():
				var key_text := str(key)
				if attributes.has(key_text):
					attributes[key_text] = int(attributes[key_text]) - int(growth[key]) * gained
		agent["attributes"] = attributes
	agent["level"] = 1
	agent["xp"] = 0
	agent["activity"] = "available"


## Adds XP and applies every level-up it unlocks, in order.
## Returns [{type: "level_up", agent_id, level}] so callers can report it.
static func add_xp(state: GameState, pack: GamePack, agent_id: String, amount: float) -> Array:
	var events: Array = []
	if amount <= 0.0 or not state.agents.has(agent_id):
		return events
	var agent: Dictionary = state.agents[agent_id]
	agent["xp"] = float(agent.get("xp", 0)) + amount
	events.append_array(apply_level_ups(state, pack, agent_id))
	return events


## Consumes stored XP for as many levels as it covers. Idempotent when the agent
## is below its threshold, so it is safe to call after every XP award.
static func apply_level_ups(state: GameState, pack: GamePack, agent_id: String) -> Array:
	var events: Array = []
	if not state.agents.has(agent_id):
		return events
	var agent: Dictionary = state.agents[agent_id]
	var level := maxi(int(agent.get("level", 1)), 1)
	var xp := maxf(float(agent.get("xp", 0)), 0.0)
	var applied := 0
	while applied < MAX_LEVELS_PER_CALL and xp >= xp_threshold(pack.leveling, level):
		xp -= xp_threshold(pack.leveling, level)
		level += 1
		applied += 1
		_apply_growth(agent, pack)
		events.append({"type": "level_up", "agent_id": agent_id, "level": level})
	agent["level"] = level
	agent["xp"] = xp
	return events


## Applies one level's attribute growth: the role's declared growth when the
## pack provides it, otherwise a flat gain on every existing attribute.
static func _apply_growth(agent: Dictionary, pack: GamePack) -> void:
	var attributes: Dictionary = {}
	if agent.get("attributes") is Dictionary:
		attributes = agent["attributes"]
	var growth: Dictionary = pack.role(str(agent.get("role_id", ""))).get("growth", {})
	if growth.is_empty():
		var flat := int(pack.leveling.get("attribute_gain_per_level", DEFAULT_ATTRIBUTE_GAIN))
		for key in attributes.keys():
			attributes[key] = int(attributes[key]) + flat
		agent["attributes"] = attributes
		return
	for key in growth.keys():
		var gain := int(growth[key])
		attributes[str(key)] = int(attributes.get(str(key), 0)) + gain
	agent["attributes"] = attributes

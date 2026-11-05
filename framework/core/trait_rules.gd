class_name TraitRules
extends RefCounted
## Game-neutral trait lookup and additive modifier helpers.
##
## A trait is one pack record with a stable id and a list of modifiers. Modifiers
## are additive within their named category, then applied once by the caller.
## Pack filters are optional: a modifier can target solo/squad work, a category,
## a role, one resource, or automatic work. No title ids or values live here.

const TRAINING_XP := "training_xp"
const TASK_REWARD := "task_reward"
const DURATION := "duration"
const RATING := "rating"
const TASK_XP := "task_xp"

const SUPPORTED_TYPES: Array[String] = [
	TRAINING_XP,
	TASK_REWARD,
	DURATION,
	RATING,
	TASK_XP,
]

const FILTER_KEYS: Array[String] = [
	"resource_id",
	"task_kind",
	"category_id",
	"role_id",
]

const MAX_REWARD_MULTIPLIER := 10.0
const MIN_DURATION_MULTIPLIER := 0.1


static func trait_for_agent(pack: GamePack, agent: Dictionary) -> Dictionary:
	if pack == null:
		return {}
	return pack.trait_data(str(agent.get("trait_id", "")))


static func trait_by_id(pack: GamePack, trait_id: String) -> Dictionary:
	if pack == null:
		return {}
	return pack.trait_data(trait_id)


static func display_name(pack: GamePack, agent: Dictionary) -> String:
	var entry := trait_for_agent(pack, agent)
	if entry.is_empty():
		return ""
	return pack.label(str(entry.get("name_key", "")), str(entry.get("id", "")))


static func description(pack: GamePack, agent: Dictionary) -> String:
	var entry := trait_for_agent(pack, agent)
	if entry.is_empty():
		return ""
	return pack.label(str(entry.get("description_key", "")), "")


static func has_trait(pack: GamePack, agent: Dictionary) -> bool:
	return not trait_for_agent(pack, agent).is_empty()


## Sum of every modifier of `type` that matches the supplied context. A missing
## trait or modifier contributes zero, so callers can stay unconditional.
static func modifier_total(
	pack: GamePack, agent: Dictionary, type: String, context: Dictionary = {}
) -> float:
	var entry := trait_for_agent(pack, agent)
	if entry.is_empty():
		return 0.0
	var raw_modifiers: Variant = entry.get("modifiers", [])
	if not (raw_modifiers is Array):
		return 0.0
	var total := 0.0
	for raw in raw_modifiers:
		if not (raw is Dictionary):
			continue
		var modifier: Dictionary = raw
		if str(modifier.get("type", "")) != type:
			continue
		if not _matches(modifier, context):
			continue
		var value := float(modifier.get("value", 0.0))
		if is_finite(value):
			total += value
	return total


static func training_multiplier(pack: GamePack, agent: Dictionary) -> float:
	return maxf(0.0, 1.0 + modifier_total(pack, agent, TRAINING_XP))


static func task_xp_multiplier(
	pack: GamePack, agent: Dictionary, task: Dictionary
) -> float:
	return maxf(0.0, 1.0 + modifier_total(pack, agent, TASK_XP, _task_context(task, agent)))


static func task_reward_multiplier(
	pack: GamePack,
	agents: Array,
	task: Dictionary,
	resource_id: String,
	automatic: bool = false
) -> float:
	var total := 0.0
	for raw in agents:
		if not (raw is Dictionary):
			continue
		var context := _task_context(task, raw, automatic)
		context["resource_id"] = resource_id
		total += modifier_total(pack, raw, TASK_REWARD, context)
	return clampf(1.0 + total, 0.0, MAX_REWARD_MULTIPLIER)


static func duration_seconds(pack: GamePack, task: Dictionary, agents: Array) -> int:
	var base := maxf(float(task.get("base_seconds", 1)), 1.0)
	var total := 0.0
	for raw in agents:
		if raw is Dictionary:
			total += modifier_total(pack, raw, DURATION, _task_context(task, raw))
	var multiplier := maxf(MIN_DURATION_MULTIPLIER, 1.0 + total)
	return maxi(int(roundf(base * multiplier)), 1)


## Rating used for a deployment. The base value comes from AgentRules; trait
## rating modifiers are applied only when their role/category/kind filters match.
static func rating_value(pack: GamePack, agent: Dictionary, task: Dictionary) -> float:
	var base := AgentRules.rating_value(agent)
	var multiplier := maxf(
		0.0, 1.0 + modifier_total(pack, agent, RATING, _task_context(task, agent))
	)
	return base * multiplier


## Fills a missing or stale trait on a saved roster without a schema migration.
## Authored starter records keep their declared trait; other saved agents get a
## stable trait from their id. Returns how many records changed.
static func backfill_agents(state: GameState, pack: GamePack) -> int:
	var ids := pack.trait_ids()
	if ids.is_empty():
		return 0
	var changed := 0
	for raw_id in state.agents.keys():
		var agent_id := str(raw_id)
		var raw_agent: Variant = state.agents[raw_id]
		if not (raw_agent is Dictionary):
			continue
		var agent: Dictionary = raw_agent
		var current := str(agent.get("trait_id", ""))
		if not current.is_empty() and pack.traits.has(current):
			continue
		var starter: Dictionary = pack.starter_agents.get(agent_id, {})
		var declared := str(starter.get("trait_id", ""))
		if not declared.is_empty() and pack.traits.has(declared):
			agent["trait_id"] = declared
		else:
			agent["trait_id"] = str(ids[_stable_hash(agent_id) % ids.size()])
		state.agents[agent_id] = agent
		changed += 1
	return changed


static func _task_context(
	task: Dictionary, agent: Dictionary, automatic: bool = false
) -> Dictionary:
	return {
		"task_kind": str(task.get("kind", "")),
		"category_id": str(task.get("category_id", "")),
		"role_id": str(agent.get("role_id", "")),
		"automatic": automatic,
	}


static func _matches(modifier: Dictionary, context: Dictionary) -> bool:
	for key in FILTER_KEYS:
		if not modifier.has(key):
			continue
		if str(modifier[key]) != str(context.get(key, "")):
			return false
	if modifier.has("automatic"):
		if bool(modifier["automatic"]) != bool(context.get("automatic", false)):
			return false
	return true


## FNV-1a: stable across runs, devices and save reloads.
static func _stable_hash(text: String) -> int:
	var value := 2166136261
	for index in text.length():
		value = ((value ^ text.unicode_at(index)) * 16777619) & 0xFFFFFFFF
	return value & 0xFFFFFFFF

class_name GamePack
extends RefCounted
## A validated content pack loaded from `res://games/<game_id>/`.
##
## Framework code only reads generic fields: ids, numeric tuning, locale keys,
## theme tokens. It never looks up a specific title's ids.

var game_id: String = ""
var content_version: int = 1
var root_path: String = ""
var manifest: Dictionary = {}
var locale: Dictionary = {}
var theme: Dictionary = {}
## id -> role definition
var roles: Dictionary = {}
## id -> task definition
var missions: Dictionary = {}
## id -> starter agent record
var starter_agents: Dictionary = {}
## Declaration document: stages, categories, command levels.
var progression: Dictionary = {}
var starting_resources: Dictionary = {}
var max_offline_seconds: float = 28800.0
var roster_capacity: int = 0
## XP curve: {xp_base, xp_per_level, attribute_gain_per_level}
var leveling: Dictionary = {}
## Paid training: {resource_id, base_cost, cost_growth, xp_per_session}.
## Empty means the pack has no training.
var training: Dictionary = {}
## Rebirth economy: {resource_id, threshold_amount, scale, exponent,
## gain_factor, bonus_per_chip, min_level}. Empty means no rebirth.
var prestige: Dictionary = {}
## Permanent research: {resource_id, branches: [{id, label_key, max_rank,
## base_cost, cost_growth, effect, per_rank}]}. Empty means no research.
var research: Dictionary = {}
## Focus: {max, regen_seconds, pulse_fraction, solo_cap_seconds,
## squad_cap_seconds, pulse_interval_seconds, minimum_remaining_seconds}.
## Empty means the pack does not use Focus.
var focus: Dictionary = {}
## Recruit pool: {resource_id, named_count, base_cost, cost_growth, given_names,
## call_signs, filler_name_format, tiers: [...]}. Empty means no recruitment.
var recruit_pool: Dictionary = {}
## id -> trait definition. Empty means the pack does not use traits.
var traits: Dictionary = {}
## [{id, label_key}] bottom navigation, in display order.
var navigation: Array = []


## Localized text for `key`. Falls back to `fallback`, then to the key itself,
## so a missing translation degrades visibly instead of crashing.
func label(key: String, fallback: String = "") -> String:
	var value: Variant = locale.get(key, null)
	if value is String and not (value as String).is_empty():
		return value
	if not fallback.is_empty():
		return fallback
	return key


func title() -> String:
	return label(str(manifest.get("display_name_key", "game.title")), game_id)


func declared_resources() -> Array:
	var resources: Variant = manifest.get("resources", [])
	if resources is Array:
		return resources
	return []


func stage_ids() -> Array:
	var stages: Variant = progression.get("stages", [])
	var ids: Array = []
	if stages is Array:
		for stage in stages:
			if stage is Dictionary:
				ids.append(str((stage as Dictionary).get("id", "")))
	return ids


func task_ids() -> Array:
	var ids: Array = missions.keys()
	ids.sort()
	return ids


func task(task_id: String) -> Dictionary:
	var value: Variant = missions.get(task_id, null)
	if value is Dictionary:
		return value
	return {}


func role(role_id: String) -> Dictionary:
	var value: Variant = roles.get(role_id, null)
	if value is Dictionary:
		return value
	return {}


func trait_data(trait_id: String) -> Dictionary:
	var value: Variant = traits.get(trait_id, null)
	if value is Dictionary:
		return value
	return {}


func trait_ids() -> Array:
	var ids: Array = traits.keys()
	ids.sort()
	return ids


func stage_label(stage_id: String) -> String:
	return _progression_label("stages", stage_id)


func category_label(category_id: String) -> String:
	return _progression_label("categories", category_id)


## Task names, stage/category labels and agent names all resolve through here.
## Generated agents carry a literal `name` because their identity is data, not
## a locale key; authored agents keep resolving through `name_key`.
func agent_name(agent_id: String, agent: Dictionary) -> String:
	var literal := str(agent.get("name", ""))
	if not literal.is_empty():
		return literal
	return label(str(agent.get("name_key", "")), agent_id)


## "Stage · Category · 0:20 · Rating 60" for a task card subtitle, plus the
## squad size and required roles when the operation declares them.
func task_detail(task_id: String) -> String:
	var task := task(task_id)
	var parts: Array[String] = []
	parts.append(stage_label(str(task.get("stage_id", ""))))
	parts.append(category_label(str(task.get("category_id", ""))))
	parts.append(TextFormat.duration(float(task.get("base_seconds", 0))))
	parts.append("%s %d" % [label("ui.rating", "Rating"), int(task.get("minimum_rating", 0))])
	var squad := maxi(int(task.get("required_agent_count", 1)), 1)
	if squad > 1:
		parts.append("%s %d" % [label("ui.squad", "Squad"), squad])
	var required_roles: Variant = task.get("required_role_ids", [])
	if required_roles is Array and not (required_roles as Array).is_empty():
		var names: Array[String] = []
		for raw_id in required_roles:
			var role_id := str(raw_id)
			names.append(label(str(role(role_id).get("name_key", "")), role_id))
		parts.append("%s %s" % [label("ui.requires", "Needs"), ", ".join(names)])
	return " · ".join(parts)


func _progression_label(section: String, entry_id: String) -> String:
	var entries: Variant = progression.get(section, null)
	if entries is Array:
		for entry in entries:
			if entry is Dictionary and str((entry as Dictionary).get("id", "")) == entry_id:
				return label(str((entry as Dictionary).get("name_key", "")), entry_id)
	return entry_id

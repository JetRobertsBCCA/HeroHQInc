class_name GameState
extends RefCounted
## Game-neutral saved state for exactly one content pack.
##
## Every key here is generic engine vocabulary (agents, squads, resources).
## Title-specific meaning is supplied by the pack; title-specific extra state
## belongs under `extensions` in a namespaced sub-dictionary.

const SAVE_SCHEMA_VERSION := 1

var game_id: String = ""
var save_schema_version: int = SAVE_SCHEMA_VERSION
var pack_content_version: int = 0
## Unix seconds (UTC) of the last settled simulation instant.
var last_settled_utc: int = 0
## resource_id -> numeric amount
var resources: Dictionary = {}
## agent_id -> agent record dictionary
var agents: Dictionary = {}
## squad_id -> squad record dictionary
var squads: Dictionary = {}
## assignment_id -> {task_id, agent_ids, started_utc, ends_utc}
var assignments: Dictionary = {}
## upgrade_id -> purchased rank
var upgrades: Dictionary = {}
var automation_rules: Array = []
## Lifetime totals used by progression requirements:
## {tasks_completed: int, earned: {resource_id: float}}
var stats: Dictionary = {}
## Rebirth state: {chips: int, count: int, run_earnings: float}
var prestige: Dictionary = {}
## module_id -> { ... } state owned by optional game-specific rule modules
var extensions: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"game_id": game_id,
		"save_schema_version": save_schema_version,
		"pack_content_version": pack_content_version,
		"last_settled_utc": last_settled_utc,
		"resources": resources.duplicate(true),
		"agents": agents.duplicate(true),
		"squads": squads.duplicate(true),
		"assignments": assignments.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"automation_rules": automation_rules.duplicate(true),
		"stats": stats.duplicate(true),
		"prestige": prestige.duplicate(true),
		"extensions": extensions.duplicate(true),
	}


static func from_dict(source: Dictionary) -> GameState:
	var state := GameState.new()
	state.game_id = str(source.get("game_id", ""))
	state.save_schema_version = int(source.get("save_schema_version", 0))
	state.pack_content_version = int(source.get("pack_content_version", 0))
	state.last_settled_utc = int(source.get("last_settled_utc", 0))
	state.resources = _as_dictionary(source.get("resources"))
	state.agents = _as_dictionary(source.get("agents"))
	state.squads = _as_dictionary(source.get("squads"))
	state.assignments = _as_dictionary(source.get("assignments"))
	state.upgrades = _as_dictionary(source.get("upgrades"))
	state.automation_rules = _as_array(source.get("automation_rules"))
	state.stats = _as_dictionary(source.get("stats"))
	state.prestige = _as_dictionary(source.get("prestige"))
	state.extensions = _as_dictionary(source.get("extensions"))
	return state


func resource(resource_id: String) -> float:
	return float(resources.get(resource_id, 0))


func tasks_completed() -> int:
	return int(stats.get("tasks_completed", 0))


func prestige_chips() -> int:
	return int(prestige.get("chips", 0))


## Earnings of the current run, in the pack's prestige resource.
func run_earnings() -> float:
	return float(prestige.get("run_earnings", 0.0))


func add_run_earnings(amount: float) -> void:
	if amount <= 0.0:
		return
	prestige["run_earnings"] = run_earnings() + amount


func earned_total(resource_id: String) -> float:
	var earned: Variant = stats.get("earned", {})
	if earned is Dictionary:
		return float((earned as Dictionary).get(resource_id, 0))
	return 0.0


static func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []

class_name Squads
extends RefCounted
## Saved squad presets, one per operation.
##
## A preset is a named list of agent ids kept on `GameState.squads`, which is
## already part of the save schema. It is a preference, not a promise: agents
## can be trained, assigned or removed afterwards, so deployment still runs the
## full `Simulation.evaluate_assignment` check and can refuse for any of the
## usual reasons.

const ERROR_EMPTY := "squad_empty"
const ERROR_UNKNOWN_AGENT := "unknown_agent"
const ERROR_DUPLICATE := "duplicate_agent"


static func preset_id(task_id: String) -> String:
	return "squad_%s" % task_id


static func for_task(state: GameState, task_id: String) -> Dictionary:
	var record: Variant = state.squads.get(preset_id(task_id), null)
	if record is Dictionary:
		return record
	return {}


static func member_ids(state: GameState, task_id: String) -> Array[String]:
	var ids: Array[String] = []
	var record := for_task(state, task_id)
	var stored: Variant = record.get("agent_ids", [])
	if stored is Array:
		for raw_id in stored:
			var agent_id := str(raw_id)
			if state.agents.has(agent_id):
				ids.append(agent_id)
	return ids


## Stores `agent_ids` as the preset for `task_id`. Returns
## {ok, code, details, squad_id, agent_ids}.
static func save(state: GameState, task_id: String, agent_ids: Array) -> Dictionary:
	var unique: Array[String] = []
	for raw_id in agent_ids:
		var agent_id := str(raw_id)
		if agent_id.is_empty():
			return _problem(ERROR_UNKNOWN_AGENT, "An empty agent id cannot be saved.")
		if unique.has(agent_id):
			return _problem(ERROR_DUPLICATE, "Agent '%s' is listed twice." % agent_id)
		if not state.agents.has(agent_id):
			return _problem(ERROR_UNKNOWN_AGENT, "Agent '%s' is not on the roster." % agent_id)
		unique.append(agent_id)
	if unique.is_empty():
		return _problem(ERROR_EMPTY, "A squad needs at least one agent.")
	var id := preset_id(task_id)
	state.squads[id] = {
		"id": id,
		"task_id": task_id,
		"agent_ids": unique,
	}
	return {"ok": true, "code": "", "details": "", "squad_id": id, "agent_ids": unique}


static func clear(state: GameState, task_id: String) -> bool:
	var id := preset_id(task_id)
	if not state.squads.has(id):
		return false
	state.squads.erase(id)
	return true


static func _problem(code: String, details: String) -> Dictionary:
	return {"ok": false, "code": code, "details": details, "squad_id": "", "agent_ids": []}

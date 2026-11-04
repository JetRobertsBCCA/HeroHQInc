class_name AutoRepeat
extends RefCounted
## Persisted "repeat the last operation" automation.
##
## A pack enables this with a research effect (`Research.EFFECT_AUTO_REPEAT`).
## The chosen task and, for a squad operation, the exact lineup are kept in
## `GameState.automation_rules`, so buying the research does not quietly stop
## working after the app is relaunched.
##
## A resume deploys at most one operation and only when nothing is already
## running. A remembered squad is re-evaluated against its saved members, so a
## missing or busy member refuses the re-arm instead of silently auto-picking a
## different squad. Recoverable refusals keep the rule so the player can see the
## current reason and retry after training, recruiting or an operation finishes.

const RULE_TYPE := "repeat_task"
const CODE_IDLE := "idle"
const CODE_LOCKED := "locked"
const CODE_BUSY := "busy"


## The remembered task id, or "" when automation is off.
static func task_id(state: GameState) -> String:
	for raw_rule in state.automation_rules:
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("type", "")) == RULE_TYPE:
			return str((raw_rule as Dictionary).get("task_id", ""))
	return ""


## The remembered squad lineup, in deploy order. Empty for a solo task or a
## legacy rule written before lineups were persisted.
static func lineup(state: GameState) -> Array[String]:
	var ids: Array[String] = []
	for raw_rule in state.automation_rules:
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		if str(rule.get("type", "")) != RULE_TYPE:
			continue
		var stored: Variant = rule.get("agent_ids", [])
		if stored is Array:
			for raw_id in stored:
				ids.append(str(raw_id))
		break
	return ids


## Remembers `task_id` as the operation to repeat. Empty turns automation off.
## `agent_ids` is the exact squad used; leave it empty for a solo task, where
## deployment can safely auto-select the one available agent.
static func remember(state: GameState, task_id: String, agent_ids: Array = []) -> void:
	forget(state)
	if task_id.is_empty():
		return
	var rule := {"type": RULE_TYPE, "task_id": task_id}
	if not agent_ids.is_empty():
		var stored: Array[String] = []
		for raw_id in agent_ids:
			stored.append(str(raw_id))
		rule["agent_ids"] = stored
	state.automation_rules.append(rule)


static func forget(state: GameState) -> void:
	var kept: Array = []
	for raw_rule in state.automation_rules:
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("type", "")) == RULE_TYPE:
			continue
		kept.append(raw_rule)
	state.automation_rules = kept


## Side-effect-free snapshot of the configured rule and whether it can start now.
##
## `code` is "" when ready, `idle` when no rule exists, `locked` when the
## research is missing, `busy` when another operation is running, or one of the
## `Simulation.ERROR_*` eligibility codes. `blocked_slots` gives the exact saved
## slots that are missing or deployed; `missing_role_ids` lists every required
## role the remembered lineup does not cover. The UI localises both. This method
## never deploys and never changes the rule, so its reason is always current.
static func status(state: GameState, pack: GamePack) -> Dictionary:
	var remembered := task_id(state)
	var ids := lineup(state)
	var result := {
		"configured": not remembered.is_empty(),
		"ok": false,
		"code": CODE_IDLE,
		"task_id": remembered,
		"agent_ids": ids,
		"squad": not ids.is_empty(),
		"rating": 0.0,
		"required_rating": 0.0,
		"required_agent_count": 0,
		"given_agent_count": ids.size(),
		"blocked_slots": [],
		"missing_role_ids": [],
		"running_task_ids": [],
	}
	if remembered.is_empty():
		return result
	if not Research.unlocked(state, pack, Research.EFFECT_AUTO_REPEAT):
		result["code"] = CODE_LOCKED
		return result
	if not pack.missions.has(remembered):
		result["code"] = Simulation.ERROR_UNKNOWN_TASK
		return result
	# The rule's own replacement locks its members. That is the automation
	# working, not a paused reason, so report it as waiting before inspecting
	# individual slots. This also catches a manual deployment of the same task.
	if _has_task_running(state, remembered):
		result["code"] = CODE_BUSY
		result["running_task_ids"] = _running_task_ids(state)
		return result

	var evaluation := {}
	if not ids.is_empty():
		evaluation = Simulation.evaluate_assignment(state, pack, remembered, ids)
	else:
		# A solo task has no saved members to check. While another operation is
		# running, auto-selection cannot know who will be free when it ends.
		if not state.assignments.is_empty():
			result["code"] = CODE_BUSY
			result["running_task_ids"] = _running_task_ids(state)
			return result
		evaluation = _evaluate_solo(state, pack, remembered)

	for key in [
		"rating",
		"required_rating",
		"required_agent_count",
		"given_agent_count",
		"agent_id",
		"slot_index",
		"assignment_id",
		"role_id",
		"duplicate",
		"details",
	]:
		if evaluation.has(key):
			result[key] = evaluation[key]
	result["ok"] = bool(evaluation.get("ok", false))
	result["code"] = str(evaluation.get("code", ""))
	result["blocked_slots"] = _blocked_slots(state, ids)
	if not ids.is_empty():
		result["missing_role_ids"] = _missing_roles(state, pack, remembered, ids)

	if bool(result["ok"]):
		if state.assignments.is_empty():
			result["code"] = ""
		else:
			result["ok"] = false
			result["code"] = CODE_BUSY
			result["running_task_ids"] = _running_task_ids(state)
	return result


## Deploys the remembered operation once. Returns the `Simulation.deploy` /
## `Simulation.assign_task` result, or the status snapshot on a refusal.
##
## A locked rule or a task the pack no longer declares is forgotten. Any other
## refusal keeps the rule so the player can recover and retry. A squad always
## uses its exact saved lineup; solo tasks still auto-select one agent.
static func resume(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	var current := status(state, pack)
	if not bool(current.get("configured", false)):
		return current
	var code := str(current.get("code", ""))
	if code == CODE_LOCKED or code == Simulation.ERROR_UNKNOWN_TASK:
		forget(state)
		return current
	if not bool(current.get("ok", false)):
		return current

	var remembered := str(current.get("task_id", ""))
	if not bool(current.get("squad", false)):
		var deployed := Simulation.deploy(state, pack, remembered, utc_now)
		if not bool(deployed.get("ok", false)):
			# Keep the rule: eligibility can change again after training or a
			# roster change, and the player needs to see why it did not start.
			return status(state, pack)
		return deployed
	var lineup_ids: Array = current.get("agent_ids", [])
	return Simulation.assign_task(state, pack, remembered, lineup_ids, utc_now)


## Mirror of `Simulation.deploy` selection without scheduling anything, so the
## status reports the same eligibility result a resume would produce.
static func _evaluate_solo(state: GameState, pack: GamePack, task_id: String) -> Dictionary:
	var required := maxi(int(pack.task(task_id).get("required_agent_count", 1)), 1)
	var selected: Array = Simulation.auto_select_agents(state, pack, task_id)
	if selected.size() >= required:
		return Simulation.evaluate_assignment(state, pack, task_id, selected)
	var relaxed: Array = Simulation.auto_select_agents(state, pack, task_id, true)
	return Simulation.evaluate_assignment(state, pack, task_id, relaxed)


static func _blocked_slots(state: GameState, ids: Array[String]) -> Array:
	var blocked: Array = []
	for index in ids.size():
		var agent_id := str(ids[index])
		var record: Variant = state.agents.get(agent_id, null)
		if not (record is Dictionary):
			blocked.append({
				"index": index,
				"agent_id": agent_id,
				"state": "missing",
			})
			continue
		var agent: Dictionary = record
		if not AgentRules.is_available(agent):
			blocked.append({
				"index": index,
				"agent_id": agent_id,
				"state": "busy",
				"assignment_id": str(agent.get("assignment_id", "")),
			})
	return blocked


static func _missing_roles(
	state: GameState,
	pack: GamePack,
	task_id: String,
	ids: Array[String]
) -> Array[String]:
	var missing: Array[String] = []
	var required: Variant = pack.task(task_id).get("required_role_ids", [])
	if not (required is Array):
		return missing
	for raw_role in required:
		var role_id := str(raw_role)
		var covered := false
		for agent_id in ids:
			var record: Variant = state.agents.get(agent_id, null)
			if record is Dictionary and str((record as Dictionary).get("role_id", "")) == role_id:
				covered = true
				break
		if not covered:
			missing.append(role_id)
	return missing


static func _has_task_running(state: GameState, task_id: String) -> bool:
	for raw_id in state.assignments.keys():
		var assignment: Variant = state.assignments.get(raw_id, null)
		if assignment is Dictionary and str((assignment as Dictionary).get("task_id", "")) == task_id:
			return true
	return false


static func _running_task_ids(state: GameState) -> Array[String]:
	var task_ids: Array[String] = []
	var assignment_ids: Array = state.assignments.keys()
	assignment_ids.sort()
	for raw_id in assignment_ids:
		var assignment: Variant = state.assignments.get(raw_id, null)
		if assignment is Dictionary:
			task_ids.append(str((assignment as Dictionary).get("task_id", "")))
	return task_ids

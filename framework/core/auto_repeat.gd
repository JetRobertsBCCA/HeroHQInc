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
## different squad. The rule is kept on such a refusal: the player may free a
## member later, and nothing has been paid twice.

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


## Deploys the remembered operation once. Returns the `Simulation.deploy` /
## `Simulation.assign_task` result, or {ok: false, code: idle|locked|busy}. A
## locked rule or a task the roster can no longer field is forgotten. A squad
## that is merely unavailable right now keeps its rule and can retry later.
static func resume(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	var remembered := task_id(state)
	if remembered.is_empty():
		return {"ok": false, "code": CODE_IDLE}
	if not Research.unlocked(state, pack, Research.EFFECT_AUTO_REPEAT):
		forget(state)
		return {"ok": false, "code": CODE_LOCKED}
	if not state.assignments.is_empty():
		return {"ok": false, "code": CODE_BUSY}

	var remembered_lineup := lineup(state)
	if not remembered_lineup.is_empty():
		var evaluation := Simulation.evaluate_assignment(
			state, pack, remembered, remembered_lineup
		)
		if not evaluation.get("ok", false):
			return evaluation
		return Simulation.assign_task(state, pack, remembered, remembered_lineup, utc_now)

	var result := Simulation.deploy(state, pack, remembered, utc_now)
	if not result.get("ok", false):
		forget(state)
	return result

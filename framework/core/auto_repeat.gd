class_name AutoRepeat
extends RefCounted
## Persisted "repeat the last operation" automation.
##
## A pack enables this with a research effect (`Research.EFFECT_AUTO_REPEAT`).
## The chosen task is kept in `GameState.automation_rules`, so buying the
## research does not quietly stop working after the app is relaunched.
##
## A resume deploys at most one operation and only when nothing is already
## running. That keeps a relaunch from chaining a whole absence worth of runs:
## each completed operation earns exactly one replacement.

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


## Remembers `task_id` as the operation to repeat. Empty turns automation off.
static func remember(state: GameState, task_id: String) -> void:
	forget(state)
	if task_id.is_empty():
		return
	state.automation_rules.append({"type": RULE_TYPE, "task_id": task_id})


static func forget(state: GameState) -> void:
	var kept: Array = []
	for raw_rule in state.automation_rules:
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("type", "")) == RULE_TYPE:
			continue
		kept.append(raw_rule)
	state.automation_rules = kept


## Deploys the remembered task once. Returns the `Simulation.deploy` result, or
## {ok: false, code: idle|locked|busy}. A locked rule or a task the roster can no
## longer field is forgotten, so it cannot fail silently forever.
static func resume(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	var remembered := task_id(state)
	if remembered.is_empty():
		return {"ok": false, "code": CODE_IDLE}
	if not Research.unlocked(state, pack, Research.EFFECT_AUTO_REPEAT):
		forget(state)
		return {"ok": false, "code": CODE_LOCKED}
	if not state.assignments.is_empty():
		return {"ok": false, "code": CODE_BUSY}
	var result := Simulation.deploy(state, pack, remembered, utc_now)
	if not result.get("ok", false):
		forget(state)
	return result

class_name AutoRepeat
extends RefCounted
## Persisted automation, in two explicit channels.
##
## The original squad rule (`repeat_task`) remembers the last squad operation
## and its exact lineup. The solo channel (`auto_patrol`) remembers one agent and
## one one-agent operation the player chose, and is enabled or paused separately.
## Both live in `GameState.automation_rules`, so they survive a relaunch.
##
## A resume deploys at most one operation and never auto-picks a different
## lineup or pays a completion itself. A remembered squad is re-evaluated
## against its saved members; the patrol is re-evaluated against its saved agent
## and operation. Recoverable refusals keep the selection so the player can see
## the current reason and retry after training, recruiting or work finishes.
##
## The launch path uses `settle_absence` so a patrol can repeat during the away
## window, but only within the pack's offline allowance and through the same
## `Simulation` completion path as online play.

const RULE_TYPE := "repeat_task"
const PATROL_RULE_TYPE := "auto_patrol"
const CODE_IDLE := "idle"
const CODE_LOCKED := "locked"
const CODE_BUSY := "busy"
const CODE_DISABLED := "patrol_disabled"
const CODE_INCOMPLETE := "patrol_incomplete"
const CODE_NOT_SOLO := "patrol_not_solo"
## A guard for a corrupt pack whose task duration is zero and whose offline
## allowance is enormous. Normal settlement never approaches this.
const MAX_SETTLEMENT_CYCLES := 100000


## The remembered task id, or "" when automation is off.
static func task_id(state: GameState) -> String:
	for raw_rule in state.automation_rules:
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		if str(rule.get("type", "")) != RULE_TYPE:
			continue
		var stored: Variant = rule.get("agent_ids", [])
		# Legacy solo repeat rules were implicit. They are migrated to an
		# explicit, disabled patrol rule at boot instead of continuing to fire.
		if stored is Array and not (stored as Array).is_empty():
			return str(rule.get("task_id", ""))
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


## Remembers a squad operation and exact lineup for the legacy auto-repeat
## channel. Empty turns it off. Solo work is configured through
## `configure_patrol` instead, because it must be an explicit player choice.
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


## The one explicit solo patrol rule, if one has been configured.
static func _patrol_rule(state: GameState) -> Dictionary:
	for raw_rule in state.automation_rules:
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("type", "")) == PATROL_RULE_TYPE:
			return raw_rule
	return {}


static func patrol_configured(state: GameState) -> bool:
	return not _patrol_rule(state).is_empty()


static func patrol_task_id(state: GameState) -> String:
	return str(_patrol_rule(state).get("task_id", ""))


static func patrol_agent_id(state: GameState) -> String:
	return str(_patrol_rule(state).get("agent_id", ""))


static func patrol_enabled(state: GameState) -> bool:
	return bool(_patrol_rule(state).get("enabled", false))


## The pack branch that unlocks Auto Patrol, or "" when it does not declare one.
static func patrol_branch_id(pack: GamePack) -> String:
	for raw in Research.branches(pack):
		if raw is Dictionary and str((raw as Dictionary).get("effect", "")) == Research.EFFECT_AUTO_PATROL:
			return str((raw as Dictionary).get("id", ""))
	return ""


## The one-time Auto Patrol research price, or -1 when already unlocked or not
## declared by the pack.
static func patrol_unlock_cost(state: GameState, pack: GamePack) -> int:
	var branch_id := patrol_branch_id(pack)
	if branch_id.is_empty():
		return -1
	return Research.cost(state, pack, branch_id)


## Stores one solo agent/task choice. Partial choices are allowed while the
## player is setting the channel up; the status reports them as incomplete.
## This never enables the channel and never deploys anything.
static func configure_patrol(
	state: GameState,
	pack: GamePack,
	task_id: String,
	agent_id: String
) -> Dictionary:
	var task := pack.task(task_id)
	if not task_id.is_empty():
		if task.is_empty():
			return {"ok": false, "code": Simulation.ERROR_UNKNOWN_TASK}
		if int(task.get("required_agent_count", 1)) != 1:
			return {"ok": false, "code": CODE_NOT_SOLO}
	if not agent_id.is_empty() and not state.agents.has(agent_id):
		return {"ok": false, "code": Simulation.ERROR_UNKNOWN_AGENT}

	for index in state.automation_rules.size():
		var raw: Variant = state.automation_rules[index]
		if not (raw is Dictionary):
			continue
		var rule: Dictionary = raw
		if str(rule.get("type", "")) != PATROL_RULE_TYPE:
			continue
		rule["task_id"] = task_id
		rule["agent_id"] = agent_id
		state.automation_rules[index] = rule
		return {"ok": true, "code": "", "task_id": task_id, "agent_id": agent_id}
	state.automation_rules.append({
		"type": PATROL_RULE_TYPE,
		"task_id": task_id,
		"agent_id": agent_id,
		"enabled": false,
	})
	return {"ok": true, "code": "", "task_id": task_id, "agent_id": agent_id}


static func set_patrol_enabled(state: GameState, enabled: bool) -> bool:
	for index in state.automation_rules.size():
		var raw: Variant = state.automation_rules[index]
		if not (raw is Dictionary):
			continue
		var rule: Dictionary = raw
		if str(rule.get("type", "")) != PATROL_RULE_TYPE:
			continue
		rule["enabled"] = enabled
		state.automation_rules[index] = rule
		return true
	return false


static func forget_patrol(state: GameState) -> void:
	var kept: Array = []
	for raw_rule in state.automation_rules:
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("type", "")) == PATROL_RULE_TYPE:
			continue
		kept.append(raw_rule)
	state.automation_rules = kept


## A pre-Auto-Patrol save could contain an implicit solo repeat rule. Keep its
## operation as a draft but turn it into an explicit, disabled patrol so it can
## never fire without the player choosing an agent and enabling it.
static func migrate_legacy_solo(state: GameState) -> bool:
	var legacy_task := ""
	var kept: Array = []
	var changed := false
	for raw_rule in state.automation_rules:
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("type", "")) == RULE_TYPE:
			var stored: Variant = (raw_rule as Dictionary).get("agent_ids", [])
			if not (stored is Array) or (stored as Array).is_empty():
				if legacy_task.is_empty():
					legacy_task = str((raw_rule as Dictionary).get("task_id", ""))
				changed = true
				continue
		kept.append(raw_rule)
	if changed:
		state.automation_rules = kept
	if not legacy_task.is_empty() and not patrol_configured(state):
		state.automation_rules.append({
			"type": PATROL_RULE_TYPE,
			"task_id": legacy_task,
			"agent_id": "",
			"enabled": false,
		})
	return changed


## Side-effect-free snapshot of the explicit solo channel. Unlike the squad
## rule, an idle chosen agent can start even while other agents are deployed.
static func patrol_status(state: GameState, pack: GamePack) -> Dictionary:
	var result := {
		"configured": false,
		"enabled": false,
		"ok": false,
		"running": false,
		"code": CODE_IDLE,
		"task_id": "",
		"agent_id": "",
		"assignment_id": "",
		"blocking_task_id": "",
		"rating": 0.0,
		"required_rating": 0.0,
		"required_agent_count": 0,
		"given_agent_count": 0,
		"unlock_branch_id": patrol_branch_id(pack),
		"unlock_cost": patrol_unlock_cost(state, pack),
		"unlock_resource_id": Research.resource_id(pack),
	}
	if not Research.unlocked(state, pack, Research.EFFECT_AUTO_PATROL):
		result["code"] = CODE_LOCKED
		return result
	var rule := _patrol_rule(state)
	if rule.is_empty():
		return result
	var task_id := str(rule.get("task_id", ""))
	var agent_id := str(rule.get("agent_id", ""))
	result["configured"] = true
	result["enabled"] = bool(rule.get("enabled", false))
	result["task_id"] = task_id
	result["agent_id"] = agent_id
	if not bool(result["enabled"]):
		result["code"] = CODE_DISABLED
		return result
	if task_id.is_empty() or agent_id.is_empty():
		result["code"] = CODE_INCOMPLETE
		return result

	var task := pack.task(task_id)
	if task.is_empty():
		result["code"] = Simulation.ERROR_UNKNOWN_TASK
		return result
	if int(task.get("required_agent_count", 1)) != 1:
		result["code"] = CODE_NOT_SOLO
		return result

	var agent_value: Variant = state.agents.get(agent_id, null)
	if agent_value is Dictionary:
		var agent: Dictionary = agent_value
		var assignment_id := str(agent.get("assignment_id", ""))
		var assignment_value: Variant = state.assignments.get(assignment_id, null)
		if assignment_value is Dictionary:
			var assignment: Dictionary = assignment_value
			var ids: Array = assignment.get("agent_ids", [])
			if str(assignment.get("task_id", "")) == task_id \
				and ids.size() == 1 and str(ids[0]) == agent_id:
				result["running"] = true
				result["code"] = CODE_BUSY
				result["assignment_id"] = assignment_id
				result["rating"] = AgentRules.rating_value(agent)
				result["required_rating"] = float(task.get("minimum_rating", 0))
				return result

	var evaluation := Simulation.evaluate_assignment(state, pack, task_id, [agent_id])
	for key in [
		"rating",
		"required_rating",
		"required_agent_count",
		"given_agent_count",
		"slot_index",
		"assignment_id",
		"role_id",
		"duplicate",
		"details",
		"stage_id",
		"required_command_level",
		"current_command_level",
	]:
		if evaluation.has(key):
			result[key] = evaluation[key]
	result["ok"] = bool(evaluation.get("ok", false))
	result["code"] = str(evaluation.get("code", ""))
	if bool(result["ok"]):
		result["code"] = ""
	elif str(result["code"]) == Simulation.ERROR_AGENT_BUSY:
		var assignment_id := str(result.get("assignment_id", ""))
		var assignment: Variant = state.assignments.get(assignment_id, null)
		if assignment is Dictionary:
			result["blocking_task_id"] = str((assignment as Dictionary).get("task_id", ""))
	return result


## Solo operations the chosen agent could take once free. Availability is
## intentionally ignored so a paused player can still change the target while
## the agent is deployed; rating, role, slot and Command gates still apply.
static func eligible_solo_task_ids(
	state: GameState, pack: GamePack, agent_id: String
) -> Array[String]:
	var result: Array[String] = []
	var record_value: Variant = state.agents.get(agent_id, null)
	if not (record_value is Dictionary):
		return result
	var record: Dictionary = record_value
	var saved_assignment := str(record.get("assignment_id", ""))
	var saved_activity := str(record.get("activity", "available"))
	record["assignment_id"] = ""
	record["activity"] = "available"
	var ids: Array = pack.task_ids()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var first := pack.task(str(a))
		var second := pack.task(str(b))
		var rating_a := int(first.get("minimum_rating", 0))
		var rating_b := int(second.get("minimum_rating", 0))
		if rating_a != rating_b:
			return rating_a < rating_b
		return str(a) < str(b)
	)
	for raw_id in ids:
		var task_id := str(raw_id)
		if int(pack.task(task_id).get("required_agent_count", 1)) != 1:
			continue
		var evaluation := Simulation.evaluate_assignment(state, pack, task_id, [agent_id])
		if bool(evaluation.get("ok", false)):
			result.append(task_id)
	record["assignment_id"] = saved_assignment
	record["activity"] = saved_activity
	return result


## Starts at most one patrol for the chosen agent. Refusals keep the selection
## and enabled state so the card can show the current recovery reason.
static func resume_patrol(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	var current := patrol_status(state, pack)
	if not bool(current.get("configured", false)):
		return current
	if not bool(current.get("enabled", false)):
		return current
	if not bool(current.get("ok", false)):
		return current
	var deployed := Simulation.assign_task(
		state, pack, str(current["task_id"]), [str(current["agent_id"])], utc_now
	)
	if not bool(deployed.get("ok", false)):
		return patrol_status(state, pack)
	return deployed


## Launch settlement: settle existing work exactly as Simulation would, but
## re-arm the chosen patrol during the away window. Only the pack's capped
## offline allowance is simulated, so an eight-hour return cannot earn days.
## Every payout still comes from Simulation._complete_assignment, so a job is
## never paid by both the absence pass and the first live tick.
static func settle_absence(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	var requested := maxf(float(utc_now - state.last_settled_utc), 0.0)
	var cap := maxf(pack.max_offline_seconds, 0.0)
	var applied := minf(requested, cap)
	var target := state.last_settled_utc + int(applied)
	var events: Array = []
	var patrol_starts := 0
	var steps := 0
	while state.last_settled_utc < target and steps < MAX_SETTLEMENT_CYCLES:
		steps += 1
		if patrol_enabled(state):
			var patrol := resume_patrol(state, pack, state.last_settled_utc)
			if bool(patrol.get("ok", false)):
				patrol_starts += 1
		var next_end := _next_end(state)
		var step_to := target
		if next_end >= 0 and next_end < target:
			step_to = next_end
		if step_to <= state.last_settled_utc:
			var due := Simulation.simulate_delta(state, 0.0, pack)
			events.append_array(due.get("events", []))
			if (due.get("events", []) as Array).is_empty():
				break
			continue
		var outcome := Simulation.simulate_delta(
			state, float(step_to - state.last_settled_utc), pack
		)
		events.append_array(outcome.get("events", []))
	# Due assignments at the exact target boundary settle once even when no
	# further time remains; no new patrol is started by this call.
	var tail := Simulation.simulate_delta(state, 0.0, pack)
	events.append_array(tail.get("events", []))
	var capped := requested > applied
	if capped:
		# A return after longer than the allowance is fully settled at launch.
		# Advancing the stamp to now prevents the next tick or relaunch from
		# claiming another capped window and paying the same kind of cycle again.
		state.last_settled_utc = utc_now
		var at_launch := Simulation.simulate_delta(state, 0.0, pack)
		events.append_array(at_launch.get("events", []))
	return {
		"state": state,
		"events": events,
		"requested_seconds": requested,
		"applied_seconds": applied,
		"capped": capped,
		"patrol_starts": patrol_starts,
		"steps": steps,
	}


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
		"stage_id",
		"required_command_level",
		"current_command_level",
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
static func _next_end(state: GameState) -> int:
	var next := -1
	for raw in state.assignments.values():
		if not (raw is Dictionary):
			continue
		var end := int((raw as Dictionary).get("ends_utc", 0))
		if next < 0 or end < next:
			next = end
	return next


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

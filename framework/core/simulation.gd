class_name Simulation
extends RefCounted
## Deterministic, game-neutral simulation.
##
## `simulate_delta` settles elapsed time identically online (one call per tick)
## and after an absence (one call at launch), so there is exactly one completion
## rule. Every number it uses — task duration, rewards, rating gate, XP curve,
## training cost — comes from the pack.
##
## Nothing in this file may import a content pack, reference a title-specific
## identifier, or touch platform SDKs.

const ERROR_UNKNOWN_TASK := "unknown_task"
const ERROR_STAGE_LOCKED := "stage_locked"
const ERROR_AGENT_COUNT := "agent_count"
const ERROR_UNKNOWN_AGENT := "unknown_agent"
const ERROR_AGENT_BUSY := "agent_busy"
const ERROR_MISSING_ROLE := "missing_role"
const ERROR_RATING_TOO_LOW := "rating_too_low"
const ERROR_INSUFFICIENT_RESOURCE := "insufficient_resource"
const ERROR_TRAINING_UNAVAILABLE := "training_unavailable"


## Builds a fresh state for a pack. Deterministic for a given
## (pack, seed, utc) triple: no clock reads, no randomness.
static func new_state(pack: GamePack, seed_value: int, utc_now: int) -> GameState:
	var state := GameState.new()
	state.game_id = pack.game_id
	state.pack_content_version = pack.content_version
	state.last_settled_utc = utc_now
	state.resources = pack.starting_resources.duplicate(true)
	state.stats = {"tasks_completed": 0, "earned": {}}
	state.prestige = {"chips": 0, "count": 0, "run_earnings": 0.0}
	seed_missing_starter_agents(state, pack)
	state.extensions["simulation"] = {"seed": seed_value, "assignment_seq": 0}
	return state


## Seeds any starter agent a save is missing and returns how many were added.
##
## A save written by an older or incomplete content build can restore with an
## empty roster, which would leave the player unable to start a single task.
## Reseeding from pack data makes that recoverable, and is idempotent once the
## roster is complete.
static func seed_missing_starter_agents(state: GameState, pack: GamePack) -> int:
	var added := 0
	for agent_id in pack.starter_agents.keys():
		var key := str(agent_id)
		if state.agents.has(key):
			continue
		var record: Variant = pack.starter_agents[agent_id]
		if record is Dictionary:
			state.agents[key] = (record as Dictionary).duplicate(true)
			added += 1
	return added


## Advances `state` by `elapsed_seconds` and returns
## {state, events, requested_seconds, applied_seconds, capped}.
##
## Elapsed time is clamped to `[0, pack.max_offline_seconds]` so a clock that
## jumps backwards cannot subtract progress and a long absence cannot pay out
## more than the pack's offline allowance. Completions are settled in
## (end time, assignment id) order so replays produce identical events.
static func simulate_delta(state: GameState, elapsed_seconds: float, pack: GamePack) -> Dictionary:
	var requested := elapsed_seconds
	if is_nan(requested) or is_inf(requested):
		requested = 0.0
	requested = maxf(requested, 0.0)
	var cap := maxf(pack.max_offline_seconds, 0.0)
	var applied := requested
	var capped := false
	if applied > cap:
		applied = cap
		capped = true
	state.last_settled_utc += int(applied)

	var due: Array = []
	for assignment_id in state.assignments.keys():
		var assignment: Variant = state.assignments[assignment_id]
		if assignment is Dictionary:
			due.append({
				"id": str(assignment_id),
				"ends_utc": int((assignment as Dictionary).get("ends_utc", 0)),
			})
	due.sort_custom(_compare_due)

	var events: Array = []
	for entry in due:
		if int(entry["ends_utc"]) > state.last_settled_utc:
			continue
		events.append_array(_complete_assignment(state, pack, str(entry["id"]), int(entry["ends_utc"])))
	return {
		"state": state,
		"events": events,
		"requested_seconds": requested,
		"applied_seconds": applied,
		"capped": capped,
	}


## Checks whether `agent_ids` may start `task_id` right now.
## Returns {ok, code, details, rating, required_rating}.
static func evaluate_assignment(
	state: GameState,
	pack: GamePack,
	task_id: String,
	agent_ids: Array
) -> Dictionary:
	if not pack.missions.has(task_id):
		return _problem(ERROR_UNKNOWN_TASK, "Task '%s' is not part of this pack." % task_id)
	var task: Dictionary = pack.missions[task_id]
	var stage_id := str(task.get("stage_id", ""))
	var stage_details := CommandProgression.stage_lock_details(state, pack, stage_id)
	if bool(stage_details.get("locked", false)):
		return {
			"ok": false,
			"code": ERROR_STAGE_LOCKED,
			"details": "Stage '%s' requires Command Level %d; current level is %d." % [
				stage_id,
				int(stage_details.get("required_command_level", 1)),
				int(stage_details.get("current_command_level", 1)),
			],
			"rating": 0.0,
			"required_rating": 0.0,
			"stage_id": stage_id,
			"required_command_level": int(stage_details.get("required_command_level", 1)),
			"current_command_level": int(stage_details.get("current_command_level", 1)),
		}
	var required_count := maxi(int(task.get("required_agent_count", 1)), 1)
	if agent_ids.size() != required_count:
		return _problem(
			ERROR_AGENT_COUNT,
			"Task '%s' needs %d agent(s), %d given." % [task_id, required_count, agent_ids.size()],
			{"required_agent_count": required_count, "given_agent_count": agent_ids.size()},
		)
	var seen: Dictionary = {}
	var assigned_roles: Dictionary = {}
	var rating_total := 0.0
	for index in agent_ids.size():
		var agent_id := str(agent_ids[index])
		if seen.has(agent_id):
			return _problem(
				ERROR_UNKNOWN_AGENT,
				"Agent '%s' was listed twice." % agent_id,
				{"agent_id": agent_id, "slot_index": index, "duplicate": true},
			)
		seen[agent_id] = true
		if not state.agents.has(agent_id):
			return _problem(
				ERROR_UNKNOWN_AGENT,
				"Agent '%s' is not in this save." % agent_id,
				{"agent_id": agent_id, "slot_index": index},
			)
		var agent: Dictionary = state.agents[agent_id]
		if not AgentRules.is_available(agent):
			return _problem(
				ERROR_AGENT_BUSY,
				"Agent '%s' is already assigned." % agent_id,
				{
					"agent_id": agent_id,
					"slot_index": index,
					"assignment_id": str(agent.get("assignment_id", "")),
				},
			)
		assigned_roles[str(agent.get("role_id", ""))] = true
		rating_total += TraitRules.rating_value(pack, agent, task)

	var required_roles: Variant = task.get("required_role_ids", [])
	if required_roles is Array:
		for role_id in required_roles:
			if not assigned_roles.has(str(role_id)):
				return _problem(
					ERROR_MISSING_ROLE,
					"Task '%s' requires role '%s'." % [task_id, str(role_id)],
					{"role_id": str(role_id)},
				)

	var required_rating := float(task.get("minimum_rating", 0))
	var rating := rating_total / float(maxi(agent_ids.size(), 1))
	if rating + 0.0001 < required_rating:
		return {
			"ok": false,
			"code": ERROR_RATING_TOO_LOW,
			"details": "Rating %.1f is below the required %.1f." % [rating, required_rating],
			"rating": rating,
			"required_rating": required_rating,
		}
	return {
		"ok": true,
		"code": "",
		"details": "",
		"rating": rating,
		"required_rating": required_rating,
	}


## Schedules `task_id` on `agent_ids`. Returns
## {ok, code, details, assignment_id, ends_utc}.
static func assign_task(
	state: GameState,
	pack: GamePack,
	task_id: String,
	agent_ids: Array,
	utc_now: int,
	automatic: bool = false
) -> Dictionary:
	var evaluation := evaluate_assignment(state, pack, task_id, agent_ids)
	if not evaluation.get("ok", false):
		return evaluation
	var task: Dictionary = pack.missions[task_id]
	var simulation_state: Dictionary = state.extensions.get("simulation", {})
	var sequence := int(simulation_state.get("assignment_seq", 0)) + 1
	simulation_state["assignment_seq"] = sequence
	state.extensions["simulation"] = simulation_state

	var assignment_id := "task_%d" % sequence
	var assigned_agents: Array = []
	for raw_id in agent_ids:
		var assigned_id := str(raw_id)
		if state.agents.has(assigned_id):
			assigned_agents.append(state.agents[assigned_id])
	var duration := TraitRules.duration_seconds(pack, task, assigned_agents)
	var ends_utc := int(utc_now) + duration
	var assignment := {
		"id": assignment_id,
		"task_id": task_id,
		"agent_ids": agent_ids.duplicate(),
		"started_utc": int(utc_now),
		"ends_utc": ends_utc,
		"automatic": automatic,
	}
	state.assignments[assignment_id] = assignment
	for raw_id in agent_ids:
		var agent: Dictionary = state.agents[str(raw_id)]
		agent["activity"] = "assigned"
		agent["assignment_id"] = assignment_id
	return {
		"ok": true,
		"code": "",
		"details": "",
		"assignment_id": assignment_id,
		"ends_utc": ends_utc,
		"automatic": automatic,
	}


## Picks the strongest available set for `task_id`: required roles first, then
## highest trait-adjusted rating for that operation, then id. Returns [] when
## no legal set exists.
static func auto_select_agents(
	state: GameState,
	pack: GamePack,
	task_id: String,
	ignore_rating: bool = false
) -> Array:
	var selected: Array = []
	if not pack.missions.has(task_id):
		return selected
	var task: Dictionary = pack.missions[task_id]
	var required_count := maxi(int(task.get("required_agent_count", 1)), 1)
	var candidates: Array = []
	var agent_ids: Array = state.agents.keys()
	agent_ids.sort()
	for raw_id in agent_ids:
		var agent: Dictionary = state.agents[raw_id]
		if not AgentRules.is_available(agent):
			continue
		candidates.append({
			"id": str(raw_id),
			"rating": TraitRules.rating_value(pack, agent, task),
			"role_id": str(agent.get("role_id", "")),
		})
	candidates.sort_custom(_compare_candidates)

	var required_roles: Variant = task.get("required_role_ids", [])
	if required_roles is Array:
		for role_id in required_roles:
			for candidate in candidates:
				if selected.has(candidate["id"]) or str(candidate["role_id"]) != str(role_id):
					continue
				selected.append(candidate["id"])
				break
	for candidate in candidates:
		if selected.size() >= required_count:
			break
		if not selected.has(candidate["id"]):
			selected.append(candidate["id"])
	if selected.size() < required_count:
		return [] if not ignore_rating else selected
	if ignore_rating:
		return selected
	return selected if evaluate_assignment(state, pack, task_id, selected).get("ok", false) else []


## One-call deployment used by the UI: chooses agents, then schedules.
static func deploy(
	state: GameState,
	pack: GamePack,
	task_id: String,
	utc_now: int,
	automatic: bool = false
) -> Dictionary:
	var agents := auto_select_agents(state, pack, task_id)
	if (agents as Array).size() >= maxi(int(pack.task(task_id).get("required_agent_count", 1)), 1):
		return assign_task(state, pack, task_id, agents, utc_now, automatic)
	var relaxed := auto_select_agents(state, pack, task_id, true)
	return evaluate_assignment(state, pack, task_id, relaxed)


## Cost of the next training session for an agent, or -1 when the pack has no
## training rules.
static func training_cost(state: GameState, pack: GamePack, agent_id: String) -> int:
	if pack.training.is_empty():
		return -1
	var agent: Dictionary = state.agents.get(agent_id, {})
	var level := maxi(int(agent.get("level", 1)), 1)
	var base := maxf(float(pack.training.get("base_cost", 0.0)), 0.0)
	var growth := maxf(float(pack.training.get("cost_growth", 1.0)), 1.0)
	var raw := base * pow(growth, float(level - 1))
	return maxi(int(ceilf(raw * Research.training_multiplier(state, pack))), 1)


## Spends the pack's training resource to grant XP, applying level-ups.
## Returns {ok, code, details, cost, resource_id, level_before, level_after, events}.
static func train_agent(state: GameState, pack: GamePack, agent_id: String) -> Dictionary:
	if pack.training.is_empty():
		return _problem(ERROR_TRAINING_UNAVAILABLE, "This pack declares no training rules.")
	if not state.agents.has(agent_id):
		return _problem(ERROR_UNKNOWN_AGENT, "Agent '%s' is not in this save." % agent_id)
	var resource_id := str(pack.training.get("resource_id", ""))
	var cost := training_cost(state, pack, agent_id)
	if state.resource(resource_id) + 0.0001 < float(cost):
		return _problem(
			ERROR_INSUFFICIENT_RESOURCE,
			"Training costs %d %s, only %.0f available." % [cost, resource_id, state.resource(resource_id)],
		)
	var agent: Dictionary = state.agents[agent_id]
	var level_before := int(agent.get("level", 1))
	state.resources[resource_id] = state.resource(resource_id) - float(cost)
	var events := AgentRules.add_xp(
		state,
		pack,
		agent_id,
		float(pack.training.get("xp_per_session", 0)) \
			* TraitRules.training_multiplier(pack, agent)
	)
	return {
		"ok": true,
		"code": "",
		"details": "",
		"cost": cost,
		"resource_id": resource_id,
		"level_before": level_before,
		"level_after": int(state.agents[agent_id].get("level", level_before)),
		"events": events,
	}


## Pays out one finished assignment: rewards, lifetime totals, agent XP,
## level-ups, and freed agents. Ordered so task XP lands before level events.
static func _complete_assignment(
	state: GameState,
	pack: GamePack,
	assignment_id: String,
	ends_utc: int
) -> Array:
	var events: Array = []
	var assignment_value: Variant = state.assignments.get(assignment_id, null)
	if not (assignment_value is Dictionary):
		return events
	var assignment: Dictionary = assignment_value
	var task_id := str(assignment.get("task_id", ""))
	var task: Dictionary = pack.task(task_id)
	var rewards := {}
	var automatic := bool(assignment.get("automatic", false))
	var agent_ids: Array = assignment.get("agent_ids", [])
	var assigned_agents: Array = []
	for raw_id in agent_ids:
		var assigned_id := str(raw_id)
		if state.agents.has(assigned_id):
			assigned_agents.append(state.agents[assigned_id])

	# Permanent multipliers stack: rebirth chips, then research ranks.
	var payout := Prestige.multiplier(state, pack) * Research.reward_multiplier(state, pack)
	var run_resource := Prestige.resource_id(pack)
	var declared: Variant = task.get("rewards", null)
	if declared is Dictionary:
		for raw_id in (declared as Dictionary).keys():
			var resource_id := str(raw_id)
			var amount := float((declared as Dictionary)[raw_id]) * payout \
				* TraitRules.task_reward_multiplier(
					pack, assigned_agents, task, resource_id, automatic
				)
			if not is_finite(amount):
				continue
			rewards[resource_id] = amount
			state.resources[resource_id] = state.resource(resource_id) + amount
			var earned: Dictionary = state.stats.get("earned", {})
			earned[resource_id] = float(earned.get(resource_id, 0.0)) + amount
			state.stats["earned"] = earned
			if resource_id == run_resource:
				state.add_run_earnings(amount)

	for raw_id in agent_ids:
		var agent_id := str(raw_id)
		if not state.agents.has(agent_id):
			continue
		var agent: Dictionary = state.agents[agent_id]
		agent["activity"] = "available"
		agent.erase("assignment_id")
		var task_xp := float(task.get("xp", 0)) \
			* TraitRules.task_xp_multiplier(pack, agent, task)
		events.append_array(AgentRules.add_xp(state, pack, agent_id, task_xp))

	state.assignments.erase(assignment_id)
	state.stats["tasks_completed"] = state.tasks_completed() + 1
	if str(task.get("kind", "")) == "squad":
		state.stats["squad_tasks_completed"] = state.squad_tasks_completed() + 1
	events.push_front({
		"type": "task_completed",
		"assignment_id": assignment_id,
		"task_id": task_id,
		"agent_ids": agent_ids.duplicate(),
		"rewards": rewards,
		"ends_utc": ends_utc,
		"automatic": automatic,
	})
	return events


static func _compare_due(a: Dictionary, b: Dictionary) -> bool:
	if int(a["ends_utc"]) != int(b["ends_utc"]):
		return int(a["ends_utc"]) < int(b["ends_utc"])
	return str(a["id"]) < str(b["id"])


static func _compare_candidates(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["rating"]), float(b["rating"])):
		return float(a["rating"]) > float(b["rating"])
	return str(a["id"]) < str(b["id"])


static func _problem(code: String, details: String, extra: Dictionary = {}) -> Dictionary:
	var problem := {
		"ok": false,
		"code": code,
		"details": details,
		"rating": 0.0,
		"required_rating": 0.0,
		"required_agent_count": 0,
		"given_agent_count": 0,
	}
	problem.merge(extra, true)
	return problem

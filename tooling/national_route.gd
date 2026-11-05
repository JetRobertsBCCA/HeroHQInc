extends SceneTree
## No-grant route model: fresh save -> City entry -> National Response unlock.
##
## The model uses only the real Simulation, Recruitment and AgentRules APIs. It
## never grants resources, skips a rating gate or edits saved totals. Its policy
## is deliberately ordinary rather than optimal:
##   - a recruit is hired when affordable, targeting a missing fourth role at
##     City level;
##   - the starter is trained to level 2 for the Street role gate;
##   - at City, the cheapest legal squad pair is trained until Joint Raid opens;
##   - otherwise every idle agent takes its best-paying legal City or Street job;
##   - the first affordable Auto Patrol is bought with earned Intel, keeping the
##     squad pair out of the solo channel and waiting on a non-squad hero if
##     necessary.
##
## It reports dispatch count, elapsed time, the longest completion gap and the
## most-repeated operation so a requirement cannot hide a deadlock or a dull
## loop. Exits non-zero if the route cannot reach either milestone.
##
## Run: godot --headless --path . -s res://tooling/national_route.gd

const PACK_ID := "hero_hq"
const MAX_STEPS := 20000
const CITY_STAGE := "city"
const NATIONAL_STAGE := "national"
const SQUAD_TASK := "s_raid"

var _pack: GamePack
var _state: GameState
var _t := 0
var _dispatches := 0
var _dispatches_at_city := 0
var _city_entry_t := -1
var _national_t := -1
var _national_tasks := 0
var _national_lifetime := 0.0
var _national_intel := 0.0
var _national_agents := 0
var _national_roles := 0
var _national_squads := 0
var _national_research := 0
var _last_completion_t := 0
var _max_completion_gap := 0
var _max_gap_at := ""
var _counts: Dictionary = {}
var _city_counts: Dictionary = {}
var _first_clear: Dictionary = {}
var _deadlock_reason := ""
var _patrol_cost := -1
var _patrol_first_t := -1
var _patrol_first_dispatches := 0
var _patrol_first_tasks := 0
var _patrol_first_intel := 0.0
var _patrol_agent := ""
var _patrol_task := ""
var _first_intel_t := -1
var _first_intel_task := ""
var _first_intel_amount := 0.0
var _first_intel_balance := 0.0
var _first_squad_t := -1
var _first_squad_credits := 0.0
var _first_squad_intel := 0.0
var _patrol_bought_t := -1
var _patrol_enabled_t := -1
var _patrol_first_start_t := -1
var _patrol_enabled_dispatches := 0
var _patrol_enabled_tasks := 0
var _patrol_first_cycle_t := -1
var _patrol_first_cycle_dispatches := 0
var _patrol_cycles := 0
var _patrol_assignment_ids: Dictionary = {}


func _initialize() -> void:
	var loaded := GamePackLoader.load_pack(PACK_ID)
	if loaded.get("pack", null) == null:
		print("ROUTE_FAIL pack did not load: %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	_pack = loaded["pack"]
	_state = Simulation.new_state(_pack, 1, 0)
	_patrol_cost = AutoRepeat.patrol_unlock_cost(_state, _pack)
	print("AUTO_PATROL_THRESHOLD branch=%s cost=%d" % [
		AutoRepeat.patrol_branch_id(_pack), _patrol_cost,
	])
	var error := _run()
	if error != 0:
		_report_failure()
		quit(error)
		return
	_report()
	quit(0)


func _run() -> int:
	var steps := 0
	while CommandProgression.current_level(_state, _pack) < 3:
		steps += 1
		if steps > MAX_STEPS:
			_deadlock_reason = "step budget exhausted before City"
			return 1
		if not _step(false):
			_deadlock_reason = "no action before City at t=%d" % _t
			return 1
	_city_entry_t = _t
	_dispatches_at_city = _dispatches
	print("CITY_ENTRY t=%s dispatches=%d tasks=%d lifetime=%.0f agents=%d roles=%d" % [
		_clock(_city_entry_t),
		_dispatches_at_city,
		_state.tasks_completed(),
		_state.earned_total("credits"),
		_state.agents.size(),
		_distinct_roles(),
	])
	var city_levels := CommandProgression.requirement_rows(
		_pack, _state, CommandProgression.level_record(_pack, 4)
	)
	for row in city_levels:
		print("  AT_CITY %-28s %s" % [str(row.get("label", "")), str(row.get("progress", ""))])

	steps = 0
	while CommandProgression.current_level(_state, _pack) < 4:
		steps += 1
		if steps > MAX_STEPS:
			_deadlock_reason = "step budget exhausted after City"
			return 1
		if not _step(true):
			_deadlock_reason = "no action after City at t=%d" % _t
			return 1
	_national_t = _t
	_national_tasks = _state.tasks_completed()
	_national_lifetime = _state.earned_total("credits")
	_national_intel = _state.earned_total("intel")
	_national_agents = _state.agents.size()
	_national_roles = _distinct_roles()
	_national_squads = _state.squad_tasks_completed()
	_national_research = _state.upgrades.size()
	if not CommandProgression.stage_unlocked(_state, _pack, NATIONAL_STAGE):
		_deadlock_reason = "National is still locked after reaching Level 4"
		return 1
	return _run_auto_patrol()


## One decision point: recruit/train, deploy every idle agent, then settle the
## earliest completion. Returns false only when no progress is possible.
## Training happens before deployment, matching the roster screen's instant
## training action; assigned heroes remain assigned.
func _step(after_city: bool) -> bool:
	if after_city:
		_prepare_city()
	else:
		_prepare_street()

	var deployed := _deploy_available(after_city)
	if deployed == 0:
		if _state.assignments.is_empty():
			return false
		# Existing work is still running; settle it rather than deadlocking.
	var ends := _next_end()
	if ends < 0:
		return false
	if ends > _t:
		var outcome := Simulation.simulate_delta(_state, float(ends - _t), _pack)
		_t = ends
		var events: Array = outcome.get("events", [])
		for raw in events:
			if raw is Dictionary and str((raw as Dictionary).get("type", "")) == "task_completed":
				_note_completion(raw as Dictionary)
	# A player who prioritizes Auto Patrol buys it at the first affordable
	# completion and re-arms it after every cycle. The purchase is still a real
	# Research spend from earned Intel, not a grant.
	return _maybe_prioritize_patrol()


func _prepare_street() -> void:
	# Three sessions take the starter from rating 70 to 90, which opens Stakeout
	# and matches the documented Street route. Spend only when the session can be
	# afforded; otherwise the agents keep working.
	if int(_state.agents["hero_volt"].get("level", 1)) < 2:
		_try_train("hero_volt")
		return
	if _state.agents.size() < 4:
		if _state.agents.size() < 3:
			_try_recruit("")
		else:
			# The level-3 role gate needs one of these two. Hiring the role that
			# is missing is cheaper than scanning for a hypothetical best hero.
			var target := "tech"
			if _has_role("tech") and not _has_role("support"):
				target = "support"
			elif not _has_role("tech"):
				target = "tech"
			else:
				target = "support"
			if not _try_recruit(target):
				_try_recruit("")


func _prepare_city() -> void:
	# Joint Raid needs both roles. The level-3 gate only requires Tech or Support,
	# so a legal City roster can still lack the Support the squad needs; target it
	# before spending the fifth roster slot on a cosmetic role.
	if _state.agents.size() < 5:
		var target := ""
		if not _has_role("support"):
			target = "support"
		elif not _has_role("striker"):
			target = "striker"
		elif _distinct_roles() < 4:
			for role_id in ["vanguard", "tech", "mystic", "support", "striker"]:
				if not _has_role(role_id):
					target = role_id
					break
		if not _try_recruit(target):
			_try_recruit("")
		return
	if _state.squad_tasks_completed() < 1:
		_train_squad_pair()


## Train the cheaper member of the Striker + Support pair until their average
## reaches the Joint Raid gate. Training is paid only from Credits the route
## actually earned. The roster screen allows training an assigned hero, so the
## model does not invent an extra availability rule.
func _train_squad_pair() -> void:
	var striker := _best_agent("striker")
	var support := _best_agent("support")
	if striker.is_empty() or support.is_empty():
		return
	var task := _pack.task(SQUAD_TASK)
	var gate := float(task.get("minimum_rating", 0))
	while _pair_rating(striker, support) + 0.0001 < gate:
		var lower := striker
		if AgentRules.rating_value(_state.agents[support]) < AgentRules.rating_value(_state.agents[striker]):
			lower = support
		if not _try_train(lower):
			return


func _deploy_available(after_city: bool) -> int:
	var dispatched := 0
	var reserved: Dictionary = {}
	if after_city and _squad_pair_ready():
		var striker := _best_agent("striker")
		var support := _best_agent("support")
		reserved[striker] = true
		reserved[support] = true
		if AgentRules.is_available(_state.agents[striker]) \
			and AgentRules.is_available(_state.agents[support]):
			if _schedule(SQUAD_TASK, [striker, support]):
				dispatched += 1

	var ids: Array = _state.agents.keys()
	ids.sort()
	for raw_id in ids:
		var agent_id := str(raw_id)
		if reserved.has(agent_id) or not AgentRules.is_available(_state.agents[agent_id]):
			continue
		var task_id := _best_task_for(agent_id, after_city)
		if task_id.is_empty():
			continue
		if _schedule(task_id, [agent_id]):
			dispatched += 1
	return dispatched


## A ready pair is deliberately held for Joint Raid instead of being split into
## solo work. Without this reservation the two heroes finish at different times
## and are immediately redeployed, so an eager policy can starve the squad it
## just trained for.
func _squad_pair_ready() -> bool:
	if _state.squad_tasks_completed() > 0:
		return false
	var striker := _best_agent("striker")
	var support := _best_agent("support")
	if striker.is_empty() or support.is_empty():
		return false
	return _pair_rating(striker, support) + 0.0001 >= float(
		_pack.task(SQUAD_TASK).get("minimum_rating", 0)
	)


func _best_task_for(agent_id: String, after_city: bool) -> String:
	var city := _best_single_task(agent_id, CITY_STAGE) if after_city else ""
	if not city.is_empty():
		return city
	return _best_single_task(agent_id, "street")


func _best_single_task(agent_id: String, stage_id: String) -> String:
	var best := ""
	var best_rate := -1.0
	var ids: Array = _pack.missions.keys()
	ids.sort()
	for raw_id in ids:
		var task_id := str(raw_id)
		var task := _pack.task(task_id)
		if int(task.get("required_agent_count", 1)) != 1:
			continue
		if str(task.get("stage_id", "")) != stage_id:
			continue
		var evaluation := Simulation.evaluate_assignment(_state, _pack, task_id, [agent_id])
		if not evaluation.get("ok", false):
			continue
		var rate := _credit_rate(task)
		if rate > best_rate + 0.0001 or (is_equal_approx(rate, best_rate) and task_id < best):
			best = task_id
			best_rate = rate
	return best


func _schedule(task_id: String, ids: Array) -> bool:
	var result := Simulation.assign_task(_state, _pack, task_id, ids, _t)
	if not result.get("ok", false):
		return false
	_dispatches += 1
	_counts[task_id] = int(_counts.get(task_id, 0)) + 1
	if _city_entry_t >= 0:
		_city_counts[task_id] = int(_city_counts.get(task_id, 0)) + 1
	return true


## Records the exact completion where the reachable Intel balance first covers
## the Auto Patrol price. This is evidence, not a grant; the purchase itself
## happens in `_maybe_prioritize_patrol`, and every value comes from the real
## settlement.
func _note_patrol_availability() -> void:
	if _patrol_first_t >= 0 or _patrol_cost < 0:
		return
	if _state.resource("intel") + 0.0001 < float(_patrol_cost):
		return
	_patrol_first_t = _t
	_patrol_first_dispatches = _dispatches
	_patrol_first_tasks = _state.tasks_completed()
	_patrol_first_intel = _state.resource("intel")
	print("AUTO_PATROL_AVAILABLE t=%s dispatches=%d tasks=%d intel=%.0f cost=%d level=%d" % [
		_clock(_patrol_first_t),
		_patrol_first_dispatches,
		_patrol_first_tasks,
		_patrol_first_intel,
		_patrol_cost,
		CommandProgression.current_level(_state, _pack),
	])


func _note_completion(event: Dictionary) -> void:
	var task_id := str(event.get("task_id", ""))
	if not _first_clear.has(task_id):
		_first_clear[task_id] = _t
		print("  FIRST_CLEAR %-18s t=%s" % [task_id, _clock(_t)])
	var rewards: Variant = event.get("rewards", {})
	var intel_paid := 0.0
	var credit_paid := 0.0
	if rewards is Dictionary:
		intel_paid = float((rewards as Dictionary).get("intel", 0.0))
		credit_paid = float((rewards as Dictionary).get("credits", 0.0))
	var balance := _state.resource("intel")
	if intel_paid > 0.0 and _first_intel_t < 0:
		_first_intel_t = _t
		_first_intel_task = task_id
		_first_intel_amount = intel_paid
		_first_intel_balance = balance
		print("  FIRST_INTEL %-18s +%.0f t=%s balance=%.0f" % [
			task_id, intel_paid, _clock(_t), balance,
		])
	if str(_pack.task(task_id).get("kind", "")) == "squad" and _first_squad_t < 0:
		_first_squad_t = _t
		_first_squad_credits = credit_paid
		_first_squad_intel = intel_paid
		print("  FIRST_SQUAD %-18s t=%s credits=%.0f intel=%.0f" % [
			task_id, _clock(_t), credit_paid, intel_paid,
		])
	var assignment_id := str(event.get("assignment_id", ""))
	if _patrol_assignment_ids.has(assignment_id):
		_patrol_cycles += 1
		if _patrol_first_cycle_t < 0:
			_patrol_first_cycle_t = _t
			_patrol_first_cycle_dispatches = _dispatches
			print("AUTO_PATROL_FIRST_CYCLE t=%s dispatches=%d task=%s" % [
				_clock(_t), _dispatches, task_id,
			])
	var gap := _t - _last_completion_t
	if gap > _max_completion_gap:
		_max_completion_gap = gap
		_max_gap_at = "%s -> %s" % [_clock(_last_completion_t), _clock(_t)]
	_last_completion_t = _t
	_note_patrol_availability()


## Buys the branch at the first completion that can both fund it and start a
## free legal patrol. This is the player-prioritized model: the Intel is earned
## by the route, the choice is real, and no other research is purchased.
func _maybe_prioritize_patrol() -> bool:
	if _patrol_bought_t >= 0:
		return _ensure_patrol_running()
	if _patrol_cost < 0 or AutoRepeat.patrol_branch_id(_pack).is_empty():
		_deadlock_reason = "Auto Patrol branch is missing"
		return false
	if _state.resource("intel") + 0.0001 < float(_patrol_cost):
		return true
	var choice := _best_patrol_choice()
	if choice.is_empty():
		return true
	_note_patrol_availability()
	var intel_before := _state.resource("intel")
	var bought := Research.buy(_state, _pack, AutoRepeat.patrol_branch_id(_pack))
	if not bool(bought.get("ok", false)):
		_deadlock_reason = "Auto Patrol purchase failed"
		print("AUTO_PATROL_BUY_FAIL %s" % str(bought.get("code", "")))
		return false
	_patrol_bought_t = _t
	print("AUTO_PATROL_UNLOCKED t=%s rank=%d cost=%d intel_before=%.0f intel_after=%.0f" % [
		_clock(_t), int(bought.get("rank", 0)), int(bought.get("cost", 0)),
		intel_before, _state.resource("intel"),
	])
	_patrol_agent = str(choice.get("agent_id", ""))
	_patrol_task = str(choice.get("task_id", ""))
	AutoRepeat.configure_patrol(_state, _pack, _patrol_task, _patrol_agent)
	AutoRepeat.set_patrol_enabled(_state, true)
	print("AUTO_PATROL_SELECTED agent=%s task=%s credits_per_second=%.2f available=%s" % [
		_patrol_agent,
		_patrol_task,
		_credit_rate(_pack.task(_patrol_task)),
		str(AgentRules.is_available(_state.agents[_patrol_agent])),
	])
	var started := AutoRepeat.resume_patrol(_state, _pack, _t)
	_patrol_enabled_t = _t
	_patrol_enabled_dispatches = _dispatches
	_patrol_enabled_tasks = _state.tasks_completed()
	if bool(started.get("ok", false)):
		_record_patrol_start(started)
		_patrol_first_start_t = _t
		print("AUTO_PATROL_STARTED t=%s assignment=%s" % [
			_clock(_t), str(started.get("assignment_id", "")),
		])
	else:
		print("AUTO_PATROL_WAITING t=%s code=%s agent_busy=%s" % [
			_clock(_t),
			str(started.get("code", "")),
			str(not AgentRules.is_available(_state.agents[_patrol_agent])),
		])
	print("AUTO_PATROL_ENABLED t=%s dispatches=%d tasks=%d intel_after=%.0f level=%d selected=%s/%s" % [
		_clock(_t),
		_patrol_enabled_dispatches,
		_patrol_enabled_tasks,
		_state.resource("intel"),
		CommandProgression.current_level(_state, _pack),
		_patrol_agent,
		_patrol_task,
	])
	return true


func _ensure_patrol_running() -> bool:
	var status := AutoRepeat.patrol_status(_state, _pack)
	if bool(status.get("running", false)):
		return true
	if not AutoRepeat.patrol_enabled(_state):
		return true
	var started := AutoRepeat.resume_patrol(_state, _pack, _t)
	if bool(started.get("ok", false)):
		_record_patrol_start(started)
		if _patrol_first_start_t < 0:
			_patrol_first_start_t = _t
			print("AUTO_PATROL_STARTED t=%s assignment=%s" % [
				_clock(_t), str(started.get("assignment_id", "")),
			])
	return true


func _record_patrol_start(result: Dictionary) -> void:
	var assignment_id := str(result.get("assignment_id", ""))
	if not assignment_id.is_empty():
		_patrol_assignment_ids[assignment_id] = true


## Exercises the launch catch-up across the pack's eight-hour cap after the
## early City purchase. Nothing here grants Credits, Intel, Command Level or a
## free operation.
func _run_auto_patrol() -> int:
	if _patrol_bought_t < 0 or _patrol_enabled_t < 0:
		_deadlock_reason = "Auto Patrol was not configured during the route"
		return 1
	if _patrol_first_cycle_t < 0 or _patrol_cycles <= 0:
		_deadlock_reason = "Auto Patrol never completed a configured cycle"
		return 1
	if not AutoRepeat.patrol_enabled(_state) or AutoRepeat.patrol_task_id(_state).is_empty():
		_deadlock_reason = "Auto Patrol did not stay enabled through National"
		return 1
	print("AUTO_PATROL_ROUTE agent=%s task=%s bought_t=%s enabled_t=%s first_start_t=%s dispatches=%d first_cycle_t=%s cycles=%d" % [
		_patrol_agent,
		_patrol_task,
		_clock(_patrol_bought_t),
		_clock(_patrol_enabled_t),
		_clock(_patrol_first_start_t),
		_patrol_enabled_dispatches,
		_clock(_patrol_first_cycle_t),
		_patrol_cycles,
	])

	var tasks_before := _state.tasks_completed()
	var credits_before := _state.resource("credits")
	var away_until := _t + int(_pack.max_offline_seconds) + 3600
	var outcome := AutoRepeat.settle_absence(_state, _pack, away_until)
	var tasks_after := _state.tasks_completed()
	var credits_after := _state.resource("credits")
	print("AUTO_PATROL_OFFLINE requested=%d applied=%d capped=%s starts=%d tasks_delta=%d credits_delta=%.0f" % [
		int(outcome.get("requested_seconds", 0)),
		int(outcome.get("applied_seconds", 0)),
		str(outcome.get("capped", false)),
		int(outcome.get("patrol_starts", 0)),
		tasks_after - tasks_before,
		credits_after - credits_before,
	])
	if not bool(outcome.get("capped", false)):
		_deadlock_reason = "Auto Patrol absence did not report the offline cap"
		return 1
	if int(outcome.get("applied_seconds", 0)) != 28800:
		_deadlock_reason = "Auto Patrol absence did not apply exactly eight hours"
		return 1
	if int(outcome.get("patrol_starts", 0)) <= 0 or tasks_after <= tasks_before:
		_deadlock_reason = "Auto Patrol did not complete any away cycles"
		return 1
	print("AUTO_PATROL_AWAY_CYCLES away_starts=%d route_cycles=%d" % [
		int(outcome.get("patrol_starts", 0)), _patrol_cycles,
	])

	var second := AutoRepeat.settle_absence(_state, _pack, away_until)
	if int(second.get("applied_seconds", -1)) != 0 \
		or _state.tasks_completed() != tasks_after \
		or not is_equal_approx(_state.resource("credits"), credits_after):
		_deadlock_reason = "Auto Patrol paid the same launch twice"
		return 1
	print("AUTO_PATROL_SETTLED_ONCE tasks=%d credits=%.0f stamp=%d" % [
		tasks_after, credits_after, _state.last_settled_utc,
	])
	return 0


## Highest Credits/second legal solo pair, preferring a hero that is free at the
## National unlock so the route can start immediately.
func _best_patrol_choice() -> Dictionary:
	# Until the first squad completes, a normal player keeps its Striker and
	# Support out of the solo channel rather than parking one of them on a
	# patrol. If no non-squad hero is free, arm the channel on a busy one and let
	# it wait; this is exactly the paused state the card explains.
	var reserved := _patrol_reserved_agents()
	var choice := _best_patrol_choice_excluding(reserved, true)
	if not choice.is_empty():
		return choice
	return _best_patrol_choice_excluding(reserved, false)


func _patrol_reserved_agents() -> Dictionary:
	var reserved: Dictionary = {}
	if _state.squad_tasks_completed() >= 1:
		return reserved
	for role_id in ["striker", "support"]:
		var agent_id := _best_agent(role_id)
		if not agent_id.is_empty():
			reserved[agent_id] = true
	return reserved


func _best_patrol_choice_excluding(reserved: Dictionary, require_available: bool) -> Dictionary:
	var best := {}
	var best_rate := -1.0
	var ids: Array = _state.agents.keys()
	ids.sort()
	for raw_id in ids:
		var agent_id := str(raw_id)
		if reserved.has(agent_id):
			continue
		if require_available and not AgentRules.is_available(_state.agents[agent_id]):
			continue
		for raw_task_id in AutoRepeat.eligible_solo_task_ids(_state, _pack, agent_id):
			var task_id := str(raw_task_id)
			var rate := _credit_rate(_pack.task(task_id))
			if rate > best_rate + 0.0001 \
				or (is_equal_approx(rate, best_rate) and (best.is_empty() or task_id < str(best.get("task_id", "")))):
				best = {"agent_id": agent_id, "task_id": task_id}
				best_rate = rate
	return best


func _next_end() -> int:
	var next := -1
	for raw in _state.assignments.values():
		if not (raw is Dictionary):
			continue
		var end := int((raw as Dictionary).get("ends_utc", 0))
		if next < 0 or end < next:
			next = end
	return next


func _try_train(agent_id: String) -> bool:
	if not _state.agents.has(agent_id):
		return false
	var cost := Simulation.training_cost(_state, _pack, agent_id)
	if cost < 0 or _state.resource("credits") + 0.0001 < float(cost):
		return false
	return bool(Simulation.train_agent(_state, _pack, agent_id).get("ok", false))


func _try_recruit(role_id: String) -> bool:
	var candidate := Recruitment.next_candidate_for_role(_state, _pack, role_id)
	if candidate.is_empty():
		if role_id.is_empty():
			return false
		candidate = Recruitment.next_candidate(_state, _pack)
		if candidate.is_empty():
			return false
	if _state.resource(Recruitment.resource_id(_pack)) + 0.0001 < float(candidate.get("cost", 0)):
		return false
	return bool(Recruitment.recruit(_state, _pack, role_id).get("ok", false))


func _best_agent(role_id: String) -> String:
	var best := ""
	var best_rating := -1.0
	for raw_id in _state.agents.keys():
		var agent_id := str(raw_id)
		var agent: Dictionary = _state.agents[agent_id]
		if str(agent.get("role_id", "")) != role_id:
			continue
		var rating := AgentRules.rating_value(agent)
		if rating > best_rating + 0.0001 or (is_equal_approx(rating, best_rating) and agent_id < best):
			best = agent_id
			best_rating = rating
	return best


func _pair_rating(striker: String, support: String) -> float:
	return (
		AgentRules.rating_value(_state.agents[striker])
		+ AgentRules.rating_value(_state.agents[support])
	) / 2.0


func _has_role(role_id: String) -> bool:
	for raw in _state.agents.values():
		if raw is Dictionary and str((raw as Dictionary).get("role_id", "")) == role_id:
			return true
	return false


func _distinct_roles() -> int:
	var roles: Dictionary = {}
	for raw in _state.agents.values():
		if raw is Dictionary:
			roles[str((raw as Dictionary).get("role_id", ""))] = true
	return roles.size()


func _credit_rate(task: Dictionary) -> float:
	var rewards: Variant = task.get("rewards", {})
	if not (rewards is Dictionary):
		return 0.0
	return float((rewards as Dictionary).get("credits", 0)) / float(maxi(int(task.get("base_seconds", 1)), 1))


func _report() -> void:
	var elapsed := _national_t - _city_entry_t
	var extra_dispatches := _dispatches - _dispatches_at_city
	print("NATIONAL_UNLOCK t=%s elapsed=%s dispatches=%d additional=%d tasks=%d lifetime=%.0f agents=%d roles=%d squads=%d" % [
		_clock(_national_t),
		_clock_span(elapsed),
		_dispatches,
		extra_dispatches,
		_national_tasks,
		_national_lifetime,
		_national_agents,
		_national_roles,
		_national_squads,
	])
	print("MAX_COMPLETION_GAP %s at %s" % [_clock_span(_max_completion_gap), _max_gap_at])
	var top: Array = []
	for task_id in _city_counts.keys():
		top.append({"id": str(task_id), "count": int(_city_counts[task_id])})
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		return str(a["id"]) < str(b["id"])
	)
	var parts: Array[String] = []
	for row in top.slice(0, 5):
		parts.append("%s x%d" % [str(row["id"]), int(row["count"])])
	print("CITY_REPEATS %s" % ", ".join(parts))
	print("INTEL_EARNED %.0f RESEARCH_RANKS %d" % [
		_national_intel, _national_research,
	])
	if _first_intel_t >= 0:
		print("FIRST_INTEL t=%s task=%s amount=%.0f balance=%.0f" % [
			_clock(_first_intel_t), _first_intel_task, _first_intel_amount, _first_intel_balance,
		])
	if _first_squad_t >= 0:
		print("FIRST_SQUAD t=%s credits=%.0f intel=%.0f" % [
			_clock(_first_squad_t), _first_squad_credits, _first_squad_intel,
		])
	if _patrol_first_t >= 0:
		print("AUTO_PATROL_FIRST t=%s dispatches=%d tasks=%d intel=%.0f cost=%d" % [
			_clock(_patrol_first_t),
			_patrol_first_dispatches,
			_patrol_first_tasks,
			_patrol_first_intel,
			_patrol_cost,
		])
	if _patrol_enabled_t >= 0:
		print("AUTO_PATROL_PACING enabled_t=%s first_start_t=%s dispatches=%d tasks=%d first_cycle_t=%s route_cycles=%d" % [
			_clock(_patrol_enabled_t),
			_clock(_patrol_first_start_t),
			_patrol_enabled_dispatches,
			_patrol_enabled_tasks,
			_clock(_patrol_first_cycle_t),
			_patrol_cycles,
		])
	print("AUTO_PATROL_RESULT agent=%s task=%s" % [
		_patrol_agent, _patrol_task,
	])
	print("ROUTE_OK National Response requires %d and current level is %d" % [
		CommandProgression.stage_unlock_level(_pack, NATIONAL_STAGE),
		CommandProgression.current_level(_state, _pack),
	])


func _report_failure() -> void:
	print("ROUTE_FAIL %s t=%s level=%d tasks=%d lifetime=%.0f agents=%d roles=%d" % [
		_deadlock_reason,
		_clock(_t),
		CommandProgression.current_level(_state, _pack),
		_state.tasks_completed(),
		_state.earned_total("credits"),
		_state.agents.size(),
		_distinct_roles(),
	])


func _clock(seconds: int) -> String:
	return "%d:%02d" % [int(seconds / 60), int(seconds % 60)]


func _clock_span(seconds: int) -> String:
	return "%d:%02d" % [int(seconds / 60), int(seconds % 60)]

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
##   - otherwise every idle agent takes its best-paying legal City or Street job.
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
var _last_completion_t := 0
var _max_completion_gap := 0
var _max_gap_at := ""
var _counts: Dictionary = {}
var _city_counts: Dictionary = {}
var _first_clear: Dictionary = {}
var _deadlock_reason := ""


func _initialize() -> void:
	var loaded := GamePackLoader.load_pack(PACK_ID)
	if loaded.get("pack", null) == null:
		print("ROUTE_FAIL pack did not load: %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	_pack = loaded["pack"]
	_state = Simulation.new_state(_pack, 1, 0)
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
	if not CommandProgression.stage_unlocked(_state, _pack, NATIONAL_STAGE):
		_deadlock_reason = "National is still locked after reaching Level 4"
		return 1
	return 0


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
	return true


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


func _note_completion(event: Dictionary) -> void:
	var task_id := str(event.get("task_id", ""))
	if not _first_clear.has(task_id):
		_first_clear[task_id] = _t
		print("  FIRST_CLEAR %-18s t=%s" % [task_id, _clock(_t)])
	var gap := _t - _last_completion_t
	if gap > _max_completion_gap:
		_max_completion_gap = gap
		_max_gap_at = "%s -> %s" % [_clock(_last_completion_t), _clock(_t)]
	_last_completion_t = _t


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
		_state.tasks_completed(),
		_state.earned_total("credits"),
		_state.agents.size(),
		_distinct_roles(),
		_state.squad_tasks_completed(),
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
		_state.earned_total("intel"),
		_state.upgrades.size(),
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

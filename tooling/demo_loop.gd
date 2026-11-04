extends SceneTree
## Scripted walkthrough of the M1 loop on a manual clock.
##
##   godot --headless --path . -s res://tooling/demo_loop.gd
##
## Runs the greedy policy a first-time player would: train when it is affordable,
## otherwise take the best-paying task on offer. Prints each completion so the
## curve can be seen without a display. Never touches the player's save.

const PACK_ID := "hero_hq"
const RUN_SECONDS := 900

var _pack: GamePack
var _state: GameState
var _t: int = 0
var _seen_level: int = 1


func _initialize() -> void:
	var loaded := GamePackLoader.load_pack(PACK_ID)
	if loaded["pack"] == null:
		print("FAIL pack did not load: %s" % str(loaded["errors"]))
		quit(1)
		return
	_pack = loaded["pack"]
	_state = Simulation.new_state(_pack, 1, 0)
	print("%s — content v%d, offline allowance %d s" % [
		_pack.title(), _pack.content_version, int(_pack.max_offline_seconds),
	])
	print("start: %s %s, rating %d at level %d" % [
		TextFormat.amount(_state.resource("credits")),
		_pack.label("resources.credits"),
		_current_rating(),
		_current_level(),
	])
	print("")

	while _t < RUN_SECONDS:
		_train_when_affordable()
		var task_id := _best_task()
		if task_id.is_empty():
			print("nothing deployable at %s" % _clock())
			break
		var deployed := Simulation.deploy(_state, _pack, task_id, _t)
		if not deployed.get("ok", false):
			print("FAIL deploy %s refused: %s" % [task_id, str(deployed.get("code", ""))])
			quit(1)
			return
		var ends := int(deployed["ends_utc"])
		var delta := maxi(ends - _t, 1)
		var outcome := Simulation.simulate_delta(_state, float(delta), _pack)
		_state = outcome["state"]
		_t = ends
		print("%s  %-16s  %s" % [
			_clock(),
			_pack.label(str(_pack.task(task_id).get("name_key", "")), task_id),
			_status_line(),
		])
		_check_level()

	print("")
	print("%s  final: %s" % [_clock(), _status_line()])
	print("tasks completed: %d, credits earned: %s" % [
		_state.tasks_completed(),
		TextFormat.amount(_state.earned_total("credits")),
	])
	print("OK loop complete")
	quit(0)


func _train_when_affordable() -> void:
	var resource_id := str(_pack.training.get("resource_id", ""))
	var guard := 0
	while guard < 500:
		guard += 1
		var cost := Simulation.training_cost(_state, _pack, _agent_id())
		if cost < 0 or _state.resource(resource_id) + 0.0001 < float(cost):
			return
		var result := Simulation.train_agent(_state, _pack, _agent_id())
		if not result.get("ok", false):
			return
		_check_level()


func _check_level() -> void:
	var level := _current_level()
	while _seen_level < level:
		_seen_level += 1
		print("%s  ** level %d (rating %d) — %s unlocked up to gate %d" % [
			_clock(),
			_seen_level,
			_current_rating(),
			_unlocked_names(),
			_best_gate(),
		])


func _unlocked_names() -> String:
	var names: Array[String] = []
	for task_id in _pack.task_ids():
		if _current_rating() + 0.0001 >= float(_pack.task(str(task_id)).get("minimum_rating", 0)):
			names.append(_pack.label(str(_pack.task(str(task_id)).get("name_key", "")), str(task_id)))
	return ", ".join(names)


func _best_gate() -> int:
	var best := 0
	for task_id in _pack.task_ids():
		if _current_rating() + 0.0001 >= float(_pack.task(str(task_id)).get("minimum_rating", 0)):
			best = maxi(best, int(_pack.task(str(task_id)).get("minimum_rating", 0)))
	return best


func _best_task() -> String:
	var best := ""
	var best_income := 0.0
	for task_id in _pack.task_ids():
		var task := _pack.task(str(task_id))
		if _current_rating() + 0.0001 < float(task.get("minimum_rating", 0)):
			continue
		# Role-gated operations are content the roster may not cover yet; the
		# demo plays one agent, so it can only take what that agent can staff.
		if Simulation.auto_select_agents(_state, _pack, str(task_id)).is_empty():
			continue
		var income := _income_per_minute(str(task_id))
		if income > best_income:
			best_income = income
			best = str(task_id)
	return best


func _income_per_minute(task_id: String) -> float:
	if task_id.is_empty():
		return 0.0
	var task := _pack.task(task_id)
	var seconds := maxf(float(task.get("base_seconds", 1)), 1.0)
	var rewards: Variant = task.get("rewards", null)
	var total := 0.0
	if rewards is Dictionary:
		for raw_id in (rewards as Dictionary).keys():
			total += float((rewards as Dictionary)[raw_id])
	return total * 60.0 / seconds


func _status_line() -> String:
	return "L%d rating %3d  %4s %s  %3s %s" % [
		_current_level(),
		_current_rating(),
		TextFormat.amount(_state.resource("credits")),
		_pack.label("resources.credits"),
		TextFormat.amount(_state.resource("intel")),
		_pack.label("resources.intel"),
	]


func _agent_id() -> String:
	var ids: Array = _state.agents.keys()
	if ids.is_empty():
		return ""
	ids.sort()
	return str(ids[0])


func _current_rating() -> int:
	var agent: Variant = _state.agents.get(_agent_id(), null)
	if agent is Dictionary:
		return AgentRules.rating(agent)
	return 0


func _current_level() -> int:
	var agent: Variant = _state.agents.get(_agent_id(), null)
	if agent is Dictionary:
		return int((agent as Dictionary).get("level", 1))
	return 1


func _clock() -> String:
	return TextFormat.duration(float(_t))

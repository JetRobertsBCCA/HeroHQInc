extends SceneTree
## Simulates a greedy player against the real pack and reports the pacing curve.
##
##   godot --headless --path . -s res://tooling/balance_report.gd
##
## Policy: train whenever it is affordable, otherwise run the highest-paying task
## the roster can clear. That is close to what a first-time player does with one
## agent, and it makes the curve measurable instead of anecdotal.
##
## The point is not to predict a real player exactly; it is to expose walls,
## dead time and runaway growth before those reach a device.

const PACK_ID := "hero_hq"
const HORIZON_SECONDS := 7200
const SAMPLE_EVERY := 300

var _pack: GamePack
var _state: GameState
var _t: int = 0
var _unlocked: Dictionary = {}
var _level_times: Dictionary = {}
var _spent: float = 0.0
var _tasks_done: int = 0
var _samples: Array = []
var _first_deploy: Dictionary = {}


func _initialize() -> void:
	var loaded := GamePackLoader.load_pack(PACK_ID)
	if loaded["pack"] == null:
		print("FAIL pack did not load: %s" % str(loaded["errors"]))
		quit(1)
		return
	_pack = loaded["pack"]
	_state = Simulation.new_state(_pack, 1, 0)
	_record_unlocks()
	_run()
	_report()
	quit(0)


func _run() -> void:
	var next_sample := 0
	var guard := 0
	while _t < HORIZON_SECONDS and guard < 100000:
		guard += 1
		_train_while_affordable()
		if _t >= next_sample:
			_samples.append({
				"t": _t,
				"credits": _state.resource("credits"),
				"rating": _current_rating(),
				"level": _current_level(),
				"best_rate": _best_rate(),
			})
			next_sample += SAMPLE_EVERY
		var task_id := _best_task()
		if task_id.is_empty():
			break
		if not _first_deploy.has(task_id):
			_first_deploy[task_id] = _t
		var result := Simulation.deploy(_state, _pack, task_id, _t)
		if not result.get("ok", false):
			print("FAIL deploy %s refused: %s" % [task_id, str(result.get("code", ""))])
			break
		var ends := int(result["ends_utc"])
		var delta := maxi(ends - _t, 1)
		var outcome := Simulation.simulate_delta(_state, float(delta), _pack)
		_state = outcome["state"]
		_t = ends
		match_count(outcome.get("events", []))


func match_count(events: Array) -> void:
	for event in events:
		if not (event is Dictionary):
			continue
		var entry: Dictionary = event
		if str(entry.get("type", "")) == "task_completed":
			_tasks_done += 1
		elif str(entry.get("type", "")) == "level_up":
			var level := int(entry.get("level", 1))
			if not _level_times.has(level):
				_level_times[level] = _t
				print("  %s  level %d reached (rating %d)" % [_clock(_t), level, _current_rating()])
	_record_unlocks()


func _train_while_affordable() -> void:
	var resource_id := str(_pack.training.get("resource_id", ""))
	var guard := 0
	while guard < 500:
		guard += 1
		var cost := Simulation.training_cost(_state, _pack, _agent_id())
		if cost < 0 or _state.resource(resource_id) + 0.0001 < float(cost):
			return
		var before := _state.resource(resource_id)
		var result := Simulation.train_agent(_state, _pack, _agent_id())
		if not result.get("ok", false):
			return
		_spent += before - _state.resource(resource_id)
		match_count(result.get("events", []))


func _record_unlocks() -> void:
	for task_id in _pack.task_ids():
		if _unlocked.has(task_id):
			continue
		if _current_rating() + 0.0001 >= float(_pack.task(str(task_id)).get("minimum_rating", 0)):
			_unlocked[str(task_id)] = _t
			print("  %s  unlocked %s (rating %d / gate %d)" % [
				_clock(_t),
				_pack.label(str(_pack.task(str(task_id)).get("name_key", "")), str(task_id)),
				_current_rating(),
				int(_pack.task(str(task_id)).get("minimum_rating", 0)),
			])


func _best_task() -> String:
	var best := ""
	var best_income := 0.0
	for task_id in _pack.task_ids():
		var task := _pack.task(str(task_id))
		if _current_rating() + 0.0001 < float(task.get("minimum_rating", 0)):
			continue
		var income := _income_per_minute(str(task_id))
		if income > best_income:
			best_income = income
			best = str(task_id)
	return best


func _best_rate() -> float:
	var task_id := _best_task()
	return _income_per_minute(task_id) if not task_id.is_empty() else 0.0


func _income_per_minute(task_id: String) -> float:
	if task_id.is_empty():
		return 0.0
	var task := _pack.task(task_id)
	var seconds := maxf(float(task.get("base_seconds", 1)), 1.0)
	var rewards: Variant = task.get("rewards", null)
	var total := 0.0
	if rewards is Dictionary:
		for raw_id in (rewards as Dictionary).keys():
			# Weight every resource equally: Intel has no sink yet, so this is a
			# rough proxy rather than a finished economy model.
			total += float((rewards as Dictionary)[raw_id])
	return total * 60.0 / seconds


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
	return 0


func _report() -> void:
	print("")
	print("PACK TASKS")
	for task_id in _pack.task_ids():
		var task := _pack.task(str(task_id))
		print("  %-12s gate %3d  %4.0fs  %6.0f/min" % [
			str(task_id),
			int(task.get("minimum_rating", 0)),
			float(task.get("base_seconds", 0)),
			_income_per_minute(str(task_id)),
		])
	print("")
	print("LEVEL TIMES")
	var levels: Array = _level_times.keys()
	levels.sort()
	for level in levels:
		print("  level %d at %s" % [int(level), _clock(int(_level_times[level]))])
	print("")
	print("FIRST DEPLOY PER TASK")
	for task_id in _pack.task_ids():
		var at := int(_first_deploy.get(str(task_id), -1))
		print("  %-12s %s" % [str(task_id), "never" if at < 0 else _clock(at)])
	print("")
	print("SAMPLE (every %ds)" % SAMPLE_EVERY)
	for sample in _samples:
		var entry: Dictionary = sample
		print("  %5s  L%d rating %3d  credits %6s  best %6.0f/min" % [
			_clock(int(entry["t"])),
			int(entry["level"]),
			int(entry["rating"]),
			TextFormat.amount(float(entry["credits"])),
			float(entry["best_rate"]),
		])
	print("")
	print("TOTALS after %s" % _clock(_t))
	print("  tasks completed : %d" % _tasks_done)
	print("  credits earned  : %s" % TextFormat.amount(_state.earned_total("credits")))
	print("  credits spent   : %s" % TextFormat.amount(_spent))
	print("  final balance   : %s credits, %s intel" % [
		TextFormat.amount(_state.resource("credits")),
		TextFormat.amount(_state.resource("intel")),
	])
	print("  final level     : %d (rating %d)" % [_current_level(), _current_rating()])
	print("  average income  : %s credits/min" % TextFormat.amount(
		_state.earned_total("credits") / maxf(float(_t) / 60.0, 1.0)
	))


func _clock(seconds: int) -> String:
	return TextFormat.duration(float(seconds))

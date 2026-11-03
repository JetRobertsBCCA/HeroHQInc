extends SceneTree
## Long-horizon model: plays the real simulation for a week, rebirthing whenever
## a run is eligible and has had time to breathe, and reports every wait.
##
## This is the check behind the "wait times lengthen but never get boring" rule.
## It measures the actual level-up gaps produced by the pack's numbers instead of
## trusting a closed-form estimate, so a retune cannot silently blow the budget.
##
## Run: godot --headless --path . -s res://tooling/long_run_report.gd

const PACK_ID := "hero_hq"
const HORIZON_SECONDS := 7 * 24 * 3600
const MAX_STEPS := 200000
## A run must last this long before it may rebirth, so the model does not reset
## the moment the gate opens.
const MIN_RUN_SECONDS := 900
## No single level-up wait inside a run may exceed this. It is the definition of
## "slow, but not boring" used by this report.
const BOREDOM_CAP_SECONDS := 1800.0
const TRAININGS_PER_STEP := 8

var _pack: GamePack
var _state: GameState
var _t := 0
var _run_start := 0
var _run_max_wait := 0.0
var _run_level := 1
var _last_level_at := 0
var _runs: Array = []
var _max_wait := 0.0
var _max_wait_run := 1
var _max_wait_level := 1


func _initialize() -> void:
	var loaded := GamePackLoader.load_pack(PACK_ID)
	if loaded.get("pack", null) == null:
		push_error("long_run: pack '%s' failed to load: %s" % [PACK_ID, str(loaded.get("errors", []))])
		quit(1)
		return
	_pack = loaded["pack"]
	_state = Simulation.new_state(_pack, 1, 0)
	_run_start = 0
	_last_level_at = 0
	var error := _simulate()
	if error != 0:
		quit(error)
		return
	_report()
	quit(0)


func _simulate() -> int:
	var steps := 0
	while _t < HORIZON_SECONDS:
		steps += 1
		if steps > MAX_STEPS:
			push_error("long_run: step budget exhausted at t=%d" % _t)
			return 1
		_train_all()
		if _should_rebirth():
			_rebirth()
			continue
		if not _run_one_task():
			push_error("long_run: no deployable task at t=%d (level %d)" % [_t, _run_level])
			return 1
	_finish_run()
	return 0


func _train_all() -> void:
	for _i in TRAININGS_PER_STEP:
		var cost := Simulation.training_cost(_state, _pack, _trainable_agent())
		if cost < 0 or _state.resource("credits") < float(cost):
			return
		var result := Simulation.train_agent(_state, _pack, _trainable_agent())
		if not result.get("ok", false):
			return
		_note_events(result.get("events", []))


func _trainable_agent() -> String:
	var ids: Array = _state.agents.keys()
	ids.sort()
	return "" if ids.is_empty() else str(ids[0])


## Deploys the best available task by payout per second, settles it, advances time.
func _run_one_task() -> bool:
	var task_ids: Array = _pack.missions.keys()
	task_ids.sort()
	task_ids.sort_custom(_compare_rate)
	for raw_id in task_ids:
		var task_id := str(raw_id)
		var result := Simulation.deploy(_state, _pack, task_id, _t)
		if not result.get("ok", false):
			continue
		var ends := int(result.get("ends_utc", _t))
		var delta := maxi(ends - _t, 1)
		var outcome := Simulation.simulate_delta(_state, float(delta), _pack)
		_t = ends
		_note_events(outcome.get("events", []))
		return true
	return false


func _compare_rate(a: Variant, b: Variant) -> bool:
	var rate_a := _rate(str(a))
	var rate_b := _rate(str(b))
	if not is_equal_approx(rate_a, rate_b):
		return rate_a > rate_b
	return str(a) < str(b)


func _rate(task_id: String) -> float:
	var task := _pack.task(task_id)
	if task.is_empty():
		return 0.0
	var seconds := maxf(float(task.get("base_seconds", 1)), 1.0)
	var rewards: Variant = task.get("rewards", {})
	if not (rewards is Dictionary):
		return 0.0
	var resource_id := Prestige.resource_id(_pack)
	var amount := float((rewards as Dictionary).get(resource_id, 0.0))
	return amount / seconds


func _note_events(events: Array) -> void:
	for raw in events:
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		if str(event.get("type", "")) != "level_up":
			continue
		var wait := float(_t - _last_level_at)
		_last_level_at = _t
		_run_level = int(event.get("level", _run_level))
		_run_max_wait = maxf(_run_max_wait, wait)
		if wait > _max_wait:
			_max_wait = wait
			_max_wait_run = _runs.size() + 1
			_max_wait_level = _run_level


func _should_rebirth() -> bool:
	if _t - _run_start < MIN_RUN_SECONDS:
		return false
	return Prestige.eligibility(_state, _pack).get("ok", false)


func _rebirth() -> void:
	var result := Prestige.rebirth(_state, _pack, _t)
	if not result.get("ok", false):
		return
	_runs.append({
		"index": _runs.size() + 1,
		"duration": _t - _run_start,
		"level": _run_level,
		"gain": int(result["gained"]),
		"chips": int(result["chips"]),
		"multiplier": float(result["multiplier"]),
		"max_wait": _run_max_wait,
	})
	_run_start = _t
	_run_max_wait = 0.0
	_run_level = 1
	_last_level_at = _t


func _finish_run() -> void:
	if _t <= _run_start:
		return
	_runs.append({
		"index": _runs.size() + 1,
		"duration": _t - _run_start,
		"level": _run_level,
		"gain": 0,
		"chips": _state.prestige_chips(),
		"multiplier": Prestige.multiplier(_state, _pack),
		"max_wait": _run_max_wait,
		"partial": true,
	})


func _report() -> void:
	print("HERO//HQ long-run model — %s horizon, rebirth at >= %s" % [
		_duration(HORIZON_SECONDS), _duration(MIN_RUN_SECONDS),
	])
	print("prestige: %s" % JSON.stringify(_pack.prestige))
	print("")
	print("run  length    level  +chips  total  multiplier  longest wait")
	for raw in _runs:
		var run: Dictionary = raw
		var index := int(run["index"])
		# Long horizons produce many runs; show the shape, not every line.
		if _runs.size() > 16 and index > 6 and index <= _runs.size() - 6:
			if index == 7:
				print("...")
			continue
		print("%-4d %-9s %-6d %-7d %-6d ×%-10.2f %s%s" % [
			index,
			_duration(int(run["duration"])),
			int(run["level"]),
			int(run["gain"]),
			int(run["chips"]),
			float(run["multiplier"]),
			_duration(int(run["max_wait"])),
			"  (partial)" if run.has("partial") else "",
		])
	print("")
	var total := 0.0
	for raw in _runs:
		total += float((raw as Dictionary)["duration"])
	var average := total / float(maxi(_runs.size(), 1))
	print("runs: %d   average run: %s   final multiplier: ×%.2f" % [
		_runs.size(), _duration(int(average)), Prestige.multiplier(_state, _pack),
	])
	print("longest single wait: %s (run %d, level %d)" % [
		_duration(int(_max_wait)), _max_wait_run, _max_wait_level,
	])
	var ok := _max_wait <= BOREDOM_CAP_SECONDS
	print("%s boredom budget: longest wait %s vs cap %s" % [
		"PASS" if ok else "FAIL", _duration(int(_max_wait)), _duration(int(BOREDOM_CAP_SECONDS)),
	])
	if not ok:
		printerr("long_run: a level-up wait exceeded the boredom budget")


func _duration(seconds: int) -> String:
	var total := maxi(seconds, 0)
	var minutes := total / 60
	var hours := minutes / 60
	if hours > 0:
		return "%dh%02dm" % [hours, minutes % 60]
	if minutes > 0:
		return "%dm%02ds" % [minutes, total % 60]
	return "%ds" % total

extends TestCase
## App composition-root coverage for the paused auto-repeat Retry action.
##
## These tests boot the real app scene against an isolated profile slot. The
## first proves the game layer subscribes both tab screens to the Retry signal
## and that a blocked tap refreshes without changing state. The second restores
## the missing member while the paused banner is on screen, then sends the same
## button press; this proves the listener re-evaluates live state, starts exactly
## one assignment, and pays nothing.

const PACK_ID := "hero_hq"
const PROFILE_ID := "test_app_retry"
const TASK_ID := "s_raid"
const NOW := 1000
const LINEUP := ["test_striker", "test_support"]


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _agent(agent_id: String, role_id: String) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": 9, "speed": 9, "skill": 9},
	}


## A controlled save whose Joint Raid rule is paused because its support is no
## longer on the roster. The support record is returned so the success test can
## put it back while the old paused banner is still on screen.
func _paused_state(pack: GamePack) -> Dictionary:
	var state := Simulation.new_state(pack, 7, NOW)
	state.game_id = PROFILE_ID
	state.resources["credits"] = 500.0
	state.stats["tasks_completed"] = 0
	state.upgrades["ops_automation"] = 1
	state.agents["test_striker"] = _agent("test_striker", "striker")
	var support := _agent("test_support", "support")
	state.agents["test_support"] = support.duplicate(true)
	AutoRepeat.remember(state, TASK_ID, LINEUP)
	state.agents.erase("test_support")
	return {"state": state, "support": support}


func _boot(state: GameState) -> Node:
	SaveService.delete_profile(PROFILE_ID)
	var written := SaveService.save_state(state)
	if not str(written.get("error", "")).is_empty():
		return null
	var scene: PackedScene = load("res://games/hero_hq/scenes/app.tscn")
	var app := scene.instantiate()
	app.set("_profile_id", PROFILE_ID)
	app.set("_clock", Clock.Manual.new(NOW))
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(app)
	# `SceneTree._initialize` does not dispatch the scene's `_ready` before this
	# synchronous test runs. Call the real boot method if add_child deferred it.
	if app.get("_state") == null:
		app.call("_ready")
	return app


func _cleanup(app: Node) -> void:
	if app != null and is_instance_valid(app):
		app.free()
	SaveService.delete_profile(PROFILE_ID)


func test_app_bootstraps_and_wires_retry_listener() -> void:
	var pack := _pack()
	var setup := _paused_state(pack)
	var app := _boot(setup["state"])
	assert_true(app != null, "the app scene boots against the controlled profile")
	if app == null:
		return

	var state: GameState = app.get("_state")
	var shell: ScreenShell = app.get("_shell")
	assert_true(state != null, "bootstrap restores the controlled state")
	assert_true(shell != null, "bootstrap builds the shell")
	assert_true(app.get("_timer") is Timer, "bootstrap starts the game timer")
	if state == null or shell == null:
		_cleanup(app)
		return
	assert_eq(state.game_id, PROFILE_ID, "the app reads the isolated profile slot")
	assert_eq(AutoRepeat.task_id(state), TASK_ID, "the paused rule survives boot")
	assert_eq(state.assignments.size(), 0, "boot does not start the blocked rule")
	assert_true(shell.current_tab() == "hq", "bootstrap opens on HQ")

	shell.select_tab("missions")
	var board: TaskBoard = app.get("_task_board")
	assert_true(board != null, "the Missions tab builds a board")
	if board == null:
		_cleanup(app)
		return
	var listener := Callable(app, "_on_auto_repeat_retry_requested")
	assert_true(
		board.auto_repeat_retry_requested.is_connected(listener),
		"the app subscribes to the Missions Retry signal",
	)
	var banner := board.auto_repeat_banner()
	assert_true(banner != null, "the board exposes the auto-repeat banner")
	if banner == null:
		_cleanup(app)
		return
	assert_eq(banner.status_code(), Simulation.ERROR_UNKNOWN_AGENT, "the banner starts paused")
	var retry := banner.retry_button()
	assert_true(retry != null and retry.visible, "Retry is visible while paused")
	if retry == null:
		_cleanup(app)
		return

	var credits := state.resource("credits")
	var tasks := state.tasks_completed()
	var old_board := board
	retry.pressed.emit()
	var refreshed: TaskBoard = app.get("_task_board")
	assert_true(refreshed != old_board, "the app listener rebuilds the tab after Retry")
	assert_eq(state.assignments.size(), 0, "a blocked Retry still starts nothing")
	assert_eq(state.resource("credits"), credits, "a blocked Retry pays nothing")
	assert_eq(state.tasks_completed(), tasks, "a blocked Retry completes nothing")
	if refreshed != null:
		var refreshed_banner := refreshed.auto_repeat_banner()
		assert_true(refreshed_banner != null, "the refreshed board still has a banner")
		if refreshed_banner != null:
			assert_eq(
				refreshed_banner.status_code(),
				Simulation.ERROR_UNKNOWN_AGENT,
				"the refreshed banner keeps the current reason",
			)
			assert_true(
				refreshed_banner.retry_button().visible,
				"Retry remains available after the refusal",
			)

	shell.select_tab("teams")
	var teams: TeamScreen = app.get("_teams")
	assert_true(teams != null, "the Teams tab builds a screen")
	if teams != null:
		assert_true(
			teams.auto_repeat_retry_requested.is_connected(listener),
			"the app subscribes to the Teams Retry signal",
		)
	_cleanup(app)


func test_successful_manual_retry_starts_one_assignment_without_payment() -> void:
	var pack := _pack()
	var setup := _paused_state(pack)
	var support: Dictionary = setup["support"]
	var seed_state: GameState = setup["state"]
	var app := _boot(seed_state)
	assert_true(app != null, "the app boots for the successful Retry case")
	if app == null:
		return

	var state: GameState = app.get("_state")
	var shell: ScreenShell = app.get("_shell")
	assert_true(state != null, "the app exposes the booted live state")
	assert_true(shell != null, "the app exposes the booted shell")
	if state == null or shell == null:
		_cleanup(app)
		return
	shell.select_tab("missions")
	var board: TaskBoard = app.get("_task_board")
	assert_true(board != null, "the paused Retry control is on screen")
	if board == null:
		_cleanup(app)
		return
	var banner := board.auto_repeat_banner()
	assert_true(banner != null, "the board exposes the auto-repeat banner")
	if banner == null:
		_cleanup(app)
		return
	assert_eq(banner.status_code(), Simulation.ERROR_UNKNOWN_AGENT, "the rule is paused before the tap")
	var retry := banner.retry_button()
	assert_true(retry != null and retry.visible, "Retry is available before the controlled recovery")
	if retry == null:
		_cleanup(app)
		return

	# This is the controlled step ordinary UI cannot reach: recovery happens
	# while the paused banner remains on screen, so the next press is the manual
	# Retry action rather than an automatic retry from training or settlement.
	state.agents["test_support"] = support.duplicate(true)
	var credits := state.resource("credits")
	var tasks := state.tasks_completed()
	retry.pressed.emit()

	var refreshed: TaskBoard = app.get("_task_board")
	assert_true(refreshed != null, "the successful Retry rebuilds the tab")
	assert_eq(state.assignments.size(), 1, "one successful Retry starts exactly one job")
	if state.assignments.size() == 1:
		var assignment: Dictionary = state.assignments.values()[0]
		assert_eq(str(assignment.get("task_id", "")), TASK_ID, "the eligible remembered task starts")
		assert_eq(assignment.get("agent_ids", []), LINEUP, "the exact saved lineup starts")
	assert_eq(state.resource("credits"), credits, "starting through Retry pays nothing")
	assert_eq(state.tasks_completed(), tasks, "starting through Retry completes nothing")
	assert_eq(AutoRepeat.lineup(state), LINEUP, "the rule keeps its saved lineup")

	var waiting := refreshed.auto_repeat_banner() if refreshed != null else null
	assert_true(waiting != null, "the refreshed board exposes the waiting banner")
	if waiting != null:
		assert_eq(waiting.status_code(), AutoRepeat.CODE_BUSY, "the started rule reads as waiting")
		assert_true(waiting.status_text().contains("Waiting"), "the refreshed banner shows the running job")
		assert_false(waiting.retry_button().visible, "Retry is hidden once the job is running")

	# A second listener call while the replacement runs must not chain a second
	# assignment or add another payment.
	app.call("_on_auto_repeat_retry_requested")
	assert_eq(state.assignments.size(), 1, "a second Retry cannot schedule a second job")
	assert_eq(state.resource("credits"), credits, "a second Retry adds no payment")
	assert_eq(state.tasks_completed(), tasks, "a second Retry completes nothing")

	# Normal completion pays exactly once and increments the task count once.
	var outcome := Simulation.simulate_delta(state, 120.0, pack)
	var completions := 0
	for event in outcome.get("events", []):
		if event is Dictionary and str((event as Dictionary).get("type", "")) == "task_completed":
			completions += 1
	assert_eq(completions, 1, "the started job completes once")
	assert_eq(state.tasks_completed(), tasks + 1, "the task is counted once")
	assert_true(state.resource("credits") > credits, "the one completion pays a reward")
	_cleanup(app)

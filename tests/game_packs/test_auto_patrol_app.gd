extends TestCase
## App-level Auto Patrol: the real Missions card configures and enables the
## channel, the choice is saved, and a long absence settles only the pack's
## offline allowance without paying the same cycle again on the next launch.

const PACK_ID := "hero_hq"
const PROFILE_ID := "test_auto_patrol_app"
const NOW := 1000


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 7, NOW)
	state.game_id = PROFILE_ID
	state.upgrades["ops_patrol"] = 1
	return state


func _boot(state: GameState, now: int) -> Node:
	SaveService.delete_profile(PROFILE_ID)
	var written := SaveService.save_state(state)
	if not str(written.get("error", "")).is_empty():
		return null
	var scene: PackedScene = load("res://games/hero_hq/scenes/app.tscn")
	var app := scene.instantiate()
	app.set("_profile_id", PROFILE_ID)
	app.set("_clock", Clock.Manual.new(now))
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(app)
	if app.get("_state") == null:
		app.call("_ready")
	var timer := app.get("_timer") as Timer
	if timer != null:
		timer.stop()
	return app


func _cleanup(app: Node) -> void:
	if app != null and is_instance_valid(app):
		app.free()
	SaveService.delete_profile(PROFILE_ID)


func test_missions_card_configures_enables_and_persists_a_patrol() -> void:
	var pack := _pack()
	var seed_state := _state(pack)
	var app := _boot(seed_state, NOW)
	assert_true(app != null, "the app boots with the patrol research")
	if app == null:
		return
	var state: GameState = app.get("_state")
	var shell: ScreenShell = app.get("_shell")
	assert_true(state != null and shell != null, "bootstrap restores state and shell")
	if state == null or shell == null:
		_cleanup(app)
		return

	shell.select_tab("missions")
	var board: TaskBoard = app.get("_task_board")
	var card: AutoPatrolCard = board.auto_patrol_card() if board != null else null
	assert_true(card != null, "Missions exposes the Auto Patrol card")
	if card == null:
		_cleanup(app)
		return
	assert_eq(card.status_text(), "NOT SET", "no patrol is configured yet")
	card.agent_button().pressed.emit()
	var agent_choice := card.agent_choice_button("hero_volt")
	assert_true(agent_choice != null, "the card lists the starter agent")
	if agent_choice == null:
		_cleanup(app)
		return
	agent_choice.pressed.emit()

	board = app.get("_task_board")
	card = board.auto_patrol_card() if board != null else null
	assert_true(card != null, "the app rebuilds Missions after the agent choice")
	if card == null:
		_cleanup(app)
		return
	assert_eq(AutoRepeat.patrol_agent_id(state), "hero_volt", "the agent choice reaches the save")
	assert_eq(AutoRepeat.patrol_task_id(state), "", "the operation is still player-selectable")
	card.operation_button().pressed.emit()
	var operation_choice := card.operation_choice_button("s_alley")
	assert_true(operation_choice != null, "the legal Alley Patrol operation is offered")
	if operation_choice == null:
		_cleanup(app)
		return
	operation_choice.pressed.emit()

	board = app.get("_task_board")
	card = board.auto_patrol_card() if board != null else null
	assert_true(card != null, "the app rebuilds Missions after the operation choice")
	if card == null:
		_cleanup(app)
		return
	assert_eq(AutoRepeat.patrol_task_id(state), "s_alley", "the operation choice reaches the save")
	assert_false(AutoRepeat.patrol_enabled(state), "choosing does not enable the channel")
	assert_eq(card.status_text(), "OFF", "the configured channel is visibly off")
	card.toggle_button().pressed.emit()
	assert_true(AutoRepeat.patrol_enabled(state), "the toggle enables the saved choice")
	assert_eq(state.assignments.size(), 1, "enabling starts exactly one patrol")
	var assignment: Dictionary = state.assignments.values()[0]
	assert_eq(str(assignment.get("task_id", "")), "s_alley", "the selected operation starts")
	assert_eq(assignment.get("agent_ids", []), ["hero_volt"], "the selected agent starts it")

	# Pause is deliberately separate from cancelling work. It stops the next
	# repeat but leaves the in-flight operation alone; re-enabling cannot add a
	# second deployment for the same hero. Enabling rebuilt the board, so use its
	# current card rather than the pre-enable control that is being replaced.
	board = app.get("_task_board")
	var card_pause: AutoPatrolCard = board.auto_patrol_card() if board != null else null
	assert_true(card_pause != null, "the live card is current after enabling")
	if card_pause == null:
		_cleanup(app)
		return
	card_pause.toggle_button().pressed.emit()
	assert_false(AutoRepeat.patrol_enabled(state), "Pause turns the channel off")
	assert_eq(state.assignments.size(), 1, "Pause does not cancel the live patrol")
	board = app.get("_task_board")
	var card_off: AutoPatrolCard = board.auto_patrol_card() if board != null else null
	assert_true(card_off != null, "the card rebuilds after Pause")
	if card_off == null:
		_cleanup(app)
		return
	assert_eq(card_off.toggle_button().text, "Enable Auto Patrol", "the paused card offers Enable again")
	card_off.toggle_button().pressed.emit()
	assert_true(AutoRepeat.patrol_enabled(state), "Enable turns the saved channel back on")
	assert_eq(state.assignments.size(), 1, "re-enabling does not duplicate the live patrol")

	app.free()
	var restored: GameState = SaveService.load_state(PROFILE_ID).get("state", null)
	assert_true(restored != null, "the enabled patrol is on disk")
	if restored != null:
		assert_eq(AutoRepeat.patrol_task_id(restored), "s_alley", "the operation survives reload")
		assert_eq(AutoRepeat.patrol_agent_id(restored), "hero_volt", "the agent survives reload")
		assert_true(AutoRepeat.patrol_enabled(restored), "the enabled switch survives reload")
		assert_eq(restored.assignments.size(), 1, "the in-flight patrol survives reload")
	SaveService.delete_profile(PROFILE_ID)


func test_nine_hour_absence_settles_only_eight_hours_and_never_pays_twice() -> void:
	var pack := _pack()
	var seed_state := _state(pack)
	seed_state.last_settled_utc = NOW
	var configured := AutoRepeat.configure_patrol(seed_state, pack, "s_alley", "hero_volt")
	assert_true(configured.get("ok", false), "the offline fixture has a legal patrol")
	assert_true(AutoRepeat.set_patrol_enabled(seed_state, true), "the offline fixture is enabled")
	var credits_before := seed_state.resource("credits")
	var late := NOW + 28800 + 3600
	var app := _boot(seed_state, late)
	assert_true(app != null, "the app boots nine hours later")
	if app == null:
		return
	var state: GameState = app.get("_state")
	assert_true(state != null, "the app restores the patrol save")
	if state == null:
		_cleanup(app)
		return
	assert_eq(int(app.get("_settled_seconds")), 28800, "only the eight-hour allowance settles")
	assert_eq(state.last_settled_utc, late, "the capped launch is fully stamped")
	assert_eq(state.tasks_completed(), 1440, "eight hours of twenty-second patrols complete")
	assert_eq(state.assignments.size(), 1, "the live launch re-arms one patrol")
	assert_true(state.resource("credits") > credits_before, "the away patrols paid")
	var credits_after := state.resource("credits")
	var tasks_after := state.tasks_completed()
	app.free()

	var restored: GameState = SaveService.load_state(PROFILE_ID).get("state", null)
	assert_true(restored != null, "the settled patrol reloads")
	if restored == null:
		SaveService.delete_profile(PROFILE_ID)
		return
	assert_eq(restored.tasks_completed(), tasks_after, "the away completion total survives")
	var second := _boot(restored, late)
	assert_true(second != null, "a second launch at the same instant boots")
	if second == null:
		SaveService.delete_profile(PROFILE_ID)
		return
	var second_state: GameState = second.get("_state")
	assert_true(second_state != null, "the second launch restores the same save")
	if second_state != null:
		assert_eq(int(second.get("_settled_seconds")), 0, "a second launch settles no extra time")
		assert_eq(second_state.tasks_completed(), tasks_after, "no completion is paid twice")
		assert_eq(second_state.resource("credits"), credits_after, "no credits are paid twice")
		assert_eq(second_state.assignments.size(), 1, "the existing patrol is not duplicated")
	_cleanup(second)

extends TestCase
## App-level coverage for the HQ operations network.
##
## The panel is intentionally a pure view. These tests verify the app feed that
## drives it: solo and squad activities, progress advancing without rebuilding,
## the completion/reward feed, and the saved reduced-motion preference.

const PACK_ID := "hero_hq"
const PROFILE_ID := "test_app_network"
const NOW := 1000


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
		"attributes": {"power": 10, "speed": 10, "skill": 10},
	}


func _crew_state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 11, NOW)
	state.game_id = PROFILE_ID
	state.resources["credits"] = 500.0
	state.stats["tasks_completed"] = 0
	state.agents["hero_volt"]["attributes"] = {"power": 10, "speed": 10, "skill": 10}
	state.agents["test_striker"] = _agent("test_striker", "striker")
	state.agents["test_support"] = _agent("test_support", "support")
	state.agents["test_tech"] = _agent("test_tech", "tech")
	return state


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
	if app.get("_state") == null:
		app.call("_ready")
	return app


func _cleanup(app: Node) -> void:
	if app != null and is_instance_valid(app):
		app.free()
	SaveService.delete_profile(PROFILE_ID)


func test_network_feed_lists_solo_and_squad_with_live_progress() -> void:
	var pack := _pack()
	var state := _crew_state(pack)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	Simulation.assign_task(state, pack, "s_raid", ["test_striker", "test_support"], NOW)
	var app := _boot(state)
	assert_true(app != null, "the app boots for the network feed case")
	if app == null:
		return
	var panel: HeroNetworkPanel = app.get("_network_panel")
	assert_true(panel != null, "the HQ tab builds the operations network")
	if panel == null:
		_cleanup(app)
		return
	assert_eq(panel.activity_count(), 2, "two running operations reach the network")
	assert_eq(panel.idle_count(), 1, "the idle reserve is counted separately")
	var solo := panel.activity_info(0)
	var squad := panel.activity_info(1)
	assert_eq(str(solo.get("title", "")), "Alley Patrol", "the solo row names its operation")
	assert_false(bool(solo.get("squad", true)), "the solo operation is not drawn as a squad")
	assert_eq(str(squad.get("title", "")), "Joint Raid", "the squad row names its operation")
	assert_true(bool(squad.get("squad", false)), "the squad operation is marked as a squad")
	assert_eq(int(squad.get("agent_count", 0)), 2, "the squad row carries its crew size")
	assert_true(str(squad.get("crew", "")).contains("+1"), "the squad row summarizes its second hero")

	var before := float(solo.get("progress", -1.0))
	var clock := app.get("_clock") as Clock.Manual
	clock.advance(10)
	app.call("_on_tick")
	var updated: HeroNetworkPanel = app.get("_network_panel")
	assert_true(updated != null, "the network survives a normal tick")
	if updated != null:
		var after := float(updated.activity_info(0).get("progress", -1.0))
		assert_true(after > before, "the progress bar advances with the live deadline")
		assert_true(after >= 0.49 and after <= 0.51, "ten seconds of a 20-second job is half done")
	_cleanup(app)


func test_completion_feed_pulses_with_the_paid_reward() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 12, NOW)
	state.game_id = PROFILE_ID
	state.resources["credits"] = 50.0
	state.stats["tasks_completed"] = 0
	var scheduled := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	var assignment_id := str(scheduled.get("assignment_id", ""))
	state.assignments[assignment_id]["ends_utc"] = NOW + 2
	var app := _boot(state)
	assert_true(app != null, "the app boots for the completion pulse case")
	if app == null:
		return
	var panel: HeroNetworkPanel = app.get("_network_panel")
	assert_true(panel != null and panel.activity_count() == 1, "the operation starts on the map")
	var clock := app.get("_clock") as Clock.Manual
	clock.advance(3)
	app.call("_on_tick")
	var live_state: GameState = app.get("_state")
	assert_eq(live_state.assignments.size(), 0, "the completed operation leaves the map")
	assert_eq(live_state.resource("credits"), 68.0, "the normal payout lands once")
	assert_eq(live_state.tasks_completed(), 1, "the completion is counted once")
	var refreshed: HeroNetworkPanel = app.get("_network_panel")
	assert_true(refreshed != null, "the network rebuilds after a completion")
	if refreshed != null:
		assert_eq(refreshed.activity_count(), 0, "no active node remains after completion")
		assert_true(refreshed.completion_visible(), "the brief completion pulse is armed")
		assert_true(
			refreshed.motion_should_run(),
			"the completion pulse keeps animating after the last operation ends",
		)
		assert_true(
			refreshed.completion_text().contains("Alley Patrol"),
			"the pulse names the completed operation",
		)
		assert_true(
			refreshed.completion_text().contains("COMPLETE"),
			"the pulse states completion in text, not colour alone",
		)
	_cleanup(app)


func test_reduced_motion_is_restored_toggled_and_saved() -> void:
	var pack := _pack()
	var state := _crew_state(pack)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	state.extensions["hero_hq.ui"] = {"reduced_motion": true}
	var app := _boot(state)
	assert_true(app != null, "the app boots for the reduced-motion case")
	if app == null:
		return
	var panel: HeroNetworkPanel = app.get("_network_panel")
	var button := app.get("_motion_button") as Button
	assert_true(panel != null, "the operations network is present")
	assert_true(button != null, "the reduced-motion toggle is present")
	if panel == null or button == null:
		_cleanup(app)
		return
	assert_true(panel.is_reduced_motion(), "the saved preference reaches the panel")
	assert_true(button.button_pressed, "the toggle reflects the saved preference")
	assert_true(button.text.contains("on"), "the toggle states reduced motion in text")
	assert_false(panel.animation_is_running(), "reduced motion stops the 5 Hz redraw timer")

	button.button_pressed = false
	button.toggled.emit(false)
	assert_false(panel.is_reduced_motion(), "turning motion back on updates the live panel")
	assert_true(panel.motion_should_run(), "full motion is requested while work is running")
	var saved := SaveService.load_state(PROFILE_ID)
	var restored: GameState = saved.get("state", null)
	assert_true(restored != null, "the preference save round-trips")
	if restored != null:
		var settings: Variant = restored.extensions.get("hero_hq.ui", {})
		assert_true(settings is Dictionary, "the UI extension is written")
		if settings is Dictionary:
			assert_false(bool((settings as Dictionary).get("reduced_motion", true)), "motion-off persists")

	button.button_pressed = true
	button.toggled.emit(true)
	assert_true(panel.is_reduced_motion(), "reduced motion can be re-enabled")
	assert_false(panel.motion_should_run(), "reduced motion stops requesting redraws")
	_cleanup(app)


func test_idle_network_reports_ready_heroes_without_activity() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 13, NOW)
	state.game_id = PROFILE_ID
	var app := _boot(state)
	assert_true(app != null, "the app boots for the idle network case")
	if app == null:
		return
	var panel: HeroNetworkPanel = app.get("_network_panel")
	assert_true(panel != null, "the idle network is present")
	if panel != null:
		assert_eq(panel.activity_count(), 0, "no operation is drawn while idle")
		assert_eq(panel.idle_count(), 1, "the available starter is reported as ready")
		assert_false(panel.completion_visible(), "idle does not show a stale completion")
	_cleanup(app)

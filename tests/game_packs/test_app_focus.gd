extends TestCase
## App-level coverage for the HERO//HQ Focus card.
##
## The card is game-specific, but it is wired through the real composition root
## and saved profile. This proves the projected pulse shown before the tap is
## the deadline change the app actually applies.

const PACK_ID := "hero_hq"
const PROFILE_ID := "test_app_focus"
const TASK_ID := "s_alley"
const NOW := 1000


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack) -> Dictionary:
	var state := Simulation.new_state(pack, 1, NOW)
	state.game_id = PROFILE_ID
	var assignment := Simulation.assign_task(
		state, pack, TASK_ID, ["hero_volt"], NOW
	)
	return {"state": state, "assignment_id": str(assignment.get("assignment_id", ""))}


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


func test_focus_card_pulses_a_running_operation_and_persists() -> void:
	var pack := _pack()
	var setup := _state(pack)
	var app := _boot(setup["state"])
	assert_true(app != null, "the app boots for the Focus case")
	if app == null:
		return
	var assignment_id := str(setup["assignment_id"])
	var state: GameState = app.get("_state")
	var card: HeroFocusCard = app.get("_focus_card")
	assert_true(state != null, "the app restores its live state")
	assert_true(card != null, "the HQ tab builds the Focus card")
	if state == null or card == null:
		_cleanup(app)
		return

	assert_true(card.status_text().contains("5 / 5"), "the card starts at full Focus")
	var button := card.focus_button(assignment_id)
	assert_true(button != null, "the running operation has a Focus button")
	assert_false(button.disabled, "the first pulse is available")
	assert_true(button.text.contains("-3s"), "the button shows the projected time saved")
	var credits := state.resource("credits")
	var tasks := state.tasks_completed()
	button.pressed.emit()

	assert_eq(int(state.assignments[assignment_id]["ends_utc"]), 1017, "the tap applies the shown pulse")
	assert_eq(HeroFocus.current(state, pack, NOW), 4, "the tap spends one Focus")
	assert_eq(state.resource("credits"), credits, "the pulse does not pay a mission")
	assert_eq(state.tasks_completed(), tasks, "the pulse does not complete a mission")

	var refreshed: HeroFocusCard = app.get("_focus_card")
	assert_true(refreshed != null, "the card rebuilds after a pulse")
	if refreshed != null:
		assert_true(refreshed.status_text().contains("4 / 5"), "the rebuilt card shows the new bank")
		var cooled := refreshed.focus_button(assignment_id)
		assert_true(cooled != null, "the rebuilt card keeps the active operation")
		if cooled != null:
			assert_true(cooled.disabled, "the rebuilt card enforces the per-operation cooldown")

	var loaded := SaveService.load_state(PROFILE_ID)
	var restored: GameState = loaded.get("state", null)
	assert_true(restored != null, "the pulsed state was saved")
	if restored != null:
		assert_eq(
			int(restored.assignments[assignment_id]["ends_utc"]),
			1017,
			"the shortened deadline survives a reload",
		)
		assert_eq(HeroFocus.current(restored, pack, NOW), 4, "the spent Focus survives a reload")
	_cleanup(app)

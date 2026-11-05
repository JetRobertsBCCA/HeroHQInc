extends TestCase
## App composition-root coverage for the Command Level slice.
##
## A fresh HQ shows the level-1 milestone and the City lock reason on Missions.
## An existing save that already satisfies level 3 restores without a migration,
## shows the unlocked City milestone, and enables a City operation.

const PACK_ID := "hero_hq"
const PROFILE_ID := "test_app_progression"
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
		"attributes": {"power": 20, "speed": 20, "skill": 20},
	}


func _level_three_state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 7, NOW)
	state.game_id = PROFILE_ID
	state.pack_content_version = 2
	state.stats["tasks_completed"] = 12
	state.stats["earned"] = {"credits": 1500.0}
	state.agents["test_support"] = _agent("test_support", "support")
	state.agents["test_support"]["level"] = 2
	state.agents["test_tech"] = _agent("test_tech", "tech")
	state.agents["test_reserve"] = _agent("test_reserve", "striker")
	return state


func _level_four_state(pack: GamePack) -> GameState:
	var state := _level_three_state(pack)
	state.agents["test_vanguard"] = _agent("test_vanguard", "vanguard")
	state.stats["tasks_completed"] = 40
	state.stats["earned"] = {"credits": 3500.0}
	state.stats["squad_tasks_completed"] = 1
	for agent_id in state.agents.keys():
		state.agents[agent_id]["attributes"] = {"power": 40, "speed": 40, "skill": 40}
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


func test_fresh_hq_shows_level_one_and_missions_explains_the_city_lock() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, NOW)
	state.game_id = PROFILE_ID
	var app := _boot(state)
	assert_true(app != null, "the app boots for the fresh progression case")
	if app == null:
		return

	var card: CommandProgressCard = app.get("_command_card")
	assert_true(card != null, "HQ builds the Command Level card")
	if card == null:
		_cleanup(app)
		return
	assert_eq(card.heading_text(), "Command Level 1", "the card shows the current level")
	assert_true(card.next_text().contains("Command Level 2"), "the card names the next milestone")
	var rows := card.requirement_rows()
	assert_eq(rows.size(), 3, "the level-2 milestone lists its requirements")
	assert_eq(str(rows[0].get("progress", "")), "1 / 3", "the card reports live roster progress")
	assert_eq(card.unlock_text(), "", "level 2 does not claim a City unlock")

	var shell: ScreenShell = app.get("_shell")
	shell.select_tab("missions")
	var board: TaskBoard = app.get("_task_board")
	assert_true(board != null, "the Missions tab builds")
	if board == null:
		_cleanup(app)
		return
	assert_true(board.deploy_button("s_drone").disabled, "a City operation is disabled at level 1")
	var expected := CommandProgression.stage_lock_text(pack, {
		"stage_id": "city",
		"required_command_level": 3,
		"current_command_level": 1,
	})
	assert_eq(board.blocked_reason("s_drone"), expected, "the mission row states the Command Level reason")
	assert_true(board.blocked_reason("s_drone").contains("Citywide Defense"), "the reason names the stage")
	assert_false(board.deploy_button("s_alley").disabled, "Street operations stay available")
	_cleanup(app)


func test_existing_level_three_save_restores_the_city_unlock() -> void:
	var pack := _pack()
	var app := _boot(_level_three_state(pack))
	assert_true(app != null, "the app boots for the existing progress case")
	if app == null:
		return

	var state: GameState = app.get("_state")
	var card: CommandProgressCard = app.get("_command_card")
	assert_true(state != null, "the existing save restores")
	assert_true(card != null, "HQ builds the restored Command Level card")
	if state == null or card == null:
		_cleanup(app)
		return
	assert_eq(state.pack_content_version, 7, "the app stamping the new content version needs no migration")
	assert_eq(state.tasks_completed(), 12, "the existing lifetime counter is preserved")
	assert_true(state.earned_total("credits") >= 1500.0, "existing lifetime earnings are preserved")
	assert_eq(card.heading_text(), "Command Level 3", "the card derives the existing level")
	assert_true(card.next_text().contains("Command Level 4"), "the card names the National milestone")
	assert_true(card.unlock_text().contains("National Response"), "the card names the National unlock")
	assert_true(card.future_text().is_empty(), "there is no unimplemented milestone ahead")
	var rows := card.requirement_rows()
	assert_eq(rows.size(), 5, "the National milestone lists all five requirements")
	assert_eq(
		str(rows[0].get("progress", "")),
		"4 / 5",
		"the card reports the live National roster progress",
	)
	var objective: Dictionary = app.call("_next_objective")
	assert_eq(int(objective.get("step", 0)), 5, "National is the next guidance step")
	assert_true(
		str(objective.get("text", "")).contains("National Response"),
		"HQ points at the National Response milestone",
	)

	var shell: ScreenShell = app.get("_shell")
	shell.select_tab("missions")
	var board: TaskBoard = app.get("_task_board")
	assert_true(board != null, "Missions rebuilds for the existing save")
	if board != null:
		assert_false(board.deploy_button("s_drone").disabled, "the City operation is now deployable")
		assert_eq(board.blocked_reason("s_drone"), "", "the stage lock reason is gone")
		for task_id in ["s_blackout", "s_siege", "s_breach", "s_siegebreak"]:
			assert_true(board.deploy_button(task_id).disabled, "%s is disabled at level 3" % task_id)
			var expected := CommandProgression.stage_lock_text(pack, {
				"stage_id": "national",
				"required_command_level": 4,
				"current_command_level": 3,
			})
			assert_eq(board.blocked_reason(task_id), expected, "%s states the National reason" % task_id)
			assert_true(board.blocked_reason(task_id).contains("National Response"), "%s names National Response" % task_id)
	_cleanup(app)


func test_level_four_save_unlocks_all_national_operations() -> void:
	var pack := _pack()
	var app := _boot(_level_four_state(pack))
	assert_true(app != null, "the app boots for the Level 4 case")
	if app == null:
		return

	var state: GameState = app.get("_state")
	var card: CommandProgressCard = app.get("_command_card")
	assert_true(state != null, "the Level 4 save restores")
	assert_true(card != null, "HQ builds the Level 4 card")
	if state == null or card == null:
		_cleanup(app)
		return
	assert_eq(CommandProgression.current_level(state, pack), 4, "the saved totals derive Level 4")
	assert_true(CommandProgression.stage_unlocked(state, pack, "national"), "National is open")
	assert_eq(card.heading_text(), "Command Level 4", "the card shows the reached level")
	assert_eq(card.next_text(), "", "there is no next implemented milestone")
	assert_true(card.unlock_text().contains("National Response"), "the card reports the National unlock")
	assert_true(card.future_text().contains("later"), "later milestones stay explicit")

	var shell: ScreenShell = app.get("_shell")
	shell.select_tab("missions")
	var board: TaskBoard = app.get("_task_board")
	assert_true(board != null, "Missions rebuilds for Level 4")
	if board != null:
		for task_id in ["s_blackout", "s_siege", "s_breach", "s_siegebreak"]:
			assert_false(board.deploy_button(task_id).disabled, "%s is deployable at level 4" % task_id)
			assert_eq(board.blocked_reason(task_id), "", "%s has no stage reason" % task_id)
	_cleanup(app)

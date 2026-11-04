extends TestCase
## App composition-root coverage for squad deployment.
##
## The Teams screen rebuilds after a deployment. If it reads only an older saved
## preset, it can show a different (even invalid) lineup while the real operation
## runs. This test recovers a role-incomplete preset through the real screen and
## proves the started lineup is both persisted and visible after the rebuild.

const PACK_ID := "hero_hq"
const PROFILE_ID := "test_app_squad_deploy"
const TASK_ID := "s_raid"
const NOW := 1000
const INITIAL_LINEUP := ["hero_volt", "test_ace"]
const RECOVERED_LINEUP := ["hero_volt", "test_support"]


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
		"attributes": {"power": 10, "speed": 9, "skill": 9},
	}


## Volt and Ace are both strong Strikers. Joint Raid needs a Striker and a
## Support, so the saved preset starts blocked even though its rating is high.
func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 9, NOW)
	state.game_id = PROFILE_ID
	state.resources["credits"] = 500.0
	state.stats["tasks_completed"] = 0
	state.upgrades = {}
	state.agents["hero_volt"]["attributes"] = {"power": 10, "speed": 9, "skill": 9}
	state.agents["test_ace"] = _agent("test_ace", "striker")
	state.agents["test_support"] = _agent("test_support", "support")
	Squads.save(state, TASK_ID, INITIAL_LINEUP)
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
	# `SceneTree._initialize` does not dispatch the scene's `_ready` before this
	# synchronous test runs. Call the real boot method if add_child deferred it.
	if app.get("_state") == null:
		app.call("_ready")
	return app


func _cleanup(app: Node) -> void:
	if app != null and is_instance_valid(app):
		app.free()
	SaveService.delete_profile(PROFILE_ID)


func test_successful_squad_deploy_saves_the_started_lineup() -> void:
	var pack := _pack()
	var app := _boot(_state(pack))
	assert_true(app != null, "the app boots for the squad deployment case")
	if app == null:
		return

	var state: GameState = app.get("_state")
	var shell: ScreenShell = app.get("_shell")
	assert_true(state != null, "bootstrap restores the controlled state")
	assert_true(shell != null, "bootstrap builds the shell")
	if state == null or shell == null:
		_cleanup(app)
		return
	shell.select_tab("teams")
	var teams: TeamScreen = app.get("_teams")
	assert_true(teams != null, "the Teams tab builds the squad screen")
	if teams == null:
		_cleanup(app)
		return

	assert_eq(teams.lineup(TASK_ID), INITIAL_LINEUP, "the saved preset seeds the row")
	assert_eq(
		teams.row_reason(TASK_ID),
		pack.label("ui.blocked_missing_role", ""),
		"the initial lineup is blocked by its missing role",
	)
	assert_true(teams.deploy_button(TASK_ID).disabled, "the invalid preset cannot deploy")

	assert_true(
		teams.select_slot_agent(TASK_ID, 1, "test_support"),
		"the missing Support can be selected",
	)
	assert_false(
		teams.deploy_button(TASK_ID).disabled,
		"the recovered lineup enables deployment",
	)
	teams.deploy_button(TASK_ID).pressed.emit()

	assert_eq(state.assignments.size(), 1, "one operation starts")
	if state.assignments.size() == 1:
		var assignment: Dictionary = state.assignments.values()[0]
		assert_eq(assignment.get("task_id", ""), TASK_ID, "the selected operation starts")
		assert_eq(
			assignment.get("agent_ids", []),
			RECOVERED_LINEUP,
			"the active operation uses the recovered lineup",
		)
	assert_eq(
		Squads.member_ids(state, TASK_ID),
		RECOVERED_LINEUP,
		"the started lineup becomes the saved preset",
	)
	assert_eq(state.resource("credits"), 500.0, "deployment consumes no Credits")
	assert_eq(state.tasks_completed(), 0, "deployment does not complete a task")

	var refreshed: TeamScreen = app.get("_teams")
	assert_true(refreshed != null, "the Teams screen rebuilds after deployment")
	if refreshed != null:
		assert_eq(
			refreshed.lineup(TASK_ID),
			RECOVERED_LINEUP,
			"the rebuilt row shows the active lineup, not the stale preset",
		)
		assert_eq(
			refreshed.row_reason(TASK_ID),
			pack.label("ui.blocked_agent_busy", ""),
			"the rebuilt row reports the deployed members instead of a missing role",
		)
	_cleanup(app)

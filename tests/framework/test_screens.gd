extends TestCase
## Headless screen tests: the widgets build, gate their buttons correctly and
## emit the signals the app wires up. No window is required.

const PACK_ID := "hero_hq"


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func test_task_board_lists_every_declared_task() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	assert_eq(board.task_row_count(), pack.missions.size(), "one row per declared task")
	assert_eq(board.active_row_count(), 0, "no active rows before deploying")
	board.free()


func test_task_board_gates_by_rating() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	assert_false(board.deploy_button("s_alley").disabled, "a task within the rating stays enabled")
	assert_true(board.deploy_button("s_rooftop").disabled, "a task above the rating is disabled")
	board.free()


func test_task_board_emits_deploy_requests() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	var received: Array = []
	board.deploy_requested.connect(func(task_id: String) -> void: received.append(task_id))
	board.deploy_button("s_alley").emit_signal("pressed")
	assert_eq(received.size(), 1, "pressing deploy emits exactly one request")
	assert_eq(str(received[0]), "s_alley", "the request names the task")
	board.free()


func test_task_board_shows_running_operations() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	assert_eq(board.active_row_count(), 1, "a running assignment gets its own row")
	assert_eq(board.task_row_count(), pack.missions.size(), "available tasks stay listed")
	board.free()


func test_roster_shows_agents_and_training() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	assert_eq(roster.agent_row_count(), state.agents.size(), "one row per agent")
	assert_false(roster.train_button("hero_volt").disabled, "training is affordable at the start")
	roster.free()


func test_roster_disables_training_without_funds() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.resources["credits"] = 0.0
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	assert_true(roster.train_button("hero_volt").disabled, "training is disabled without funds")
	roster.free()


func test_roster_offers_an_affordable_first_recruit() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	var button := roster.recruit_button()
	assert_true(button != null, "a recruit offer is shown")
	assert_false(button.disabled, "the first recruit is affordable with starting funds")
	var received: Array = []
	roster.recruit_requested.connect(func(role_id: String) -> void: received.append(role_id))
	button.emit_signal("pressed")
	assert_eq(received.size(), 1, "pressing recruit emits exactly one request")
	roster.free()


func test_roster_targets_a_recruit_role() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.resources["credits"] = 1000.0
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	assert_true(roster.recruit_role_option() != null, "the recruit panel offers a role picker")
	roster.select_recruit_role("tech")
	assert_eq(roster.recruit_role(), "tech", "the chosen role sticks")
	var received: Array = []
	roster.recruit_requested.connect(func(role_id: String) -> void: received.append(role_id))
	roster.recruit_button().emit_signal("pressed")
	assert_eq(received.size(), 1, "recruiting emits one request")
	assert_eq(str(received[0]), "tech", "the request carries the chosen role")
	roster.free()


func test_roster_emits_training_requests() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	var received: Array = []
	roster.train_requested.connect(func(agent_id: String) -> void: received.append(agent_id))
	roster.train_button("hero_volt").emit_signal("pressed")
	assert_eq(received.size(), 1, "pressing train emits one request")
	assert_eq(str(received[0]), "hero_volt", "the request names the agent")
	roster.free()


func test_team_screen_lists_only_squad_operations() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	var expected := 0
	for task_id in pack.task_ids():
		if int(pack.task(task_id).get("required_agent_count", 1)) > 1:
			expected += 1
	assert_true(expected > 0, "this pack declares squad operations")
	assert_eq(screen.squad_row_count(), expected, "one row per squad operation")
	screen.free()


func test_team_screen_previews_and_deploys_a_valid_squad() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	assert_true(screen.deploy_button("s_raid").disabled, "a lone starter cannot field a squad")

	# Two strong specialists satisfy Joint Raid's striker + support requirement.
	_add_squad_agents(pack, state)
	screen.refresh(pack, state)
	assert_false(screen.deploy_button("s_raid").disabled, "a valid squad enables the deploy button")
	var received: Array = []
	screen.deploy_requested.connect(func(task_id: String, agent_ids: Array) -> void:
		received.append({"task_id": task_id, "agent_ids": agent_ids})
	)
	screen.deploy_button("s_raid").emit_signal("pressed")
	assert_eq(received.size(), 1, "pressing deploy emits one request")
	var request: Dictionary = received[0]
	assert_eq(str(request.get("task_id", "")), "s_raid", "the request names the squad operation")
	assert_eq((request.get("agent_ids", []) as Array).size(), 2, "the request carries the chosen squad")
	screen.free()


func test_team_screen_saves_and_clears_a_lineup() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	_add_squad_agents(pack, state)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	var save := screen.save_button("s_raid")
	assert_true(save != null, "a squad lineup can be saved")
	save.emit_signal("pressed")
	assert_eq(Squads.member_ids(state, "s_raid").size(), 2, "the saved lineup keeps both members")
	screen.refresh(pack, state)
	var clear := screen.clear_button("s_raid")
	assert_true(clear != null, "a saved lineup can be cleared")
	clear.emit_signal("pressed")
	assert_true(Squads.for_task(state, "s_raid").is_empty(), "clearing removes the preset")
	screen.free()


func _add_squad_agents(pack: GamePack, state: GameState) -> void:
	var attributes: Dictionary = {}
	for attribute in Recruitment.attribute_names(pack):
		attributes[str(attribute)] = 40
	for role_id in ["striker", "support"]:
		var agent_id := "test_%s" % role_id
		state.agents[agent_id] = {
			"id": agent_id,
			"role_id": role_id,
			"level": 1,
			"xp": 0,
			"activity": "available",
			"attributes": attributes.duplicate(true),
		}

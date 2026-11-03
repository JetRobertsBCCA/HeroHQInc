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
	roster.recruit_requested.connect(func() -> void: received.append(1))
	button.emit_signal("pressed")
	assert_eq(received.size(), 1, "pressing recruit emits exactly one request")
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

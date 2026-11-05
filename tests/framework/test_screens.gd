extends TestCase
## Headless screen tests: the widgets build, gate their buttons correctly and
## emit the signals the app wires up. No window is required.

const PACK_ID := "hero_hq"


func _pack() -> GamePack:
	return without_stage_gates(GamePackLoader.load_pack(PACK_ID)["pack"])


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


func test_team_screen_edits_individual_slots() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	_add_squad_agents(pack, state)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	assert_eq(screen.slot_count("s_raid"), 2, "each required hero gets its own slot")
	assert_true(screen.slot_button("s_raid", 0) != null, "slot one renders a picker")
	assert_true(screen.slot_button("s_raid", 1) != null, "slot two renders a picker")
	assert_false(screen.slot_picker_open("s_raid", 0), "the chooser starts closed")
	assert_true(screen.open_slot_picker("s_raid", 0), "a slot opens its inline chooser")
	assert_true(screen.slot_picker_open("s_raid", 0), "the chooser stays under its slot")
	assert_true(screen.slot_choice_button("s_raid", 0, "test_support") != null, "the chooser lists roster agents")
	assert_true(screen.select_slot_agent("s_raid", 0, "test_striker"), "the first slot takes a hero")
	assert_false(screen.select_slot_agent("s_raid", 1, "test_striker"), "a hero cannot fill two slots")
	assert_true(screen.select_slot_agent("s_raid", 1, "test_support"), "the second slot takes another hero")
	assert_eq(screen.lineup("s_raid"), ["test_striker", "test_support"], "the lineup follows the slots")
	assert_false(screen.deploy_button("s_raid").disabled, "a full valid lineup enables deploy")
	var received: Array = []
	screen.deploy_requested.connect(func(task_id: String, agent_ids: Array) -> void:
		received.append({"task_id": task_id, "agent_ids": agent_ids})
	)
	screen.deploy_button("s_raid").pressed.emit()
	assert_eq(received.size(), 1, "pressing deploy emits one request")
	assert_eq((received[0]["agent_ids"] as Array).size(), 2, "the request carries the drafted lineup")
	screen.free()


func test_team_screen_explains_an_empty_slot_and_saves_the_draft() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	_add_squad_agents(pack, state)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	assert_true(screen.select_slot_agent("s_raid", 1, ""), "a slot can be emptied")
	assert_true(screen.deploy_button("s_raid").disabled, "an empty slot blocks deploy")
	assert_eq(
		screen.row_reason("s_raid"),
		pack.label("ui.blocked_squad_incomplete", ""),
		"the empty slot states what to do",
	)
	assert_true(screen.save_button("s_raid").disabled, "an incomplete lineup cannot be saved")
	assert_true(screen.select_slot_agent("s_raid", 1, "test_support"), "the slot can be filled again")
	assert_false(screen.save_button("s_raid").disabled, "a complete lineup can be saved")
	screen.save_button("s_raid").pressed.emit()
	assert_eq(
		Squads.member_ids(state, "s_raid"),
		["test_striker", "test_support"],
		"the drafted lineup is saved",
	)
	screen.refresh(pack, state)
	assert_eq(
		screen.lineup("s_raid"),
		["test_striker", "test_support"],
		"the saved lineup reloads into the slots",
	)
	screen.free()


func test_team_screen_blocks_a_deployed_hero_with_its_reason() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	_add_squad_agents(pack, state)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	screen.select_slot_agent("s_raid", 0, "test_striker")
	screen.select_slot_agent("s_raid", 1, "test_support")
	screen.save_button("s_raid").pressed.emit()
	state.agents["test_striker"]["activity"] = "assigned"
	var deployed: Dictionary = state.agents["test_striker"].duplicate(true)
	deployed["id"] = "test_deployed"
	deployed["activity"] = "assigned"
	state.agents["test_deployed"] = deployed
	screen.refresh(pack, state)
	assert_true(screen.deploy_button("s_raid").disabled, "a deployed hero blocks deploy")
	assert_eq(
		screen.row_reason("s_raid"),
		pack.label("ui.blocked_agent_busy", ""),
		"the row names the deployed hero as the reason",
	)
	assert_false(screen.select_slot_agent("s_raid", 0, "test_deployed"), "a deployed hero cannot be picked")
	screen.open_slot_picker("s_raid", 0)
	var support_choice := screen.slot_choice_button("s_raid", 0, "test_support")
	assert_true(
		support_choice != null and support_choice.disabled,
		"a hero already in the other slot is disabled in the chooser",
	)
	var busy_choice := screen.slot_choice_button("s_raid", 0, "test_deployed")
	assert_true(
		busy_choice != null and busy_choice.disabled,
		"a deployed hero is disabled in the chooser",
	)
	screen.free()


func test_task_board_auto_repeat_banner_is_current_and_clears() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades["ops_automation"] = 1
	_add_squad_agents(pack, state)
	var support: Dictionary = state.agents["test_support"].duplicate(true)
	AutoRepeat.remember(state, "s_raid", ["test_striker", "test_support"])
	state.agents.erase("test_support")
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	var banner := board.auto_repeat_banner()
	assert_true(banner != null and banner.visible, "a configured rule shows its status")
	assert_eq(banner.status_code(), Simulation.ERROR_UNKNOWN_AGENT, "the banner names the missing member")
	assert_true(banner.reason_text().contains("Slot 2"), "the banner names the saved slot")
	assert_true(banner.reason_text().contains("no longer on the roster"), "the reason is explicit")
	var retry := banner.retry_button()
	assert_true(retry != null and retry.visible, "a paused rule offers Retry")
	assert_eq(retry.text, pack.label("ui.auto_repeat_retry", "Retry"), "Retry uses pack copy")
	var retry_requests: Array = []
	board.auto_repeat_retry_requested.connect(func() -> void: retry_requests.append(true))
	retry.pressed.emit()
	assert_eq(retry_requests.size(), 1, "pressing Retry reaches the app once")

	# A retry while the slot is still missing changes nothing and keeps the
	# current reason on screen; it must not silently drop the rule.
	var still_blocked := AutoRepeat.resume(state, pack, 1000)
	assert_false(still_blocked.get("ok", true), "a blocked retry does not start")
	board.refresh(pack, state, 1000)
	assert_eq(banner.status_code(), Simulation.ERROR_UNKNOWN_AGENT, "the reason survives the retry")
	assert_true(banner.reason_text().contains("Slot 2"), "the retried banner still names the slot")
	assert_true(retry.visible, "Retry stays available while still blocked")

	state.agents["test_support"] = support
	board.refresh(pack, state, 1000)
	assert_eq(banner.status_code(), "", "filling the slot clears the refusal")
	assert_false(banner.reason_text().contains("no longer on the roster"), "the old reason is not reused")
	assert_true(banner.status_text().contains("Armed"), "the banner now reads as armed")
	assert_false(retry.visible, "Retry is hidden once the rule is ready")

	var started := AutoRepeat.resume(state, pack, 1000)
	assert_true(started.get("ok", false), "a retry after recovery starts the rule")
	board.refresh(pack, state, 1000)
	assert_eq(banner.status_code(), AutoRepeat.CODE_BUSY, "the started rule reads as waiting")
	assert_true(banner.status_text().contains("Waiting"), "the banner reflects the running job")
	assert_false(retry.visible, "Retry is hidden while the repeated job runs")

	AutoRepeat.forget(state)
	board.refresh(pack, state, 1000)
	assert_false(banner.visible, "removing the rule hides the banner")
	assert_eq(banner.reason_text(), "", "a hidden banner leaves no stale reason")
	board.free()


func test_team_auto_repeat_banner_names_a_locked_slot_and_recovers() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades["ops_automation"] = 1
	_add_squad_agents(pack, state)
	AutoRepeat.remember(state, "s_raid", ["test_striker", "test_support"])
	Simulation.assign_task(state, pack, "s_alley", ["test_support"], 1000)
	var screen := TeamScreen.new()
	screen.refresh(pack, state)
	var banner := screen.auto_repeat_banner()
	assert_eq(banner.status_code(), Simulation.ERROR_AGENT_BUSY, "the banner names the locked slot")
	assert_true(banner.reason_text().contains("Slot 2"), "the banner names the saved slot")
	assert_true(banner.reason_text().contains("Alley Patrol"), "the banner names the locking operation")
	var retry := banner.retry_button()
	assert_true(retry != null and retry.visible, "the locked rule offers Retry")
	var retry_requests: Array = []
	screen.auto_repeat_retry_requested.connect(func() -> void: retry_requests.append(true))
	retry.pressed.emit()
	assert_eq(retry_requests.size(), 1, "the team banner forwards one Retry request")

	# Retry may not steal the slot or schedule a second job while it is locked.
	var blocked := AutoRepeat.resume(state, pack, 1000)
	assert_false(blocked.get("ok", true), "a locked retry does not start")
	assert_eq(state.assignments.size(), 1, "only the blocking job is running")
	screen.refresh(pack, state)
	assert_eq(banner.status_code(), Simulation.ERROR_AGENT_BUSY, "the lock reason survives the retry")
	assert_true(banner.reason_text().contains("Alley Patrol"), "the retried banner still names the lock")
	assert_true(retry.visible, "Retry stays available while still locked")

	Simulation.simulate_delta(state, 30.0, pack)
	var resumed := AutoRepeat.resume(state, pack, 1030)
	assert_true(resumed.get("ok", false), "finishing the other job lets the rule start")
	screen.refresh(pack, state)
	assert_eq(banner.status_code(), AutoRepeat.CODE_BUSY, "the rule's own job reads as waiting")
	assert_false(banner.reason_text().contains("Alley Patrol"), "the previous lock is gone")
	assert_false(banner.reason_text().contains("locked"), "the rule's own job is not called paused")
	assert_true(banner.status_text().contains("Waiting"), "the recovered rule is shown as running")
	assert_false(retry.visible, "Retry is hidden after the rule starts")
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

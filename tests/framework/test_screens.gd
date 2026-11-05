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


func test_task_board_separates_ready_and_locked_operations() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	assert_eq(
		board.ready_row_count() + board.locked_row_count(),
		pack.missions.size(),
		"every operation appears in exactly one board section",
	)
	assert_true(board.ready_row_count() > 0, "the starter has a ready operation")
	assert_true(board.locked_row_count() > 0, "the higher ladder stays visibly locked")
	assert_eq(
		board.deploy_button("s_alley").text,
		pack.label("ui.deploy", "Deploy"),
		"a ready operation keeps its deploy action",
	)
	assert_eq(
		board.deploy_button("s_rooftop").text,
		pack.label("ui.locked", "Locked"),
		"a locked operation shows a locked action instead",
	)
	assert_true(
		board.task_status_text("s_rooftop").contains(pack.label("ui.rating", "Rating").to_upper()),
		"the locked row states the rating gate",
	)
	board.free()


func test_task_board_updates_active_progress_in_place() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var deployed := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	var assignment_id := str(deployed["assignment_id"])
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	assert_eq(board.active_progress(assignment_id), 0, "a fresh operation starts at zero percent")
	assert_eq(
		board.active_countdown(assignment_id),
		"Time left 0:20",
		"the active row starts with the full countdown",
	)
	board.tick(1010)
	assert_eq(board.active_progress(assignment_id), 50, "the bar advances with the one-second tick")
	assert_eq(
		board.active_countdown(assignment_id),
		"Time left 0:10",
		"the countdown shares the same one-second tick",
	)
	board.tick(1020)
	assert_eq(board.active_progress(assignment_id), 100, "the bar reaches full at the deadline")
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


func test_roster_shows_two_affordable_offer_cards() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	var ids := roster.recruit_offer_ids()
	assert_eq(ids.size(), 2, "the Heroes screen shows two offers")
	assert_true(ids[0] != ids[1], "the offers are distinct")
	var enabled := 0
	var first_enabled := ""
	for agent_id in ids:
		var button := roster.recruit_offer_button(agent_id)
		var card := roster.recruit_offer_card(agent_id)
		assert_true(button != null, "offer %s has a hire button" % agent_id)
		assert_true(card != null, "offer %s has a visible card" % agent_id)
		if button != null:
			assert_true(button.text.contains("Credits"), "offer %s shows its exact Credit price" % agent_id)
			if not button.disabled:
				enabled += 1
				if first_enabled.is_empty():
					first_enabled = agent_id
	assert_true(enabled > 0, "at least one offer is affordable with starting funds")
	var received: Array = []
	roster.recruit_requested.connect(func(agent_id: String) -> void: received.append(agent_id))
	roster.recruit_offer_button(first_enabled).emit_signal("pressed")
	assert_eq(received.size(), 1, "pressing one offer emits exactly one request")
	assert_eq(str(received[0]), first_enabled, "the request carries the chosen offer id")
	roster.free()


func test_roster_offer_cards_show_role_tier_attributes_and_price() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	var offers := Recruitment.offers(state, pack)
	assert_eq(offers.size(), 2, "two core offers back the two cards")
	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		var agent_id := str(offer["id"])
		var role_id := str(offer["role_id"])
		var card := roster.recruit_offer_card(agent_id)
		assert_true(card != null, "offer %s has a card" % agent_id)
		if card == null:
			continue
		var role_label := card.find_child("OfferRole_*", true, false) as Label
		var attrs_label := card.find_child("OfferAttrs_*", true, false) as Label
		var fit_label := card.find_child("OfferFit_*", true, false) as Label
		assert_true(role_label != null, "offer %s names its role" % agent_id)
		assert_true(attrs_label != null, "offer %s shows attributes" % agent_id)
		assert_true(fit_label != null, "offer %s explains its roster fit" % agent_id)
		if role_label != null:
			assert_true(role_label.text.contains(pack.label(str(pack.role(role_id).get("name_key", "")), role_id)), "offer %s shows the role name" % agent_id)
			assert_true(role_label.text.contains(pack.label("tiers.%s" % str(offer["tier_id"]), str(offer["tier_id"]))), "offer %s shows the tier" % agent_id)
		if attrs_label != null:
			assert_true(attrs_label.text.contains("Power"), "offer %s shows packed attributes" % agent_id)
		if fit_label != null:
			assert_true(fit_label.text.begins_with("Adds"), "offer %s states what it adds" % agent_id)
		var button := roster.recruit_offer_button(agent_id)
		assert_true(button != null and button.text.contains(str(offer["cost"])), "offer %s exposes its exact cost" % agent_id)
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


func test_auto_patrol_card_is_locked_before_research() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	var card := board.auto_patrol_card()
	assert_true(card != null, "Missions exposes the Auto Patrol card")
	if card == null:
		board.free()
		return
	assert_eq(card.status_text(), pack.label("ui.auto_patrol_locked", "Locked").to_upper(), "the locked state is explicit")
	assert_true(card.reason_text().contains("2"), "the card states the two-Intel price")
	assert_false(card.toggle_button().visible, "no toggle is offered before the research")
	board.free()


func test_auto_patrol_card_collects_only_eligible_solo_choices() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades["ops_patrol"] = 1
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	var card := board.auto_patrol_card()
	assert_true(card != null, "the unlocked card builds")
	if card == null:
		board.free()
		return
	assert_eq(card.status_text(), pack.label("ui.auto_patrol_not_set", "Not set").to_upper(), "an empty channel reads Not set")
	assert_true(card.toggle_button().disabled, "Enable waits for both choices")

	var requests: Array = []
	board.auto_patrol_configure_requested.connect(
		func(task_id: String, agent_id: String) -> void:
			requests.append({"task_id": task_id, "agent_id": agent_id})
	)
	card.agent_button().pressed.emit()
	assert_eq(card.picker_open(), "agent", "the agent chooser opens inline")
	var agent_choice := card.agent_choice_button("hero_volt")
	assert_true(agent_choice != null and not agent_choice.disabled, "the starter agent is offered")
	if agent_choice != null:
		agent_choice.pressed.emit()
	assert_eq(requests.size(), 1, "choosing an agent emits one configuration request")
	if requests.size() == 1:
		assert_eq(str(requests[0]["agent_id"]), "hero_volt", "the request names the agent")
		assert_eq(str(requests[0]["task_id"]), "", "the operation waits for a second choice")

	var configured := AutoRepeat.configure_patrol(state, pack, "s_alley", "hero_volt")
	assert_true(configured.get("ok", false), "the card can show a stored selection")
	board.refresh(pack, state, 1000)
	card = board.auto_patrol_card()
	assert_eq(card.status_text(), pack.label("ui.auto_patrol_off", "Off").to_upper(), "a chosen channel starts off")
	assert_eq(card.toggle_button().text, pack.label("ui.auto_patrol_enable", "Enable Auto Patrol"), "the deliberate Enable action is shown")
	assert_false(card.toggle_button().disabled, "a complete selection can be enabled")
	assert_true(card.summary_text().contains("Alley Patrol"), "the summary names the operation")

	card.operation_button().pressed.emit()
	assert_eq(card.picker_open(), "operation", "the operation chooser opens inline")
	var alley_choice := card.operation_choice_button("s_alley")
	assert_true(alley_choice != null, "the legal solo operation is offered")
	assert_true(card.operation_choice_button("s_drone") == null, "a Command-locked operation is not offered")
	assert_true(card.operation_choice_button("s_raid") == null, "a squad operation is not offered")
	var toggles: Array = []
	board.auto_patrol_enabled_requested.connect(func(enabled: bool) -> void: toggles.append(enabled))
	card.toggle_button().pressed.emit()
	assert_eq(toggles.size(), 1, "Enable emits one request")
	if toggles.size() == 1:
		assert_true(bool(toggles[0]), "the request turns the channel on")
	board.free()


func test_auto_patrol_card_shows_live_and_paused_reasons() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades["ops_patrol"] = 1
	state.agents["hero_volt"]["attributes"] = {"power": 40, "speed": 40, "skill": 40}
	AutoRepeat.configure_patrol(state, pack, "s_alley", "hero_volt")
	AutoRepeat.set_patrol_enabled(state, true)
	var deployed := Simulation.assign_task(state, pack, "s_breakin", ["hero_volt"], 1000)
	assert_true(deployed.get("ok", false), "the chosen agent can be busy on another operation")
	var board := TaskBoard.new()
	board.refresh(pack, state, 1000)
	var card := board.auto_patrol_card()
	assert_true(card != null, "the card builds with a paused channel")
	if card == null:
		board.free()
		return
	assert_eq(card.status_text(), pack.label("ui.auto_patrol_paused", "Paused").to_upper(), "a busy agent reads Paused")
	assert_true(card.reason_text().contains("Break-In Response"), "the paused reason names the blocking operation")
	assert_eq(card.toggle_button().text, pack.label("ui.auto_patrol_disable", "Pause Auto Patrol"), "the player can still pause it")

	Simulation.simulate_delta(state, 30.0, pack)
	board.refresh(pack, state, 1030)
	card = board.auto_patrol_card()
	assert_eq(card.status_text(), pack.label("ui.auto_patrol_armed", "Armed").to_upper(), "freeing the agent re-arms the selection")
	assert_true(card.reason_text().contains("Starts whenever"), "the live reason explains the next start")
	var started := AutoRepeat.resume_patrol(state, pack, 1030)
	assert_true(started.get("ok", false), "the armed channel starts its selected operation")
	board.refresh(pack, state, 1030)
	card = board.auto_patrol_card()
	assert_eq(card.status_text(), pack.label("ui.auto_patrol_patrolling", "Patrolling").to_upper(), "an active patrol reads Patrolling")
	assert_true(card.reason_text().contains("on patrol"), "the live reason says the agent is on patrol")
	assert_eq(board.active_row_count(), 1, "the active operation remains on the board")
	board.free()


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

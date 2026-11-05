extends TestCase
## Command-level milestones and stage access.
##
## These tests use the unmodified HERO//HQ pack. The older framework suites
## open stage gates for fixtures that are testing some other gate; this suite is
## where the actual level and stage boundary is verified.

const PACK_ID := "hero_hq"
const NOW := 1000
const PROFILE_ID := "test_command_progression"


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _agent(agent_id: String, role_id: String, attribute: int = 20) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": attribute, "speed": attribute, "skill": attribute},
	}


func _level_three_state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 3, NOW)
	state.stats["tasks_completed"] = 12
	state.stats["earned"] = {"credits": 1500.0}
	state.agents["test_support"] = _agent("test_support", "support")
	state.agents["test_tech"] = _agent("test_tech", "tech")
	state.agents["test_reserve"] = _agent("test_reserve", "striker")
	return state


func _row(rows: Array, requirement_type: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and str((raw as Dictionary).get("type", "")) == requirement_type:
			return raw
	return {}


func test_fresh_state_is_level_one_and_city_is_locked() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, NOW)
	assert_eq(CommandProgression.current_level(state, pack), 1, "a fresh save starts at level 1")
	assert_eq(CommandProgression.stage_unlock_level(pack, "city"), 3, "City unlocks at level 3")
	assert_false(CommandProgression.stage_unlocked(state, pack, "city"), "City is locked at level 1")

	var evaluation := Simulation.evaluate_assignment(state, pack, "s_drone", ["hero_volt"])
	assert_eq(
		str(evaluation.get("code", "")),
		Simulation.ERROR_STAGE_LOCKED,
		"the simulation refuses a locked City operation",
	)
	assert_eq(int(evaluation.get("required_command_level", 0)), 3, "the refusal names the required level")
	assert_eq(int(evaluation.get("current_command_level", 0)), 1, "the refusal names the current level")
	assert_true(
		CommandProgression.stage_lock_text(pack, evaluation).contains("Command Level 3"),
		"the lock text is explicit",
	)


func test_level_two_shows_the_next_milestone_and_city_requirements() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 2, NOW)
	state.agents["test_one"] = _agent("test_one", "striker", 10)
	state.agents["test_two"] = _agent("test_two", "striker", 10)
	state.stats["tasks_completed"] = 6
	state.stats["earned"] = {"credits": 500.0}

	assert_eq(CommandProgression.current_level(state, pack), 2, "the level-2 milestone is met")
	var next := CommandProgression.next_level(state, pack)
	assert_eq(int(next.get("level", 0)), 3, "level 3 is the next milestone")
	var rows := CommandProgression.requirement_rows(pack, state, next)
	assert_eq(rows.size(), 4, "the next milestone lists all four requirements")
	assert_eq(
		str(_row(rows, CommandProgression.TYPE_OWN_AGENTS).get("progress", "")),
		"3 / 4",
		"the roster requirement is measured against four agents",
	)
	assert_eq(
		str(_row(rows, CommandProgression.TYPE_COMPLETE_TASKS).get("progress", "")),
		"6 / 12",
		"the completion requirement is measured against twelve tasks",
	)
	assert_eq(
		str(_row(rows, CommandProgression.TYPE_EARN_RESOURCE_LIFETIME).get("progress", "")),
		"500 / 1500",
		"the lifetime requirement is measured against the saved total",
	)
	assert_eq(
		str(_row(rows, CommandProgression.TYPE_OWN_ROLE_ANY).get("label", "")),
		"Own a Tech or Support hero",
		"the role requirement separates the localized alternatives",
	)
	assert_eq(
		CommandProgression.unlocked_stage_labels(pack, 3),
		["Citywide Defense"],
		"the HQ card can name the City unlock",
	)
	assert_false(CommandProgression.stage_unlocked(state, pack, "city"), "level 2 does not unlock City")


func test_level_three_role_requirement_is_reachable_and_unlocks_city() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 4, NOW)
	state.resources["credits"] = 1000.0
	state.stats["tasks_completed"] = 12
	state.stats["earned"] = {"credits": 1500.0}
	for index in 3:
		state.agents["test_striker_%d" % index] = _agent(
			"test_striker_%d" % index,
			"striker",
		)

	assert_eq(CommandProgression.current_level(state, pack), 2, "four Strikers do not unlock City")
	var next := CommandProgression.next_level(state, pack)
	var role_row := _row(
		CommandProgression.requirement_rows(pack, state, next),
		CommandProgression.TYPE_OWN_ROLE_ANY,
	)
	assert_eq(str(role_row.get("progress", "")), "0 / 1", "the missing Tech/Support role is visible")
	assert_false(CommandProgression.stage_unlocked(state, pack, "city"), "the role requirement blocks City")

	# Recruitment can target either role, and the State still derives the level
	# from the roster; no saved command field has to be changed.
	var recruited := Recruitment.recruit(state, pack, "support")
	assert_true(recruited.get("ok", false), "a Support hero can be recruited")
	assert_eq(CommandProgression.current_level(state, pack), 3, "the role requirement completes level 3")
	assert_true(CommandProgression.stage_unlocked(state, pack, "city"), "City unlocks immediately")
	var city_agents := Simulation.auto_select_agents(state, pack, "s_drone")
	assert_eq(city_agents.size(), 1, "the City entry operation has a legal candidate")
	var city_evaluation := Simulation.evaluate_assignment(
		state, pack, "s_drone", city_agents
	)
	assert_true(city_evaluation.get("ok", false), "a role-free City entry operation is now deployable")


func test_street_only_progress_can_reach_city() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 5, NOW)
	var start := NOW
	var guard := 0
	while state.earned_total("credits") < 1500.0 and guard < 100:
		var assigned := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], start)
		if not assigned.get("ok", false):
			break
		Simulation.simulate_delta(state, 20.0, pack)
		start += 20
		guard += 1
	assert_true(state.earned_total("credits") >= 1500.0, "Street patrols can reach the lifetime target")
	assert_true(state.tasks_completed() >= 12, "Street patrols can reach the completion target")

	for role_id in ["support", "tech", "vanguard"]:
		var recruited := Recruitment.recruit(state, pack, role_id)
		assert_true(recruited.get("ok", false), "the %s role can be recruited" % role_id)
	assert_eq(state.agents.size(), 4, "the roster target is reachable through recruitment")
	assert_eq(CommandProgression.current_level(state, pack), 3, "Street-only play reaches level 3")
	assert_true(
		CommandProgression.stage_unlocked(state, pack, "city"),
		"City is reachable without any City or Intel step",
	)
	assert_eq(state.earned_total("intel"), 0.0, "the route never required Intel")


func test_existing_save_keeps_progress_without_a_saved_level_field() -> void:
	var pack := _pack()
	var state := _level_three_state(pack)
	state.game_id = PROFILE_ID
	state.pack_content_version = 2
	SaveService.save_state(state)

	var loaded := SaveService.load_state(PROFILE_ID)
	var restored: GameState = loaded.get("state", null)
	assert_true(restored != null, "the pre-command-level save loads")
	if restored != null:
		assert_eq(restored.pack_content_version, 2, "the save keeps its old content version")
		assert_eq(CommandProgression.current_level(restored, pack), 3, "progress is derived from saved totals")
		assert_true(CommandProgression.stage_unlocked(restored, pack, "city"), "City is open on reload")
		assert_eq(restored.stats.get("tasks_completed", 0), 12, "the lifetime counter survives")
		assert_true(restored.earned_total("credits") >= 1500.0, "lifetime earnings survive")
	SaveService.delete_profile(PROFILE_ID)


func test_active_legacy_city_assignment_still_settles() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 6, NOW)
	state.game_id = PROFILE_ID
	state.agents["test_high"] = _agent("test_high", "support")
	state.agents["test_high"]["activity"] = "assigned"
	state.agents["test_high"]["assignment_id"] = "legacy_city"
	state.assignments["legacy_city"] = {
		"id": "legacy_city",
		"task_id": "s_drone",
		"agent_ids": ["test_high"],
		"started_utc": NOW,
		"ends_utc": NOW + 1,
	}
	state.last_settled_utc = NOW
	SaveService.save_state(state)

	var loaded := SaveService.load_state(PROFILE_ID)
	var restored: GameState = loaded.get("state", null)
	assert_true(restored != null, "the save with an active City assignment loads")
	if restored == null:
		SaveService.delete_profile(PROFILE_ID)
		return
	assert_false(CommandProgression.stage_unlocked(restored, pack, "city"), "the old save is still level 1")
	assert_eq(
		str(Simulation.evaluate_assignment(restored, pack, "s_drone", ["hero_volt"]).get("code", "")),
		Simulation.ERROR_STAGE_LOCKED,
		"new City work is refused while locked",
	)
	var credits_before := restored.resource("credits")
	var outcome := Simulation.simulate_delta(restored, 1.0, pack)
	assert_eq((outcome.get("events", []) as Array).size(), 1, "the in-flight legacy assignment still settles")
	assert_true(restored.assignments.is_empty(), "the settled legacy assignment is cleared")
	assert_true(restored.resource("credits") > credits_before, "the legacy completion still pays")
	SaveService.delete_profile(PROFILE_ID)

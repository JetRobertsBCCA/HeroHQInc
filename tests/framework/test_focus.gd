extends TestCase
## HERO//HQ Focus rules: regeneration, pulse bounds, cooldown and persistence.

const PACK_ID := "hero_hq"
const NOW := 1000


func _pack() -> GamePack:
	return without_stage_gates(GamePackLoader.load_pack(PACK_ID)["pack"])


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, NOW)
	state.game_id = "test_focus"
	return state


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


func test_focus_starts_full_and_regenerates_offline() -> void:
	var pack := _pack()
	var state := _state(pack)
	var data := HeroFocus.settle(state, pack, NOW)
	assert_eq(int(data.get("current", 0)), 5, "Focus starts at 5/5")
	var assignment := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	var assignment_id := str(assignment.get("assignment_id", ""))
	assert_true(assignment.get("ok", false), "the test operation starts")

	var pulse := HeroFocus.spend_on_assignment(state, pack, assignment_id, NOW)
	assert_true(pulse.get("ok", false), "a running solo operation accepts a pulse")
	assert_eq(int(pulse.get("saved_seconds", 0)), 3, "15% of 20 seconds saves 3 seconds")
	assert_eq(int(state.assignments[assignment_id]["ends_utc"]), 1017, "the deadline moves once")
	assert_eq(HeroFocus.current(state, pack, NOW), 4, "the pulse spends one Focus")

	assert_eq(HeroFocus.current(state, pack, 1059), 4, "regeneration is not rounded up")
	assert_eq(HeroFocus.current(state, pack, 1060), 5, "one minute restores one Focus")
	assert_eq(HeroFocus.current(state, pack, 5000), 5, "the bank caps at 5")


func test_solo_and_squad_pulses_have_their_declared_caps() -> void:
	var pack := _pack()
	var solo_state := _state(pack)
	var solo_assignment := Simulation.assign_task(
		solo_state, pack, "s_alley", ["hero_volt"], NOW
	)
	var solo_id := str(solo_assignment.get("assignment_id", ""))
	solo_state.assignments[solo_id]["ends_utc"] = 5000
	var solo := HeroFocus.spend_on_assignment(solo_state, pack, solo_id, NOW)
	assert_true(solo.get("ok", false), "the long solo operation accepts a pulse")
	assert_eq(int(solo.get("saved_seconds", 0)), 30, "solo pulses cap at 30 seconds")

	var squad_state := _state(pack)
	squad_state.agents["test_striker"] = _agent("test_striker", "striker")
	squad_state.agents["test_support"] = _agent("test_support", "support")
	var squad_assignment := Simulation.assign_task(
		squad_state, pack, "s_raid", ["test_striker", "test_support"], NOW
	)
	var squad_id := str(squad_assignment.get("assignment_id", ""))
	assert_true(squad_assignment.get("ok", false), "the test squad operation starts")
	squad_state.assignments[squad_id]["ends_utc"] = 5000
	var squad := HeroFocus.spend_on_assignment(squad_state, pack, squad_id, NOW)
	assert_true(squad.get("ok", false), "the long squad operation accepts a pulse")
	assert_eq(int(squad.get("saved_seconds", 0)), 90, "squad pulses cap at 90 seconds")


func test_focus_cooldown_is_per_assignment_and_persists() -> void:
	var pack := _pack()
	var state := _state(pack)
	var assignment := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	var assignment_id := str(assignment.get("assignment_id", ""))
	state.assignments[assignment_id]["ends_utc"] = 5000

	var first := HeroFocus.spend_on_assignment(state, pack, assignment_id, NOW)
	assert_true(first.get("ok", false), "the first pulse succeeds")
	var blocked := HeroFocus.spend_on_assignment(state, pack, assignment_id, NOW)
	assert_false(blocked.get("ok", true), "a second pulse in the cooldown is refused")
	assert_eq(str(blocked.get("code", "")), HeroFocus.CODE_COOLDOWN, "the refusal names the cooldown")
	assert_eq(int(state.assignments[assignment_id]["ends_utc"]), 4970, "the refused pulse moves nothing")
	assert_eq(HeroFocus.current(state, pack, NOW), 4, "the refused pulse spends nothing")

	var restored := GameState.from_dict(state.to_dict())
	var restored_projection := HeroFocus.project(restored, pack, assignment_id, 1005)
	assert_eq(
		str(restored_projection.get("code", "")),
		HeroFocus.CODE_COOLDOWN,
		"the cooldown survives a save round trip",
	)
	assert_eq(HeroFocus.current(restored, pack, 1005), 4, "the spent Focus survives a reload")

	var second := HeroFocus.spend_on_assignment(state, pack, assignment_id, 1010)
	assert_true(second.get("ok", false), "the pulse is available after ten seconds")
	assert_eq(int(second.get("saved_seconds", 0)), 30, "the second pulse uses the same cap")
	assert_eq(int(state.assignments[assignment_id]["ends_utc"]), 4940, "the second deadline moves")
	assert_eq(HeroFocus.current(state, pack, 1010), 3, "the second pulse spends another Focus")


func test_focus_empty_refuses_without_changing_the_deadline() -> void:
	var pack := _pack()
	var state := _state(pack)
	var assignment := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	var assignment_id := str(assignment.get("assignment_id", ""))
	state.assignments[assignment_id]["ends_utc"] = 5000
	state.extensions[HeroFocus.MODULE_ID] = {"current": 0, "last_regen_utc": NOW}

	var blocked := HeroFocus.spend_on_assignment(state, pack, assignment_id, NOW)
	assert_false(blocked.get("ok", true), "an empty Focus bank refuses the pulse")
	assert_eq(str(blocked.get("code", "")), HeroFocus.CODE_EMPTY, "the refusal names empty Focus")
	assert_eq(int(state.assignments[assignment_id]["ends_utc"]), 5000, "the deadline is unchanged")
	assert_eq(HeroFocus.current(state, pack, 1060), 1, "an empty bank regenerates on schedule")


func test_focus_pulse_hastens_one_completion_without_double_payment() -> void:
	var pack := _pack()
	var state := _state(pack)
	var assignment := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	var assignment_id := str(assignment.get("assignment_id", ""))
	var pulse := HeroFocus.spend_on_assignment(state, pack, assignment_id, NOW)
	assert_true(pulse.get("ok", false), "the pulse applies to the starter operation")

	var outcome := Simulation.simulate_delta(state, 17.0, pack)
	assert_eq((outcome.get("events", []) as Array).size(), 1, "the earlier deadline completes once")
	assert_eq(state.tasks_completed(), 1, "one completion is counted")
	assert_eq(state.resource("credits"), 68.0, "one completion pays once")
	assert_eq(state.assignments.size(), 0, "the completed assignment is cleared")
	assert_eq(HeroFocus.current(state, pack, 1017), 4, "the pulse stays spent after completion")

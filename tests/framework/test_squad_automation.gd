extends TestCase
## Squad auto-repeat: the exact lineup survives a reload, resume never substitutes
## an agent, and a missing or busy member blocks the re-arm without paying twice.

const PACK_ID := "hero_hq"
const AUTOMATION_BRANCH := "ops_automation"
const TASK_ID := "s_raid"


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades[AUTOMATION_BRANCH] = 1
	# Three legal members at different ratings: auto-selection would prefer the
	# reserve support, so a test can prove the remembered lineup wins.
	state.agents["test_striker"] = _agent("test_striker", "striker", 9)
	state.agents["test_support"] = _agent("test_support", "support", 9)
	state.agents["test_reserve"] = _agent("test_reserve", "support", 10)
	return state


func _agent(agent_id: String, role_id: String, attribute: int) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": attribute, "speed": attribute, "skill": attribute},
	}


func _lineup() -> Array[String]:
	return ["test_striker", "test_support"]


func _settled_state(pack: GamePack) -> GameState:
	var state := _state(pack)
	var deployed := Simulation.assign_task(state, pack, TASK_ID, _lineup(), 1000)
	assert_true(deployed.get("ok", false), "the baseline squad deploys")
	Simulation.simulate_delta(state, 120.0, pack)
	assert_eq(state.assignments.size(), 0, "the baseline operation settled")
	assert_eq(state.stats.get("tasks_completed", 0), 1, "the baseline paid once")
	return state


func test_a_remembered_squad_lineup_survives_a_reload() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.game_id = "test_squad_automation"
	AutoRepeat.remember(state, TASK_ID, _lineup())
	SaveService.save_state(state)
	var restored: GameState = SaveService.load_state("test_squad_automation").get("state", null)
	assert_true(restored != null, "a state with a squad rule loads back")
	if restored != null:
		assert_eq(AutoRepeat.task_id(restored), TASK_ID, "the task survives JSON")
		assert_eq(AutoRepeat.lineup(restored), _lineup(), "the exact lineup survives JSON")
	SaveService.delete_profile("test_squad_automation")


func test_resume_redeploys_the_remembered_lineup_not_an_auto_pick() -> void:
	var pack := _pack()
	var state := _settled_state(pack)
	var reserve_rating := AgentRules.rating(state.agents["test_reserve"])
	assert_true(reserve_rating > AgentRules.rating(state.agents["test_support"]), "the reserve is stronger")
	AutoRepeat.remember(state, TASK_ID, _lineup())
	var resumed := AutoRepeat.resume(state, pack, 1120)
	assert_true(resumed.get("ok", false), "the remembered squad re-arms")
	assert_eq(state.assignments.size(), 1, "exactly one replacement is scheduled")
	var assignment: Dictionary = state.assignments.values()[0]
	assert_eq(assignment.get("agent_ids", []), _lineup(), "the saved lineup is used verbatim")
	assert_true(AgentRules.is_available(state.agents["test_reserve"]), "the stronger reserve is not substituted")
	assert_false(AgentRules.is_available(state.agents["test_support"]), "the remembered support is locked to the job")
	assert_false(AgentRules.is_available(state.agents["test_striker"]), "the remembered striker is locked to the job")


func test_a_missing_member_blocks_rearm_without_another_payout() -> void:
	var pack := _pack()
	var state := _settled_state(pack)
	AutoRepeat.remember(state, TASK_ID, _lineup())
	state.agents.erase("test_support")
	var credits_before := state.resource("credits")
	var tasks_before := state.tasks_completed()
	var result := AutoRepeat.resume(state, pack, 1120)
	assert_false(result.get("ok", true), "a missing squad member refuses the re-arm")
	assert_eq(state.assignments.size(), 0, "nothing is scheduled")
	assert_eq(state.resource("credits"), credits_before, "no second payout is added")
	assert_eq(state.tasks_completed(), tasks_before, "the completed task is not counted again")
	assert_eq(AutoRepeat.lineup(state), _lineup(), "the rule is kept for a later retry")
	var again := AutoRepeat.resume(state, pack, 1121)
	assert_false(again.get("ok", true), "a second resume still refuses")
	assert_eq(state.resource("credits"), credits_before, "a repeated refusal also pays nothing")


func test_a_busy_member_blocks_rearm_without_another_payout() -> void:
	var pack := _pack()
	var state := _settled_state(pack)
	AutoRepeat.remember(state, TASK_ID, _lineup())
	state.agents["test_support"]["activity"] = "assigned"
	state.agents["test_support"]["assignment_id"] = "other_job"
	var credits_before := state.resource("credits")
	var tasks_before := state.tasks_completed()
	var result := AutoRepeat.resume(state, pack, 1120)
	assert_false(result.get("ok", true), "a busy squad member refuses the re-arm")
	assert_eq(state.assignments.size(), 0, "nothing is scheduled")
	assert_eq(state.resource("credits"), credits_before, "no payout is added")
	assert_eq(state.tasks_completed(), tasks_before, "the task count is unchanged")
	assert_eq(AutoRepeat.lineup(state), _lineup(), "the rule survives the refusal")

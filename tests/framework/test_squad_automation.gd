extends TestCase
## Squad auto-repeat: the exact lineup survives a reload, resume never substitutes
## an agent, and a missing or busy member blocks the re-arm without paying twice.

const PACK_ID := "hero_hq"
const AUTOMATION_BRANCH := "ops_automation"
const TASK_ID := "s_raid"


func _pack() -> GamePack:
	return without_stage_gates(GamePackLoader.load_pack(PACK_ID)["pack"])


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
	var running := AutoRepeat.status(state, pack)
	assert_eq(str(running.get("code", "")), AutoRepeat.CODE_BUSY, "the rule's own job reads as running, not blocked")
	assert_true((running.get("running_task_ids", []) as Array).has(TASK_ID), "the running reason names the repeated task")


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
	var status := AutoRepeat.status(state, pack)
	assert_eq(str(status.get("code", "")), Simulation.ERROR_UNKNOWN_AGENT, "the reason is the missing member")
	assert_eq(int(status.get("slot_index", -1)), 1, "the reason names the missing slot")
	var blocked: Array = status.get("blocked_slots", [])
	assert_eq(blocked.size(), 1, "one saved slot is unavailable")
	if blocked.size() == 1:
		assert_eq(str((blocked[0] as Dictionary).get("state", "")), "missing", "the slot is marked missing")
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
	var status := AutoRepeat.status(state, pack)
	assert_eq(str(status.get("code", "")), Simulation.ERROR_AGENT_BUSY, "the reason is the locked slot")
	var blocked: Array = status.get("blocked_slots", [])
	assert_eq(blocked.size(), 1, "one saved slot is locked")
	if blocked.size() == 1:
		assert_eq(int((blocked[0] as Dictionary).get("index", -1)), 1, "the locked slot is named")
		assert_eq(str((blocked[0] as Dictionary).get("assignment_id", "")), "other_job", "the lock names the operation")


func test_status_names_the_active_job_holding_a_saved_slot() -> void:
	var pack := _pack()
	var state := _settled_state(pack)
	AutoRepeat.remember(state, TASK_ID, _lineup())
	var deployed := Simulation.assign_task(state, pack, "s_alley", ["test_support"], 1120)
	assert_true(deployed.get("ok", false), "the support can be locked to another job")
	var status := AutoRepeat.status(state, pack)
	assert_eq(str(status.get("code", "")), Simulation.ERROR_AGENT_BUSY, "a locked slot is not a generic running wait")
	var blocked: Array = status.get("blocked_slots", [])
	assert_eq(blocked.size(), 1, "the saved slot is reported")
	if blocked.size() == 1:
		assert_eq(str((blocked[0] as Dictionary).get("assignment_id", "")), "task_2", "the lock points at the active assignment")
	assert_eq(AutoRepeat.task_id(state), TASK_ID, "an active job leaves the rule to retry")


func test_status_reports_rating_role_and_count_refusals() -> void:
	var pack := _pack()
	var low := _state(pack)
	low.agents["test_striker"]["attributes"] = {"power": 1, "speed": 1, "skill": 1}
	low.agents["test_support"]["attributes"] = {"power": 1, "speed": 1, "skill": 1}
	AutoRepeat.remember(low, TASK_ID, _lineup())
	var rating := AutoRepeat.status(low, pack)
	assert_eq(str(rating.get("code", "")), Simulation.ERROR_RATING_TOO_LOW, "the rating gate is reported")
	assert_true(float(rating.get("rating", 0.0)) < float(rating.get("required_rating", 0.0)), "the rating values are current")

	var role_state := _state(pack)
	role_state.agents["test_brute"] = _agent("test_brute", "striker", 9)
	AutoRepeat.remember(role_state, TASK_ID, ["test_striker", "test_brute"])
	var role := AutoRepeat.status(role_state, pack)
	assert_eq(str(role.get("code", "")), Simulation.ERROR_MISSING_ROLE, "the role gate is reported")
	assert_true((role.get("missing_role_ids", []) as Array).has("support"), "the missing role is named")

	var count := _state(pack)
	AutoRepeat.remember(count, TASK_ID, ["test_striker"])
	var short := AutoRepeat.status(count, pack)
	assert_eq(str(short.get("code", "")), Simulation.ERROR_AGENT_COUNT, "a short lineup is reported")
	assert_eq(int(short.get("required_agent_count", 0)), 2, "the required slot count is current")
	assert_eq(int(short.get("given_agent_count", 0)), 1, "the saved slot count is current")

	var duplicate := _state(pack)
	AutoRepeat.remember(duplicate, TASK_ID, ["test_striker", "test_striker"])
	var repeated := AutoRepeat.status(duplicate, pack)
	assert_eq(str(repeated.get("code", "")), Simulation.ERROR_UNKNOWN_AGENT, "a duplicated slot is reported")
	assert_true(bool(repeated.get("duplicate", false)), "the status flags the duplicate")
	assert_eq(int(repeated.get("slot_index", -1)), 1, "the status names the repeated slot")


func test_retry_rechecks_a_missing_member_and_starts_one_job() -> void:
	var pack := _pack()
	var state := _settled_state(pack)
	AutoRepeat.remember(state, TASK_ID, _lineup())
	var support: Dictionary = state.agents["test_support"].duplicate(true)
	state.agents.erase("test_support")
	var credits := state.resource("credits")
	var tasks := state.tasks_completed()
	var blocked := AutoRepeat.resume(state, pack, 1120)
	assert_false(blocked.get("ok", true), "retry refuses the missing member")
	assert_eq(state.assignments.size(), 0, "a refused retry schedules nothing")
	assert_eq(state.resource("credits"), credits, "a refused retry pays nothing")
	assert_eq(state.tasks_completed(), tasks, "a refused retry completes nothing")
	assert_eq(AutoRepeat.lineup(state), _lineup(), "a refused retry keeps the lineup")

	state.agents["test_support"] = support
	var retried := AutoRepeat.resume(state, pack, 1121)
	assert_true(retried.get("ok", false), "retry starts once the member is back")
	assert_eq(state.assignments.size(), 1, "recovery schedules exactly one job")
	var assignment: Dictionary = state.assignments.values()[0]
	assert_eq(str(assignment.get("task_id", "")), TASK_ID, "the intended operation starts")
	assert_eq(assignment.get("agent_ids", []), _lineup(), "the exact saved lineup starts")
	assert_eq(state.resource("credits"), credits, "starting the rule pays nothing up front")
	assert_eq(state.tasks_completed(), tasks, "starting the rule completes nothing")

	var again := AutoRepeat.resume(state, pack, 1121)
	assert_false(again.get("ok", true), "a second retry waits for the started job")
	assert_eq(str(again.get("code", "")), AutoRepeat.CODE_BUSY, "the second retry names the running job")
	assert_eq(state.assignments.size(), 1, "a repeated retry cannot schedule a second job")


func test_retry_does_not_bypass_a_locked_slot() -> void:
	var pack := _pack()
	var state := _settled_state(pack)
	AutoRepeat.remember(state, TASK_ID, _lineup())
	var deployed := Simulation.assign_task(state, pack, "s_alley", ["test_support"], 1120)
	assert_true(deployed.get("ok", false), "the support can be locked to another job")
	var credits := state.resource("credits")
	var tasks := state.tasks_completed()
	var blocked := AutoRepeat.resume(state, pack, 1120)
	assert_false(blocked.get("ok", true), "retry refuses the locked slot")
	assert_eq(str(blocked.get("code", "")), Simulation.ERROR_AGENT_BUSY, "the refusal names the lock")
	assert_eq(state.assignments.size(), 1, "retry does not add a second assignment")
	var blocking: Dictionary = state.assignments.values()[0]
	assert_eq(str(blocking.get("task_id", "")), "s_alley", "the original blocking job survives")
	assert_eq(state.resource("credits"), credits, "a locked retry pays nothing")
	assert_eq(state.tasks_completed(), tasks, "a locked retry completes nothing")
	assert_eq(AutoRepeat.lineup(state), _lineup(), "a locked retry keeps the saved lineup")


func test_a_removed_operation_is_forgotten_instead_of_left_stale() -> void:
	var pack := _pack()
	var state := _state(pack)
	AutoRepeat.remember(state, "s_not_in_pack")
	assert_eq(str(AutoRepeat.status(state, pack).get("code", "")), Simulation.ERROR_UNKNOWN_TASK, "the missing operation is reported")
	var result := AutoRepeat.resume(state, pack, 1000)
	assert_false(result.get("ok", true), "the missing operation does not deploy")
	assert_eq(AutoRepeat.task_id(state), "", "an operation that cannot return is dropped")

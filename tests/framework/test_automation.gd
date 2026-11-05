extends TestCase
## Persisted auto-repeat: what survives a reload, and when it may deploy again.

const PACK_ID := "hero_hq"
const AUTOMATION_BRANCH := "ops_automation"


func _pack() -> GamePack:
	return without_stage_gates(GamePackLoader.load_pack(PACK_ID)["pack"])


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades[AUTOMATION_BRANCH] = 1
	return state


func test_a_remembered_task_survives_a_reload() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.game_id = "test_automation"
	AutoRepeat.remember(state, "s_alley")
	SaveService.save_state(state)
	var restored: GameState = SaveService.load_state("test_automation").get("state", null)
	assert_true(restored != null, "a state with an automation rule loads back")
	if restored != null:
		assert_eq(AutoRepeat.task_id(restored), "s_alley", "the chosen task survives JSON")
		# Buying or keeping the research is what makes the rule effective.
		assert_true(
			Research.unlocked(restored, pack, Research.EFFECT_AUTO_REPEAT),
			"the research rank survives too",
		)
	SaveService.delete_profile("test_automation")


func test_resume_deploys_one_operation_after_settlement() -> void:
	var pack := _pack()
	var state := _state(pack)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	Simulation.simulate_delta(state, 20.0, pack)
	assert_eq(state.assignments.size(), 0, "the first operation settled while away")
	AutoRepeat.remember(state, "s_alley")
	var resumed := AutoRepeat.resume(state, pack, 1020)
	assert_true(resumed.get("ok", false), "a free roster re-arms the remembered task")
	assert_eq(state.assignments.size(), 1, "exactly one replacement is scheduled")
	var assignment: Dictionary = state.assignments.values()[0]
	assert_eq(str(assignment.get("task_id", "")), "s_alley", "the replacement is the same task")

	var again := AutoRepeat.resume(state, pack, 1020)
	assert_false(again.get("ok", true), "a second resume waits for the replacement")
	assert_eq(str(again.get("code", "")), AutoRepeat.CODE_BUSY, "the refusal names the running job")
	assert_eq(state.assignments.size(), 1, "no chain of jobs is scheduled")


func test_resume_needs_the_research_and_forgets_a_locked_rule() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.upgrades.erase(AUTOMATION_BRANCH)
	AutoRepeat.remember(state, "s_alley")
	assert_eq(
		str(AutoRepeat.status(state, pack).get("code", "")),
		AutoRepeat.CODE_LOCKED,
		"the status names the missing research",
	)
	var result := AutoRepeat.resume(state, pack, 1000)
	assert_false(result.get("ok", true), "automation is inert without the research")
	assert_eq(str(result.get("code", "")), AutoRepeat.CODE_LOCKED, "the reason is the missing research")
	assert_eq(AutoRepeat.task_id(state), "", "the stale rule is dropped")


func test_an_under_rated_solo_rule_is_kept_and_reports_its_reason() -> void:
	var pack := _pack()
	var state := _state(pack)
	AutoRepeat.remember(state, "s_rooftop")
	var result := AutoRepeat.resume(state, pack, 1000)
	assert_false(result.get("ok", true), "an under-rated task does not deploy")
	assert_eq(state.assignments.size(), 0, "nothing is scheduled on a refusal")
	assert_eq(AutoRepeat.task_id(state), "s_rooftop", "the recoverable rule is kept")
	var status := AutoRepeat.status(state, pack)
	assert_eq(
		str(status.get("code", "")),
		Simulation.ERROR_RATING_TOO_LOW,
		"the status names the rating gate",
	)
	assert_true(float(status.get("rating", 0.0)) < float(status.get("required_rating", 0.0)), "the status carries both ratings")

	# Training the roster past the gate makes the same rule deploy immediately.
	state.agents["hero_volt"]["attributes"] = {"power": 10, "speed": 10, "skill": 10}
	var recovered := AutoRepeat.status(state, pack)
	assert_true(recovered.get("ok", false), "the rule becomes ready after training")
	assert_eq(str(recovered.get("code", "")), "", "a ready rule has no block code")
	var deployed := AutoRepeat.resume(state, pack, 1000)
	assert_true(deployed.get("ok", false), "the recovered rule starts")
	assert_eq(state.assignments.size(), 1, "one operation is scheduled after recovery")

extends TestCase
## Task assignment, settlement, XP and training. Everything runs on a manual
## clock so durations are inputs rather than wall time.

const PACK_ID := "hero_hq"


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack, utc_now: int) -> GameState:
	return Simulation.new_state(pack, 1, utc_now)


func test_rating_comes_from_attributes() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	var agent: Dictionary = state.agents["hero_volt"]
	assert_eq(AgentRules.rating(agent), 70, "5+5+4 attributes rate 70 at 5 points each")
	assert_true(
		AgentRules.rating_value(agent) >= float(pack.task("s_alley").get("minimum_rating", 0)),
		"the starter agent clears the first task's rating gate",
	)


func test_assignment_marks_agents_busy_and_sets_deadline() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	var result := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	assert_true(result.get("ok", false), "a legal assignment is accepted")
	assert_eq(int(result["ends_utc"]), 1020, "a 20 second task ends 20 seconds later")
	assert_eq(state.assignments.size(), 1, "exactly one assignment is recorded")
	assert_eq(str(state.agents["hero_volt"]["activity"]), "assigned", "the agent is marked busy")


func test_busy_agents_cannot_be_reassigned() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	var retry := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	assert_false(retry.get("ok", true), "a busy agent is refused")
	assert_eq(str(retry.get("code", "")), "agent_busy", "the refusal names the reason")
	assert_eq(state.assignments.size(), 1, "no second assignment is recorded")


func test_completion_pays_once_and_frees_agents() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)

	var early := Simulation.simulate_delta(state, 19.0, pack)
	assert_eq((early["events"] as Array).size(), 0, "19 of 20 seconds is not a completion")
	assert_eq(state.resource("credits"), 50.0, "no reward is paid early")

	var finished := Simulation.simulate_delta(state, 1.0, pack)
	var events: Array = finished["events"]
	assert_eq(events.size(), 1, "one completion event is emitted")
	var event: Dictionary = events[0]
	assert_eq(str(event.get("type", "")), "task_completed", "the event names the completion")
	assert_eq(str(event.get("task_id", "")), "s_alley", "the event names the task")
	assert_eq(state.resource("credits"), 68.0, "the reward is paid exactly once")
	assert_eq(state.assignments.size(), 0, "the assignment is cleared")
	assert_eq(str(state.agents["hero_volt"]["activity"]), "available", "the agent is freed")
	assert_eq(state.tasks_completed(), 1, "the lifetime counter advances")
	assert_eq(state.earned_total("credits"), 18.0, "lifetime earnings are tracked")


func test_completion_awards_task_xp() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	Simulation.simulate_delta(state, 20.0, pack)
	assert_eq(float(state.agents["hero_volt"]["xp"]), 8.0, "task XP comes from pack data")
	assert_eq(int(state.agents["hero_volt"]["level"]), 1, "8 XP is far below the 120 XP threshold")


func test_long_absence_is_capped_and_settles_once() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	var outcome := Simulation.simulate_delta(state, 1_000_000.0, pack)
	assert_true(outcome["capped"], "an unbounded absence is capped")
	assert_eq(
		float(outcome["applied_seconds"]),
		pack.max_offline_seconds,
		"settlement stops at the pack's offline allowance",
	)
	assert_eq(state.resource("credits"), 68.0, "the finished task pays once, not repeatedly")


func test_deploy_names_the_blocking_reason() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	var weak := Simulation.deploy(state, pack, "s_rooftop", 1000)
	assert_false(weak.get("ok", true), "a task above the agent's rating is refused")
	assert_eq(str(weak.get("code", "")), "rating_too_low", "the refusal names the rating gate")
	assert_eq(state.assignments.size(), 0, "nothing is scheduled on a refusal")

	var good := Simulation.deploy(state, pack, "s_alley", 1000)
	assert_true(good.get("ok", false), "a task within the rating is accepted")
	assert_eq(state.assignments.size(), 1, "the deployment is scheduled")


func test_training_spends_resources_and_levels_up() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	state.resources["credits"] = 200.0
	var rating_before := AgentRules.rating(state.agents["hero_volt"])

	var first := Simulation.train_agent(state, pack, "hero_volt")
	assert_true(first.get("ok", false), "training succeeds with funds")
	assert_eq(int(first["cost"]), 25, "the first session costs the base price")
	assert_eq(state.resource("credits"), 175.0, "the cost is deducted")
	assert_eq(int(first["level_after"]), 1, "40 XP does not reach the 120 XP threshold")

	Simulation.train_agent(state, pack, "hero_volt")
	var third := Simulation.train_agent(state, pack, "hero_volt")
	assert_eq(int(third["level_before"]), 1, "the third session is still level 1")
	assert_eq(int(state.agents["hero_volt"]["level"]), 2, "120 XP reaches level 2")
	assert_eq(int(state.agents["hero_volt"]["xp"]), 0, "XP carries over exactly")
	assert_eq(
		int(state.agents["hero_volt"]["attributes"]["speed"]),
		7,
		"the striker role's declared growth adds +2 speed",
	)
	assert_true(
		AgentRules.rating(state.agents["hero_volt"]) > rating_before,
		"levelling raises the rating",
	)
	assert_eq(
		int(Simulation.training_cost(state, pack, "hero_volt")),
		35,
		"the next session costs more than the first",
	)


func test_training_requires_resources() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	state.resources["credits"] = 0.0
	var result := Simulation.train_agent(state, pack, "hero_volt")
	assert_false(result.get("ok", true), "training with no funds is refused")
	assert_eq(str(result.get("code", "")), "insufficient_resource", "the refusal names the reason")
	assert_eq(float(state.agents["hero_volt"]["xp"]), 0.0, "no XP is granted on a refusal")


func test_a_save_without_a_roster_is_healed_from_pack_data() -> void:
	var pack := _pack()
	var state := _state(pack, 1000)
	state.agents.clear()
	assert_false(
		Simulation.deploy(state, pack, "s_alley", 1000).get("ok", true),
		"an empty roster cannot deploy anything",
	)
	assert_eq(Simulation.seed_missing_starter_agents(state, pack), 1, "the missing starter is restored")
	assert_true(state.agents.has("hero_volt"), "the roster is usable again")
	assert_true(
		Simulation.deploy(state, pack, "s_alley", 1000).get("ok", false),
		"the healed roster can deploy again",
	)
	assert_eq(Simulation.seed_missing_starter_agents(state, pack), 0, "reseeding is idempotent")


func test_save_round_trip_preserves_running_assignments() -> void:
	var pack := _pack()
	var state := _state(pack, 5000)
	state.game_id = "test_m1_tasks"
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 5000)
	SaveService.save_state(state)

	var loaded := SaveService.load_state("test_m1_tasks")
	var restored: GameState = loaded.get("state", null)
	assert_true(restored != null, "a saved state loads back")
	if restored != null:
		assert_eq(restored.assignments.size(), 1, "the running assignment survives a reload")
		var assignment: Dictionary = restored.assignments[restored.assignments.keys()[0]]
		assert_eq(int(assignment["ends_utc"]), 5020, "deadlines survive JSON as integers")
		assert_eq(
			str(restored.agents["hero_volt"]["activity"]),
			"assigned",
			"the busy flag survives a reload",
		)
		assert_eq(restored.last_settled_utc, 5000, "the settled instant survives")
		var resumed := Simulation.simulate_delta(restored, 20.0, pack)
		assert_eq((resumed["events"] as Array).size(), 1, "the assignment still completes after a reload")
	SaveService.delete_profile("test_m1_tasks")

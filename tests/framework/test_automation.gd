extends TestCase
## Explicit Auto Patrol: the player chooses one hero and one solo operation,
## enables or pauses it, and the selection survives reloads. Refusals must keep
## the choice, never start another job, and never pay a completion twice.

const PACK_ID := "hero_hq"
const PATROL_BRANCH := "ops_patrol"
const SAVE_ID := "test_auto_patrol"


func _pack(gated: bool = false) -> GamePack:
	var pack: GamePack = GamePackLoader.load_pack(PACK_ID)["pack"]
	if gated:
		return pack
	return without_stage_gates(pack)


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.upgrades[PATROL_BRANCH] = 1
	return state


func _agent(agent_id: String, role_id: String, attribute: int = 40) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": attribute, "speed": attribute, "skill": attribute},
	}


func test_selection_survives_reload_and_stays_disabled() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.game_id = SAVE_ID
	var configured := AutoRepeat.configure_patrol(state, pack, "s_alley", "hero_volt")
	assert_true(configured.get("ok", false), "a legal hero and solo operation are stored")
	assert_false(AutoRepeat.patrol_enabled(state), "choosing alone never enables the channel")
	var status := AutoRepeat.patrol_status(state, pack)
	assert_eq(str(status.get("code", "")), AutoRepeat.CODE_DISABLED, "the choice starts paused")
	assert_eq(state.assignments.size(), 0, "configuring does not deploy")

	SaveService.save_state(state)
	var restored: GameState = SaveService.load_state(SAVE_ID).get("state", null)
	assert_true(restored != null, "the selection reloads")
	if restored != null:
		assert_eq(AutoRepeat.patrol_task_id(restored), "s_alley", "the operation survives JSON")
		assert_eq(AutoRepeat.patrol_agent_id(restored), "hero_volt", "the chosen hero survives JSON")
		assert_false(AutoRepeat.patrol_enabled(restored), "the paused state survives JSON")
		assert_eq(
			str(AutoRepeat.patrol_status(restored, pack).get("code", "")),
			AutoRepeat.CODE_DISABLED,
			"a relaunch does not silently turn the choice on",
		)
	SaveService.delete_profile(SAVE_ID)


func test_enable_starts_one_at_a_time_and_pays_each_completion_once() -> void:
	var pack := _pack()
	var state := _state(pack)
	AutoRepeat.configure_patrol(state, pack, "s_alley", "hero_volt")
	assert_true(AutoRepeat.set_patrol_enabled(state, true), "the player can enable the channel")
	var credits_before := state.resource("credits")

	var first := AutoRepeat.resume_patrol(state, pack, 1000)
	assert_true(first.get("ok", false), "an enabled, legal patrol starts")
	assert_eq(state.assignments.size(), 1, "exactly one operation is scheduled")
	var second := AutoRepeat.resume_patrol(state, pack, 1000)
	assert_false(second.get("ok", true), "a second resume waits for the running patrol")
	assert_eq(state.assignments.size(), 1, "a repeated resume cannot chain another job")
	assert_eq(state.tasks_completed(), 0, "starting a patrol pays nothing")
	assert_eq(state.resource("credits"), credits_before, "starting a patrol pays nothing")

	Simulation.simulate_delta(state, 20.0, pack)
	assert_eq(state.tasks_completed(), 1, "the operation completes exactly once")
	assert_true(state.resource("credits") > credits_before, "the completion pays once")
	var after_one := state.resource("credits")

	var restarted := AutoRepeat.resume_patrol(state, pack, 1020)
	assert_true(restarted.get("ok", false), "the next completion re-arms once")
	assert_eq(state.assignments.size(), 1, "one replacement is scheduled")
	Simulation.simulate_delta(state, 20.0, pack)
	assert_eq(state.tasks_completed(), 2, "the replacement completes once")
	assert_true(state.resource("credits") > after_one, "the second completion pays once")


func test_research_stage_rating_role_and_busy_gates_block_a_start() -> void:
	var pack := _pack()
	var locked := Simulation.new_state(pack, 1, 1000)
	AutoRepeat.configure_patrol(locked, pack, "s_alley", "hero_volt")
	AutoRepeat.set_patrol_enabled(locked, true)
	assert_eq(
		str(AutoRepeat.patrol_status(locked, pack).get("code", "")),
		AutoRepeat.CODE_LOCKED,
		"the channel needs its research branch",
	)
	assert_false(AutoRepeat.resume_patrol(locked, pack, 1000).get("ok", true), "locked research never starts")
	assert_eq(locked.assignments.size(), 0, "a locked channel schedules nothing")

	var gated_pack := _pack(true)
	var gated := _state(gated_pack)
	AutoRepeat.configure_patrol(gated, gated_pack, "s_drone", "hero_volt")
	AutoRepeat.set_patrol_enabled(gated, true)
	var stage := AutoRepeat.patrol_status(gated, gated_pack)
	assert_eq(str(stage.get("code", "")), Simulation.ERROR_STAGE_LOCKED, "Command stage gates still apply")
	assert_eq(int(stage.get("required_command_level", 0)), 3, "the stage refusal names the required level")
	assert_false(
		AutoRepeat.resume_patrol(gated, gated_pack, 1000).get("ok", true),
		"stage-locked work does not start",
	)

	var low := _state(pack)
	AutoRepeat.configure_patrol(low, pack, "s_rooftop", "hero_volt")
	AutoRepeat.set_patrol_enabled(low, true)
	var rating := AutoRepeat.patrol_status(low, pack)
	assert_eq(str(rating.get("code", "")), Simulation.ERROR_RATING_TOO_LOW, "the rating gate is reported")
	assert_false(AutoRepeat.resume_patrol(low, pack, 1000).get("ok", true), "under-rated work does not start")

	var wrong_role := _state(pack)
	wrong_role.agents["test_tech"] = _agent("test_tech", "tech", 50)
	AutoRepeat.configure_patrol(wrong_role, pack, "s_stakeout", "test_tech")
	AutoRepeat.set_patrol_enabled(wrong_role, true)
	assert_eq(
		str(AutoRepeat.patrol_status(wrong_role, pack).get("code", "")),
		Simulation.ERROR_MISSING_ROLE,
		"the chosen role must cover the operation",
	)
	assert_false(
		AutoRepeat.resume_patrol(wrong_role, pack, 1000).get("ok", true),
		"a missing role does not start",
	)

	var busy := _state(pack)
	busy.agents["hero_volt"]["attributes"] = {"power": 30, "speed": 30, "skill": 30}
	AutoRepeat.configure_patrol(busy, pack, "s_alley", "hero_volt")
	AutoRepeat.set_patrol_enabled(busy, true)
	var deployed := Simulation.assign_task(busy, pack, "s_rooftop", ["hero_volt"], 1000)
	assert_true(deployed.get("ok", false), "the chosen hero can be locked to another operation")
	var blocked := AutoRepeat.patrol_status(busy, pack)
	assert_eq(str(blocked.get("code", "")), Simulation.ERROR_AGENT_BUSY, "the hero lock is reported")
	assert_eq(str(blocked.get("blocking_task_id", "")), "s_rooftop", "the blocking operation is named")
	assert_false(AutoRepeat.resume_patrol(busy, pack, 1000).get("ok", true), "a busy hero is not stolen")
	assert_eq(busy.assignments.size(), 1, "the patrol adds no second assignment")

	var squad := _state(pack)
	var rejected := AutoRepeat.configure_patrol(squad, pack, "s_raid", "hero_volt")
	assert_false(rejected.get("ok", true), "a squad operation is not a valid patrol")
	assert_eq(str(rejected.get("code", "")), AutoRepeat.CODE_NOT_SOLO, "the refusal explains the solo rule")


func test_eligible_operations_honor_stage_role_and_rating_but_allow_busy_choice() -> void:
	var pack := _pack(true)
	var state := _state(pack)
	state.agents["hero_volt"]["attributes"] = {"power": 40, "speed": 40, "skill": 40}
	var eligible := AutoRepeat.eligible_solo_task_ids(state, pack, "hero_volt")
	assert_true(eligible.has("s_alley"), "an easy solo operation is offered")
	assert_true(eligible.has("s_breakin"), "an unlocked solo operation is offered")
	assert_true(eligible.has("s_stakeout"), "a role-matching solo operation is offered")
	assert_false(eligible.has("s_drone"), "a Command-locked City operation is not offered")
	assert_false(eligible.has("s_raid"), "a squad operation is not offered")

	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	var while_busy := AutoRepeat.eligible_solo_task_ids(state, pack, "hero_volt")
	assert_true(while_busy.has("s_breakin"), "the picker stays usable while the hero is deployed")
	assert_true(AgentRules.is_available(state.agents["hero_volt"]) == false, "the probe restores the hero lock")


func test_legacy_solo_rule_becomes_a_disabled_draft_and_squads_are_untouched() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.automation_rules = [
		{"type": AutoRepeat.RULE_TYPE, "task_id": "s_alley"},
		{"type": AutoRepeat.RULE_TYPE, "task_id": "s_raid", "agent_ids": ["hero_volt"]},
	]
	assert_eq(AutoRepeat.task_id(state), "s_raid", "the squad rule remains visible")
	assert_true(AutoRepeat.migrate_legacy_solo(state), "the legacy solo rule is migrated")
	assert_eq(AutoRepeat.patrol_task_id(state), "s_alley", "its operation is kept as a draft")
	assert_eq(AutoRepeat.patrol_agent_id(state), "", "no hero is chosen on the player's behalf")
	assert_false(AutoRepeat.patrol_enabled(state), "the migrated draft is disabled")
	assert_eq(AutoRepeat.task_id(state), "s_raid", "the squad rule survives migration")
	assert_eq(AutoRepeat.lineup(state), ["hero_volt"], "the squad lineup survives migration")
	assert_eq(state.assignments.size(), 0, "migration starts nothing")


func test_offline_patrol_stops_at_the_cap_and_is_not_paid_twice() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.game_id = SAVE_ID
	state.last_settled_utc = 1000
	AutoRepeat.configure_patrol(state, pack, "s_alley", "hero_volt")
	AutoRepeat.set_patrol_enabled(state, true)
	var credits_before := state.resource("credits")
	var requested_now := 1000 + 28800 + 3600

	var outcome := AutoRepeat.settle_absence(state, pack, requested_now)
	assert_true(bool(outcome.get("capped", false)), "an over-long absence reports the cap")
	assert_eq(int(outcome.get("applied_seconds", 0)), 28800, "only eight hours are settled")
	assert_eq(state.last_settled_utc, requested_now, "the launch instant becomes the new stamp")
	assert_eq(state.tasks_completed(), 1440, "twenty-second patrols fill exactly eight hours")
	assert_eq(int(outcome.get("patrol_starts", 0)), 1440, "each completed patrol was re-armed once")
	assert_true(state.resource("credits") > credits_before, "the away operations paid")
	var credits_after := state.resource("credits")
	var tasks_after := state.tasks_completed()
	assert_eq(state.assignments.size(), 0, "no assignment is left to settle twice")

	SaveService.save_state(state)
	var restored: GameState = SaveService.load_state(SAVE_ID).get("state", null)
	assert_true(restored != null, "the settled patrol state reloads")
	if restored != null:
		assert_eq(restored.last_settled_utc, requested_now, "the capped stamp survives the reload")
		assert_eq(restored.tasks_completed(), tasks_after, "the completion total survives the reload")
		var again := AutoRepeat.settle_absence(restored, pack, requested_now)
		assert_eq(int(again.get("applied_seconds", -1)), 0, "a second settlement at the same instant adds no time")
		assert_eq(restored.tasks_completed(), tasks_after, "no completion is paid twice")
		assert_eq(restored.resource("credits"), credits_after, "no credits are paid twice")
	SaveService.delete_profile(SAVE_ID)


func test_auto_patrol_research_is_funded_by_the_early_city_payout() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.resources["intel"] = 2.0
	assert_eq(AutoRepeat.patrol_branch_id(pack), PATROL_BRANCH, "the pack declares one patrol branch")
	assert_eq(
		int((pack.task("s_breakin").get("rewards", {}) as Dictionary).get("intel", 0)),
		2,
		"Break-In Response alone funds the first patrol",
	)
	assert_eq(AutoRepeat.patrol_unlock_cost(state, pack), 2, "the branch costs the early two Intel")
	var bought := Research.buy(state, pack, PATROL_BRANCH)
	assert_true(bought.get("ok", false), "the early payout buys the branch")
	assert_true(
		Research.unlocked(state, pack, Research.EFFECT_AUTO_PATROL),
		"the purchase unlocks Auto Patrol",
	)
	assert_eq(state.resource("intel"), 0.0, "the early choose-to-idle unlock spends the first Intel")

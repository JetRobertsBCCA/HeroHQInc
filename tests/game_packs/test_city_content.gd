extends TestCase
## City content invariants: the high-rating solo belongs to a role, and the
## first squad operation pays better than the best Support/Striker solo pair.

const PACK_ID := "hero_hq"
const NOW := 1000


func _pack() -> GamePack:
	return without_stage_gates(GamePackLoader.load_pack(PACK_ID)["pack"])


func _agent(agent_id: String, role_id: String, attributes: Dictionary) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": attributes,
	}


func _city_state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, NOW)
	state.agents["test_support"] = _agent(
		"test_support", "support", {"power": 10, "speed": 10, "skill": 9}
	)
	state.agents["test_striker"] = _agent(
		"test_striker", "striker", {"power": 9, "speed": 8, "skill": 8}
	)
	state.agents["test_ace_striker"] = _agent(
		"test_ace_striker", "striker", {"power": 10, "speed": 10, "skill": 9}
	)
	return state


func _rate(pack: GamePack, task_id: String, resource_id: String) -> float:
	var task := pack.task(task_id)
	var rewards: Dictionary = task.get("rewards", {})
	var seconds := float(maxi(int(task.get("base_seconds", 1)), 1))
	return float(rewards.get(resource_id, 0)) / seconds


func test_convoy_is_a_support_payoff_and_raid_keeps_its_team_gate() -> void:
	var pack := _pack()
	var state := _city_state(pack)

	assert_eq(
		pack.task("s_convoy").get("required_role_ids", []),
		["support"],
		"Convoy is the Support's high-rating solo",
	)
	var convoy := Simulation.evaluate_assignment(state, pack, "s_convoy", ["test_support"])
	assert_true(convoy.get("ok", false), "a 145 Support can run Convoy")

	var ace_striker := Simulation.evaluate_assignment(
		state, pack, "s_convoy", ["test_ace_striker"]
	)
	assert_eq(
		str(ace_striker.get("code", "")),
		Simulation.ERROR_MISSING_ROLE,
		"a rating-eligible Striker cannot take the Support's Convoy",
	)

	var raid_task := pack.task("s_raid")
	assert_eq(int(raid_task.get("required_agent_count", 0)), 2, "Joint Raid stays a two-hero job")
	assert_eq(int(raid_task.get("minimum_rating", 0)), 130, "Joint Raid keeps its rating gate")
	assert_eq(
		raid_task.get("required_role_ids", []),
		["striker", "support"],
		"Joint Raid keeps its Striker and Support requirement",
	)
	var raid := Simulation.evaluate_assignment(
		state, pack, "s_raid", ["test_striker", "test_support"]
	)
	assert_true(raid.get("ok", false), "a 125 Striker and 145 Support clear the squad gate")


func test_raid_out_earns_the_support_striker_solo_pair() -> void:
	var pack := _pack()
	var raid_credits := _rate(pack, "s_raid", "credits")
	var solo_credits := _rate(pack, "s_convoy", "credits") + _rate(pack, "s_rooftop", "credits")
	var raid_intel := _rate(pack, "s_raid", "intel")
	var solo_intel := _rate(pack, "s_convoy", "intel") + _rate(pack, "s_rooftop", "intel")

	assert_true(
		raid_credits > solo_credits,
		"Joint Raid out-earns Convoy plus Rooftop (%.3f vs %.3f Credits/s)" % [
			raid_credits, solo_credits,
		],
	)
	assert_true(
		raid_intel > solo_intel,
		"Joint Raid also yields more Intel (%.3f vs %.3f Intel/s)" % [
			raid_intel, solo_intel,
		],
	)

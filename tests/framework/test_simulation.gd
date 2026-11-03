extends TestCase
## Framework-generic simulation and clock tests. No title identifiers appear
## here: the pack is built inline, exactly as a second game's pack would be.

const CAP_SECONDS := 100.0


func _make_pack() -> GamePack:
	var pack := GamePack.new()
	pack.game_id = "fixture_pack"
	pack.content_version = 3
	pack.max_offline_seconds = CAP_SECONDS
	pack.starting_resources = {"tokens": 5, "shards": 1}
	pack.starter_agents = {
		"agent_one": {"id": "agent_one", "role_id": "role_a", "level": 1, "xp": 0},
	}
	return pack


func _make_state(utc: int = 1000) -> GameState:
	return Simulation.new_state(_make_pack(), 7, utc)


func test_new_state_seeds_from_pack_data() -> void:
	var pack := _make_pack()
	var state := Simulation.new_state(pack, 7, 1000)
	assert_eq(state.game_id, "fixture_pack", "state is scoped to the pack game id")
	assert_eq(state.pack_content_version, 3, "content version is copied")
	assert_eq(state.last_settled_utc, 1000, "settlement stamp starts at the supplied time")
	assert_eq(state.resources, {"tokens": 5, "shards": 1}, "starting resources come from the pack")
	assert_true(state.agents.has("agent_one"), "starter agents are seeded from pack data")
	assert_eq(state.save_schema_version, GameState.SAVE_SCHEMA_VERSION, "save schema is stamped")


func test_simulation_is_deterministic_for_same_inputs() -> void:
	var first := Simulation.simulate_delta(_make_state(), 30.0, _make_pack())
	var second := Simulation.simulate_delta(_make_state(), 30.0, _make_pack())
	assert_eq(first["applied_seconds"], second["applied_seconds"], "same input, same advance")
	assert_eq(first["state"].to_dict(), second["state"].to_dict(), "same input, same state")


func test_negative_elapsed_never_subtracts_progress() -> void:
	var state := _make_state()
	var outcome := Simulation.simulate_delta(state, -500.0, _make_pack())
	assert_eq(outcome["applied_seconds"], 0.0, "negative elapsed clamps to zero")
	assert_eq(outcome["state"].last_settled_utc, 1000, "clock did not move backwards")
	assert_false(outcome["capped"], "a backward clock is not a capped absence")


func test_elapsed_time_is_capped_by_the_pack_allowance() -> void:
	var outcome := Simulation.simulate_delta(_make_state(), CAP_SECONDS * 5.0, _make_pack())
	assert_eq(outcome["applied_seconds"], CAP_SECONDS, "absence is capped at the pack allowance")
	assert_true(outcome["capped"], "capping is reported to the caller")
	assert_eq(outcome["requested_seconds"], CAP_SECONDS * 5.0, "requested time is preserved for reporting")
	assert_eq(outcome["state"].last_settled_utc, 1000 + int(CAP_SECONDS), "settlement advanced by the capped amount")


func test_zero_elapsed_is_a_noop() -> void:
	var state := _make_state()
	var before := state.to_dict()
	var outcome := Simulation.simulate_delta(state, 0.0, _make_pack())
	assert_eq(outcome["state"].to_dict(), before, "zero elapsed leaves state untouched")


func test_state_round_trips_through_serialisation() -> void:
	var state := _make_state()
	state.agents["agent_two"] = {"id": "agent_two", "role_id": "role_b", "level": 4, "xp": 12}
	state.upgrades = {"upgrade_a": 2}
	state.extensions = {"module_x": {"counter": 3}}
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(restored.to_dict(), state.to_dict(), "to_dict/from_dict is lossless")
	assert_eq(restored.game_id, state.game_id, "game id survives the round trip")


func test_manual_clock_advances_on_demand() -> void:
	var clock := Clock.Manual.new(500)
	assert_eq(clock.now_utc(), 500, "manual clock starts at the given time")
	clock.advance(120)
	assert_eq(clock.now_utc(), 620, "manual clock only moves when told to")
	assert_eq(clock.monotonic_seconds(), 120.0, "monotonic counter tracks advances")

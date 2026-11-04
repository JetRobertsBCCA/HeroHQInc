extends TestCase
## Saved squad presets: validation, per-task lookup, removal and save round-trip.

const PACK_ID := "hero_hq"


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.agents["test_striker"] = {"id": "test_striker", "role_id": "striker", "level": 1}
	state.agents["test_support"] = {"id": "test_support", "role_id": "support", "level": 1}
	return state


func test_saving_a_squad_keeps_it_per_task() -> void:
	var pack := _pack()
	var state := _state(pack)
	var result := Squads.save(state, "s_raid", ["test_striker", "test_support"])
	assert_true(result.get("ok", false), "a valid squad saves")
	assert_eq(Squads.member_ids(state, "s_raid").size(), 2, "both members are kept")
	assert_eq(Squads.member_ids(state, "s_blackout").size(), 0, "presets are scoped to their task")


func test_a_squad_rejects_bad_members() -> void:
	var pack := _pack()
	var state := _state(pack)
	assert_eq(
		str(Squads.save(state, "s_raid", []).get("code", "")),
		Squads.ERROR_EMPTY,
		"an empty squad is refused",
	)
	assert_eq(
		str(Squads.save(state, "s_raid", ["nobody"]).get("code", "")),
		Squads.ERROR_UNKNOWN_AGENT,
		"an unknown agent is refused",
	)
	assert_eq(
		str(Squads.save(state, "s_raid", ["test_striker", "test_striker"]).get("code", "")),
		Squads.ERROR_DUPLICATE,
		"a duplicate agent is refused",
	)
	assert_true(Squads.for_task(state, "s_raid").is_empty(), "a refused squad writes nothing")


func test_clearing_removes_the_preset() -> void:
	var pack := _pack()
	var state := _state(pack)
	Squads.save(state, "s_raid", ["test_striker", "test_support"])
	assert_true(Squads.clear(state, "s_raid"), "a saved preset can be cleared")
	assert_true(Squads.for_task(state, "s_raid").is_empty(), "the preset is gone")
	assert_false(Squads.clear(state, "s_raid"), "clearing twice is a no-op")


func test_a_saved_squad_survives_a_reload() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.game_id = "test_squads"
	Squads.save(state, "s_raid", ["test_striker", "test_support"])
	SaveService.save_state(state)
	var restored: GameState = SaveService.load_state("test_squads").get("state", null)
	assert_true(restored != null, "a state with a preset loads back")
	if restored != null:
		assert_eq(Squads.member_ids(restored, "s_raid").size(), 2, "the preset survives JSON")
	SaveService.delete_profile("test_squads")


func test_members_removed_from_the_roster_drop_out() -> void:
	var pack := _pack()
	var state := _state(pack)
	Squads.save(state, "s_raid", ["test_striker", "test_support"])
	state.agents.erase("test_support")
	assert_eq(Squads.member_ids(state, "s_raid").size(), 1, "a departed agent is skipped")

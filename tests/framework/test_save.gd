extends TestCase
## Save isolation, atomic write, backup recovery and schema guards.

const GAME_A := "fixture_save_a"
const GAME_B := "fixture_save_b"


func _make_state(game_id: String, tokens: int) -> GameState:
	var state := GameState.new()
	state.game_id = game_id
	state.resources = {"tokens": tokens}
	state.last_settled_utc = 123
	state.agents = {"agent_one": {"id": "agent_one", "role_id": "role_a", "level": 1}}
	return state


func test_save_and_load_round_trip() -> void:
	SaveService.delete_profile(GAME_A)
	assert_false(SaveService.has_save(GAME_A), "starts with no profile")
	var write := SaveService.save_state(_make_state(GAME_A, 42))
	assert_eq(write["error"], "", "save succeeds")
	assert_true(SaveService.has_save(GAME_A), "profile now exists")
	var loaded := SaveService.load_state(GAME_A)
	assert_eq(loaded["error"], "", "load succeeds without errors")
	var state: GameState = loaded["state"]
	assert_eq(state.game_id, GAME_A, "loaded state keeps its game id")
	assert_eq(state.resource("tokens"), 42.0, "resource amounts survive the round trip")
	SaveService.delete_profile(GAME_A)


func test_profiles_are_scoped_by_game_id() -> void:
	SaveService.delete_profile(GAME_A)
	SaveService.delete_profile(GAME_B)
	SaveService.save_state(_make_state(GAME_A, 10))
	assert_false(SaveService.has_save(GAME_B), "another game id sees no profile")
	var missing := SaveService.load_state(GAME_B)
	assert_eq(missing["error"], "not_found", "unknown game id reports not_found")
	SaveService.delete_profile(GAME_A)


func test_save_declaring_another_game_id_is_rejected() -> void:
	SaveService.delete_profile(GAME_B)
	assert_true(
		SaveService.profile_path(GAME_B).get_base_dir().length() > 0,
		"profile path is derivable"
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveService.profile_path(GAME_B).get_base_dir()))
	var file := FileAccess.open(SaveService.profile_path(GAME_B), FileAccess.WRITE)
	assert_true(file != null, "test can write a foreign save")
	file.store_string(JSON.stringify(_make_state(GAME_A, 5).to_dict()))
	file.close()
	var result := SaveService.load_state(GAME_B)
	assert_eq(result["error"], "game_id_mismatch", "a save for another game is refused")
	assert_true(result["state"] == null, "no state leaks across game ids")
	SaveService.delete_profile(GAME_B)


func test_backup_is_used_when_primary_is_corrupt() -> void:
	SaveService.delete_profile(GAME_A)
	SaveService.save_state(_make_state(GAME_A, 11))
	var second := SaveService.save_state(_make_state(GAME_A, 99))
	assert_eq(second["error"], "", "second save succeeds")
	var corrupt := FileAccess.open(SaveService.profile_path(GAME_A), FileAccess.WRITE)
	assert_true(corrupt != null, "test can corrupt the primary profile")
	corrupt.store_string("{ this is not json")
	corrupt.close()
	var recovered := SaveService.load_state(GAME_A)
	assert_eq(recovered["error"], "", "load falls back instead of failing")
	var state: GameState = recovered["state"]
	assert_eq(state.resource("tokens"), 11.0, "backup holds the previous settlement")
	SaveService.delete_profile(GAME_A)


func test_newer_schema_is_rejected() -> void:
	SaveService.delete_profile(GAME_A)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveService.profile_path(GAME_A).get_base_dir()))
	var future := _make_state(GAME_A, 1).to_dict()
	future["save_schema_version"] = GameState.SAVE_SCHEMA_VERSION + 1
	var file := FileAccess.open(SaveService.profile_path(GAME_A), FileAccess.WRITE)
	assert_true(file != null, "test can write a future save")
	file.store_string(JSON.stringify(future))
	file.close()
	var result := SaveService.load_state(GAME_A)
	assert_eq(result["error"], "newer_schema", "a newer save schema is not loaded blindly")
	SaveService.delete_profile(GAME_A)


func test_state_without_game_id_is_not_written() -> void:
	var orphan := GameState.new()
	var result := SaveService.save_state(orphan)
	assert_eq(result["error"], "missing_game_id", "an unscoped state cannot be saved")

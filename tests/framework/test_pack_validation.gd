extends TestCase
## Pack validation tests. Fixtures are written to user:// so the negatives never
## touch the real game packs.

const FIXTURE_ROOT := "user://test_packs"


func _base_files(game_id: String) -> Dictionary:
	var theme := {}
	for token in ThemeTokens.REQUIRED_TOKENS:
		theme[token] = "#112233"
	return {
		"manifest.json": {
			"pack_schema_version": 1,
			"game_id": game_id,
			"content_version": 1,
			"display_name_key": "game.title",
			"default_locale": "en",
			"mechanics": ["agents", "training"],
			"resources": ["tokens"],
			"max_offline_seconds": 3600,
			"navigation": [{"id": "main", "label_key": "tabs.main"}],
			"data_paths": {
				"roles": "data/roles.json",
				"missions": "data/missions.json",
				"progression": "data/progression.json",
				"agents": "data/agents.json"
			},
			"locale_path": "locale/en.json",
			"theme_path": "ui/theme.json"
		},
		"data/roles.json": [
			{"id": "role_a", "name_key": "roles.role_a", "growth": {"power": 1}}
		],
		"data/missions.json": [
			{
				"id": "task_one",
				"name_key": "tasks.task_one",
				"kind": "solo",
				"stage_id": "stage_one",
				"category_id": "category_one",
				"base_seconds": 20,
				"required_agent_count": 1,
				"minimum_rating": 10,
				"required_role_ids": [],
				"rewards": {"tokens": 5}
			}
		],
		"data/progression.json": {
			"stages": [{"id": "stage_one", "name_key": "stages.stage_one"}],
			"categories": [{"id": "category_one", "name_key": "categories.category_one"}],
			"command_levels": [{"level": 1, "name_key": "command.level_1", "requirements": []}]
		},
		"data/agents.json": {
			"starting_agents": [
				{
					"id": "agent_one",
					"name_key": "agents.agent_one",
					"role_id": "role_a",
					"level": 1,
					"xp": 0,
					"attributes": {"power": 3}
				}
			]
		},
		"locale/en.json": {
			"game.title": "Fixture Pack",
			"tabs.main": "Main",
			"roles.role_a": "Role A",
			"tasks.task_one": "Task One",
			"stages.stage_one": "Stage One",
			"categories.category_one": "Category One",
			"command.level_1": "Level One",
			"resources.tokens": "Tokens",
			"agents.agent_one": "Agent One"
		},
		"ui/theme.json": theme
	}


func _write_fixture(game_id: String, files: Dictionary) -> String:
	var root := "%s/%s" % [FIXTURE_ROOT, game_id]
	_remove_fixture(game_id)
	for relative_path in files.keys():
		var full_path := root.path_join(str(relative_path))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(full_path.get_base_dir()))
		var file := FileAccess.open(full_path, FileAccess.WRITE)
		assert_true(file != null, "fixture file writable: %s" % full_path)
		file.store_string(JSON.stringify(files[relative_path], "\t"))
		file.close()
	return root


func _remove_fixture(game_id: String) -> void:
	var root := "%s/%s" % [FIXTURE_ROOT, game_id]
	_remove_tree(root)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))
	for sub_directory in directory.get_directories():
		_remove_tree(path.path_join(sub_directory))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_valid_fixture_produces_no_errors() -> void:
	var root := _write_fixture("fixture_valid", _base_files("fixture_valid"))
	assert_eq(PackValidator.validate_pack_root(root), [], "a contract-following pack validates")
	_remove_fixture("fixture_valid")


func test_missing_manifest_is_reported() -> void:
	var root := "%s/%s" % [FIXTURE_ROOT, "fixture_no_manifest"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"manifest_missing",
		"a pack without a manifest is rejected"
	)
	_remove_fixture("fixture_no_manifest")


func test_unsupported_schema_version_is_reported() -> void:
	var files := _base_files("fixture_schema")
	(files["manifest.json"] as Dictionary)["pack_schema_version"] = 99
	var root := _write_fixture("fixture_schema", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"unsupported_schema_version",
		"unknown pack schema versions are refused"
	)
	_remove_fixture("fixture_schema")


func test_data_path_escaping_the_pack_is_reported() -> void:
	var files := _base_files("fixture_escape")
	((files["manifest.json"] as Dictionary)["data_paths"] as Dictionary)["roles"] = "../outside.json"
	var root := _write_fixture("fixture_escape", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"data_path_escape",
		"a pack may not reference files outside its root"
	)
	_remove_fixture("fixture_escape")


func test_missing_locale_key_is_reported() -> void:
	var files := _base_files("fixture_locale")
	(files["locale/en.json"] as Dictionary).erase("roles.role_a")
	var root := _write_fixture("fixture_locale", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"missing_locale_key",
		"content referencing an undefined label is rejected"
	)
	_remove_fixture("fixture_locale")


func test_dangling_role_reference_is_reported() -> void:
	var files := _base_files("fixture_dangling")
	((files["data/missions.json"] as Array)[0] as Dictionary)["required_role_ids"] = ["role_missing"]
	var root := _write_fixture("fixture_dangling", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"dangling_reference",
		"a task requiring an unknown role is rejected"
	)
	_remove_fixture("fixture_dangling")


func test_duplicate_task_id_is_reported() -> void:
	var files := _base_files("fixture_duplicate")
	var missions: Array = files["data/missions.json"]
	missions.append((missions[0] as Dictionary).duplicate(true))
	var root := _write_fixture("fixture_duplicate", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"duplicate_id",
		"duplicate task ids are rejected"
	)
	_remove_fixture("fixture_duplicate")


func test_invalid_theme_token_is_reported() -> void:
	var files := _base_files("fixture_theme")
	(files["ui/theme.json"] as Dictionary)["accent"] = "not-a-color"
	var root := _write_fixture("fixture_theme", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"invalid_theme_token",
		"a non-hex theme value is rejected"
	)
	_remove_fixture("fixture_theme")


func test_invalid_mechanics_are_reported() -> void:
	var files := _base_files("fixture_mechanics")
	(files["manifest.json"] as Dictionary)["mechanics"] = ["agents", "time_travel"]
	var root := _write_fixture("fixture_mechanics", files)
	assert_has_error_code(
		PackValidator.validate_pack_root(root),
		"unsupported_mechanic",
		"an unimplemented mechanic is refused rather than silently ignored"
	)
	_remove_fixture("fixture_mechanics")


func test_loader_refuses_an_invalid_pack() -> void:
	var files := _base_files("fixture_loader_bad")
	((files["data/missions.json"] as Array)[0] as Dictionary)["base_seconds"] = 0
	var root := _write_fixture("fixture_loader_bad", files)
	var loaded := GamePackLoader.load_pack_from_root(root)
	assert_true(loaded["pack"] == null, "no pack object is returned for invalid content")
	assert_false((loaded["errors"] as Array).is_empty(), "validation errors are surfaced")
	_remove_fixture("fixture_loader_bad")


func test_loader_builds_a_usable_pack_from_a_valid_fixture() -> void:
	var root := _write_fixture("fixture_loader_good", _base_files("fixture_loader_good"))
	var loaded := GamePackLoader.load_pack_from_root(root)
	assert_true(loaded["pack"] != null, "a valid fixture loads")
	var pack: GamePack = loaded["pack"]
	assert_eq(pack.game_id, "fixture_loader_good", "pack keeps its own game id")
	assert_eq(pack.title(), "Fixture Pack", "labels resolve from the pack locale")
	assert_true(pack.missions.has("task_one"), "tasks are indexed by id")
	assert_true(pack.starter_agents.has("agent_one"), "starter agents are indexed by id")
	_remove_fixture("fixture_loader_good")

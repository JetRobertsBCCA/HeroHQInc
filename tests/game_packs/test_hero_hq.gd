extends TestCase
## HERO//HQ pack contract. Also the reuse guard: fails if shared framework code
## ever absorbs title-specific content.

const FORBIDDEN_IN_FRAMEWORK: Array[String] = [
	"hero",
	"volt",
	"striker",
	"vanguard",
	"mystic",
	"credit",
	"intel",
	"sector",
	"alley",
	"nemesis",
	"superhero",
	"games/hero_hq",
]


func test_pack_validates_and_loads() -> void:
	var errors := PackValidator.validate_pack_root("res://games/hero_hq")
	assert_eq(errors, [], "the HERO//HQ pack satisfies the pack contract")
	var loaded := GamePackLoader.load_pack("hero_hq")
	assert_true(loaded["pack"] != null, "the HERO//HQ pack loads")
	assert_eq((loaded["errors"] as Array).size(), 0, "loading reports no errors")


func test_pack_declares_the_locked_mvp_shell() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	assert_eq(pack.title(), "HERO//HQ", "title comes from pack locale")
	assert_eq(pack.declared_resources(), ["credits", "intel"], "declared resources match the spec")
	assert_eq(pack.navigation.size(), 5, "five primary tabs are declared")
	assert_eq(pack.roles.size(), 5, "five hero classes are declared")
	assert_eq(pack.missions.size(), 6, "the task ladder has six steps")
	assert_true(pack.missions.has("s_alley"), "the starter task exists")
	assert_true(pack.missions.has("s_siege"), "the highest-gated task exists")
	assert_true(pack.starter_agents.has("hero_volt"), "the starter hero comes from pack data")
	assert_eq(pack.max_offline_seconds, 28800.0, "the offline allowance is eight hours")
	assert_eq(pack.label("roles.striker"), "Striker", "labels resolve through locale")
	assert_eq(pack.label("missing.key"), "missing.key", "a missing label degrades to its key")


func test_pack_carries_the_tuning_the_loop_needs() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	assert_eq(float(pack.leveling.get("xp_base", 0)), 120.0, "the XP curve is pack data")
	assert_eq(float(pack.leveling.get("xp_per_level", 0)), 80.0, "the XP curve grows with level")
	assert_eq(str(pack.training.get("resource_id", "")), "credits", "training spends a declared resource")
	assert_true(float(pack.training.get("xp_per_session", 0)) > 0.0, "training grants XP")
	assert_eq(pack.roster_capacity, 240, "roster capacity is pack data")
	assert_eq(Recruitment.named_count(pack), 200, "the named recruit pool is pack data")
	assert_eq(Recruitment.tier_rules(pack).size(), 3, "recruit tiers are pack data")


func test_every_task_pays_only_declared_resources() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	var declared := PackValidator.string_set(pack.manifest.get("resources", []))
	for task_id in pack.task_ids():
		var rewards: Variant = pack.task(str(task_id)).get("rewards", null)
		if not (rewards is Dictionary):
			continue
		for resource_id in (rewards as Dictionary).keys():
			assert_true(
				declared.has(str(resource_id)),
				"task %s pays declared resource %s" % [str(task_id), str(resource_id)]
			)


func test_state_creation_uses_pack_content_only() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	var state := Simulation.new_state(pack, 1, 1700000000)
	assert_eq(state.game_id, "hero_hq", "state is stamped with the pack id")
	assert_eq(state.resource("credits"), 50.0, "starter credits come from pack data")
	assert_eq(state.resource("intel"), 0.0, "starter intel comes from pack data")
	var volt: Dictionary = state.agents["hero_volt"]
	assert_eq(str(volt["role_id"]), "striker", "the starter hero's role is data-driven")
	assert_eq(int(volt["level"]), 1, "the starter hero begins at level one")


func test_theme_tokens_build_a_usable_theme() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	assert_eq(ThemeTokens.missing_tokens(pack), [], "every required token is present")
	assert_eq(ThemeTokens.color(pack, "accent"), Color.from_string("#00E5F5", Color.BLACK), "accent resolves")
	assert_eq(ThemeTokens.color(pack, "background"), Color.from_string("#080C13", Color.BLACK), "background resolves")
	var theme := ThemeTokens.build_theme(pack)
	assert_true(theme is Theme, "a Theme is produced")
	assert_true(theme.has_stylebox("panel", "PanelContainer"), "panels are themed")
	assert_true(theme.has_stylebox("normal", "Button"), "buttons are themed")


func test_shell_builds_a_tab_per_declared_section() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	var shell := ScreenShell.new()
	shell.build(pack)
	assert_eq(shell.tab_ids().size(), 5, "one tab button per declared section")
	var emitted: Array = []
	shell.tab_selected.connect(func(tab_id: String) -> void: emitted.append(tab_id))
	shell.select_tab("missions")
	assert_eq(shell.current_tab(), "missions", "selection is tracked")
	assert_eq(emitted.size(), 1, "selecting emits exactly one signal")
	assert_eq(str(emitted[0]), "missions", "the emitted tab id is correct")
	shell.select_tab("not_a_tab")
	assert_eq(shell.current_tab(), "missions", "an unknown tab is ignored")
	shell.free()


func test_framework_contains_no_title_identifiers() -> void:
	var violations: Array[String] = []
	for path in _gd_files("res://framework"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			violations.append("unreadable: %s" % path)
			continue
		var text := file.get_as_text().to_lower()
		file.close()
		for word in FORBIDDEN_IN_FRAMEWORK:
			if text.contains(word):
				violations.append("%s contains '%s'" % [path, word])
	assert_true(
		violations.is_empty(),
		"framework/ must stay game-neutral; violations: %s" % str(violations)
	)


func test_hero_pack_does_not_import_framework_internals() -> void:
	var pack: GamePack = GamePackLoader.load_pack("hero_hq")["pack"]
	assert_true(pack.root_path.begins_with("res://games/"), "the pack lives under games/")
	assert_true(
		not SaveService.profile_path(pack.game_id).begins_with(SaveService.profile_path("fixture")),
		"the hero pack keeps its own save namespace"
	)


func _gd_files(path: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return files
	for file_name in directory.get_files():
		if file_name.ends_with(".gd"):
			files.append(path.path_join(file_name))
	for sub_directory in directory.get_directories():
		files.append_array(_gd_files(path.path_join(sub_directory)))
	return files

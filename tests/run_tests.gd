extends SceneTree
## Headless test runner.
##
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Exits 0 when every test passes, 1 otherwise.

const SUITES: Array[String] = [
	"res://tests/framework/test_simulation.gd",
	"res://tests/framework/test_save.gd",
	"res://tests/framework/test_pack_validation.gd",
	"res://tests/framework/test_tasks.gd",
	"res://tests/framework/test_screens.gd",
	"res://tests/framework/test_prestige.gd",
	"res://tests/framework/test_research.gd",
	"res://tests/framework/test_focus.gd",
	"res://tests/framework/test_recruitment.gd",
	"res://tests/framework/test_squads.gd",
	"res://tests/framework/test_automation.gd",
	"res://tests/framework/test_squad_automation.gd",
	"res://tests/framework/test_command_progression.gd",
	"res://tests/game_packs/test_hero_hq.gd",
	"res://tests/game_packs/test_city_content.gd",
	"res://tests/game_packs/test_app_retry.gd",
	"res://tests/game_packs/test_app_focus.gd",
	"res://tests/game_packs/test_app_network.gd",
	"res://tests/game_packs/test_app_squads.gd",
	"res://tests/game_packs/test_app_progression.gd",
	"res://tests/game_packs/test_auto_patrol_app.gd",
]


func _initialize() -> void:
	var total := 0
	var failed := 0
	var failed_tests: Array[String] = []
	print("Running %d suite(s)" % SUITES.size())
	for suite_path in SUITES:
		var script: Variant = load(suite_path)
		if not (script is GDScript):
			print("ERROR could not load suite %s" % suite_path)
			failed += 1
			total += 1
			continue
		var suite: Object = (script as GDScript).new()
		if not (suite is TestCase):
			print("ERROR suite %s does not extend TestCase" % suite_path)
			failed += 1
			total += 1
			continue
		for method in suite.get_method_list():
			var method_name := str(method.get("name", ""))
			if not method_name.begins_with("test_"):
				continue
			if not (method.get("args", []) as Array).is_empty():
				continue
			total += 1
			suite.call("begin", method_name)
			suite.call(method_name)
			var failures: Array = suite.call("failures")
			var label := "%s::%s" % [suite_path.get_file(), method_name]
			if failures.is_empty():
				print("PASS  %s" % label)
			else:
				failed += 1
				failed_tests.append(label)
				for failure in failures:
					print("FAIL  %s: %s" % [label, str(failure)])
	print("")
	if failed > 0:
		print("RESULT: %d test(s) run, %d failed" % [total, failed])
		for name in failed_tests:
			print("  failed: %s" % name)
		quit(1)
		return
	print("RESULT: %d test(s) run, all passed" % total)
	quit(0)

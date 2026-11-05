class_name TestCase
extends RefCounted
## Minimal assertion harness for the headless runner.
##
## Deliberately dependency-free: the specification asks for a plain GDScript
## test path that works with `godot --headless -s res://tests/run_tests.gd`.

var _failures: Array[String] = []
var _checks: int = 0


func begin(_test_name: String) -> void:
	_failures.clear()
	_checks = 0


func assert_true(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func assert_is_instance(value: Variant, expected_type: Variant, message: String) -> void:
	assert_true(is_instance_of(value, expected_type), message)


func assert_has_error_code(errors: Array, expected_code: String, message: String) -> void:
	var codes: Array[String] = []
	for error in errors:
		if error is Dictionary:
			codes.append(str((error as Dictionary).get("code", "")))
	assert_true(codes.has(expected_code), "%s (codes: %s)" % [message, str(codes)])


## Framework fixtures that are testing a later-stage task's rating, role or
## automation logic can open its stage for that fixture. Progression itself is
## covered against the unmodified pack in test_command_progression.gd.
func without_stage_gates(pack: GamePack) -> GamePack:
	var stages: Variant = pack.progression.get("stages", [])
	if stages is Array:
		for raw in stages:
			if raw is Dictionary:
				(raw as Dictionary).erase("unlock_command_level")
	return pack


func failures() -> Array[String]:
	return _failures


func check_count() -> int:
	return _checks

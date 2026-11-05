extends SceneTree
## Reproducible 360x640 captures and geometry evidence for the HQ first viewport.
##
## Run windowed:
##   godot --path . --resolution 360x640 -s res://tooling/hq_viewport_capture.gd
##   godot --path . --resolution 360x640 -s res://tooling/hq_viewport_capture.gd -- --tag=before
##
## Uses throwaway profiles and a manual clock; it never reads or writes a real
## save. The layout line and exit status check that the live row, objective,
## Command card and touch targets clear the content slot, so the captures have a
## machine-readable check beside the image.

const PACK_ID := "hero_hq"
const PROFILE_PREFIX := "hq_viewport_capture_"
const SHOT_DIR := "res://ui_shots"
const PACK_NOW := 1000

var _tag := "after"
var _failures: Array[String] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--tag="):
			_tag = text.trim_prefix("--tag=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var pack := GamePackLoader.load_pack(PACK_ID)["pack"] as GamePack
	var scenarios := [
		{"id": "fresh", "state": _fresh_state(pack), "reduced": false},
		{"id": "active_solo", "state": _active_state(pack, false, false), "reduced": false},
		{"id": "active_squad", "state": _active_state(pack, true, false), "reduced": false},
		{"id": "reduced_motion", "state": _active_state(pack, true, true), "reduced": true},
	]
	for scenario in scenarios:
		var scenario_id := str(scenario.get("id", ""))
		await _capture_scenario(
			pack,
			scenario_id,
			scenario.get("state") as GameState,
			bool(scenario.get("reduced", false)),
		)
	if not _failures.is_empty():
		for failure in _failures:
			print("HQ viewport check failed: %s" % failure)
		quit(1)
		return
	print("HQ viewport captures complete and within bounds: tag=%s" % _tag)
	quit(0)


func _capture_scenario(
	pack: GamePack,
	scenario_id: String,
	state: GameState,
	expected_reduced: bool
) -> void:
	var profile_id := "%s%s_%s" % [PROFILE_PREFIX, _tag, scenario_id]
	SaveService.delete_profile(profile_id)
	state.game_id = profile_id
	var written := SaveService.save_state(state)
	if not str(written.get("error", "")).is_empty():
		print("CAPTURE FAILED save %s: %s" % [scenario_id, str(written)])
		return

	var scene := load("res://games/hero_hq/scenes/app.tscn") as PackedScene
	var app := scene.instantiate() as Control
	app.set("_profile_id", profile_id)
	app.set("_clock", Clock.Manual.new(PACK_NOW))
	root.add_child(app)
	if app.get("_state") == null:
		app.call("_ready")
	await process_frame
	await process_frame
	var game_timer := app.get("_timer") as Timer
	if game_timer != null:
		game_timer.stop()

	var panel: HeroNetworkPanel = app.get("_network_panel")
	if panel != null and panel.is_reduced_motion() != expected_reduced:
		print(
			"CAPTURE WARNING %s reduced=%s expected=%s" % [
				scenario_id,
				str(panel.is_reduced_motion()),
				str(expected_reduced),
			]
		)
	if not _report_layout(app, scenario_id):
		_failures.append(scenario_id)
	var path := "%s/hq_%s_%s.png" % [SHOT_DIR, _tag, scenario_id]
	await _save_capture(path)
	app.queue_free()
	await process_frame
	await process_frame
	SaveService.delete_profile(profile_id)


func _report_layout(app: Control, scenario_id: String) -> bool:
	var content: Control = app.find_child("Content", true, false) as Control
	var network: HeroNetworkPanel = app.get("_network_panel") as HeroNetworkPanel
	var command: Control = app.get("_command_card") as Control
	var objective: Control = app.get("_objective_card") as Control
	var content_bottom := content.get_global_rect().end.y if content != null else -1.0
	var network_top := network.get_global_rect().position.y if network != null else -1.0
	var network_bottom := network.get_global_rect().end.y if network != null else -1.0
	var objective_bottom := objective.get_global_rect().end.y if objective != null else -1.0
	var command_bottom := command.get_global_rect().end.y if command != null else -1.0
	var motion: Button = app.get("_motion_button") as Button
	var tab: Button = app.find_child("Tab_hq", true, false) as Button
	var first_row_bottom := -1.0
	var second_row_bottom := -1.0
	if network != null and network.activity_count() > 0:
		first_row_bottom = network_top + HeroNetworkPanel.PAD_TOP \
			+ HeroNetworkPanel.HEADER_HEIGHT + HeroNetworkPanel.DIAGRAM_HEIGHT \
			+ HeroNetworkPanel.GAP_BEFORE_ROWS + HeroNetworkPanel.ROW_HEIGHT
		second_row_bottom = first_row_bottom + HeroNetworkPanel.ROW_HEIGHT
	print((
		"LAYOUT %s viewport=%s content_bottom=%.1f network_top=%.1f network_bottom=%.1f "
		+ "first_row_bottom=%.1f first_row_fits=%s second_row_fits=%s "
		+ "objective_h=%.1f objective_bottom=%.1f objective_fits=%s "
		+ "command_h=%.1f command_bottom=%.1f command_fits=%s "
		+ "motion_h=%.1f tab_h=%.1f activities=%d reduced=%s"
	) % [
			scenario_id,
			str(root.get_visible_rect().size),
			content_bottom,
			network_top,
			network_bottom,
			first_row_bottom,
			str(first_row_bottom > 0.0 and first_row_bottom <= content_bottom),
			str(second_row_bottom > 0.0 and second_row_bottom <= content_bottom),
			objective.get_global_rect().size.y if objective != null else -1.0,
			objective_bottom,
			str(objective != null and objective_bottom <= content_bottom),
			command.get_global_rect().size.y if command != null else -1.0,
			command_bottom,
			str(command != null and command_bottom <= content_bottom),
			motion.size.y if motion != null else -1.0,
			tab.size.y if tab != null else -1.0,
			network.activity_count() if network != null else -1,
			str(network.is_reduced_motion()) if network != null else "missing",
		]
	)
	var first_ok := network != null and (
		network.activity_count() == 0 or first_row_bottom <= content_bottom
	)
	var second_ok := network != null and (
		network.activity_count() < 2 or second_row_bottom <= content_bottom
	)
	var objective_ok := objective != null and objective_bottom <= content_bottom
	var command_ok := command != null and command_bottom <= content_bottom
	var touch_ok := motion != null and motion.size.y >= 44.0 \
		and tab != null and tab.size.y >= 48.0
	var layout_ok := content != null and network != null and first_ok and second_ok \
		and objective_ok and command_ok and touch_ok
	if not layout_ok:
		print(
			"LAYOUT CHECK FAILED %s first=%s second=%s objective=%s command=%s touch=%s" % [
				scenario_id,
				str(first_ok),
				str(second_ok),
				str(objective_ok),
				str(command_ok),
				str(touch_ok),
			]
		)
	return layout_ok


func _save_capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	print(
		"CAPTURE %s %dx%d err=%d" % [
			ProjectSettings.globalize_path(path),
			image.get_width(),
			image.get_height(),
			error,
		]
	)


func _fresh_state(pack: GamePack) -> GameState:
	return Simulation.new_state(pack, 31, PACK_NOW)


func _active_state(pack: GamePack, squad: bool, reduced: bool) -> GameState:
	var state := Simulation.new_state(pack, 32, PACK_NOW)
	state.resources["credits"] = 4415.0
	state.resources["intel"] = 9.0
	state.stats["tasks_completed"] = 12 if squad else 3
	if squad:
		state.stats["earned"] = {"credits": 1500.0}
	state.agents["hero_volt"]["attributes"] = {"power": 10, "speed": 10, "skill": 10}
	state.agents["shot_striker"] = _agent("shot_striker", "striker", 4)
	state.agents["shot_support"] = _agent("shot_support", "support", 4)
	state.agents["shot_tech"] = _agent("shot_tech", "tech", 3)
	if reduced:
		state.extensions["hero_hq.ui"] = {"reduced_motion": true}

	var solo := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], PACK_NOW)
	_retime(state, str(solo.get("assignment_id", "")), PACK_NOW - 14, PACK_NOW + 6)
	if squad:
		var raid := Simulation.assign_task(
			state, pack, "s_raid", ["shot_striker", "shot_support"], PACK_NOW
		)
		if not raid.get("ok", false):
			print("CAPTURE WARNING squad assignment refused: %s" % str(raid))
		_retime(state, str(raid.get("assignment_id", "")), PACK_NOW - 60, PACK_NOW + 40)
	return state


func _retime(state: GameState, assignment_id: String, started: int, ends: int) -> void:
	if assignment_id.is_empty() or not state.assignments.has(assignment_id):
		return
	state.assignments[assignment_id]["started_utc"] = started
	state.assignments[assignment_id]["ends_utc"] = ends


func _agent(agent_id: String, role_id: String, level: int) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": level,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": 10, "speed": 10, "skill": 10},
	}

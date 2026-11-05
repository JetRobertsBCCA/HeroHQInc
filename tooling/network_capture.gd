extends SceneTree
## Reproducible 360x640 captures for the HQ operations network.
##
## Uses a throwaway profile and a manual clock, so it never reads or writes the
## player's save. Run windowed:
##   godot --path . --resolution 360x640 -s res://tooling/network_capture.gd

const PACK_ID := "hero_hq"
const PROFILE_ID := "ui_network_capture"
const SHOT_DIR := "res://ui_shots"
const NOW := 1000

var _app: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var pack := GamePackLoader.load_pack(PACK_ID)["pack"] as GamePack
	var state := _build_state(pack)
	SaveService.delete_profile(PROFILE_ID)
	var written := SaveService.save_state(state)
	if not str(written.get("error", "")).is_empty():
		print("capture save failed: ", written)
		quit(1)
		return

	var scene := load("res://games/hero_hq/scenes/app.tscn") as PackedScene
	_app = scene.instantiate()
	_app.set("_profile_id", PROFILE_ID)
	_app.set("_clock", Clock.Manual.new(NOW))
	root.add_child(_app)
	if _app.get("_state") == null:
		_app.call("_ready")
	await process_frame
	await process_frame
	var game_timer := _app.get("_timer") as Timer
	if game_timer != null:
		game_timer.stop()

	var panel: HeroNetworkPanel = _app.get("_network_panel")
	print(
		"working activities=%d idle=%d motion_running=%s" % [
			panel.activity_count() if panel != null else -1,
			panel.idle_count() if panel != null else -1,
			str(panel.animation_is_running()) if panel != null else "missing",
		]
	)
	var first := await _capture("network_after_working")
	await create_timer(0.35).timeout
	var second := await _capture("network_after_working_b")
	if first != null and second != null:
		print("motion_changed_sampled_pixels=", _sample_difference(first, second))

	var button := _app.get("_motion_button") as Button
	if button != null:
		button.button_pressed = true
		button.toggled.emit(true)
	await process_frame
	panel = _app.get("_network_panel")
	print(
		"reduced motion=%s panel_reduced=%s timer_running=%s" % [
			button.text,
			str(panel.is_reduced_motion()) if panel != null else "missing",
			str(panel.animation_is_running()) if panel != null else "missing",
		]
	)
	await _capture("network_after_reduced")

	if button != null:
		button.button_pressed = false
		button.toggled.emit(false)
	var clock := _app.get("_clock") as Clock.Manual
	clock.advance(7)
	_app.call("_on_tick")
	await create_timer(0.35).timeout
	panel = _app.get("_network_panel")
	print(
		"completion visible=%s text=%s activities=%d" % [
			str(panel.completion_visible()) if panel != null else "missing",
			panel.completion_text() if panel != null else "",
			panel.activity_count() if panel != null else -1,
		]
	)
	await _capture("network_after_completion")

	clock.advance(70)
	_app.call("_on_tick")
	await create_timer(2.6).timeout
	_app.call("_on_tick")
	await process_frame
	panel = _app.get("_network_panel")
	print(
		"idle activities=%d idle=%d completion=%s" % [
			panel.activity_count() if panel != null else -1,
			panel.idle_count() if panel != null else -1,
			str(panel.completion_visible()) if panel != null else "missing",
		]
	)
	await _capture("network_after_idle")

	_app.queue_free()
	await process_frame
	await process_frame
	SaveService.delete_profile(PROFILE_ID)
	print("capture profile cleaned")
	quit(0)


func _build_state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 21, NOW)
	state.game_id = PROFILE_ID
	state.resources["credits"] = 4415.0
	state.resources["intel"] = 9.0
	state.stats["tasks_completed"] = 3
	state.agents["hero_volt"]["attributes"] = {"power": 10, "speed": 10, "skill": 10}
	state.agents["shot_striker"] = _agent("shot_striker", "striker")
	state.agents["shot_support"] = _agent("shot_support", "support")
	state.agents["shot_tech"] = _agent("shot_tech", "tech")
	var solo := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], NOW)
	var squad := Simulation.assign_task(
		state,
		pack,
		"s_raid",
		["shot_striker", "shot_support"],
		NOW
	)
	var solo_id := str(solo.get("assignment_id", ""))
	var squad_id := str(squad.get("assignment_id", ""))
	if state.assignments.has(solo_id):
		state.assignments[solo_id]["started_utc"] = NOW - 14
		state.assignments[solo_id]["ends_utc"] = NOW + 6
	if state.assignments.has(squad_id):
		state.assignments[squad_id]["started_utc"] = NOW - 60
		state.assignments[squad_id]["ends_utc"] = NOW + 60
	return state


func _agent(agent_id: String, role_id: String) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 3,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": 10, "speed": 10, "skill": 10},
	}


func _capture(shot_name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, shot_name]
	var error := image.save_png(path)
	print(
		"capture %s %s %dx%d err=%d" % [
			shot_name,
			ProjectSettings.globalize_path(path),
			image.get_width(),
			image.get_height(),
			error,
		]
	)
	return image


func _sample_difference(first: Image, second: Image) -> int:
	if first.get_size() != second.get_size():
		return -1
	var changed := 0
	for y in range(0, first.get_height(), 4):
		for x in range(0, first.get_width(), 4):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				changed += 1
	return changed

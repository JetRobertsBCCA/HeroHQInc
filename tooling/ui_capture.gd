extends SceneTree
## Temporary: boots the real app windowed and saves one PNG per tab.

const PACK_ID := "hero_hq"
const SHOT_DIR := "res://ui_shots"

var _app: Control
var _saved: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_backup_profile()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var scene := load("res://games/hero_hq/scenes/app.tscn") as PackedScene
	_app = scene.instantiate()
	root.add_child(_app)
	await process_frame
	await process_frame
	var timer := _app.get("_timer") as Timer
	if timer != null:
		timer.stop()
	var pack: GamePack = _app.get("_pack")
	var state: GameState = _app.get("_state")
	state.resources["credits"] = 5000.0
	state.resources["intel"] = 24.0
	for _i in range(6):
		Recruitment.recruit(state, pack)
	for _i in range(6):
		Simulation.train_agent(state, pack, "hero_volt")
	Research.buy(state, pack, "ops_reward")
	Simulation.deploy(state, pack, "s_alley", int(Time.get_unix_time_from_system()))
	_app.call("_refresh_content")
	await process_frame

	for entry in pack.navigation:
		var tab_id := str((entry as Dictionary).get("id", ""))
		var button := _app.find_child("Tab_%s" % tab_id, true, false) as Button
		if button == null:
			print("missing tab ", tab_id)
			continue
		button.pressed.emit()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/%s.png" % [SHOT_DIR, tab_id]
		var error := image.save_png(path)
		print("%s %s %dx%d err=%d" % [tab_id, ProjectSettings.globalize_path(path), image.get_width(), image.get_height(), error])

	_app.queue_free()
	await process_frame
	await process_frame
	_restore_profile()
	quit(0)


func _backup_profile() -> void:
	for path in [SaveService.profile_path(PACK_ID), SaveService.backup_path(PACK_ID)]:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			_saved[path] = file.get_buffer(file.get_length())
			file.close()
	SaveService.delete_profile(PACK_ID)


func _restore_profile() -> void:
	SaveService.delete_profile(PACK_ID)
	for path in _saved.keys():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_saved[path])
			file.close()
	print("restored %d file(s)" % _saved.size())

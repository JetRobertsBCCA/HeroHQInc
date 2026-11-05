extends SceneTree
## Captures the Missions board at 360x640 in four states and checks the parts
## that must survive a compact portrait layout:
##   fresh   - no live work, the first ready operation and the locked ladder
##   active  - a running operation with a live progress bar and countdown
##   locked  - a scrolled view of blocked operations with their reasons
##   national - level 3 scrolled to the National Response Command Level lock
##
## The player's save is backed up and restored. Exit code 1 on any failed
## layout assertion so this is a check, not just a screenshot generator.

const PACK_ID := "hero_hq"
const SHOT_DIR := "res://ui_shots"

var _app: Control
var _pack: GamePack
var _saved: Dictionary = {}
var _failures: int = 0
var _tag := "after"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
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
	_pack = _app.get("_pack") as GamePack
	var now := int(Time.get_unix_time_from_system())

	# Fresh: the starter has not deployed anything.
	var fresh := Simulation.new_state(_pack, 1, now)
	await _capture_state("fresh", fresh, now, false)

	# Active: the same spread used by the full tab capture, with the starter
	# operation already halfway through so the in-place signal is visible.
	var active := _active_state(now)
	await _capture_state("active", active, now, false)

	# Locked: a fresh starter scrolled to the blocked half of the board.
	var locked := Simulation.new_state(_pack, 1, now)
	await _capture_state("locked", locked, now, true)

	# National: a level-3 roster scrolled to the first National operation, so the
	# full Command Level 4 reason is visible on a 360px-wide device.
	var national := _national_state(now)
	await _capture_state("national", national, now, true, "s_blackout")

	_app.queue_free()
	await process_frame
	await process_frame
	_restore_profile()
	if _failures > 0:
		print("MISSION_CAPTURE_FAILED failures=%d" % _failures)
		quit(1)
		return
	print("MISSION_CAPTURE_OK tag=%s" % _tag)
	quit(0)


func _national_state(now: int) -> GameState:
	var state := Simulation.new_state(_pack, 1, now)
	state.stats["tasks_completed"] = 12
	state.stats["earned"] = {"credits": 1500.0}
	state.agents["test_support"] = _capture_agent("test_support", "support")
	state.agents["test_tech"] = _capture_agent("test_tech", "tech")
	state.agents["test_reserve"] = _capture_agent("test_reserve", "striker")
	return state


func _capture_agent(agent_id: String, role_id: String) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": 20, "speed": 20, "skill": 20},
	}


func _active_state(now: int) -> GameState:
	var state := Simulation.new_state(_pack, 1, now)
	state.resources["credits"] = 5000.0
	state.resources["intel"] = 24.0
	for _i in range(6):
		Recruitment.recruit(state, _pack)
	for _i in range(6):
		Simulation.train_agent(state, _pack, "hero_volt")
	Research.buy(state, _pack, "ops_reward")
	var deployed := Simulation.assign_task(
		state, _pack, "s_alley", ["hero_volt"], now - 10
	)
	_check(deployed.get("ok", false), "the active capture can schedule its operation")
	return state


func _capture_state(
	state_name: String,
	state: GameState,
	now: int,
	scroll_locked: bool,
	focus_task_id: String = ""
) -> void:
	_app.set("_state", state)
	var shell := _app.get("_shell") as ScreenShell
	shell.refresh(state)
	shell.select_tab("missions")
	await process_frame
	await process_frame
	var board := _app.get("_task_board") as TaskBoard
	_check(board != null, "%s state builds a TaskBoard" % state_name)
	if board == null:
		return
	var scroll := board.find_child("BoardScroll", true, false) as ScrollContainer
	_check(scroll != null, "%s state has the board scroller" % state_name)
	if scroll != null:
		scroll.scroll_vertical = 0
	await process_frame
	if scroll_locked and scroll != null:
		var locked_list := board.find_child("LockedList", true, false) as VBoxContainer
		var locked_heading := board.find_child("LockedHeading", true, false) as Control
		_check(locked_list != null and locked_list.get_child_count() > 0, "locked state has rows")
		var target := 0
		if not focus_task_id.is_empty() and locked_list != null:
			var focus_card := board.find_child("Task_%s" % focus_task_id, true, false) as Control
			_check(focus_card != null, "%s has a focused locked card" % focus_task_id)
			if focus_card != null:
				target = maxi(int(locked_list.position.y + focus_card.position.y) - 6, 0)
		elif locked_heading != null:
			target = maxi(int(locked_heading.position.y) - 6, 0)
		scroll.scroll_vertical = target
		await process_frame
		scroll.scroll_vertical = target
		print("LOCKED_SCROLL state=%s target=%d actual=%d max=%.1f" % [
			state_name,
			target,
			scroll.scroll_vertical,
			scroll.get_v_scroll_bar().max_value,
		])
		await process_frame
		await process_frame

	var content := shell.find_child("Content", true, false) as Control
	_check(content != null, "%s state has the content slot" % state_name)
	if content == null:
		return
	var content_rect := content.get_global_rect()
	_check(content_rect.size.x > 0.0 and content_rect.size.y > 0.0, "content slot has size")

	var ready_button := board.deploy_button("s_alley")
	_check(ready_button != null, "the starter operation has a deploy button")
	if ready_button != null:
		_check(
			ready_button.size.y >= TaskBoard.MIN_TAP_HEIGHT,
			"ready deploy button is at least 48px tall",
		)
		_check(not ready_button.disabled, "the starter operation is deployable")

	var ready_card := board.find_child("Task_s_alley", true, false) as Control
	_check(ready_card != null, "the starter operation has a card")
	if not scroll_locked and ready_card != null and content_rect.size.y > 0.0:
		_check(
			ready_card.get_global_rect().intersects(content_rect),
			"the starter card is visible in the content slot",
		)

	var status := board.find_child("Status_s_alley", true, false) as Label
	_check(status != null and status.text.contains("READY"), "ready work states READY")

	if state_name == "active":
		_check(board.active_row_count() == 1, "active state has one live row")
		var assignment_id := str(state.assignments.keys()[0])
		var active_card := board.find_child("Active_%s" % assignment_id, true, false) as Control
		var progress := board.find_child("Progress_%s" % assignment_id, true, false) as ProgressBar
		_check(active_card != null, "the live operation has a card")
		_check(progress != null, "the live operation has a progress bar")
		if active_card != null:
			_check(
				active_card.get_global_rect().intersects(content_rect),
				"the live operation is visible in the first viewport",
			)
		if progress != null:
			_check(progress.value > 0.0 and progress.value < 100.0, "live progress is in flight")
			_check(progress.get_global_rect().size.x > 100.0, "live progress bar has usable width")
		var countdown := board.active_countdown(assignment_id)
		_check(countdown.contains("Time left"), "the live row carries a countdown")

	var live_list := board.find_child("LiveList", true, false) as VBoxContainer
	var locked_list_for_size := board.find_child("LockedList", true, false) as VBoxContainer
	var ready_height: float = ready_card.size.y if ready_card != null else 0.0
	var active_height: float = live_list.get_child(0).size.y if live_list != null and live_list.get_child_count() > 0 else 0.0
	var locked_height: float = locked_list_for_size.get_child(0).size.y if locked_list_for_size != null and locked_list_for_size.get_child_count() > 0 else 0.0
	print("GEOMETRY %s content=%s ready_card=%.0f active_card=%.0f locked_card=%.0f ready_button=%.0f" % [
		state_name,
		content_rect.size,
		ready_height,
		active_height,
		locked_height,
		ready_button.size.y if ready_button != null else 0.0,
	])

	if state_name == "national":
		for task_id in ["s_blackout", "s_siege", "s_breach", "s_siegebreak"]:
			_check(
				board.blocked_reason(task_id).contains("National Response"),
				"%s names National Response" % task_id,
			)
			_check(
				board.blocked_reason(task_id).contains("Command Level 4"),
				"%s names Command Level 4" % task_id,
			)
			_check(board.deploy_button(task_id).disabled, "%s is disabled" % task_id)

	if scroll_locked:
		_check(scroll != null and scroll.scroll_vertical > 0, "locked state is scrolled")
		var locked_list := board.find_child("LockedList", true, false) as VBoxContainer
		var locked_card: Control = null
		if not focus_task_id.is_empty():
			locked_card = board.find_child("Task_%s" % focus_task_id, true, false) as Control
		elif locked_list != null and locked_list.get_child_count() > 0:
			locked_card = locked_list.get_child(0) as Control
		if locked_card != null:
			_check(
				locked_card.get_global_rect().intersects(content_rect),
				"the focused locked operation is visible",
			)
			var locked_status := locked_card.find_child("Status_*", true, false) as Label
			_check(
				locked_status != null and locked_status.text.contains("LOCKED"),
				"a locked row states LOCKED and its bottleneck",
			)
			var locked_button := locked_card.find_child("Deploy_*", true, false) as Button
			_check(locked_button != null and locked_button.disabled, "locked work keeps its disabled action")
			if locked_button != null:
				_check(
					locked_button.size.y >= TaskBoard.MIN_TAP_HEIGHT,
					"locked action keeps the 48px touch height",
				)

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/missions_%s_%s.png" % [SHOT_DIR, _tag, state_name]
	var error := image.save_png(path)
	_check(error == OK, "saved %s" % path)
	print("CAPTURE %s %dx%d scroll=%d" % [
		ProjectSettings.globalize_path(path),
		image.get_width(),
		image.get_height(),
		scroll.scroll_vertical if scroll != null else -1,
	])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("CHECK_FAIL %s" % message)


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

extends SceneTree
## End-to-end in-game demo: boots the real app scene and plays it through the UI.
##
##   godot --headless --path . -s res://tooling/playthrough_demo.gd
##
## Every action is a real button press on the real screens: Missions, Heroes and
## Upgrades tabs, Deploy, Train, Recruit, Research and the two-step Rebirth. The
## only thing faked is the clock, so a 70-second operation settles immediately.
##
## The demo owns the profile while it runs: the player's save is read into memory,
## removed, and restored after the app is freed, so a failed demo cannot corrupt
## real progress.

const PACK_ID := "hero_hq"
const DEMO_CREDITS := 100000.0
const TECH_GATE_RATING := 110
const REBIRTH_LEVEL := 7
const REBIRTH_EARNINGS := 4000.0

var _app: Control
var _saved: Dictionary = {}
var _failures: Array[String] = []
var _completed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("HERO//HQ in-game playthrough")
	_backup_profile()
	await _boot()
	await _play()
	await _finish()


func _boot() -> void:
	var scene := load("res://games/hero_hq/scenes/app.tscn") as PackedScene
	_app = scene.instantiate()
	root.add_child(_app)
	await process_frame
	await process_frame
	_ok(_state() != null, "app restored or created a state")
	_ok(_app.get("_shell") != null, "screen shell built from pack navigation")
	var timer := _app.get("_timer") as Timer
	if timer != null:
		timer.stop()
	# Swap the wall clock for a manual one so operations settle on command.
	var manual := Clock.Manual.new(int(_state().last_settled_utc))
	_app.set("_clock", manual)


func _play() -> void:
	# --- Missions: the starter job, end to end -----------------------------
	await _select_tab("missions")
	var board := _board()
	_ok(board != null, "missions tab built a task board")
	if board == null:
		return
	_ok(board.task_row_count() == _pack().missions.size(), "one row per declared operation")
	_ok(board.deploy_button("s_pursuit").disabled, "Signal Pursuit is locked before a Tech exists")

	var credits_start := _state().resource("credits")
	var deployed := await _deploy("s_alley")
	_ok(deployed, "Alley Patrol deploys through its button")
	_ok(_state().assignments.size() == 1, "the operation is scheduled")
	await _advance(20)
	_ok(_state().assignments.is_empty(), "the operation settles after its duration")
	_ok(_state().resource("credits") > credits_start, "the reward is paid into the header resource")
	_ok(_state().tasks_completed() == 1, "the completion is counted once")
	_ok(_objective_step() == 2, "guidance moves past the first deployment")

	# --- Heroes: train, then hire a Tech through the role picker ------------
	await _select_tab("heroes")
	var roster := _roster()
	_ok(roster != null, "heroes tab built the roster")
	if roster == null:
		return
	_state().resources["credits"] = DEMO_CREDITS
	_ok(await _train("hero_volt"), "the starter trains")
	_ok(float(_state().agents["hero_volt"]["xp"]) > 0.0, "training granted XP")

	var recruit_start := _state().agents.size()
	# Screens are rebuilt on every refresh, so never hold one across an await.
	_ok(_roster().recruit_role_option() != null, "the recruit panel offers a role picker")
	_ok(await _recruit("tech"), "the role picker recruits")
	_ok(_state().agents.size() == recruit_start + 1, "one hire adds exactly one operative")
	var tech := _first_agent_with_role("tech")
	_ok(not tech.is_empty(), "the requested Tech joins on the first hire")

	if tech.is_empty():
		return

	# --- Teams: explicit slot editing, duplicates and empty-slot reasons ----
	await _select_tab("teams")
	var teams := _teams()
	_ok(teams != null, "teams tab built the lineup editor")
	if teams == null:
		return
	_ok(teams.slot_count("s_raid") == 2, "each required hero has its own slot")
	_ok(teams.select_slot_agent("s_raid", 0, "hero_volt"), "slot one takes the starter")
	_ok(not teams.select_slot_agent("s_raid", 1, "hero_volt"), "one hero cannot fill two slots")
	_ok(teams.select_slot_agent("s_raid", 1, ""), "a slot can be emptied")
	_ok(teams.deploy_button("s_raid").disabled, "an empty slot blocks deployment")
	_ok(
		teams.row_reason("s_raid") == _pack().label("ui.blocked_squad_incomplete", ""),
		"an empty slot explains itself",
	)
	_ok(teams.select_slot_agent("s_raid", 1, tech), "the second slot takes a second hero")
	_ok(not teams.save_button("s_raid").disabled, "a complete lineup can be saved")
	teams.save_button("s_raid").pressed.emit()
	await process_frame
	var saved_ids := Squads.member_ids(_state(), "s_raid")
	_ok(saved_ids.size() == 2, "the manual lineup is saved")
	_ok(saved_ids.has("hero_volt") and saved_ids.has(tech), "the saved lineup keeps the chosen heroes")

	# Saving rebuilt the tab, so return to Heroes before training again.
	await _select_tab("heroes")
	var sessions := 0
	while AgentRules.rating(_state().agents[tech]) < TECH_GATE_RATING and sessions < 200:
		sessions += 1
		if not (await _train(tech)):
			break
	_ok(
		AgentRules.rating(_state().agents[tech]) >= TECH_GATE_RATING,
		"the Tech reaches the 110 rating gate (%d sessions)" % sessions,
	)

	# --- The role gate opens ------------------------------------------------
	await _select_tab("missions")
	_ok(not _board().deploy_button("s_pursuit").disabled, "Signal Pursuit unlocks with a Tech on the roster")
	var intel_before := _state().resource("intel")
	_ok(await _deploy("s_pursuit"), "the gated operation deploys")
	await _advance(70)
	_ok(_state().resource("intel") > intel_before, "the gated operation pays Intel")

	# --- Earn the research and rebirth gates --------------------------------
	var runs := 0
	while _state().earned_total("credits") < REBIRTH_EARNINGS + 200.0 and runs < 40:
		runs += 1
		if not (await _deploy("s_pursuit")):
			break
		await _advance(70)
	_ok(
		_state().earned_total("credits") >= REBIRTH_EARNINGS,
		"lifetime earnings clear the rebirth gate (%d runs)" % runs,
	)

	# --- Research -----------------------------------------------------------
	await _select_tab("upgrades")
	var research := _app.find_child("Research_ops_reward", true, false) as Button
	_ok(research != null, "the research row renders in Upgrades")
	if research != null:
		var intel_pre := _state().resource("intel")
		research.pressed.emit()
		await process_frame
		_ok(int(Research.rank(_state(), "ops_reward")) == 1, "payout research bought a rank")
		_ok(_state().resource("intel") < intel_pre, "research spent Intel")
	else:
		return

	# --- Reach the rebirth level gate ---------------------------------------
	await _select_tab("heroes")
	sessions = 0
	while int(_state().agents["hero_volt"].get("level", 1)) < REBIRTH_LEVEL and sessions < 400:
		sessions += 1
		if not (await _train("hero_volt")):
			break
	_ok(
		int(_state().agents["hero_volt"].get("level", 1)) >= REBIRTH_LEVEL,
		"the starter reaches the rebirth level gate",
	)

	# --- Rebirth, two-step confirm ------------------------------------------
	await _select_tab("upgrades")
	var eligibility := Prestige.eligibility(_state(), _pack())
	_ok(eligibility.get("ok", false), "rebirth is eligible (%s)" % str(eligibility.get("code", "ok")))
	if not eligibility.get("ok", false):
		return
	var roster_before := _state().agents.size()
	var prestige_screen := _app.get("_prestige_screen") as PrestigeScreen
	var rebirth := prestige_screen.rebirth_button()
	_ok(rebirth != null and not rebirth.disabled, "the rebirth button is enabled")
	if rebirth == null:
		return
	rebirth.pressed.emit()
	_ok(_state().prestige_chips() == 0, "the first tap only arms the confirm")
	rebirth.pressed.emit()
	await process_frame
	_ok(_state().prestige_chips() > 0, "the second tap banks chips")
	_ok(_state().agents.size() == roster_before, "the roster survives rebirth")
	_ok(_state().assignments.is_empty(), "rebirth clears running operations")
	_ok(int(_state().agents["hero_volt"].get("level", 1)) == 1, "rebirth resets levels")
	_ok(_objective_step() == 2, "guidance re-arms for the new run")

	# --- Persistence --------------------------------------------------------
	var loaded := SaveService.load_state(PACK_ID)
	var restored := loaded.get("state") as GameState
	_ok(restored != null, "the demo state is on disk")
	if restored != null:
		_ok(restored.prestige_chips() > 0, "chips persist through a reload")
		_ok(restored.agents.size() == roster_before, "the roster persists through a reload")
		_ok(restored.squads.has("squad_s_raid"), "the manual lineup persists through a reload")
	_completed = true


func _finish() -> void:
	print("")
	# A runtime error aborts _play but not this function, so prove it reached the end.
	_ok(_completed, "the playthrough reached the end")
	if _failures.is_empty():
		print("PASS in-game playthrough")
	else:
		print("FAIL %d check(s)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	if _app != null and is_instance_valid(_app):
		_app.queue_free()
		await process_frame
		await process_frame
	_restore_profile()
	quit(0 if _failures.is_empty() else 1)


func _select_tab(tab_id: String) -> void:
	var button := _app.find_child("Tab_%s" % tab_id, true, false) as Button
	if button == null:
		_failures.append("tab '%s' is missing" % tab_id)
		return
	button.pressed.emit()
	await process_frame


func _deploy(task_id: String) -> bool:
	var board := _board()
	var button := board.deploy_button(task_id) if board != null else null
	if button == null:
		_failures.append("no deploy button for '%s'" % task_id)
		return false
	if button.disabled:
		_failures.append("deploy '%s' is disabled" % task_id)
		return false
	button.pressed.emit()
	await process_frame
	return true


func _train(agent_id: String) -> bool:
	var roster := _roster()
	var button := roster.train_button(agent_id) if roster != null else null
	if button == null:
		_failures.append("no train button for '%s'" % agent_id)
		return false
	if button.disabled:
		_failures.append("train '%s' is disabled" % agent_id)
		return false
	button.pressed.emit()
	await process_frame
	return true


func _recruit(role_id: String = "") -> bool:
	var roster := _roster()
	if roster == null:
		_failures.append("no roster screen")
		return false
	roster.select_recruit_role(role_id)
	await process_frame
	var button := roster.recruit_button()
	if button == null:
		_failures.append("no recruit button")
		return false
	if button.disabled:
		_failures.append("recruit button is disabled")
		return false
	button.pressed.emit()
	await process_frame
	return true


func _advance(seconds: int) -> void:
	var manual := _app.get("_clock") as Clock.Manual
	manual.advance(seconds)
	_app.call("_on_tick")
	await process_frame


func _objective() -> Dictionary:
	var value: Variant = _app.call("_next_objective")
	return value if value is Dictionary else {}


func _objective_step() -> int:
	return int(_objective().get("step", 0))


func _first_agent_with_role(role_id: String) -> String:
	var ids: Array = _state().agents.keys()
	ids.sort()
	for agent_id in ids:
		if str(_state().agents[agent_id].get("role_id", "")) == role_id:
			return str(agent_id)
	return ""


func _board() -> TaskBoard:
	return _app.get("_task_board") as TaskBoard


func _roster() -> RosterScreen:
	return _app.get("_roster") as RosterScreen


func _teams() -> TeamScreen:
	return _app.get("_teams") as TeamScreen


func _state() -> GameState:
	return _app.get("_state") as GameState


func _pack() -> GamePack:
	return _app.get("_pack") as GamePack


func _ok(condition: bool, message: String) -> void:
	if condition:
		print("  ok    %s" % message)
	else:
		_failures.append(message)
		print("  FAIL  %s" % message)


## Keeps the player's real progress out of the demo.
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
	print("restored %d saved profile file(s)" % _saved.size())

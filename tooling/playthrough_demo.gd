extends SceneTree
## End-to-end in-game demo: boots the real app scene and plays it through the UI.
##
##   godot --headless --path . -s res://tooling/playthrough_demo.gd
##
## Every action is a real button press on the real screens: Missions, Heroes and
## Upgrades tabs, Deploy, Train, Recruit, Research and the two-step Rebirth. The
## only thing faked is the clock, so an operation settles immediately.
##
## The run starts with the pack's actual 50 Credits and no grant. It earns the
## City Command Level 3 gate with ordinary Street deployments, hires only from
## the two visible offers (pressing the offer's own button), pays for training,
## then trains the hired Tech to the Signal Pursuit rating gate. There is no
## direct hidden-role recruitment and no mutated resource or progress total.
##
## The demo owns the profile while it runs: the player's save is read into memory,
## removed, and restored after the app is freed, so a failed demo cannot corrupt
## real progress.

const PACK_ID := "hero_hq"
const TECH_GATE_RATING := 110
const REBIRTH_LEVEL := 7
const REBIRTH_EARNINGS := 4000.0
const MAX_CITY_STEPS := 400
const MAX_WORK_CYCLES := 140
const MAX_TRAINING_SESSIONS := 160

var _app: Control
var _saved: Dictionary = {}
var _failures: Array[String] = []
var _completed := false
var _started_utc := 0
var _dispatch_count := 0


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
	if _state() == null:
		return
	var timer := _app.get("_timer") as Timer
	if timer != null:
		timer.stop()
	# Swap the wall clock for a manual one so operations settle on command.
	var manual := Clock.Manual.new(int(_state().last_settled_utc))
	_started_utc = manual.now_utc()
	_app.set("_clock", manual)
	var starting_credits := float(_pack().starting_resources.get("credits", 0.0))
	_ok(
		is_equal_approx(_state().resource("credits"), starting_credits),
		"the fresh save starts with the pack's %d Credits (no demo grant)" % int(starting_credits),
	)
	print("NO_GRANT_START credits=%.0f intel=%.0f agents=%d" % [
		_state().resource("credits"),
		_state().resource("intel"),
		_state().agents.size(),
	])


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

	# --- Heroes: train once, then earn the visible Tech offer ---------------
	await _select_tab("heroes")
	var roster := _roster()
	_ok(roster != null, "heroes tab built the roster")
	if roster == null:
		return
	_ok(await _train("hero_volt"), "the starter trains with earned Credits")
	_ok(float(_state().agents["hero_volt"]["xp"]) > 0.0, "training granted XP")
	_ok(_roster().recruit_offer_count() == 2, "the Heroes panel shows two offers")

	var recruit_start := _state().agents.size()
	var tech := await _hire_visible_role("tech")
	_ok(not tech.is_empty(), "the visible Tech offer recruits")
	_ok(_state().agents.size() == recruit_start + 1, "one hire adds exactly one operative")
	if tech.is_empty():
		return
	_ok(_first_agent_with_role("tech") == tech, "the requested Tech joins on the first hire")

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

	# --- Earn City, then train the hired Tech to its role gate --------------
	_ok(
		await _reach_city(),
		"normal Street work and visible hires reach Command Level 3 without a grant",
	)
	if CommandProgression.current_level(_state(), _pack()) < 3:
		return

	var tech_sessions := 0
	while AgentRules.rating(_state().agents[tech]) < TECH_GATE_RATING \
		and tech_sessions < MAX_TRAINING_SESSIONS:
		var cost := Simulation.training_cost(_state(), _pack(), tech)
		if _state().resource("credits") + 0.0001 < float(cost):
			if not await _work_until_credits(cost):
				_ok(false, "the City route can fund the Tech's training")
				return
			continue
		if not await _train_visible(tech):
			return
		tech_sessions += 1
	_ok(
		AgentRules.rating(_state().agents[tech]) >= TECH_GATE_RATING,
		"the Tech reaches the 110 rating gate (%d sessions)" % tech_sessions,
	)
	print("TECH_GATE t=%s sessions=%d rating=%d credits=%.0f" % [
		_clock(),
		tech_sessions,
		AgentRules.rating(_state().agents[tech]),
		_state().resource("credits"),
	])

	# --- The role and Command Level gates open ------------------------------
	await _select_tab("missions")
	_ok(not _board().deploy_button("s_pursuit").disabled, "Signal Pursuit unlocks with City and a Tech")
	var intel_before := _state().resource("intel")
	_ok(await _deploy("s_pursuit"), "the gated operation deploys")
	await _advance(int(_pack().task("s_pursuit").get("base_seconds", 70)))
	_ok(_state().resource("intel") > intel_before, "the gated operation pays Intel")

	# --- Earn the research and rebirth gates --------------------------------
	var runs := 0
	while _state().earned_total("credits") < REBIRTH_EARNINGS + 200.0 and runs < 60:
		runs += 1
		if not await _work_cycle():
			_ok(false, "the operation loop earns the rebirth gate")
			return
	_ok(
		_state().earned_total("credits") >= REBIRTH_EARNINGS,
		"lifetime earnings clear the rebirth gate (%d work cycles)" % runs,
	)

	# --- Research -----------------------------------------------------------
	await _settle_all()
	await _select_tab("upgrades")
	var research := _app.find_child("Research_ops_reward", true, false) as Button
	_ok(research != null, "the research row renders in Upgrades")
	if research == null:
		return
	var intel_pre := _state().resource("intel")
	_ok(not research.disabled, "the payout research is affordable with earned Intel")
	research.pressed.emit()
	await process_frame
	_ok(int(Research.rank(_state(), "ops_reward")) == 1, "payout research bought a rank")
	_ok(_state().resource("intel") < intel_pre, "research spent Intel")
	print("RESEARCH t=%s intel_before=%.0f intel_after=%.0f rank=%d" % [
		_clock(),
		intel_pre,
		_state().resource("intel"),
		int(Research.rank(_state(), "ops_reward")),
	])

	# --- Reach the rebirth level gate ---------------------------------------
	var sessions := 0
	while int(_state().agents["hero_volt"].get("level", 1)) < REBIRTH_LEVEL \
		and sessions < MAX_TRAINING_SESSIONS:
		var cost := Simulation.training_cost(_state(), _pack(), "hero_volt")
		if _state().resource("credits") + 0.0001 < float(cost):
			if not await _work_until_credits(cost):
				_ok(false, "the operation loop can fund the starter's next level")
				return
			continue
		if not await _train_visible("hero_volt"):
			return
		sessions += 1
	_ok(
		int(_state().agents["hero_volt"].get("level", 1)) >= REBIRTH_LEVEL,
		"the starter reaches the rebirth level gate (%d sessions)" % sessions,
	)
	print("STARTER_LEVEL t=%s level=%d sessions=%d lifetime=%.0f credits=%.0f" % [
		_clock(),
		int(_state().agents["hero_volt"].get("level", 1)),
		sessions,
		_state().earned_total("credits"),
		_state().resource("credits"),
	])

	# --- Rebirth, two-step confirm ------------------------------------------
	await _settle_all()
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


## Hires the first affordable visible offer with `role_id`.
##
## The preferred role must already be on one of the two cards. If it is visible
## but still unaffordable, ordinary Street work pays for it; no substitute is
## bought and no hidden slot is scanned.
func _hire_visible_role(role_id: String) -> String:
	var guard := 0
	while not _has_role(role_id) and guard < 100:
		guard += 1
		if await _recruit_visible([role_id]):
			await process_frame
			return _first_agent_with_role(role_id)
		if not await _work_cycle():
			_ok(false, "the visible %s offer can be earned with normal work" % role_id)
			return ""
	return _first_agent_with_role(role_id)


## earns Command Level 3 through Street operations and visible hires.
func _reach_city() -> bool:
	var steps := 0
	while CommandProgression.current_level(_state(), _pack()) < 3 and steps < MAX_CITY_STEPS:
		steps += 1
		if int(_state().agents["hero_volt"].get("level", 1)) < 2:
			var train_cost := Simulation.training_cost(_state(), _pack(), "hero_volt")
			if _state().resource("credits") + 0.0001 >= float(train_cost):
				if not await _train_visible("hero_volt"):
					return false
				continue
		if _state().agents.size() < 4:
			if await _recruit_visible():
				continue
		if not await _work_cycle():
			_ok(false, "the Street loop reaches City without a deadlock")
			return false
	await _settle_all()
	var reached := CommandProgression.current_level(_state(), _pack()) >= 3
	if reached:
		print("CITY_ENTRY t=%s steps=%d dispatches=%d tasks=%d lifetime=%.0f credits=%.0f agents=%d roles=%d" % [
			_clock(),
			steps,
			_dispatch_count,
			_state().tasks_completed(),
			_state().earned_total("credits"),
			_state().resource("credits"),
			_state().agents.size(),
			_distinct_roles(),
		])
	return reached


## Trains the selected agent after ensuring the Heroes screen is visible.
func _train_visible(agent_id: String) -> bool:
	var cost := Simulation.training_cost(_state(), _pack(), agent_id)
	if cost < 0 or _state().resource("credits") + 0.0001 < float(cost):
		return false
	await _select_tab("heroes")
	return await _train(agent_id)


## Presses one of the two visible offer buttons. Empty `preferred` takes the
## cheapest affordable card; otherwise a matching visible role is required.
func _recruit_visible(preferred: Array = []) -> bool:
	await _select_tab("heroes")
	var screen := _roster()
	if screen == null:
		_ok(false, "the Heroes screen is available for recruitment")
		return false
	var offers := Recruitment.offers(_state(), _pack())
	var visible: Array[String] = []
	var chosen: Dictionary = {}
	var cheapest: Dictionary = {}
	for raw in offers:
		var offer: Dictionary = raw
		var offer_id := str(offer.get("id", ""))
		var button := screen.recruit_offer_button(offer_id)
		visible.append("%s/%s/%dcr" % [
			offer_id, str(offer.get("role_id", "")), int(offer.get("cost", 0)),
		])
		if button == null or button.disabled:
			continue
		if cheapest.is_empty() or int(offer.get("cost", 0)) < int(cheapest.get("cost", 0)):
			cheapest = offer
		if preferred.is_empty():
			continue
		if preferred.has(str(offer.get("role_id", ""))) and chosen.is_empty():
			chosen = offer
	if chosen.is_empty() and preferred.is_empty():
		chosen = cheapest
	if chosen.is_empty():
		return false
	var offer_id := str(chosen.get("id", ""))
	var button := screen.recruit_offer_button(offer_id)
	if button == null or button.disabled:
		return false
	var before := _state().agents.size()
	button.pressed.emit()
	await process_frame
	if _state().agents.size() != before + 1:
		_ok(false, "the selected visible offer completed its hire")
		return false
	print("  RECRUIT t=%s visible=%s -> %s/%s/%dcr" % [
		_clock(),
		" + ".join(visible),
		offer_id,
		str(chosen.get("role_id", "")),
		int(chosen.get("cost", 0)),
	])
	return true


## Deploys every idle hero to its best legal solo operation through the board,
## settles the earliest completion, and returns whether time advanced.
func _work_cycle() -> bool:
	await _select_tab("missions")
	var dispatched := 0
	var guard := 0
	while guard < 8:
		guard += 1
		var task_id := _best_ready_solo_task()
		if task_id.is_empty():
			break
		if not await _deploy(task_id):
			return false
		dispatched += 1
	if _state().assignments.is_empty():
		if dispatched == 0:
			_ok(false, "a legal solo operation is available for idle heroes")
		return false
	return await _settle_next()


func _work_until_credits(target: int) -> bool:
	var guard := 0
	while _state().resource("credits") + 0.0001 < float(target) and guard < MAX_WORK_CYCLES:
		guard += 1
		if not await _work_cycle():
			return false
	return _state().resource("credits") + 0.0001 >= float(target)


func _best_ready_solo_task() -> String:
	var screen := _board()
	if screen == null:
		return ""
	var best := ""
	var best_rate := -1.0
	var task_ids: Array = _pack().task_ids()
	task_ids.sort()
	for raw_id in task_ids:
		var task_id := str(raw_id)
		var task := _pack().task(task_id)
		if int(task.get("required_agent_count", 1)) != 1:
			continue
		var button := screen.deploy_button(task_id)
		if button == null or button.disabled:
			continue
		var rate := _credit_rate(task)
		if rate > best_rate + 0.0001 \
			or (is_equal_approx(rate, best_rate) and (best.is_empty() or task_id < best)):
			best = task_id
			best_rate = rate
	return best


func _settle_next() -> bool:
	var ends := -1
	for raw in _state().assignments.values():
		if not (raw is Dictionary):
			continue
		var end := int((raw as Dictionary).get("ends_utc", 0))
		if ends < 0 or end < ends:
			ends = end
	if ends < 0:
		return false
	var now := _manual().now_utc()
	await _advance(maxi(ends - now, 1))
	return true


func _settle_all() -> bool:
	var guard := 0
	while not _state().assignments.is_empty() and guard < 200:
		guard += 1
		if not await _settle_next():
			return false
	return _state().assignments.is_empty()


func _credit_rate(task: Dictionary) -> float:
	var rewards: Variant = task.get("rewards", {})
	if not (rewards is Dictionary):
		return 0.0
	return float((rewards as Dictionary).get("credits", 0.0)) / float(
		maxi(int(task.get("base_seconds", 1)), 1)
	)


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
	var before := _state().assignments.size()
	button.pressed.emit()
	await process_frame
	if _state().assignments.size() != before + 1:
		_failures.append("deploy '%s' did not schedule an operation" % task_id)
		return false
	_dispatch_count += 1
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


func _advance(seconds: int) -> void:
	var manual := _manual()
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


func _has_role(role_id: String) -> bool:
	for raw in _state().agents.values():
		if raw is Dictionary and str((raw as Dictionary).get("role_id", "")) == role_id:
			return true
	return false


func _distinct_roles() -> int:
	var roles: Dictionary = {}
	for raw in _state().agents.values():
		if raw is Dictionary:
			roles[str((raw as Dictionary).get("role_id", ""))] = true
	return roles.size()


func _clock() -> String:
	if _app == null:
		return "0:00"
	var seconds := maxi(_manual().now_utc() - _started_utc, 0)
	return "%d:%02d" % [int(seconds / 60), int(seconds % 60)]


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


func _manual() -> Clock.Manual:
	return _app.get("_clock") as Clock.Manual


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

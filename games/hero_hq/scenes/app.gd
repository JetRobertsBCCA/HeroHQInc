extends Control
## HERO//HQ composition root (game layer).
##
## The only place allowed to name the title: it loads the hero_hq pack, restores
## or creates the state, settles the time the player was away, and wires the HQ,
## roster and task screens. Shared behaviour lives in `framework/`.
##
## One timer drives everything. Each tick settles elapsed time through the same
## `Simulation.simulate_delta` used at launch, so a task finishes the same way
## whether the app was open or closed.

const PACK_ID := "hero_hq"
const STARTING_SEED := 1
const HOME_TAB := "hq"
const HEROES_TAB := "heroes"
const MISSIONS_TAB := "missions"
const TEAMS_TAB := "teams"
const UPGRADES_TAB := "upgrades"
const TICK_SECONDS := 1.0
const SAVE_EVERY_TICKS := 10
const EVENT_LOG_LIMIT := 4
const NETWORK_COMPLETION_MS := 2400
const UI_EXTENSION := "hero_hq.ui"

var _pack: GamePack
var _state: GameState
## Profile slot loaded by the composition root. Production uses the pack id;
## tests override it before add_child so bootstrapping never touches a real save.
var _profile_id: String = PACK_ID
var _shell: ScreenShell
var _clock: Clock = Clock.new()
var _timer: Timer
var _settled_seconds: float = 0.0
var _events_log: Array[String] = []
var _task_board: TaskBoard
var _objective_card: Control
var _command_card: CommandProgressCard
var _roster: RosterScreen
var _teams: TeamScreen
var _prestige_screen: PrestigeScreen
var _focus_card: HeroFocusCard
var _network_panel: HeroNetworkPanel
var _motion_button: Button
var _network_completion: Dictionary = {}
var _network_completion_until_msec: int = 0
var _reduced_motion: bool = false
var _tick_count: int = 0


func _ready() -> void:
	UILayout.fill(self)
	var loaded := GamePackLoader.load_pack(PACK_ID)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		_build_error_view(errors)
		return
	_pack = loaded["pack"]
	_state = _restore_or_create_state()
	_reduced_motion = _read_reduced_motion()
	_settle_absence()
	# Re-arm a persisted auto-repeat after the absence has settled, before the
	# shell is built, so the operation a player left running picks up again.
	_maybe_auto_repeat(_clock.now_utc())
	_build_shell()
	_start_timer()


func _exit_tree() -> void:
	if _state != null:
		SaveService.save_state(_state)


func _restore_or_create_state() -> GameState:
	var loaded := SaveService.load_state(_profile_id)
	var existing: Variant = loaded.get("state", null)
	if existing is GameState:
		var state: GameState = existing
		state.pack_content_version = _pack.content_version
		# A save from an incomplete content build can restore without a roster.
		# Without an agent no task can start, so rebuild it from pack data.
		if state.agents.is_empty():
			Simulation.seed_missing_starter_agents(state, _pack)
		return state
	var fresh := Simulation.new_state(_pack, STARTING_SEED, _clock.now_utc())
	fresh.game_id = _profile_id
	return fresh


## Advances the simulation by the time the app was closed, and logs whatever
## finished while the player was away.
func _settle_absence() -> void:
	var elapsed := float(_clock.now_utc() - _state.last_settled_utc)
	var outcome := Simulation.simulate_delta(_state, elapsed, _pack)
	_state = outcome["state"]
	_settled_seconds = float(outcome["applied_seconds"])
	_record_events(outcome.get("events", []))
	# Focus regenerates in wall-clock time too; settle it once at launch so a
	# return after a long absence starts with the correct bank and timestamp.
	HeroFocus.settle(_state, _pack, _clock.now_utc())
	SaveService.save_state(_state)


func _build_shell() -> void:
	_shell = ScreenShell.new()
	_shell.name = "ScreenShell"
	add_child(_shell)
	_shell.build(_pack)
	_shell.refresh(_state)
	_shell.tab_selected.connect(_on_tab_selected)
	_shell.select_tab(HOME_TAB)


func _start_timer() -> void:
	_timer = Timer.new()
	_timer.name = "Tick"
	_timer.wait_time = TICK_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)


func _on_tick() -> void:
	var now := _clock.now_utc()
	HeroFocus.settle(_state, _pack, now)
	var elapsed := float(now - _state.last_settled_utc)
	if elapsed >= 1.0:
		var outcome := Simulation.simulate_delta(_state, elapsed, _pack)
		_state = outcome["state"]
		var events: Array = outcome.get("events", [])
		_tick_count += 1
		if not events.is_empty():
			_record_events(events)
			SaveService.save_state(_state)
			_maybe_auto_repeat(now)
			_refresh_content()
		else:
			_shell.refresh(_state)
			if _tick_count % SAVE_EVERY_TICKS == 0:
				SaveService.save_state(_state)
	if _task_board != null and is_instance_valid(_task_board):
		_task_board.tick(now)
	if _focus_card != null and is_instance_valid(_focus_card):
		_focus_card.tick(now)
	if _network_panel != null and is_instance_valid(_network_panel):
		_network_panel.tick(_network_feed(now))


func _on_tab_selected(tab_id: String) -> void:
	_task_board = null
	_objective_card = null
	_command_card = null
	_roster = null
	_teams = null
	_prestige_screen = null
	_focus_card = null
	_network_panel = null
	_motion_button = null
	if tab_id == HOME_TAB:
		_shell.set_content(_build_hq_content())
		return
	if tab_id == MISSIONS_TAB:
		_task_board = TaskBoard.new()
		_task_board.name = "TaskBoard"
		_task_board.deploy_requested.connect(_on_deploy_requested)
		_task_board.auto_repeat_retry_requested.connect(_on_auto_repeat_retry_requested)
		_task_board.refresh(_pack, _state, _clock.now_utc())
		_shell.set_content(_task_board)
		return
	if tab_id == TEAMS_TAB:
		_teams = TeamScreen.new()
		_teams.name = "TeamScreen"
		_teams.deploy_requested.connect(_on_squad_deploy_requested)
		_teams.squads_changed.connect(_on_squads_changed)
		_teams.auto_repeat_retry_requested.connect(_on_auto_repeat_retry_requested)
		_teams.refresh(_pack, _state)
		_shell.set_content(_teams)
		return
	if tab_id == HEROES_TAB:
		_roster = RosterScreen.new()
		_roster.name = "RosterScreen"
		_roster.train_requested.connect(_on_train_requested)
		_roster.recruit_requested.connect(_on_recruit_requested)
		_roster.refresh(_pack, _state)
		_shell.set_content(_roster)
		return
	if tab_id == UPGRADES_TAB:
		_prestige_screen = PrestigeScreen.new()
		_prestige_screen.name = "PrestigeScreen"
		_prestige_screen.rebirth_requested.connect(_on_rebirth_requested)
		_prestige_screen.research_purchase_requested.connect(_on_research_requested)
		_prestige_screen.refresh(_pack, _state)
		_shell.set_content(_prestige_screen)
		return
	_shell.set_content(_build_placeholder(tab_id))


func _refresh_content() -> void:
	_shell.refresh(_state)
	_on_tab_selected(_shell.current_tab())


func _on_deploy_requested(task_id: String) -> void:
	var result := Simulation.deploy(_state, _pack, task_id, _clock.now_utc())
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("ui.deploy_failed", "Cannot deploy"),
			_pack.label(
				"ui.blocked_%s" % str(result.get("code", "")),
				str(result.get("code", "")),
			),
		])
		_refresh_content()
		return
	if Research.unlocked(_state, _pack, Research.EFFECT_AUTO_REPEAT):
		AutoRepeat.remember(_state, task_id)
	SaveService.save_state(_state)
	_refresh_content()


func _on_train_requested(agent_id: String) -> void:
	var result := Simulation.train_agent(_state, _pack, agent_id)
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("ui.train", "Train"),
			_pack.label(
				"ui.blocked_%s" % str(result.get("code", "")),
				str(result.get("code", "")),
			),
		])
		_refresh_content()
		return
	_record_events(result.get("events", []))
	SaveService.save_state(_state)
	# Training can cross a saved lineup's rating gate; retry immediately so the
	# banner moves from Paused to Armed without waiting for another completion.
	_maybe_auto_repeat(_clock.now_utc())
	_refresh_content()


func _on_recruit_requested(role_id: String) -> void:
	var result := Recruitment.recruit(_state, _pack, role_id)
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("ui.recruit", "Recruit"),
			_pack.label(
				"ui.blocked_%s" % str(result.get("code", "")),
				str(result.get("code", "")),
			),
		])
		_refresh_content()
		return
	_log("%s %s" % [
		_pack.label("ui.recruited", "Recruited"),
		str(result["name"]),
	])
	SaveService.save_state(_state)
	_maybe_auto_repeat(_clock.now_utc())
	_refresh_content()


func _on_squad_deploy_requested(task_id: String, agent_ids: Array) -> void:
	var result := Simulation.assign_task(_state, _pack, task_id, agent_ids, _clock.now_utc())
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("ui.deploy_failed", "Cannot deploy"),
			_pack.label(
				"ui.blocked_%s" % str(result.get("code", "")),
				str(result.get("code", "")),
			),
		])
		_refresh_content()
		return
	if Research.unlocked(_state, _pack, Research.EFFECT_AUTO_REPEAT):
		AutoRepeat.remember(_state, task_id, agent_ids)
	# Save the lineup that actually started so the rebuilt Teams row does not
	# fall back to an older preset that differs from the active operation.
	Squads.save(_state, task_id, agent_ids)
	SaveService.save_state(_state)
	_refresh_content()


## A saved lineup changed: persist it and rebuild the tab so the buttons match.
func _on_squads_changed() -> void:
	SaveService.save_state(_state)
	_refresh_content()


func _on_rebirth_requested() -> void:
	var result := Prestige.rebirth(_state, _pack, _clock.now_utc())
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("ui.prestige_button", "Rebirth"),
			_pack.label(
				"ui.blocked_%s" % str(result.get("code", "")),
				str(result.get("code", "")),
			),
		])
		_refresh_content()
		return
	_record_events([{
		"type": "prestige",
		"gained": int(result["gained"]),
		"chips": int(result["chips"]),
	}])
	AutoRepeat.forget(_state)
	SaveService.save_state(_state)
	_refresh_content()


func _on_focus_requested(assignment_id: String) -> void:
	var result := HeroFocus.spend_on_assignment(
		_state, _pack, assignment_id, _clock.now_utc()
	)
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("ui.focus", "Focus"),
			_focus_error_text(result),
		])
		SaveService.save_state(_state)
		_refresh_content()
		return
	var task_id := ""
	var assignment: Variant = _state.assignments.get(assignment_id, null)
	if assignment is Dictionary:
		task_id = str((assignment as Dictionary).get("task_id", ""))
	var task_name := _pack.label(
		str(_pack.task(task_id).get("name_key", "")), task_id
	)
	_log(_pack.label("ui.focus_used", "Focus pulse · -%ds on %s") % [
		int(result.get("saved_seconds", 0)),
		task_name,
	])
	SaveService.save_state(_state)
	_refresh_content()


func _focus_error_text(result: Dictionary) -> String:
	var code := str(result.get("code", ""))
	if code == HeroFocus.CODE_EMPTY:
		return _pack.label("ui.focus_empty", "No Focus. Next in %s.") % TextFormat.duration(
			float(HeroFocus.next_in_seconds(_state, _pack, _clock.now_utc()))
		)
	if code == HeroFocus.CODE_COOLDOWN:
		return _pack.label("ui.focus_cooldown", "Pulse ready in %s.") % TextFormat.duration(
			float(result.get("cooldown_seconds", 0))
		)
	if code == HeroFocus.CODE_FINISHED:
		return _pack.label("ui.focus_finished", "Operation already finished.")
	if code == HeroFocus.CODE_NO_TIME:
		return _pack.label("ui.focus_no_time", "Too little time remains.")
	if code == HeroFocus.CODE_UNKNOWN_ASSIGNMENT:
		return _pack.label("ui.focus_unknown", "Operation not found.")
	return _pack.label("ui.focus_unavailable", "Focus is not configured.")


func _on_research_requested(branch_id: String) -> void:
	var result := Research.buy(_state, _pack, branch_id)
	if not result.get("ok", false):
		_log("%s: %s" % [
			_pack.label("research.title", "Research"),
			_pack.label(
				"ui.blocked_%s" % str(result.get("code", "")),
				str(result.get("code", "")),
			),
		])
		_refresh_content()
		return
	_log("%s %s %d" % [
		_pack.label("research.title", "Research"),
		_pack.label("ui.research_rank", "Rank"),
		int(result["rank"]),
	])
	SaveService.save_state(_state)
	_refresh_content()


## Explicit Retry from the paused banner. The guarded resume re-evaluates the
## live roster, starts at most one operation, and never pays a completion by
## itself; if the rule is still blocked, the refreshed banner keeps the reason.
func _on_auto_repeat_retry_requested() -> void:
	_maybe_auto_repeat(_clock.now_utc())
	_refresh_content()


## Repeats the remembered operation once it finishes, but only when the
## research branch is bought. One repeat per completion, never a chain. The
## rule lives in the save, so this also works after the app was killed and the
## operation completed while it was closed.
func _maybe_auto_repeat(now: int) -> void:
	if AutoRepeat.task_id(_state).is_empty():
		return
	var result := AutoRepeat.resume(_state, _pack, now)
	if not result.get("ok", false):
		# A locked or removed task is dropped by resume(); persist that. Any
		# other refusal keeps the rule so the screen can explain it.
		SaveService.save_state(_state)
		return
	SaveService.save_state(_state)


func _build_hq_content() -> Control:
	var scroll := TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	column.add_child(_build_network_card())
	_objective_card = _build_objective_card()
	column.add_child(_objective_card)
	_command_card = CommandProgressCard.new()
	_command_card.name = "CommandProgressCard"
	_command_card.refresh(_pack, _state)
	column.add_child(_command_card)
	if HeroFocus.enabled(_pack):
		_focus_card = HeroFocusCard.new()
		_focus_card.name = "FocusCard"
		_focus_card.focus_requested.connect(_on_focus_requested)
		_focus_card.refresh(_pack, _state, _clock.now_utc())
		column.add_child(_focus_card)
	column.add_child(_info_row(
		_pack.label("ui.roster_active"),
		"%d / %d" % [_state.agents.size(), _pack.roster_capacity]
	))
	var status_text := _pack.label("ui.idle_status")
	if _state.assignments.size() > 0:
		status_text = "%s: %d" % [_pack.label("ui.active_operations"), _state.assignments.size()]
	elif _settled_seconds > 0.0:
		status_text = "%s (%s s)" % [_pack.label("ui.offline_settled"), str(int(_settled_seconds))]
	column.add_child(_info_row(_pack.label("ui.status"), status_text))
	column.add_child(_recent_events_panel())
	return scroll


## First-run guidance: one concrete next step, derived from live state so it
## cannot drift from what the game actually needs.
func _next_objective() -> Dictionary:
	var first_branch := ""
	var branches: Array = Research.branches(_pack)
	if not branches.is_empty() and branches[0] is Dictionary:
		first_branch = str((branches[0] as Dictionary).get("id", ""))
	if _state.tasks_completed() == 0:
		return {
			"step": 1,
			"done": false,
			"text": _pack.label("ui.objective_deploy", "Deploy your first operation from Missions."),
		}
	if Prestige.highest_level(_state) < 2:
		return {
			"step": 2,
		"done": false,
			"text": _pack.label("ui.objective_train", "Train an operative to level 2 in Heroes."),
		}
	if _state.agents.size() < 2:
		return {
			"step": 3,
			"done": false,
			"text": _pack.label("ui.objective_recruit", "Recruit a second operative in Heroes."),
		}
	if CommandProgression.current_level(_state, _pack) < CommandProgression.stage_unlock_level(_pack, "city"):
		return {
			"step": 4,
			"done": false,
			"text": _pack.label("ui.objective_city", "Reach Command Level 3 to unlock Citywide Defense."),
		}
	if not first_branch.is_empty() and Research.rank(_state, first_branch) == 0:
		return {
			"step": 4,
			"done": false,
			"text": _pack.label("ui.objective_research", "Buy your first Research rank in Upgrades."),
		}
	if _state.prestige_chips() == 0:
		return {
			"step": 5,
			"done": false,
			"text": _pack.label(
				"ui.objective_rebirth",
				"Reach level %d and %d lifetime Credits, then Rebirth in Upgrades."
			) % [Prestige.min_level(_pack), int(Prestige.threshold_amount(_pack))],
		}
	return {
		"step": 5,
		"done": true,
		"text": _pack.label(
			"ui.objective_done", "Starter goals complete — push the ladder, bank chips, repeat."
		),
	}


func _build_objective_card() -> Control:
	var objective := _next_objective()
	var panel := PanelContainer.new()
	panel.name = "ObjectiveCard"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)

	var heading := Label.new()
	heading.text = _pack.label("ui.objective_title", "Next objective")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	top.add_child(heading)

	var progress := Label.new()
	if bool(objective.get("done", false)):
		progress.text = _pack.label("ui.objective_complete", "Complete")
	else:
		progress.text = "%s %d / 5" % [
			_pack.label("ui.objective_step", "Step"), int(objective.get("step", 1)),
		]
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.add_theme_font_size_override("font_size", 11)
	progress.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	top.add_child(progress)

	var text := Label.new()
	text.text = str(objective.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.max_lines_visible = 2
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	column.add_child(text)
	return panel


func _build_network_card() -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = _pack.label("ui.network_title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	header.add_child(title)

	_motion_button = Button.new()
	_motion_button.name = "MotionToggle"
	_motion_button.toggle_mode = true
	_motion_button.flat = true
	_motion_button.button_pressed = _reduced_motion
	_motion_button.custom_minimum_size = Vector2(0, 44)
	_motion_button.add_theme_font_size_override("font_size", 14)
	_motion_button.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_motion_button.add_theme_color_override("font_pressed_color", ThemeTokens.color(_pack, "accent"))
	_motion_button.tooltip_text = _pack.label(
		"ui.motion_hint", "Turns off the network pulse animation."
	)
	_motion_button.toggled.connect(_on_motion_toggled)
	header.add_child(_motion_button)
	_update_motion_button()

	var network := HeroNetworkPanel.new()
	network.name = "OperationsNetwork"
	network.setup(_pack, _network_feed(_clock.now_utc()), _reduced_motion)
	column.add_child(network)
	_network_panel = network
	return panel


## Compact, deterministic feed for the operations map. The panel receives text
## and numbers, never the GameState, so drawing cannot mutate simulation state.
func _network_feed(now: int) -> Dictionary:
	var activities: Array = []
	var active_agents: Dictionary = {}
	var assignment_ids: Array = _state.assignments.keys()
	assignment_ids.sort()
	for raw_id in assignment_ids:
		var assignment_value: Variant = _state.assignments[raw_id]
		if not (assignment_value is Dictionary):
			continue
		var assignment: Dictionary = assignment_value
		var task_id := str(assignment.get("task_id", ""))
		var agent_ids: Array = []
		var raw_agents: Variant = assignment.get("agent_ids", [])
		if raw_agents is Array:
			agent_ids = raw_agents
		for raw_agent in agent_ids:
			active_agents[str(raw_agent)] = true
		var started := int(assignment.get("started_utc", now))
		var ends := int(assignment.get("ends_utc", now))
		var total := maxi(ends - started, 1)
		var remaining := maxi(ends - now, 0)
		var progress := clampf(1.0 - float(remaining) / float(total), 0.0, 1.0)
		var task := _pack.task(task_id)
		activities.append({
			"assignment_id": str(raw_id),
			"task_id": task_id,
			"title": _pack.label(str(task.get("name_key", "")), task_id),
			"squad": agent_ids.size() > 1,
			"agent_count": agent_ids.size(),
			"crew": _network_crew(agent_ids),
			"progress": progress,
			"remaining": TextFormat.duration(float(remaining)),
		})

	var idle := 0
	for raw_agent_id in _state.agents.keys():
		var agent_id := str(raw_agent_id)
		if active_agents.has(agent_id):
			continue
		var record: Variant = _state.agents[raw_agent_id]
		if record is Dictionary and str((record as Dictionary).get("activity", "available")) == "available":
			idle += 1

	return {
		"activities": activities,
		"idle_count": idle,
		"completion": _network_completion_feed(),
	}


func _network_crew(agent_ids: Array) -> String:
	var names: Array[String] = []
	for raw_id in agent_ids:
		var agent_id := str(raw_id)
		var record: Variant = _state.agents.get(agent_id, {})
		names.append(_pack.agent_name(agent_id, record if record is Dictionary else {}))
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	return "%s +%d" % [names[0], names.size() - 1]


func _network_completion_feed() -> Dictionary:
	if _network_completion.is_empty():
		return {}
	if Time.get_ticks_msec() >= _network_completion_until_msec:
		_network_completion.clear()
		return {}
	return _network_completion.duplicate(true)


func _queue_network_completion(entry: Dictionary) -> void:
	var task_id := str(entry.get("task_id", ""))
	var task := _pack.task(task_id)
	var reward_text := ""
	var rewards: Variant = entry.get("rewards", null)
	if rewards is Dictionary:
		reward_text = TextFormat.rewards(_pack, rewards)
	_network_completion = {
		"id": "%s:%s" % [str(entry.get("assignment_id", "")), str(entry.get("ends_utc", ""))],
		"title": _pack.label(str(task.get("name_key", "")), task_id),
		"reward": reward_text,
	}
	_network_completion_until_msec = Time.get_ticks_msec() + NETWORK_COMPLETION_MS


func _read_reduced_motion() -> bool:
	var settings: Variant = _state.extensions.get(UI_EXTENSION, {})
	if settings is Dictionary:
		return bool((settings as Dictionary).get("reduced_motion", false))
	return false


func _on_motion_toggled(enabled: bool) -> void:
	_reduced_motion = enabled
	_update_motion_button()
	if _network_panel != null and is_instance_valid(_network_panel):
		_network_panel.set_reduced_motion(_reduced_motion)
	var settings: Variant = _state.extensions.get(UI_EXTENSION, {})
	var values: Dictionary = settings if settings is Dictionary else {}
	values["reduced_motion"] = _reduced_motion
	_state.extensions[UI_EXTENSION] = values
	SaveService.save_state(_state)


func _update_motion_button() -> void:
	if _motion_button == null:
		return
	_motion_button.text = _pack.label(
		"ui.motion_on" if _reduced_motion else "ui.motion_off",
		"Reduce motion: on" if _reduced_motion else "Reduce motion: off",
	)


func _recent_events_panel() -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = _pack.label("ui.recent_events")
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(heading)

	if _events_log.is_empty():
		var empty := Label.new()
		empty.text = _pack.label("ui.no_events")
		empty.add_theme_font_size_override("font_size", 12)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
		column.add_child(empty)
		return panel

	for line in _events_log:
		var label := Label.new()
		label.text = str(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		column.add_child(label)
	return panel


func _info_row(caption: String, value: String) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	row.add_child(caption_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return panel


func _build_placeholder(tab_id: String) -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = _pack.label("tabs.%s" % tab_id, tab_id)
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	column.add_child(heading)

	var note := Label.new()
	note.text = _pack.label("ui.section_placeholder")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(note)
	return panel


func _record_events(events: Array) -> void:
	for event in events:
		if not (event is Dictionary):
			continue
		var entry: Dictionary = event
		var event_type := str(entry.get("type", ""))
		if event_type == "task_completed":
			_queue_network_completion(entry)
			_log(_task_completed_text(entry))
		elif event_type == "level_up":
			_log(_level_up_text(entry))
		elif event_type == "prestige":
			_log(_prestige_text(entry))


func _task_completed_text(entry: Dictionary) -> String:
	var task_id := str(entry.get("task_id", ""))
	var task_name := _pack.label(str(_pack.task(task_id).get("name_key", "")), task_id)
	var suffix := ""
	var rewards: Variant = entry.get("rewards", null)
	if rewards is Dictionary and not (rewards as Dictionary).is_empty():
		suffix = "  %s" % TextFormat.rewards(_pack, rewards)
	return "%s %s%s" % [task_name, _pack.label("ui.task_complete", "complete"), suffix]


func _level_up_text(entry: Dictionary) -> String:
	var agent_id := str(entry.get("agent_id", ""))
	var record: Variant = _state.agents.get(agent_id, null)
	var agent_name := _pack.agent_name(agent_id, record if record is Dictionary else {})
	return "%s %s %d" % [
		agent_name,
		_pack.label("ui.level_up", "reached level"),
		int(entry.get("level", 1)),
	]


func _prestige_text(entry: Dictionary) -> String:
	return "%s +%d (%s %d)" % [
		_pack.label("ui.prestige_done", "Rebirth complete"),
		int(entry.get("gained", 0)),
		_pack.label("ui.prestige_chips", "chips"),
		int(entry.get("chips", 0)),
	]


func _log(line: String) -> void:
	_events_log.push_front(line)
	while _events_log.size() > EVENT_LOG_LIMIT:
		_events_log.pop_back()


func _build_error_view(errors: Array) -> void:
	var margin := MarginContainer.new()
	UILayout.fill(margin)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = "Content pack failed validation"
	heading.add_theme_font_size_override("font_size", 18)
	column.add_child(heading)

	for error in errors:
		var line := Label.new()
		if error is Dictionary:
			var entry: Dictionary = error
			line.text = "[%s] %s" % [str(entry.get("code", "")), str(entry.get("message", ""))]
		else:
			line.text = str(error)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		column.add_child(line)

	var hint := Label.new()
	hint.text = "godot --headless --path . -s res://tooling/validate_packs.gd"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	column.add_child(hint)

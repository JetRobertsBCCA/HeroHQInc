class_name AutoPatrolCard
extends PanelContainer
## One explicit solo automation channel, configured by the player.
##
## The card is a view over `AutoRepeat.patrol_status`: it never schedules work
## itself. It offers only solo operations the chosen agent is qualified for and
## honors Command, role and rating gates when listing them. The Enable/Pause
## action is a separate, deliberate step after both choices are made.

signal configure_requested(task_id: String, agent_id: String)
signal enabled_requested(enabled: bool)

const MIN_TAP_HEIGHT := 48

var _pack: GamePack
var _state: GameState
var _snapshot: Dictionary = {}
var _title: Label
var _status: Label
var _summary: Label
var _selectors: HBoxContainer
var _agent_button: Button
var _operation_button: Button
var _toggle: Button
var _reason: Label
var _agent_picker: VBoxContainer
var _operation_picker: VBoxContainer
var _open_picker := ""


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_snapshot = AutoRepeat.patrol_status(state, pack)
	_ensure_built()
	_update()


func status_text() -> String:
	return _status.text if _status != null else ""


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func reason_text() -> String:
	return _reason.text if _reason != null else ""


func agent_button() -> Button:
	return _agent_button


func operation_button() -> Button:
	return _operation_button


func toggle_button() -> Button:
	return _toggle


func agent_choice_button(agent_id: String) -> Button:
	if _agent_picker == null:
		return null
	return _agent_picker.find_child("agentChoice_%s" % agent_id, true, false) as Button


func operation_choice_button(task_id: String) -> Button:
	if _operation_picker == null:
		return null
	return _operation_picker.find_child("OperationChoice_%s" % task_id, true, false) as Button


func open_agent_picker() -> void:
	_open_picker = "agent"
	_update()


func open_operation_picker() -> void:
	_open_picker = "operation"
	_update()


func picker_open() -> String:
	return _open_picker


func _ensure_built() -> void:
	if _title != null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeTokens.color(_pack, "panel", Color(0.07, 0.11, 0.16))
	style.border_color = ThemeTokens.color(_pack, "accent", Color(0.3, 0.7, 1.0))
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)

	_title = Label.new()
	_title.name = "AutoPatrolTitle"
	_title.text = _pack.label("ui.auto_patrol_title", "Auto Patrol").to_upper()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	header.add_child(_title)

	_status = Label.new()
	_status.name = "AutoPatrolStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", 12)
	header.add_child(_status)

	_summary = Label.new()
	_summary.name = "AutoPatrolSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.max_lines_visible = 2
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", ThemeTokens.color(_pack, "text"))
	column.add_child(_summary)

	_selectors = HBoxContainer.new()
	_selectors.name = "AutoPatrolSelectors"
	_selectors.add_theme_constant_override("separation", 6)
	column.add_child(_selectors)

	_agent_button = _choice_button("AutoPatrolAgent")
	_selectors.add_child(_agent_button)
	_operation_button = _choice_button("AutoPatrolOperation")
	_selectors.add_child(_operation_button)

	_agent_picker = VBoxContainer.new()
	_agent_picker.name = "AutoPatrolAgentPicker"
	_agent_picker.add_theme_constant_override("separation", 4)
	column.add_child(_agent_picker)

	_operation_picker = VBoxContainer.new()
	_operation_picker.name = "AutoPatrolOperationPicker"
	_operation_picker.add_theme_constant_override("separation", 4)
	column.add_child(_operation_picker)

	_reason = Label.new()
	_reason.name = "AutoPatrolReason"
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.max_lines_visible = 3
	_reason.add_theme_font_size_override("font_size", 11)
	_reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(_reason)

	_toggle = Button.new()
	_toggle.name = "AutoPatrolToggle"
	_toggle.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	_toggle.add_theme_font_size_override("font_size", 12)
	_toggle.pressed.connect(_on_toggle_pressed)
	column.add_child(_toggle)


func _choice_button(button_name: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 11)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(_on_choice_pressed.bind(button_name))
	return button


func _update() -> void:
	var locked := str(_snapshot.get("code", "")) == AutoRepeat.CODE_LOCKED
	var configured := bool(_snapshot.get("configured", false))
	var enabled := bool(_snapshot.get("enabled", false))
	var running := bool(_snapshot.get("running", false))
	var task_id := str(_snapshot.get("task_id", ""))
	var agent_id := str(_snapshot.get("agent_id", ""))
	var has_selection := not task_id.is_empty() and not agent_id.is_empty()

	if locked:
		_status.text = _pack.label("ui.auto_patrol_locked", "Locked").to_upper()
		_summary.visible = false
		_selectors.visible = false
		_agent_picker.visible = false
		_operation_picker.visible = false
		_toggle.visible = false
		_reason.text = _locked_reason()
		_set_status_color("warning")
		_apply_border("warning")
		return

	_summary.visible = true
	_selectors.visible = true
	_toggle.visible = true
	_summary.text = _summary_text(task_id, agent_id)
	_agent_button.text = _pack.label("ui.auto_patrol_agent", "agent · %s") % _agent_name(agent_id) \
		if not agent_id.is_empty() else _pack.label("ui.auto_patrol_choose_agent", "Choose agent")
	_operation_button.text = _pack.label("ui.auto_patrol_operation", "Operation · %s") % _task_name(task_id) \
		if not task_id.is_empty() else _pack.label("ui.auto_patrol_choose_operation", "Choose operation")
	_toggle.text = _pack.label("ui.auto_patrol_disable", "Pause Auto Patrol") if enabled \
		else _pack.label("ui.auto_patrol_enable", "Enable Auto Patrol")
	_toggle.disabled = not configured or (not enabled and not has_selection)
	_reason.text = _reason_text()
	_update_pickers(agent_id, task_id)

	var status := _pack.label("ui.auto_patrol_not_set", "Not set")
	var token := "muted"
	if running:
		status = _pack.label("ui.auto_patrol_patrolling", "Patrolling")
		token = "accent"
	elif configured and not enabled:
		status = _pack.label("ui.auto_patrol_off", "Off")
	elif configured and bool(_snapshot.get("ok", false)):
		status = _pack.label("ui.auto_patrol_armed", "Armed")
		token = "success"
	elif configured:
		status = _pack.label("ui.auto_patrol_paused", "Paused")
		token = "warning"
	_status.text = status.to_upper()
	_set_status_color(token)
	_apply_border(token)


func _summary_text(task_id: String, agent_id: String) -> String:
	if task_id.is_empty() and agent_id.is_empty():
		return _pack.label("ui.auto_patrol_no_selection", "Choose an agent and a solo operation.")
	if task_id.is_empty():
		return _agent_name(agent_id)
	if agent_id.is_empty():
		return _task_name(task_id)
	return _pack.label("ui.auto_patrol_summary", "%s · %s") % [
		_agent_name(agent_id), _task_name(task_id),
	]


func _reason_text() -> String:
	var code := str(_snapshot.get("code", ""))
	if not bool(_snapshot.get("configured", false)):
		return _pack.label("ui.auto_patrol_reason_incomplete", "Choose an agent and a solo operation.")
	if not bool(_snapshot.get("enabled", false)):
		return _pack.label(
			"ui.auto_patrol_reason_disabled",
			"Auto Patrol is off. Enable it to repeat this operation.",
		)
	if code == AutoRepeat.CODE_INCOMPLETE:
		return _pack.label("ui.auto_patrol_reason_incomplete", "Choose an agent and a solo operation.")
	if bool(_snapshot.get("running", false)):
		return _pack.label("ui.auto_patrol_reason_running", "The selected agent is on patrol.")
	if bool(_snapshot.get("ok", false)):
		return _pack.label(
			"ui.auto_patrol_reason_ready", "Starts whenever the selected agent is free."
		)
	if code == Simulation.ERROR_STAGE_LOCKED:
		return CommandProgression.stage_lock_text(_pack, _snapshot)
	if code == Simulation.ERROR_RATING_TOO_LOW:
		return _pack.label("ui.auto_patrol_reason_rating", "Selected agent rating %d / %d.") % [
			int(roundf(float(_snapshot.get("rating", 0.0)))),
			int(_snapshot.get("required_rating", 0)),
		]
	if code == Simulation.ERROR_AGENT_BUSY:
		var blocking := str(_snapshot.get("blocking_task_id", ""))
		if not blocking.is_empty():
			return _pack.label(
				"ui.auto_patrol_reason_busy", "The selected agent is deployed on %s."
			) % _task_name(blocking)
		return _pack.label(
			"ui.auto_patrol_reason_busy", "The selected agent is deployed on %s."
		) % _pack.label("ui.blocked_agent_busy", "another operation")
	if code == Simulation.ERROR_UNKNOWN_AGENT:
		return _pack.label(
			"ui.auto_patrol_reason_missing_agent", "The selected agent is no longer on the roster."
		)
	if code == Simulation.ERROR_UNKNOWN_TASK:
		return _pack.label(
			"ui.auto_patrol_reason_missing_task", "The selected operation is no longer available."
		)
	if code == AutoRepeat.CODE_NOT_SOLO:
		return _pack.label(
			"ui.auto_patrol_reason_not_solo", "Auto Patrol repeats one-agent operations only."
		)
	if code == Simulation.ERROR_MISSING_ROLE:
		return _pack.label(
			"ui.blocked_missing_role", "The selected agent does not cover this operation's role."
		)
	return _pack.label("ui.auto_patrol_reason_unknown", "Auto Patrol cannot start (%s).") % code


func _locked_reason() -> String:
	var branch := str(_snapshot.get("unlock_branch_id", ""))
	if branch.is_empty():
		return _pack.label("ui.auto_patrol_unavailable", "Auto Patrol is not part of this pack.")
	var cost := int(_snapshot.get("unlock_cost", -1))
	if cost < 0:
		cost = 2
	return _pack.label(
		"ui.auto_patrol_reason_locked", "Unlock Auto Patrol in Upgrades · %d."
	) % cost


func _update_pickers(agent_id: String, task_id: String) -> void:
	_clear(_agent_picker)
	_clear(_operation_picker)
	_agent_picker.visible = _open_picker == "agent"
	_operation_picker.visible = _open_picker == "operation"
	if _agent_picker.visible:
		_fill_agent_picker(agent_id)
	if _operation_picker.visible:
		_fill_operation_picker(agent_id, task_id)


func _fill_agent_picker(current_agent_id: String) -> void:
	var ids: Array = _state.agents.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var first: Dictionary = _state.agents[a]
		var second: Dictionary = _state.agents[b]
		var rating_a := AgentRules.rating_value(first)
		var rating_b := AgentRules.rating_value(second)
		if rating_a != rating_b:
			return rating_a > rating_b
		return str(a) < str(b)
	)
	for raw_id in ids:
		var agent_id := str(raw_id)
		var record: Dictionary = _state.agents[agent_id]
		var available := AgentRules.is_available(record)
		var button := _picker_button(
			"agentChoice_%s" % agent_id,
			"%s · %d%s" % [
				_pack.agent_name(agent_id, record),
				AgentRules.rating(record),
				" · %s" % _pack.label("ui.auto_patrol_busy", "deployed") if not available else "",
			],
		)
		button.disabled = not available
		button.button_pressed = agent_id == current_agent_id
		button.pressed.connect(_on_agent_choice.bind(agent_id))
		_agent_picker.add_child(button)
	if _state.agents.is_empty():
		_agent_picker.add_child(_picker_note(
			_pack.label("ui.no_agents", "No agents")
		))


func _fill_operation_picker(agent_id: String, current_task_id: String) -> void:
	if agent_id.is_empty():
		_operation_picker.add_child(_picker_note(
			_pack.label("ui.auto_patrol_select_agent_first", "Choose an agent first.")
		))
		return
	var eligible := AutoRepeat.eligible_solo_task_ids(_state, _pack, agent_id)
	for task_id in eligible:
		var task := _pack.task(task_id)
		var button := _picker_button(
			"OperationChoice_%s" % task_id,
			"%s · %s %d" % [
				_pack.label(str(task.get("name_key", "")), task_id),
				_pack.label("ui.rating", "Rating").to_upper(),
				int(task.get("minimum_rating", 0)),
			],
		)
		button.button_pressed = task_id == current_task_id
		button.pressed.connect(_on_operation_choice.bind(task_id))
		_operation_picker.add_child(button)
	if eligible.is_empty():
		_operation_picker.add_child(_picker_note(
			_pack.label(
				"ui.auto_patrol_no_eligible", "No eligible solo operations for this agent."
			)
		))


func _picker_button(button_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.add_theme_font_size_override("font_size", 11)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _picker_note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	return label


func _on_choice_pressed(button_name: String) -> void:
	if button_name == "AutoPatrolAgent":
		_open_picker = "" if _open_picker == "agent" else "agent"
	elif button_name == "AutoPatrolOperation":
		_open_picker = "" if _open_picker == "operation" else "operation"
	_update()


func _on_agent_choice(agent_id: String) -> void:
	var task_id := str(_snapshot.get("task_id", ""))
	if not task_id.is_empty() \
		and not AutoRepeat.eligible_solo_task_ids(_state, _pack, agent_id).has(task_id):
		task_id = ""
	_open_picker = ""
	configure_requested.emit(task_id, agent_id)


func _on_operation_choice(task_id: String) -> void:
	_open_picker = ""
	configure_requested.emit(task_id, str(_snapshot.get("agent_id", "")))


func _on_toggle_pressed() -> void:
	enabled_requested.emit(not bool(_snapshot.get("enabled", false)))


func _agent_name(agent_id: String) -> String:
	if agent_id.is_empty():
		return ""
	var record: Variant = _state.agents.get(agent_id, {})
	return _pack.agent_name(agent_id, record if record is Dictionary else {})


func _task_name(task_id: String) -> String:
	if task_id.is_empty():
		return ""
	var task := _pack.task(task_id)
	return _pack.label(str(task.get("name_key", "")), task_id)


func _set_status_color(token: String) -> void:
	_status.add_theme_color_override("font_color", ThemeTokens.color(_pack, token))


func _apply_border(token: String) -> void:
	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	var accent := ThemeTokens.color(_pack, token, ThemeTokens.color(_pack, "accent"))
	style.border_color = Color(accent.r, accent.g, accent.b, 0.65)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

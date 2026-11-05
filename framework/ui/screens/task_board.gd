class_name TaskBoard
extends Control
## Missions operation board.
##
## Running work sits above a compact board of deployable operations. Ready jobs
## and locked jobs are separated so the next action is visible without reading
## every card, and each row states its role gate and the reason it is or is not
## ready. Active rows carry an in-place progress bar that changes on the normal
## one-second tick; there is no tween or other continuous motion.
##
## Neutral by construction. Task ids, names, durations, rewards, roles and
## categories come from the pack. Category accents are assigned by declaration
## order, never by a title-specific id.

signal deploy_requested(task_id: String)
signal auto_repeat_retry_requested
signal auto_patrol_configure_requested(task_id: String, agent_id: String)
signal auto_patrol_enabled_requested(enabled: bool)

const MIN_TAP_HEIGHT := 48
const ACTION_WIDTH := 84
const PROGRESS_HEIGHT := 6
## Generic accents in declaration order. The glyphs are simple printable
## symbols so the default font does not turn a category into a missing-glyph
## box; the middle dot is the same one the existing task details use.
const CATEGORY_GLYPHS := ["◆", "+", "#", "*", "!"]
const CATEGORY_TOKENS := ["accent", "success", "accent_alt", "reward", "warning"]

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _active_heading: Label
var _active_list: VBoxContainer
var _board_heading: Label
var _ready_heading: Label
var _ready_list: VBoxContainer
var _locked_heading: Label
var _locked_list: VBoxContainer
## assignment_id -> countdown Label, refreshed every tick without rebuilding.
var _countdowns: Dictionary = {}
## assignment_id -> ProgressBar / percent Label, updated without rebuilding.
var _progress_bars: Dictionary = {}
var _progress_labels: Dictionary = {}
var _deploy_buttons: Dictionary = {}
var _status_labels: Dictionary = {}
var _reasons: Dictionary = {}
var _auto_repeat: AutoRepeatBanner
var _auto_patrol: AutoPatrolCard
var _utc_now: int = 0
var _task_count: int = 0
var _ready_count: int = 0
var _locked_count: int = 0


func task_row_count() -> int:
	return _task_count


func active_row_count() -> int:
	return _active_list.get_child_count() if _active_list != null else 0


func ready_row_count() -> int:
	return _ready_count


func locked_row_count() -> int:
	return _locked_count


func deploy_button(task_id: String) -> Button:
	var button: Variant = _deploy_buttons.get(task_id, null)
	if button is Button:
		return button
	return null


func blocked_reason(task_id: String) -> String:
	var reason: Variant = _reasons.get(task_id, null)
	if reason is String:
		return str(reason)
	return ""


func auto_repeat_banner() -> AutoRepeatBanner:
	return _auto_repeat


func auto_patrol_card() -> AutoPatrolCard:
	return _auto_patrol


## The current progress percentage for a running assignment, or -1 when the
## assignment is not on the board.
func active_progress(assignment_id: String) -> int:
	var bar: Variant = _progress_bars.get(assignment_id, null)
	if bar is ProgressBar:
		return int(roundf((bar as ProgressBar).value))
	return -1


func active_countdown(assignment_id: String) -> String:
	var label: Variant = _countdowns.get(assignment_id, null)
	if label is Label:
		return (label as Label).text
	return ""


## The full readiness line shown for an available operation.
func task_status_text(task_id: String) -> String:
	var label: Variant = _status_labels.get(task_id, null)
	if label is Label:
		return (label as Label).text
	return ""


func refresh(pack: GamePack, state: GameState, utc_now: int) -> void:
	_pack = pack
	_state = state
	_utc_now = utc_now
	_ensure_built()
	_auto_repeat.refresh(pack, state)
	_auto_patrol.refresh(pack, state)
	_clear(_active_list)
	_clear(_ready_list)
	_clear(_locked_list)
	_countdowns.clear()
	_progress_bars.clear()
	_progress_labels.clear()
	_deploy_buttons.clear()
	_status_labels.clear()
	_reasons.clear()
	_task_count = 0
	_ready_count = 0
	_locked_count = 0

	var active_ids: Array = state.assignments.keys()
	active_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var first: Dictionary = state.assignments[a]
		var second: Dictionary = state.assignments[b]
		var first_end := int(first.get("ends_utc", 0))
		var second_end := int(second.get("ends_utc", 0))
		if first_end != second_end:
			return first_end < second_end
		return str(a) < str(b)
	)
	for raw_id in active_ids:
		_active_list.add_child(_active_row(str(raw_id)))
	var has_active := not active_ids.is_empty()
	_active_heading.text = "%s · %d" % [
		_pack.label("ui.live_operations", "Live operations").to_upper(),
		active_ids.size(),
	]
	_active_heading.visible = has_active
	_active_list.visible = has_active

	# Ready first, each group sorted by its rating gate. The player sees what can
	# start now before the long locked ladder.
	var task_ids: Array = pack.task_ids()
	task_ids.sort_custom(func(a: String, b: String) -> bool:
		var rating_a := int(pack.task(a).get("minimum_rating", 0))
		var rating_b := int(pack.task(b).get("minimum_rating", 0))
		if rating_a != rating_b:
			return rating_a < rating_b
		return a < b
	)
	var ready_ids: Array = []
	var locked_ids: Array = []
	var evaluations: Dictionary = {}
	for raw_id in task_ids:
		var task_id := str(raw_id)
		var evaluation := _evaluate(task_id)
		evaluations[task_id] = evaluation
		if evaluation.get("ok", false):
			ready_ids.append(task_id)
		else:
			locked_ids.append(task_id)
	_task_count = task_ids.size()
	_ready_count = ready_ids.size()
	_locked_count = locked_ids.size()

	if task_ids.is_empty():
		_board_heading.text = pack.label("ui.no_tasks", "No tasks in this pack").to_upper()
	else:
		_board_heading.text = "%s · %d %s · %d %s" % [
			pack.label("ui.operation_board", "Operation board").to_upper(),
			_ready_count,
			pack.label("ui.ready_short", "ready").to_upper(),
			_locked_count,
			pack.label("ui.locked_short", "locked").to_upper(),
		]
	_ready_heading.text = "%s · %d" % [
		pack.label("ui.ready_now", "Ready now").to_upper(),
		_ready_count,
	]
	_locked_heading.text = "%s · %d" % [
		pack.label("ui.locked_operations", "Locked").to_upper(),
		_locked_count,
	]
	_ready_heading.visible = not ready_ids.is_empty()
	_ready_list.visible = not ready_ids.is_empty()
	_locked_heading.visible = not locked_ids.is_empty()
	_locked_list.visible = not locked_ids.is_empty()

	for raw_id in ready_ids:
		var task_id := str(raw_id)
		_ready_list.add_child(_task_row(task_id, evaluations[task_id]))
	for raw_id in locked_ids:
		var task_id := str(raw_id)
		_locked_list.add_child(_task_row(task_id, evaluations[task_id]))
	tick(utc_now)


## Cheap per-second update: only countdown labels and active progress bars
## change. No node is rebuilt, so an in-flight board does not jump.
func tick(utc_now: int) -> void:
	_utc_now = utc_now
	if _state == null:
		return
	for raw_id in _countdowns.keys():
		var assignment_id := str(raw_id)
		var assignment: Variant = _state.assignments.get(assignment_id, null)
		if not (assignment is Dictionary):
			continue
		var countdown: Variant = _countdowns.get(assignment_id, null)
		if countdown is Label:
			(countdown as Label).text = _remaining_text(
				int((assignment as Dictionary).get("ends_utc", 0))
			)
		_update_progress(assignment_id, assignment as Dictionary)


func _update_progress(assignment_id: String, assignment: Dictionary) -> void:
	var percent := _progress_percent(assignment)
	var bar: Variant = _progress_bars.get(assignment_id, null)
	if bar is ProgressBar:
		(bar as ProgressBar).value = float(percent)
	var label: Variant = _progress_labels.get(assignment_id, null)
	if label is Label:
		(label as Label).text = "%d%%" % percent


func _progress_percent(assignment: Dictionary) -> int:
	var started := int(assignment.get("started_utc", _utc_now))
	var ends := int(assignment.get("ends_utc", started))
	var total := maxi(ends - started, 1)
	var elapsed := clampi(_utc_now - started, 0, total)
	return int(roundf(100.0 * float(elapsed) / float(total)))


func _ensure_built() -> void:
	if _root != null:
		return
	UILayout.fill(self)
	var scroll := TouchScroll.new()
	scroll.name = "BoardScroll"
	UILayout.fill(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_root)

	_auto_repeat = AutoRepeatBanner.new()
	_auto_repeat.name = "AutoRepeat"
	_auto_repeat.retry_requested.connect(func() -> void: auto_repeat_retry_requested.emit())
	_root.add_child(_auto_repeat)

	_auto_patrol = AutoPatrolCard.new()
	_auto_patrol.name = "AutoPatrol"
	_auto_patrol.configure_requested.connect(
		func(task_id: String, agent_id: String) -> void:
			auto_patrol_configure_requested.emit(task_id, agent_id)
	)
	_auto_patrol.enabled_requested.connect(
		func(enabled: bool) -> void: auto_patrol_enabled_requested.emit(enabled)
	)
	_root.add_child(_auto_patrol)

	_active_heading = _section_label(12, ThemeTokens.color(_pack, "success"))
	_active_heading.name = "LiveHeading"
	_root.add_child(_active_heading)
	_active_list = VBoxContainer.new()
	_active_list.name = "LiveList"
	_active_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_list.add_theme_constant_override("separation", 6)
	_root.add_child(_active_list)

	_board_heading = _section_label(11, ThemeTokens.color(_pack, "muted"))
	_board_heading.name = "BoardHeading"
	_root.add_child(_board_heading)
	_ready_heading = _section_label(11, ThemeTokens.color(_pack, "success"))
	_ready_heading.name = "ReadyHeading"
	_root.add_child(_ready_heading)
	_ready_list = VBoxContainer.new()
	_ready_list.name = "ReadyList"
	_ready_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_list.add_theme_constant_override("separation", 6)
	_root.add_child(_ready_list)

	_locked_heading = _section_label(11, ThemeTokens.color(_pack, "warning"))
	_locked_heading.name = "LockedHeading"
	_root.add_child(_locked_heading)
	_locked_list = VBoxContainer.new()
	_locked_list.name = "LockedList"
	_locked_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locked_list.add_theme_constant_override("separation", 6)
	_root.add_child(_locked_list)


func _task_row(task_id: String, evaluation: Dictionary) -> Control:
	var task := _pack.task(task_id)
	var ready := bool(evaluation.get("ok", false))
	var code := str(evaluation.get("code", ""))
	if not ready:
		_reasons[task_id] = _blocked_text(code, task, evaluation)
	var category := _category_meta(task)
	var panel := PanelContainer.new()
	panel.name = "Task_%s" % task_id
	panel.add_theme_stylebox_override("panel", _card_style(category.color, false, not ready))

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 3)
	panel.add_child(content)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	content.add_child(top)
	top.add_child(_glyph_label(category, not ready))

	var name_label := Label.new()
	name_label.text = _pack.label(str(task.get("name_key", "")), task_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override(
		"font_color",
		ThemeTokens.color(_pack, "text" if not ready else "accent")
	)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_label)

	var rewards: Variant = task.get("rewards", null)
	if rewards is Dictionary:
		var reward_label := Label.new()
		reward_label.text = TextFormat.rewards(_pack, rewards)
		reward_label.add_theme_font_size_override("font_size", 11)
		reward_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
		top.add_child(reward_label)

	var meta := Label.new()
	meta.text = _task_meta_text(task)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.max_lines_visible = 2
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	content.add_child(meta)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)

	var status := Label.new()
	status.name = "Status_%s" % task_id
	status.text = _status_text(evaluation, task)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override(
		"font_color",
		ThemeTokens.color(_pack, "success" if ready else "warning")
	)
	footer.add_child(status)
	_status_labels[task_id] = status

	var button := Button.new()
	button.name = "Deploy_%s" % task_id
	button.text = _pack.label("ui.deploy", "Deploy") if ready else _pack.label("ui.locked", "Locked")
	button.tooltip_text = status.text
	button.custom_minimum_size = Vector2(ACTION_WIDTH, MIN_TAP_HEIGHT)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 12)
	button.disabled = not ready
	button.pressed.connect(_on_deploy_pressed.bind(task_id))
	footer.add_child(button)
	_deploy_buttons[task_id] = button
	return panel


func _active_row(assignment_id: String) -> Control:
	var assignment: Dictionary = _state.assignments[assignment_id]
	var task_id := str(assignment.get("task_id", ""))
	var task := _pack.task(task_id)
	var category := _category_meta(task)
	var panel := PanelContainer.new()
	panel.name = "Active_%s" % assignment_id
	panel.add_theme_stylebox_override("panel", _card_style(category.color, true, false))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	column.add_child(top)
	top.add_child(_glyph_label(category, false))

	var name_label := Label.new()
	name_label.text = _pack.label(str(task.get("name_key", "")), task_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_label)

	var countdown := Label.new()
	countdown.name = "Countdown_%s" % assignment_id
	countdown.text = _remaining_text(int(assignment.get("ends_utc", 0)))
	countdown.add_theme_font_size_override("font_size", 12)
	countdown.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
	top.add_child(countdown)
	_countdowns[assignment_id] = countdown

	var meta := Label.new()
	meta.text = _active_meta_text(task)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.max_lines_visible = 2
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(meta)

	var agents := Label.new()
	agents.text = _agent_names(assignment)
	agents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	agents.max_lines_visible = 2
	agents.add_theme_font_size_override("font_size", 11)
	agents.add_theme_color_override("font_color", ThemeTokens.color(_pack, "text"))
	column.add_child(agents)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	column.add_child(progress_row)
	var progress_caption := Label.new()
	progress_caption.text = _pack.label("ui.in_progress", "In progress").to_upper()
	progress_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_caption.add_theme_font_size_override("font_size", 11)
	progress_caption.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	progress_row.add_child(progress_caption)
	var percent_label := Label.new()
	percent_label.name = "Percent_%s" % assignment_id
	percent_label.text = "%d%%" % _progress_percent(assignment)
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent_label.add_theme_font_size_override("font_size", 11)
	percent_label.add_theme_color_override("font_color", category.color)
	progress_row.add_child(percent_label)
	_progress_labels[assignment_id] = percent_label

	var bar := ProgressBar.new()
	bar.name = "Progress_%s" % assignment_id
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = float(_progress_percent(assignment))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, PROGRESS_HEIGHT)
	bar.add_theme_stylebox_override(
		"background",
		_bar_style(ThemeTokens.color(_pack, "border").darkened(0.25))
	)
	bar.add_theme_stylebox_override("fill", _bar_style(category.color))
	column.add_child(bar)
	_progress_bars[assignment_id] = bar
	return panel


func _evaluate(task_id: String) -> Dictionary:
	var candidates := Simulation.auto_select_agents(_state, _pack, task_id, true)
	return Simulation.evaluate_assignment(_state, _pack, task_id, candidates)


func _status_text(evaluation: Dictionary, task: Dictionary) -> String:
	var ready := bool(evaluation.get("ok", false))
	var locked_word := _pack.label("ui.locked", "Locked").to_upper()
	if ready:
		return "%s · %s %d · %s %d" % [
			_pack.label("ui.ready", "Ready").to_upper(),
			_pack.label("ui.rating", "Rating").to_upper(),
			int(roundf(float(evaluation.get("rating", 0.0)))),
			_pack.label("ui.gate", "Gate").to_upper(),
			int(task.get("minimum_rating", 0)),
		]
	var code := str(evaluation.get("code", ""))
	if code == Simulation.ERROR_RATING_TOO_LOW:
		return "%s · %s %d · %s %d" % [
			locked_word,
			_pack.label("ui.rating", "Rating").to_upper(),
			int(roundf(float(evaluation.get("rating", 0.0)))),
			_pack.label("ui.gate", "Gate").to_upper(),
			int(evaluation.get("required_rating", task.get("minimum_rating", 0))),
		]
	return "%s · %s" % [locked_word, _blocked_text(code, task, evaluation).to_upper()]


## Role names the operation requires, already localized.
func _role_names(task: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var required: Variant = task.get("required_role_ids", [])
	if not (required is Array):
		return names
	for raw_role in required:
		var role_id := str(raw_role)
		names.append(_pack.label(str(_pack.role(role_id).get("name_key", "")), role_id))
	return names


func _task_meta_text(task: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(_pack.stage_label(str(task.get("stage_id", ""))).to_upper())
	parts.append(_pack.category_label(str(task.get("category_id", ""))).to_upper())
	parts.append(TextFormat.duration(float(task.get("base_seconds", 0))))
	var squad := maxi(int(task.get("required_agent_count", 1)), 1)
	if squad > 1:
		parts.append("%s %d" % [_pack.label("ui.squad", "Squad").to_upper(), squad])
	var roles := _role_names(task)
	if not roles.is_empty():
		parts.append("%s %s" % [
			_pack.label("ui.requires", "Needs").to_upper(),
			" + ".join(roles).to_upper(),
		])
	return " · ".join(parts)


func _active_meta_text(task: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(_pack.stage_label(str(task.get("stage_id", ""))).to_upper())
	parts.append(_pack.category_label(str(task.get("category_id", ""))).to_upper())
	var rewards: Variant = task.get("rewards", null)
	if rewards is Dictionary:
		parts.append(TextFormat.rewards(_pack, rewards))
	var roles := _role_names(task)
	if not roles.is_empty():
		parts.append("%s %s" % [
			_pack.label("ui.requires", "Needs").to_upper(),
			" + ".join(roles).to_upper(),
		])
	return " · ".join(parts)


func _agent_names(assignment: Dictionary) -> String:
	var names: Array[String] = []
	var agent_ids: Variant = assignment.get("agent_ids", [])
	if agent_ids is Array:
		for raw_id in agent_ids:
			var agent_id := str(raw_id)
			var record: Variant = _state.agents.get(agent_id, {})
			names.append(_pack.agent_name(agent_id, record if record is Dictionary else {}))
	if names.is_empty():
		return _pack.label("ui.no_agents", "No agents")
	return " · ".join(names)


## Category accents are positional, not title-specific: the first declared
## category gets the first glyph and palette token, the second the next, and so
## on. A second game can declare its own categories and inherit the board.
func _category_meta(task: Dictionary) -> Dictionary:
	var category_id := str(task.get("category_id", ""))
	var index := 0
	var entries: Variant = _pack.progression.get("categories", [])
	if entries is Array:
		for i in entries.size():
			var entry: Variant = entries[i]
			if entry is Dictionary and str((entry as Dictionary).get("id", "")) == category_id:
				index = i
				break
	var token := str(CATEGORY_TOKENS[index % CATEGORY_TOKENS.size()])
	var color := ThemeTokens.color(_pack, token, ThemeTokens.color(_pack, "accent"))
	return {
		"glyph": str(CATEGORY_GLYPHS[index % CATEGORY_GLYPHS.size()]),
		"color": color,
	}


func _glyph_label(category: Dictionary, locked: bool) -> Label:
	var glyph := Label.new()
	glyph.text = str(category.get("glyph", "·"))
	glyph.custom_minimum_size = Vector2(18, 0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 18)
	var color: Color = category.get("color", Color.WHITE)
	glyph.add_theme_color_override("font_color", color.darkened(0.25) if locked else color)
	return glyph


func _section_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _card_style(accent: Color, active: bool, locked: bool) -> StyleBoxFlat:
	var panel := ThemeTokens.color(_pack, "panel", Color(0.07, 0.11, 0.16))
	var background := panel
	if active:
		background = panel.lightened(0.04)
	elif locked:
		background = panel.darkened(0.05)
	var style := StyleBoxFlat.new()
	style.bg_color = background
	if active:
		style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	elif locked:
		style.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	else:
		style.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style


## Locale text for a block code. A count shortfall states how many agents the
## operation needs, so "1 of 2" does not read as "every agent is busy".
func _blocked_text(code: String, task: Dictionary, evaluation: Dictionary) -> String:
	if code == Simulation.ERROR_STAGE_LOCKED:
		return CommandProgression.stage_lock_text(_pack, evaluation)
	if code == Simulation.ERROR_AGENT_COUNT:
		return _pack.label("ui.blocked_agent_count", "Needs %d available agents") % maxi(
			int(task.get("required_agent_count", 1)), 1
		)
	if code == Simulation.ERROR_MISSING_ROLE:
		var roles := _role_names(task)
		if not roles.is_empty():
			return "%s %s" % [
				_pack.label("ui.requires", "Needs"),
				" + ".join(roles),
			]
	return _pack.label("ui.blocked_%s" % code, code)


func _remaining_text(ends_utc: int) -> String:
	var remaining := maxi(ends_utc - _utc_now, 0)
	return "%s %s" % [
		_pack.label("ui.time_remaining", "Time left"),
		TextFormat.duration(float(remaining)),
	]


func _on_deploy_pressed(task_id: String) -> void:
	deploy_requested.emit(task_id)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

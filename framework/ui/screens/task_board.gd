class_name TaskBoard
extends Control
## Task board: running operations on top, everything deployable below.
##
## Neutral by construction. Task ids, names, durations, rewards and gates come
## from the pack, and every block reason is a locale key the pack provides.

signal deploy_requested(task_id: String)

const MIN_TAP_HEIGHT := 48

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _active_heading: Label
var _active_list: VBoxContainer
var _available_heading: Label
var _available_list: VBoxContainer
## assignment_id -> countdown Label, refreshed every tick without rebuilding.
var _countdowns: Dictionary = {}
var _deploy_buttons: Dictionary = {}
var _utc_now: int = 0


func task_row_count() -> int:
	return _available_list.get_child_count() if _available_list != null else 0


func active_row_count() -> int:
	return _active_list.get_child_count() if _active_list != null else 0


func deploy_button(task_id: String) -> Button:
	var button: Variant = _deploy_buttons.get(task_id, null)
	if button is Button:
		return button
	return null


func refresh(pack: GamePack, state: GameState, utc_now: int) -> void:
	_pack = pack
	_state = state
	_utc_now = utc_now
	_ensure_built()
	_clear(_active_list)
	_clear(_available_list)
	_countdowns.clear()
	_deploy_buttons.clear()

	var active_ids: Array = state.assignments.keys()
	active_ids.sort()
	for raw_id in active_ids:
		_active_list.add_child(_active_row(str(raw_id)))
	var has_active := not active_ids.is_empty()
	_active_heading.text = pack.label("ui.active_operations", "Active operations")
	_active_heading.visible = has_active
	_active_list.visible = has_active

	_available_heading.text = pack.label("ui.available_tasks", "Available tasks")
	# The ladder reads by difficulty, not alphabetically: with fifteen tasks the
	# next reachable operation should be the first one you see.
	var task_ids: Array = pack.task_ids()
	task_ids.sort_custom(func(a: String, b: String) -> bool:
		var rating_a := int(pack.task(a).get("minimum_rating", 0))
		var rating_b := int(pack.task(b).get("minimum_rating", 0))
		if rating_a != rating_b:
			return rating_a < rating_b
		return a < b
	)
	for task_id in task_ids:
		_available_list.add_child(_task_row(str(task_id)))
	if pack.task_ids().is_empty():
		var empty := Label.new()
		empty.text = pack.label("ui.no_tasks", "No tasks in this pack")
		empty.add_theme_color_override("font_color", ThemeTokens.color(pack, "muted"))
		_available_list.add_child(empty)
	tick(utc_now)


## Cheap per-second update: only the countdown labels change.
func tick(utc_now: int) -> void:
	_utc_now = utc_now
	if _state == null:
		return
	for raw_id in _countdowns.keys():
		var label: Variant = _countdowns[raw_id]
		if not (label is Label):
			continue
		var assignment: Variant = _state.assignments.get(str(raw_id), null)
		if not (assignment is Dictionary):
			continue
		(label as Label).text = _remaining_text(int((assignment as Dictionary).get("ends_utc", 0)))


func _ensure_built() -> void:
	if _root != null:
		return
	UILayout.fill(self)
	var scroll := TouchScroll.new()
	UILayout.fill(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 10)
	scroll.add_child(_root)

	_active_heading = _heading()
	_root.add_child(_active_heading)
	_active_list = VBoxContainer.new()
	_active_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_list.add_theme_constant_override("separation", 8)
	_root.add_child(_active_list)

	_available_heading = _heading()
	_root.add_child(_available_heading)
	_available_list = VBoxContainer.new()
	_available_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available_list.add_theme_constant_override("separation", 8)
	_root.add_child(_available_list)


func _task_row(task_id: String) -> Control:
	var task := _pack.task(task_id)
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)

	var name_label := Label.new()
	name_label.text = _pack.label(str(task.get("name_key", "")), task_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	top.add_child(name_label)

	var rewards: Variant = task.get("rewards", null)
	if rewards is Dictionary:
		var reward_label := Label.new()
		reward_label.text = TextFormat.rewards(_pack, rewards)
		reward_label.add_theme_font_size_override("font_size", 12)
		reward_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
		top.add_child(reward_label)

	var detail := Label.new()
	detail.text = _pack.task_detail(task_id)
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var candidates := Simulation.auto_select_agents(_state, _pack, task_id, true)
	var evaluation := Simulation.evaluate_assignment(_state, _pack, task_id, candidates)

	var button := Button.new()
	button.name = "Deploy_%s" % task_id
	button.text = _pack.label("ui.deploy", "Deploy")
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not evaluation.get("ok", false)
	button.pressed.connect(_on_deploy_pressed.bind(task_id))
	row.add_child(button)
	_deploy_buttons[task_id] = button

	# The reason gets its own full-width line: a wrapping label inside the button
	# row has zero minimum width and collapses into a one-character column.
	if not evaluation.get("ok", false):
		var code := str(evaluation.get("code", ""))
		var reason := Label.new()
		reason.text = _blocked_text(code, task)
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(reason)
	return panel


## Locale text for a block code. A count shortfall states how many agents the
## operation needs, so "1 of 2" does not read as "every agent is busy".
func _blocked_text(code: String, task: Dictionary) -> String:
	if code == Simulation.ERROR_AGENT_COUNT:
		return _pack.label("ui.blocked_agent_count", "Needs %d available agents") % maxi(
			int(task.get("required_agent_count", 1)), 1
		)
	return _pack.label("ui.blocked_%s" % code, code)


func _active_row(assignment_id: String) -> Control:
	var assignment: Dictionary = _state.assignments[assignment_id]
	var task_id := str(assignment.get("task_id", ""))
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)

	var name_label := Label.new()
	var task := _pack.task(task_id)
	name_label.text = _pack.label(str(task.get("name_key", "")), task_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "success"))
	top.add_child(name_label)

	var countdown := Label.new()
	countdown.text = _remaining_text(int(assignment.get("ends_utc", 0)))
	countdown.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
	top.add_child(countdown)
	_countdowns[assignment_id] = countdown

	var names: Array[String] = []
	var agent_ids: Variant = assignment.get("agent_ids", [])
	if agent_ids is Array:
		for raw_id in agent_ids:
			var record: Variant = _state.agents.get(str(raw_id), {})
			names.append(_pack.agent_name(str(raw_id), record if record is Dictionary else {}))
	if not names.is_empty():
		var agents_label := Label.new()
		agents_label.text = ", ".join(names)
		agents_label.add_theme_font_size_override("font_size", 11)
		agents_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
		column.add_child(agents_label)
	return panel


func _remaining_text(ends_utc: int) -> String:
	var remaining := maxi(ends_utc - _utc_now, 0)
	return "%s %s" % [
		_pack.label("ui.time_remaining", "Time left"),
		TextFormat.duration(float(remaining)),
	]


func _heading() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	return label


func _on_deploy_pressed(task_id: String) -> void:
	deploy_requested.emit(task_id)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

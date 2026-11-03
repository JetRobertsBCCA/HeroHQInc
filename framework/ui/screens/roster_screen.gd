class_name RosterScreen
extends Control
## Agent roster: rating, level, XP progress and paid training.
##
## Training rules come from the pack, so a pack without `training` simply shows
## no train button instead of a dead control.

signal train_requested(agent_id: String)

const MIN_TAP_HEIGHT := 48

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _list: VBoxContainer
var _buttons: Dictionary = {}


func agent_row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func train_button(agent_id: String) -> Button:
	var button: Variant = _buttons.get(agent_id, null)
	if button is Button:
		return button
	return null


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_ensure_built()
	_clear(_list)
	_buttons.clear()
	var agent_ids: Array = state.agents.keys()
	agent_ids.sort()
	for raw_id in agent_ids:
		_list.add_child(_agent_row(str(raw_id), state.agents[raw_id]))
	if agent_ids.is_empty():
		var empty := Label.new()
		empty.text = pack.label("ui.no_agents", "No agents yet")
		empty.add_theme_color_override("font_color", ThemeTokens.color(pack, "muted"))
		_list.add_child(empty)


func _ensure_built() -> void:
	if _root != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_root)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_root.add_child(_list)


func _agent_row(agent_id: String, agent: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)

	var name_label := Label.new()
	name_label.text = _pack.agent_name(agent_id, agent)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	top.add_child(name_label)

	var level := maxi(int(agent.get("level", 1)), 1)
	var level_label := Label.new()
	level_label.text = "%s %d" % [_pack.label("ui.level", "Lv"), level]
	level_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	level_label.add_theme_font_size_override("font_size", 12)
	top.add_child(level_label)

	var rating_label := Label.new()
	rating_label.text = "%s %d" % [_pack.label("ui.rating", "Rating"), AgentRules.rating(agent)]
	rating_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
	rating_label.add_theme_font_size_override("font_size", 12)
	top.add_child(rating_label)

	var role_label := Label.new()
	role_label.text = _pack.label(
		str(_pack.role(str(agent.get("role_id", ""))).get("name_key", "")),
		str(agent.get("role_id", "")),
	)
	role_label.add_theme_font_size_override("font_size", 11)
	role_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(role_label)

	var threshold := AgentRules.xp_threshold(_pack.leveling, level)
	var progress := ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = threshold
	progress.value = clampf(float(agent.get("xp", 0)), 0.0, threshold)
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 6)
	column.add_child(progress)

	if not _pack.training.is_empty():
		column.add_child(_training_row(agent_id))

	return panel


func _training_row(agent_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var resource_id := str(_pack.training.get("resource_id", ""))
	var cost := Simulation.training_cost(_state, _pack, agent_id)
	var affordable := _state.resource(resource_id) + 0.0001 >= float(cost)

	var button := Button.new()
	button.name = "Train_%s" % agent_id
	button.text = "%s · %d %s" % [
		_pack.label("ui.train", "Train"),
		cost,
		_pack.label("resources.%s" % resource_id, resource_id),
	]
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not affordable
	button.pressed.connect(_on_train_pressed.bind(agent_id))
	row.add_child(button)
	_buttons[agent_id] = button

	if not affordable:
		var reason := Label.new()
		reason.text = _pack.label("ui.blocked_insufficient_resource", "Not enough resources")
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(reason)
	return row


func _on_train_pressed(agent_id: String) -> void:
	train_requested.emit(agent_id)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

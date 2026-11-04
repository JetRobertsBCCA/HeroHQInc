class_name TeamScreen
extends Control
## Squad operations: every multi-agent task, its required roles, and the
## strongest squad the roster can currently field.
##
## The preview uses `Simulation.auto_select_agents` and
## `Simulation.evaluate_assignment`, the same helpers the deploy path uses, so
## what is shown here cannot disagree with what deployment would actually do.

signal deploy_requested(task_id: String)

const MIN_TAP_HEIGHT := 48

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _list: VBoxContainer
var _buttons: Dictionary = {}


func squad_row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func deploy_button(task_id: String) -> Button:
	var button: Variant = _buttons.get(task_id, null)
	if button is Button:
		return button
	return null


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_ensure_built()
	_clear(_list)
	_buttons.clear()

	var task_ids: Array = []
	for task_id in pack.task_ids():
		if int(pack.task(task_id).get("required_agent_count", 1)) > 1:
			task_ids.append(task_id)
	task_ids.sort_custom(func(a: String, b: String) -> bool:
		var rating_a := int(pack.task(a).get("minimum_rating", 0))
		var rating_b := int(pack.task(b).get("minimum_rating", 0))
		if rating_a != rating_b:
			return rating_a < rating_b
		return a < b
	)
	for task_id in task_ids:
		_list.add_child(_squad_row(str(task_id)))
	if task_ids.is_empty():
		var empty := Label.new()
		empty.text = pack.label("ui.no_squads", "No squad operations in this pack")
		empty.add_theme_color_override("font_color", ThemeTokens.color(pack, "muted"))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


func _ensure_built() -> void:
	if _root != null:
		return
	UILayout.fill(self)
	var scroll := ScrollContainer.new()
	UILayout.fill(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_root)

	var heading := Label.new()
	heading.text = _pack.label("ui.squad_operations", "Squad operations")
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_root.add_child(heading)

	var hint := Label.new()
	hint.text = _pack.label("ui.squad_hint", "")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	hint.visible = not hint.text.is_empty()
	_root.add_child(hint)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_root.add_child(_list)


func _squad_row(task_id: String) -> Control:
	var task := _pack.task(task_id)
	var required_count := maxi(int(task.get("required_agent_count", 1)), 1)
	var selected := Simulation.auto_select_agents(_state, _pack, task_id, true)
	var evaluation := Simulation.evaluate_assignment(_state, _pack, task_id, selected)

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
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(detail)

	var names: Array[String] = []
	var rating_total := 0.0
	for raw_id in selected:
		var agent_id := str(raw_id)
		var record: Variant = _state.agents.get(agent_id, {})
		if not (record is Dictionary):
			continue
		var agent: Dictionary = record
		names.append("%s (%d)" % [_pack.agent_name(agent_id, agent), AgentRules.rating(agent)])
		rating_total += AgentRules.rating_value(agent)

	var members := Label.new()
	members.text = "%s %d/%d · %s" % [
		_pack.label("ui.squad", "Squad"),
		selected.size(),
		required_count,
		", ".join(names) if not names.is_empty() else _pack.label("ui.no_agents", "No agents yet"),
	]
	members.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	members.add_theme_font_size_override("font_size", 11)
	members.add_theme_color_override("font_color", ThemeTokens.color(_pack, "text"))
	column.add_child(members)

	var required_rating := int(task.get("minimum_rating", 0))
	var average := rating_total / float(maxi(selected.size(), 1))
	var rating_label := Label.new()
	rating_label.text = "%s %d / %d" % [
		_pack.label("ui.squad_rating", "Squad rating"),
		int(roundf(average)),
		required_rating,
	]
	rating_label.add_theme_font_size_override("font_size", 11)
	rating_label.add_theme_color_override("font_color", ThemeTokens.color(
		_pack, "success" if evaluation.get("ok", false) else "warning"
	))
	column.add_child(rating_label)

	var missing := _missing_roles(task, selected)
	if not missing.is_empty():
		var missing_label := Label.new()
		missing_label.text = "%s %s" % [_pack.label("ui.requires", "Needs"), ", ".join(missing)]
		missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing_label.add_theme_font_size_override("font_size", 11)
		missing_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		column.add_child(missing_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var button := Button.new()
	button.name = "Deploy_%s" % task_id
	button.text = _pack.label("ui.deploy", "Deploy")
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not evaluation.get("ok", false)
	button.pressed.connect(func() -> void: deploy_requested.emit(task_id))
	row.add_child(button)
	_buttons[task_id] = button

	# The reason gets its own full-width line: a wrapping label inside the button
	# row has zero minimum width and collapses into a one-character column.
	if not evaluation.get("ok", false):
		var code := str(evaluation.get("code", ""))
		var reason := Label.new()
		reason.text = _pack.label("ui.blocked_%s" % code, code)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		column.add_child(reason)
	return panel


## Required roles the auto-selected squad does not cover, as display names.
func _missing_roles(task: Dictionary, selected: Array) -> Array[String]:
	var missing: Array[String] = []
	var required: Variant = task.get("required_role_ids", [])
	if not (required is Array):
		return missing
	for raw_role in required:
		var role_id := str(raw_role)
		var covered := false
		for raw_id in selected:
			var record: Variant = _state.agents.get(str(raw_id), {})
			if record is Dictionary and str((record as Dictionary).get("role_id", "")) == role_id:
				covered = true
				break
		if not covered:
			missing.append(_pack.label(str(_pack.role(role_id).get("name_key", "")), role_id))
	return missing


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

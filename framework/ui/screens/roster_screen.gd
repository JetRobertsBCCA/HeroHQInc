class_name RosterScreen
extends Control
## Agent roster: rating, level, XP progress, paid training and recruitment.
##
## Training and recruitment rules come from the pack, so a pack without those
## blocks simply shows no control instead of a dead button.

signal train_requested(agent_id: String)
signal recruit_requested(role_id: String)

const MIN_TAP_HEIGHT := 48
## A 240-slot roster does not need 240 live rows to be usable, and building
## them every refresh would cost a frame on a phone.
const MAX_ROWS := 60

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _list: VBoxContainer
var _recruit_box: VBoxContainer
var _recruit_button: Button
var _recruit_role_option: OptionButton
var _recruit_role: String = ""
var _buttons: Dictionary = {}


func agent_row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func train_button(agent_id: String) -> Button:
	var button: Variant = _buttons.get(agent_id, null)
	if button is Button:
		return button
	return null


func recruit_button() -> Button:
	return _recruit_button


func recruit_role_option() -> OptionButton:
	return _recruit_role_option


func recruit_role() -> String:
	return _recruit_role


## Chooses the role the next recruit should have. An empty id means any role.
func select_recruit_role(role_id: String) -> void:
	_recruit_role = role_id
	if _pack != null and _state != null:
		_refresh_recruitment()


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_ensure_built()
	_clear(_list)
	_buttons.clear()
	_refresh_recruitment()
	var agent_ids: Array = state.agents.keys()
	agent_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var first: Dictionary = state.agents[a]
		var second: Dictionary = state.agents[b]
		var rating_a := AgentRules.rating_value(first)
		var rating_b := AgentRules.rating_value(second)
		if not is_equal_approx(rating_a, rating_b):
			return rating_a > rating_b
		return str(a) < str(b)
	)
	var shown := 0
	for raw_id in agent_ids:
		if shown >= MAX_ROWS:
			break
		_list.add_child(_agent_row(str(raw_id), state.agents[raw_id]))
		shown += 1
	if agent_ids.is_empty():
		var empty := Label.new()
		empty.text = pack.label("ui.no_agents", "No agents yet")
		empty.add_theme_color_override("font_color", ThemeTokens.color(pack, "muted"))
		_list.add_child(empty)
	elif agent_ids.size() > MAX_ROWS:
		var note := Label.new()
		note.text = pack.label("ui.roster_showing", "Showing first %d of %d") % [
			MAX_ROWS, agent_ids.size(),
		]
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", ThemeTokens.color(pack, "muted"))
		_list.add_child(note)


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
	var recruit_panel := PanelContainer.new()
	_root.add_child(recruit_panel)
	_recruit_box = VBoxContainer.new()
	_recruit_box.add_theme_constant_override("separation", 4)
	recruit_panel.add_child(_recruit_box)
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


func _refresh_recruitment() -> void:
	for child in _recruit_box.get_children():
		_recruit_box.remove_child(child)
		child.queue_free()
	_recruit_button = null
	_recruit_role_option = null
	if not Recruitment.enabled(_pack):
		_recruit_box.get_parent().visible = false
		return
	_recruit_box.get_parent().visible = true

	var heading := Label.new()
	heading.text = _pack.label("ui.recruit", "Recruit")
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	_recruit_box.add_child(heading)

	# Without this the ladder can stall on a single missing role: a uniform pool
	# may take dozens of hires to produce the one role the next operation needs.
	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 8)
	var role_label := Label.new()
	role_label.text = _pack.label("ui.recruit_role", "Role")
	role_label.add_theme_font_size_override("font_size", 11)
	role_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	role_row.add_child(role_label)

	_recruit_role_option = OptionButton.new()
	_recruit_role_option.name = "RecruitRole"
	_recruit_role_option.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	_recruit_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recruit_role_option.add_item(_pack.label("ui.any_role", "Any role"))
	_recruit_role_option.set_item_metadata(0, "")
	var selected_index := 0
	var role_ids: Array = _pack.roles.keys()
	role_ids.sort()
	for raw_role in role_ids:
		var role_id := str(raw_role)
		var index := _recruit_role_option.item_count
		_recruit_role_option.add_item(
			_pack.label(str(_pack.role(role_id).get("name_key", "")), role_id)
		)
		_recruit_role_option.set_item_metadata(index, role_id)
		if role_id == _recruit_role:
			selected_index = index
	_recruit_role_option.select(selected_index)
	_recruit_role_option.item_selected.connect(_on_recruit_role_selected)
	role_row.add_child(_recruit_role_option)
	_recruit_box.add_child(role_row)

	var candidate := Recruitment.next_candidate_for_role(_state, _pack, _recruit_role)
	if candidate.is_empty():
		var unavailable := Label.new()
		unavailable.text = _pack.label(
			"ui.blocked_role_unavailable", "No recruit of that role is available"
		)
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unavailable.add_theme_font_size_override("font_size", 11)
		unavailable.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		_recruit_box.add_child(unavailable)
		return

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = str(candidate["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "text"))
	top.add_child(name_label)
	var rating_label := Label.new()
	rating_label.text = "%s %d" % [_pack.label("ui.rating", "Rating"), int(candidate["rating"])]
	rating_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
	rating_label.add_theme_font_size_override("font_size", 12)
	top.add_child(rating_label)
	_recruit_box.add_child(top)

	var role_id := str(candidate["role_id"])
	var tier_id := str(candidate["tier_id"])
	var detail := Label.new()
	detail.text = "%s · %s" % [
		_pack.label(str(_pack.role(role_id).get("name_key", "")), role_id),
		_pack.label("tiers.%s" % tier_id, tier_id),
	]
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_recruit_box.add_child(detail)

	var resource := Recruitment.resource_id(_pack)
	var price := int(candidate.get("cost", 0))
	var affordable := _state.resource(resource) + 0.0001 >= float(price)
	var full := _state.agents.size() >= Recruitment.capacity(_pack)
	_recruit_button = Button.new()
	_recruit_button.name = "RecruitButton"
	_recruit_button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	_recruit_button.disabled = full or not affordable
	if full:
		_recruit_button.text = _pack.label("ui.roster_full", "Roster full")
	else:
		_recruit_button.text = "%s · %d %s" % [
			_pack.label("ui.recruit", "Recruit"),
			price,
			_pack.label("resources.%s" % resource, resource),
		]
	_recruit_button.pressed.connect(_on_recruit_pressed)
	_recruit_box.add_child(_recruit_button)
	if not full and not affordable:
		var reason := Label.new()
		reason.text = _pack.label("ui.blocked_insufficient_resource", "Not enough resources")
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_recruit_box.add_child(reason)


func _on_recruit_role_selected(index: int) -> void:
	if _recruit_role_option == null:
		return
	select_recruit_role.call_deferred(str(_recruit_role_option.get_item_metadata(index)))


func _on_recruit_pressed() -> void:
	recruit_requested.emit(_recruit_role)


func _on_train_pressed(agent_id: String) -> void:
	train_requested.emit(agent_id)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

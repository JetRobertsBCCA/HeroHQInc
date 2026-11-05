class_name RosterScreen
extends Control
## Agent roster: rating, level, XP progress, paid training and recruitment.
##
## Training and recruitment rules come from the pack, so a pack without those
## blocks simply shows no control instead of a dead button.

signal train_requested(agent_id: String)
## The player pressed one visible offer. The app revalidates that exact id.
signal recruit_requested(agent_id: String)

const MIN_TAP_HEIGHT := 48
## A 240-slot roster does not need 240 live rows to be usable, and building
## them every refresh would cost a frame on a phone.
const MAX_ROWS := 60

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _list: VBoxContainer
var _recruit_box: VBoxContainer
var _recruit_buttons: Dictionary = {}
var _recruit_cards: Dictionary = {}
var _recruit_ids: Array[String] = []
var _buttons: Dictionary = {}


func agent_row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func train_button(agent_id: String) -> Button:
	var button: Variant = _buttons.get(agent_id, null)
	if button is Button:
		return button
	return null


func recruit_offer_count() -> int:
	return _recruit_ids.size()


func recruit_offer_ids() -> Array[String]:
	return _recruit_ids.duplicate()


func recruit_offer_button(agent_id: String) -> Button:
	var value: Variant = _recruit_buttons.get(agent_id, null)
	if value is Button:
		return value
	return null


func recruit_offer_card(agent_id: String) -> Control:
	var value: Variant = _recruit_cards.get(agent_id, null)
	if value is Control:
		return value
	return null


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
	var scroll := TouchScroll.new()
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
	# The reason gets its own line: inside the button row a wrapping label has
	# zero minimum width and collapses into a one-character column.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

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
		reason.text = _pack.label("ui.blocked_insufficient_resource", "Not enough %s") % _pack.label(
			"resources.%s" % resource_id, resource_id
		)
		reason.add_theme_font_size_override("font_size", 11)
		reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(reason)
	return box


func _refresh_recruitment() -> void:
	for child in _recruit_box.get_children():
		_recruit_box.remove_child(child)
		child.queue_free()
	_recruit_buttons.clear()
	_recruit_cards.clear()
	_recruit_ids.clear()
	if not Recruitment.enabled(_pack):
		_recruit_box.get_parent().visible = false
		return
	_recruit_box.get_parent().visible = true

	var heading := Label.new()
	heading.text = _pack.label("ui.recruit_choose", "Choose one of two offers")
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	_recruit_box.add_child(heading)

	var offers := Recruitment.offers(_state, _pack)
	if offers.is_empty():
		var unavailable := Label.new()
		unavailable.text = _pack.label("ui.recruit_none", "No recruit offers are available")
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unavailable.add_theme_font_size_override("font_size", 11)
		unavailable.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		_recruit_box.add_child(unavailable)
		return

	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		var card := _recruit_offer_card(offer)
		_recruit_box.add_child(card)
		_recruit_cards[str(offer["id"])] = card
		_recruit_ids.append(str(offer["id"]))

	var hint := Label.new()
	hint.text = _pack.label(
		"ui.recruit_refresh_hint",
		"New offers after a hire or a Command Level increase."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_recruit_box.add_child(hint)


func _recruit_offer_card(offer: Dictionary) -> Control:
	var agent_id := str(offer.get("id", ""))
	var role_id := str(offer.get("role_id", ""))
	var tier_id := str(offer.get("tier_id", ""))
	var role_name := _pack.label(str(_pack.role(role_id).get("name_key", "")), role_id)
	var tier_name := _pack.label("tiers.%s" % tier_id, tier_id)
	var resource := Recruitment.resource_id(_pack)
	var price := int(offer.get("cost", 0))
	var affordable := _state.resource(resource) + 0.0001 >= float(price)
	var full := _state.agents.size() >= Recruitment.capacity(_pack)

	var card := PanelContainer.new()
	card.name = "RecruitOffer_%s" % agent_id
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	var name_label := Label.new()
	name_label.name = "OfferName_%s" % agent_id
	name_label.text = str(offer.get("name", agent_id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "text"))
	top.add_child(name_label)
	var rating_label := Label.new()
	rating_label.name = "OfferRating_%s" % agent_id
	rating_label.text = "%s %d" % [
		_pack.label("ui.rating", "Rating"), int(offer.get("rating", 0)),
	]
	rating_label.add_theme_font_size_override("font_size", 12)
	rating_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
	top.add_child(rating_label)

	var role_label := Label.new()
	role_label.name = "OfferRole_%s" % agent_id
	role_label.text = "%s · %s" % [role_name, tier_name]
	role_label.add_theme_font_size_override("font_size", 11)
	role_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(role_label)

	var attributes_label := Label.new()
	attributes_label.name = "OfferAttrs_%s" % agent_id
	attributes_label.text = _attribute_text(offer.get("attributes", {}))
	attributes_label.add_theme_font_size_override("font_size", 10)
	attributes_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(attributes_label)

	var role_count := maxi(int(offer.get("role_count", 0)), 0)
	var fit_label := Label.new()
	fit_label.name = "OfferFit_%s" % agent_id
	if role_count == 0:
		fit_label.text = _pack.label("ui.recruit_adds_new_role", "Adds a new %s role") % role_name
	else:
		fit_label.text = _pack.label("ui.recruit_adds_role_n", "Adds %s #%d") % [
			role_name, role_count + 1,
		]
	fit_label.add_theme_font_size_override("font_size", 10)
	fit_label.add_theme_color_override(
		"font_color",
		ThemeTokens.color(_pack, "accent" if role_count == 0 else "muted"),
	)
	column.add_child(fit_label)

	var button := Button.new()
	button.name = "Recruit_%s" % agent_id
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = full or not affordable
	if full:
		button.text = _pack.label("ui.roster_full", "Roster full")
	else:
		button.text = "%s · %d %s" % [
			_pack.label("ui.recruit", "Recruit"),
			price,
			_pack.label("resources.%s" % resource, resource),
		]
	button.pressed.connect(_on_recruit_pressed.bind(agent_id))
	column.add_child(button)
	_recruit_buttons[agent_id] = button

	if not full and not affordable:
		var reason := Label.new()
		reason.name = "OfferReason_%s" % agent_id
		reason.text = _pack.label("ui.blocked_insufficient_resource", "Not enough %s") % _pack.label(
			"resources.%s" % resource, resource
		)
		reason.add_theme_font_size_override("font_size", 10)
		reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(reason)
	return card


func _attribute_text(attributes: Variant) -> String:
	var values: Dictionary = attributes if attributes is Dictionary else {}
	var parts: Array[String] = []
	for raw_name in Recruitment.attribute_names(_pack):
		var name := str(raw_name)
		var label := _pack.label("attributes.%s" % name, name.capitalize())
		parts.append("%s %d" % [label, int(values.get(name, 0))])
	return " · ".join(parts)


func _on_recruit_pressed(agent_id: String) -> void:
	recruit_requested.emit(agent_id)


func _on_train_pressed(agent_id: String) -> void:
	train_requested.emit(agent_id)


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

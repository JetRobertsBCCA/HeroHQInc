class_name PrestigeScreen
extends Control
## Command panel for the Upgrades tab: permanent Research ranks, then Rebirth.
##
## Research spends a declared resource on ranks that survive every reset; the
## rebirth banks chips that multiply every payout. Both are driven by pack data,
## so a pack without those blocks renders a readable "unavailable" state.
##
## The reset is gated behind a two-step confirm so a tap cannot wipe a run by
## accident.

signal rebirth_requested()
signal research_purchase_requested(branch_id: String)

const MIN_TAP_HEIGHT := 48

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _research_box: VBoxContainer
var _chips_label: Label
var _multiplier_label: Label
var _run_label: Label
var _progress: ProgressBar
var _gain_label: Label
var _note_label: Label
var _button: Button
var _confirming: bool = false


func rebirth_button() -> Button:
	return _button


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_confirming = false
	_ensure_built()
	_refresh_research()
	_refresh_rebirth()


func _refresh_research() -> void:
	for child in _research_box.get_children():
		child.queue_free()
		_research_box.remove_child(child)

	_research_box.add_child(_heading(
		_pack.label("research.title", "Research"), 16, ThemeTokens.color(_pack, "accent")
	))
	_research_box.add_child(_body_label(_pack.label("research.subtitle", "")))
	if not Research.enabled(_pack):
		_research_box.add_child(_body_label(
			_pack.label("ui.blocked_research_unavailable", "Research is not part of this pack")
		))
		return

	var resource := Research.resource_id(_pack)
	for raw in Research.branches(_pack):
		if not (raw is Dictionary):
			continue
		_research_box.add_child(_build_branch_row(raw as Dictionary, resource))


func _build_branch_row(rules: Dictionary, resource: String) -> Control:
	var branch_id := str(rules.get("id", ""))
	var current := Research.rank(_state, branch_id)
	var maximum := maxi(int(rules.get("max_rank", 1)), 1)
	var price := Research.cost(_state, _pack, branch_id)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	var name_label := _body_label(_pack.label(str(rules.get("label_key", "")), branch_id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	# A wrapping label has zero minimum width, so an HBox will squeeze it to a
	# single character column. The rank must keep its natural width.
	var rank_label := Label.new()
	rank_label.text = "%s %d / %d" % [
		_pack.label("ui.research_rank", "Rank"), current, maximum,
	]
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	rank_label.add_theme_font_size_override("font_size", 11)
	rank_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	header.add_child(rank_label)
	column.add_child(header)

	column.add_child(_body_label(_effect_text(rules, branch_id)))

	var button := Button.new()
	button.name = "Research_%s" % branch_id
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	if price < 0:
		button.text = _pack.label("ui.research_maxed", "Fully researched")
		button.disabled = true
	else:
		button.text = "%s · %d %s" % [
			_pack.label("ui.research_buy", "Research"),
			price,
			_pack.label("resources.%s" % resource, resource),
		]
		button.pressed.connect(func() -> void: research_purchase_requested.emit(branch_id))
	column.add_child(button)
	return column


func _effect_text(rules: Dictionary, branch_id: String) -> String:
	var effect := str(rules.get("effect", ""))
	var per_rank := float(rules.get("per_rank", 0.0))
	match effect:
		Research.EFFECT_REWARD:
			return _pack.label(
				"research.reward_effect",
				"+%d%% task payouts per rank" % int(roundf(per_rank * 100.0)),
			)
		Research.EFFECT_TRAINING:
			return _pack.label(
				"research.training_effect",
				"-%d%% training cost per rank" % int(roundf(per_rank * 100.0)),
			)
		Research.EFFECT_AUTO_REPEAT:
			return _pack.label("research.automation_effect", "Repeats your last operation")
	return branch_id


func _refresh_rebirth() -> void:
	var check := Prestige.eligibility(_state, _pack)
	var lifetime := Prestige.lifetime_earnings(_state, _pack)
	var target := maxf(Prestige.next_chip_at(_state, _pack), lifetime + 1.0)

	_chips_label.text = "%s %d" % [
		_pack.label("ui.prestige_chips", "Chips"), _state.prestige_chips(),
	]
	_multiplier_label.text = "%s ×%.2f" % [
		_pack.label("ui.prestige_multiplier", "Reward multiplier"),
		Prestige.multiplier(_state, _pack),
	]
	_run_label.text = "%s %s / %s" % [
		_pack.label("ui.prestige_run", "Lifetime earnings"),
		TextFormat.amount(lifetime),
		TextFormat.amount(target),
	]
	_progress.max_value = target
	_progress.value = clampf(lifetime, 0.0, target)

	_gain_label.text = "%s +%d  ·  %s %s  ·  %s %d / %d" % [
		_pack.label("ui.prestige_gain", "Rebirth for"),
		int(check.get("gain", 0)),
		_pack.label("ui.prestige_run_now", "This run"),
		TextFormat.amount(_state.run_earnings()),
		_pack.label("ui.level", "Lv"),
		int(check.get("level", 1)),
		int(check.get("required_level", 1)),
	]

	if check.get("ok", false):
		_note_label.text = _pack.label("ui.prestige_note", "")
		_button.disabled = false
		_button.text = _pack.label("ui.prestige_button", "Rebirth") if not _confirming \
			else _pack.label("ui.prestige_confirm", "Confirm rebirth")
	else:
		var code := str(check.get("code", ""))
		_note_label.text = _pack.label("ui.blocked_%s" % code, code)
		_button.disabled = true
		_button.text = _pack.label("ui.prestige_button", "Rebirth")


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
	_root.add_theme_constant_override("separation", 10)
	scroll.add_child(_root)

	var research_panel := PanelContainer.new()
	_root.add_child(research_panel)
	_research_box = VBoxContainer.new()
	_research_box.add_theme_constant_override("separation", 6)
	research_panel.add_child(_research_box)

	var panel := PanelContainer.new()
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	column.add_child(_heading(
		_pack.label("ui.prestige_title", "Rebirth"), 16, ThemeTokens.color(_pack, "accent")
	))
	_chips_label = _value_label(column, 17, ThemeTokens.color(_pack, "reward"))
	_multiplier_label = _value_label(column, 13, ThemeTokens.color(_pack, "success"))
	_run_label = _value_label(column, 12, ThemeTokens.color(_pack, "muted"))

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 8)
	column.add_child(_progress)

	_gain_label = _value_label(column, 12, ThemeTokens.color(_pack, "text"))

	_note_label = _body_label("")
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note_label)

	_button = Button.new()
	_button.name = "RebirthButton"
	_button.text = _pack.label("ui.prestige_button", "Rebirth")
	_button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	_button.pressed.connect(_on_pressed)
	column.add_child(_button)


func _heading(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	return label


func _value_label(parent: VBoxContainer, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _on_pressed() -> void:
	if _pack == null or _state == null:
		return
	if not Prestige.eligibility(_state, _pack).get("ok", false):
		return
	if not _confirming:
		# First tap arms the button; the second tap commits the reset.
		_confirming = true
		_button.text = _pack.label("ui.prestige_confirm", "Confirm rebirth")
		return
	rebirth_requested.emit()

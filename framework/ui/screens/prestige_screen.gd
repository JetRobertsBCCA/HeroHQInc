class_name PrestigeScreen
extends Control
## Rebirth panel. Shows the banked chips, the multiplier they buy, progress
## toward the next chip, and what a rebirth would add right now.
##
## The reset is gated behind a two-step confirm so a tap cannot wipe a run by
## accident. Every number and label comes from the pack, so a pack without a
## `prestige` block renders the "unavailable" state instead.

signal rebirth_requested()

const MIN_TAP_HEIGHT := 48

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
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
	var check := Prestige.eligibility(state, pack)
	var lifetime := Prestige.lifetime_earnings(state, pack)
	var target := maxf(Prestige.next_chip_at(state, pack), lifetime + 1.0)

	_chips_label.text = "%s %d" % [
		_pack.label("ui.prestige_chips", "Chips"), state.prestige_chips(),
	]
	_multiplier_label.text = "%s ×%.2f" % [
		_pack.label("ui.prestige_multiplier", "Reward multiplier"),
		Prestige.multiplier(state, pack),
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
		TextFormat.amount(state.run_earnings()),
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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_root)

	var panel := PanelContainer.new()
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var title := Label.new()
	title.text = _pack.label("ui.prestige_title", "Rebirth")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	column.add_child(title)

	_chips_label = _value_label(column, 17, ThemeTokens.color(_pack, "reward"))
	_multiplier_label = _value_label(column, 13, ThemeTokens.color(_pack, "success"))
	_run_label = _value_label(column, 12, ThemeTokens.color(_pack, "muted"))

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 8)
	column.add_child(_progress)

	_gain_label = _value_label(column, 12, ThemeTokens.color(_pack, "text"))

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.add_theme_font_size_override("font_size", 11)
	_note_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(_note_label)

	_button = Button.new()
	_button.name = "RebirthButton"
	_button.text = _pack.label("ui.prestige_button", "Rebirth")
	_button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	_button.pressed.connect(_on_pressed)
	column.add_child(_button)


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

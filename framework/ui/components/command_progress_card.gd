class_name CommandProgressCard
extends PanelContainer
## HQ card for the next explicit command milestone.
##
## The card reads pack data and derived progress only. It never stores a command
## level, so it stays correct for fresh profiles and for saves written before
## milestones existed.

const FONT_SIZE := 11
const HEADING_SIZE := 13

var _pack: GamePack
var _state: GameState
var _heading: Label
var _next: Label
var _requirements: VBoxContainer
var _unlock: Label
var _future: Label
var _rows: Array[Dictionary] = []


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_ensure_built()
	_clear_requirements()
	_rows.clear()

	var current := CommandProgression.current_level(state, pack)
	var current_record := CommandProgression.level_record(pack, current)
	_heading.text = _level_name(current_record, current)
	_heading.add_theme_color_override("font_color", ThemeTokens.color(pack, "accent"))

	var next := CommandProgression.next_level(state, pack)
	if next.is_empty():
		_next.visible = false
		var unlocked := CommandProgression.unlocked_stage_labels(pack, current)
		_unlock.text = _pack.label("ui.command_unlocked", "Unlocked: %s") % ", ".join(unlocked)
		_unlock.visible = not unlocked.is_empty()
		_future.text = _pack.label(
			"ui.command_future",
			"Next milestone arrives in a later update.",
		)
		_future.visible = true
		return

	_next.visible = true
	var next_number := int(next.get("level", current + 1))
	_next.text = _pack.label("ui.command_next", "Next · %s") % _level_name(next, next_number)
	_future.visible = false

	var raw_rows := CommandProgression.requirement_rows(pack, state, next)
	for raw in raw_rows:
		if raw is Dictionary:
			var row: Dictionary = raw
			_rows.append(row)
			_requirements.add_child(_requirement_row(row))

	var unlocked := CommandProgression.unlocked_stage_labels(pack, next_number)
	_unlock.text = ""
	if not unlocked.is_empty():
		_unlock.text = _pack.label("ui.command_unlock", "Unlocks: %s") % ", ".join(unlocked)
	_unlock.visible = not unlocked.is_empty()


func heading_text() -> String:
	return _heading.text if _heading != null else ""


func next_text() -> String:
	return _next.text if _next != null else ""


func unlock_text() -> String:
	return _unlock.text if _unlock != null else ""


func future_text() -> String:
	return _future.text if _future != null else ""


func requirement_rows() -> Array[Dictionary]:
	return _rows.duplicate(true)


func _ensure_built() -> void:
	if _heading != null:
		return
	UILayout.fill(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)

	_heading = Label.new()
	_heading.name = "CommandLevel"
	_heading.add_theme_font_size_override("font_size", HEADING_SIZE)
	top.add_child(_heading)

	_next = Label.new()
	_next.name = "NextMilestone"
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_next.add_theme_font_size_override("font_size", FONT_SIZE)
	_next.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_next)

	_requirements = VBoxContainer.new()
	_requirements.name = "Requirements"
	_requirements.add_theme_constant_override("separation", 0)
	column.add_child(_requirements)

	_unlock = Label.new()
	_unlock.name = "Unlock"
	_unlock.add_theme_font_size_override("font_size", FONT_SIZE)
	_unlock.add_theme_color_override("font_color", ThemeTokens.color(_pack, "success"))
	_unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_unlock)

	_future = Label.new()
	_future.name = "FutureMilestone"
	_future.add_theme_font_size_override("font_size", FONT_SIZE)
	_future.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_future.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_future)


func _requirement_row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = str(row.get("label", ""))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "text"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	var progress := Label.new()
	progress.text = str(row.get("progress", ""))
	progress.add_theme_font_size_override("font_size", FONT_SIZE)
	progress.add_theme_color_override(
		"font_color",
		ThemeTokens.color(_pack, "success") if bool(row.get("met", false)) else ThemeTokens.color(_pack, "muted"),
	)
	line.add_child(progress)
	return line


func _level_name(record: Dictionary, number: int) -> String:
	return _pack.label(
		str(record.get("name_key", "")),
		"Command Level %d" % number,
	)


func _clear_requirements() -> void:
	if _requirements == null:
		return
	for child in _requirements.get_children():
		_requirements.remove_child(child)
		child.queue_free()

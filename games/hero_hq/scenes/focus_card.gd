class_name HeroFocusCard
extends PanelContainer
## HERO//HQ-specific Focus control on HQ.
##
## Shared screens stay game-neutral; this card owns the Focus presentation and
## forwards one assignment id at a time to the composition root.

signal focus_requested(assignment_id: String)

const MIN_TAP_HEIGHT := 44

var _pack: GamePack
var _state: GameState
var _utc_now: int = 0
var _column: VBoxContainer
var _status: Label
var _list: VBoxContainer
var _empty: Label
var _buttons: Dictionary = {}
var _notes: Dictionary = {}


func focus_button(assignment_id: String) -> Button:
	var value: Variant = _buttons.get(assignment_id, null)
	if value is Button:
		return value
	return null


func status_text() -> String:
	return _status.text if _status != null else ""


func refresh(pack: GamePack, state: GameState, utc_now: int) -> void:
	_pack = pack
	_state = state
	_utc_now = utc_now
	_ensure_built()
	_rebuild_rows()
	_update_controls()


func tick(utc_now: int) -> void:
	_utc_now = utc_now
	_update_controls()


func _ensure_built() -> void:
	if _column != null:
		return
	UILayout.fill(self)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	add_child(_column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_column.add_child(top)

	var heading := Label.new()
	heading.text = _pack.label("ui.focus", "Focus")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	top.add_child(heading)

	_status = Label.new()
	_status.name = "FocusStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	top.add_child(_status)

	_empty = Label.new()
	_empty.text = _pack.label("ui.focus_no_active", "No operations running.")
	_empty.add_theme_font_size_override("font_size", 11)
	_empty.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_empty)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_column.add_child(_list)


func _rebuild_rows() -> void:
	_clear(_list)
	_buttons.clear()
	_notes.clear()
	var assignment_ids: Array = _state.assignments.keys()
	assignment_ids.sort()
	_empty.visible = assignment_ids.is_empty()
	for raw_id in assignment_ids:
		_list.add_child(_assignment_row(str(raw_id)))


func _assignment_row(assignment_id: String) -> Control:
	var assignment: Dictionary = _state.assignments[assignment_id]
	var task_id := str(assignment.get("task_id", ""))
	var task: Dictionary = _pack.task(task_id)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var task_name := Label.new()
	task_name.text = _pack.label(str(task.get("name_key", "")), task_id)
	task_name.add_theme_font_size_override("font_size", 12)
	task_name.add_theme_color_override("font_color", ThemeTokens.color(_pack, "success"))
	row.add_child(task_name)

	var button := Button.new()
	button.name = "FocusPulse_%s" % assignment_id
	button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(func() -> void: focus_requested.emit(assignment_id))
	row.add_child(button)
	_buttons[assignment_id] = button

	var note := Label.new()
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = false
	row.add_child(note)
	_notes[assignment_id] = note
	return row


func _update_controls() -> void:
	if _status == null:
		return
	var cap := HeroFocus.max_focus(_pack)
	var current := HeroFocus.current(_state, _pack, _utc_now)
	if current >= cap:
		_status.text = _pack.label("ui.focus_header_ready", "Focus %d / %d · Pulse ready") % [
			current, cap,
		]
	else:
		_status.text = _pack.label("ui.focus_header_next", "Focus %d / %d · Next in %s") % [
			current,
			cap,
			TextFormat.duration(float(HeroFocus.next_in_seconds(_state, _pack, _utc_now))),
		]

	for raw_id in _buttons.keys():
		var assignment_id := str(raw_id)
		var button: Button = _buttons[assignment_id]
		var note: Label = _notes[assignment_id]
		var projection := HeroFocus.project(_state, _pack, assignment_id, _utc_now)
		button.disabled = not bool(projection.get("ok", false))
		button.text = _button_text(projection)
		note.text = _reason_text(projection)
		note.visible = not note.text.is_empty()


func _button_text(projection: Dictionary) -> String:
	var code := str(projection.get("code", ""))
	if bool(projection.get("ok", false)):
		return _pack.label("ui.focus_pulse", "Focus · -%ds") % int(projection.get("saved_seconds", 0))
	if code == HeroFocus.CODE_COOLDOWN:
		return _pack.label("ui.focus_wait", "Focus · %s") % TextFormat.duration(
			float(projection.get("cooldown_seconds", 0))
		)
	return _pack.label("ui.focus", "Focus")


func _reason_text(projection: Dictionary) -> String:
	var code := str(projection.get("code", ""))
	if code.is_empty():
		return ""
	if code == HeroFocus.CODE_COOLDOWN:
		return _pack.label("ui.focus_cooldown", "Pulse ready in %s.") % TextFormat.duration(
			float(projection.get("cooldown_seconds", 0))
		)
	if code == HeroFocus.CODE_EMPTY:
		return _pack.label("ui.focus_empty", "No Focus. Next in %s.") % TextFormat.duration(
			float(HeroFocus.next_in_seconds(_state, _pack, _utc_now))
		)
	if code == HeroFocus.CODE_FINISHED:
		return _pack.label("ui.focus_finished", "Operation already finished.")
	if code == HeroFocus.CODE_NO_TIME:
		return _pack.label("ui.focus_no_time", "Too little time remains.")
	if code == HeroFocus.CODE_UNKNOWN_ASSIGNMENT:
		return _pack.label("ui.focus_unknown", "Operation not found.")
	return _pack.label("ui.focus_unavailable", "Focus is not configured.")


func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

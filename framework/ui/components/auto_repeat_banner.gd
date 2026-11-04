class_name AutoRepeatBanner
extends PanelContainer
## Live "why is auto-repeat waiting?" card.
##
## The status is recomputed from `AutoRepeat.status` on every refresh; nothing is
## cached in the save, so a reason cannot outlive the roster or activity state
## that produced it. The card is only visible while a rule is configured.

signal retry_requested

var _pack: GamePack
var _state: GameState
var _snapshot: Dictionary = {}
var _title: Label
var _status_label: Label
var _reason_label: Label
var _retry: Button


## Recomputes the card. A hidden card also clears its labels so tests and screen
## readers cannot observe a reason left over from an earlier rule.
func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_ensure_built()
	_snapshot = AutoRepeat.status(state, pack)
	visible = bool(_snapshot.get("configured", false))
	if not visible:
		_status_label.text = ""
		_reason_label.text = ""
		_retry.visible = false
		return

	_title.text = _pack.label("ui.auto_repeat_title", "Auto-repeat")
	var task_name := _task_name(str(_snapshot.get("task_id", "")))
	var code := status_code()
	if code.is_empty():
		_status_label.text = _pack.label("ui.auto_repeat_armed", "Armed · %s") % task_name
		_reason_label.text = _pack.label(
			"ui.auto_repeat_ready_reason",
			"Starts automatically when no operation is running.",
		)
		_status_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "success"))
		_reason_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	elif code == AutoRepeat.CODE_BUSY:
		_status_label.text = _pack.label("ui.auto_repeat_waiting", "Waiting · %s") % task_name
		_reason_label.text = _waiting_reason()
		_status_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "reward"))
		_reason_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	else:
		_status_label.text = _pack.label("ui.auto_repeat_paused", "Paused · %s") % task_name
		_reason_label.text = _paused_reason()
		_status_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		_reason_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))

	# Retry is an explicit action only for a paused rule. While armed there is
	# nothing to retry, and while waiting the remembered job is already running.
	_retry.text = _pack.label("ui.auto_repeat_retry", "Retry")
	_retry.visible = not code.is_empty() and code != AutoRepeat.CODE_BUSY


func task_id() -> String:
	return str(_snapshot.get("task_id", ""))


func status_code() -> String:
	return str(_snapshot.get("code", ""))


func status_text() -> String:
	return _status_label.text if _status_label != null else ""


func reason_text() -> String:
	return _reason_label.text if _reason_label != null else ""


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func retry_button() -> Button:
	return _retry


func _ensure_built() -> void:
	if _title != null:
		return
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(_title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_status_label)

	_reason_label = Label.new()
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason_label.add_theme_font_size_override("font_size", 11)
	column.add_child(_reason_label)

	_retry = Button.new()
	_retry.name = "Retry"
	_retry.text = _pack.label("ui.auto_repeat_retry", "Retry")
	_retry.custom_minimum_size = Vector2(0, 48)
	_retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry.visible = false
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	column.add_child(_retry)


func _waiting_reason() -> String:
	var names := _task_names(_snapshot.get("running_task_ids", []))
	if names.is_empty():
		return _pack.label(
			"ui.auto_repeat_waiting_reason",
			"Waiting for the current operation to finish.",
		)
	if names.size() == 1:
		return _pack.label(
			"ui.auto_repeat_waiting_one",
			"Starts when %s finishes.",
		) % names[0]
	return _pack.label(
		"ui.auto_repeat_waiting_many",
		"Starts when these operations finish: %s.",
	) % ", ".join(names)


func _paused_reason() -> String:
	match status_code():
		AutoRepeat.CODE_LOCKED:
			return _pack.label(
				"ui.auto_repeat_research_locked",
				"Auto-repeat research is locked.",
			)
		Simulation.ERROR_UNKNOWN_TASK:
			return _pack.label(
				"ui.auto_repeat_missing_task",
				"The saved operation is no longer available.",
			)
		Simulation.ERROR_UNKNOWN_AGENT:
			if bool(_snapshot.get("duplicate", false)):
				return _slot_text("ui.auto_repeat_duplicate", "Slot %d: %s is listed twice.")
			return _slot_issue_text(true)
		Simulation.ERROR_AGENT_BUSY:
			return _slot_issue_text(false)
		Simulation.ERROR_RATING_TOO_LOW:
			var rating := int(roundf(float(_snapshot.get("rating", 0.0))))
			var required := int(roundf(float(_snapshot.get("required_rating", 0.0))))
			if bool(_snapshot.get("squad", false)):
				return _pack.label(
					"ui.auto_repeat_squad_rating",
					"Squad rating %d / %d.",
				) % [rating, required]
			return _pack.label(
				"ui.auto_repeat_rating",
				"Available rating %d / %d.",
			) % [rating, required]
		Simulation.ERROR_MISSING_ROLE:
			var role_ids: Array = _snapshot.get("missing_role_ids", [])
			if role_ids.is_empty() and _snapshot.has("role_id"):
				role_ids = [_snapshot["role_id"]]
			var names: Array[String] = []
			for raw_id in role_ids:
				names.append(_role_name(str(raw_id)))
			return _pack.label(
				"ui.auto_repeat_missing_role",
				"Missing required role: %s.",
			) % ", ".join(names)
		Simulation.ERROR_AGENT_COUNT:
			return _pack.label(
				"ui.auto_repeat_agent_count",
				"Needs %d agents; %d available.",
			) % [
				int(_snapshot.get("required_agent_count", 0)),
				int(_snapshot.get("given_agent_count", 0)),
			]
	return _pack.label(
		"ui.auto_repeat_unknown_reason",
		"Cannot repeat this operation (%s).",
	) % status_code()


## One sentence per missing or locked slot. Busy slots name the operation that
## holds the agent, so "locked" is actionable rather than a generic refusal.
func _slot_issue_text(missing: bool) -> String:
	var blocked: Array = _snapshot.get("blocked_slots", [])
	var parts: Array[String] = []
	for raw in blocked:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		var index := int(item.get("index", 0)) + 1
		var agent_id := str(item.get("agent_id", ""))
		if agent_id.is_empty():
			parts.append(_pack.label(
				"ui.auto_repeat_empty_slot",
				"Slot %d has no agent.",
			) % index)
			continue
		var agent_name := _agent_name(agent_id)
		if missing and agent_name.is_empty():
			parts.append(_pack.label(
				"ui.auto_repeat_missing_slot",
				"Slot %d: the saved agent is no longer on the roster.",
			) % index)
			continue
		if missing:
			parts.append(_pack.label(
				"ui.auto_repeat_missing_member",
				"Slot %d: %s is no longer on the roster.",
			) % [index, agent_name])
			continue
		var assignment_id := str(item.get("assignment_id", ""))
		var task_id := _assignment_task(assignment_id)
		if task_id.is_empty():
			parts.append(_pack.label(
				"ui.auto_repeat_locked_slot",
				"Slot %d: %s is locked by another operation.",
			) % [index, agent_name])
		else:
			parts.append(_pack.label(
				"ui.auto_repeat_locked_slot_task",
				"Slot %d: %s is locked to %s.",
			) % [index, agent_name, _task_name(task_id)])
	if parts.is_empty():
		if missing:
			return _pack.label("ui.auto_repeat_missing_member_generic", "A saved agent is no longer on the roster.")
		return _pack.label("ui.auto_repeat_locked_slot_generic", "A saved agent is locked by another operation.")
	return " ".join(parts)


func _slot_text(label_key: String, fallback: String) -> String:
	var index := int(_snapshot.get("slot_index", 0)) + 1
	var agent_name := _agent_name(str(_snapshot.get("agent_id", "")))
	if agent_name.is_empty():
		return _pack.label(
			"ui.auto_repeat_duplicate_slot",
			"Slot %d: a saved agent is listed twice.",
		) % index
	return _pack.label(label_key, fallback) % [index, agent_name]


func _task_names(raw_ids: Variant) -> Array[String]:
	var names: Array[String] = []
	if not (raw_ids is Array):
		return names
	for raw_id in raw_ids:
		names.append(_task_name(str(raw_id)))
	return names


func _task_name(task_id: String) -> String:
	if _pack == null or not _pack.missions.has(task_id):
		return task_id
	return _pack.label(str(_pack.task(task_id).get("name_key", "")), task_id)


func _agent_name(agent_id: String) -> String:
	if _pack == null or agent_id.is_empty():
		return ""
	var record: Variant = _state.agents.get(agent_id, null)
	if not (record is Dictionary):
		record = _pack.starter_agents.get(agent_id, {})
	if record is Dictionary and not (record as Dictionary).is_empty():
		var display := _pack.agent_name(agent_id, record)
		# `agent_name` falls back to the id, which is an internal token. Leave it
		# unresolved so the banner can describe the slot without leaking the id.
		if display != agent_id:
			return display
	return ""


func _role_name(role_id: String) -> String:
	if _pack == null:
		return role_id
	return _pack.label(str(_pack.role(role_id).get("name_key", "")), role_id)


func _assignment_task(assignment_id: String) -> String:
	if assignment_id.is_empty() or _state == null:
		return ""
	var assignment: Variant = _state.assignments.get(assignment_id, null)
	if not (assignment is Dictionary):
		return ""
	return str((assignment as Dictionary).get("task_id", ""))

class_name TeamScreen
extends Control
## Squad operations: every multi-agent task with one picker per required agent.
##
## Each row keeps a draft lineup. Tapping a slot opens an inline list of agents
## under it: one full-width button per choice, so touch targets stay large and a
## list never depends on a popup's hit area. An agent already used by another
## slot is shown disabled, and a deployed agent is shown disabled with its state,
## so duplicates and activity locks are refused before they reach the deploy
## check. Saving stores the draft as a preference; deployment still runs the full
## `Simulation.evaluate_assignment` check, so an under-rated or busy lineup is
## refused with the usual reason.
##
## The draft is seeded from the saved preset, or from
## `Simulation.auto_select_agents` when none exists, so the tab still opens with
## a usable suggestion rather than empty rows.

signal deploy_requested(task_id: String, agent_ids: Array)
signal squads_changed()
signal auto_repeat_retry_requested

const MIN_TAP_HEIGHT := 48
const SLOT_OPTION_HEIGHT := 44
const CHOICE_HEIGHT := 42
const SAVE_BUTTON_WIDTH := 112
const SLOT_LABEL_WIDTH := 58

var _pack: GamePack
var _state: GameState
var _root: VBoxContainer
var _list: VBoxContainer
var _auto_repeat: AutoRepeatBanner
var _deploy_buttons: Dictionary = {}
var _save_buttons: Dictionary = {}
var _clear_buttons: Dictionary = {}
var _slot_buttons: Dictionary = {}
var _choice_buttons: Dictionary = {}
var _reasons: Dictionary = {}
var _drafts: Dictionary = {}
var _open_slot: String = ""
## Tasks whose draft has been touched by hand. Untouched rows re-seed from the
## saved preset or auto-selection on refresh, so roster changes appear without
## overwriting a lineup the player edited.
var _edited: Dictionary = {}


func squad_row_count() -> int:
	return _list.get_child_count() if _list != null else 0


func deploy_button(task_id: String) -> Button:
	return _button(_deploy_buttons, task_id)


func auto_repeat_banner() -> AutoRepeatBanner:
	return _auto_repeat


func save_button(task_id: String) -> Button:
	return _button(_save_buttons, task_id)


func clear_button(task_id: String) -> Button:
	return _button(_clear_buttons, task_id)


func slot_button(task_id: String, index: int) -> Button:
	return _button(_slot_buttons, "%s:%d" % [task_id, index])


func slot_count(task_id: String) -> int:
	var task := _pack.task(task_id) if _pack != null else {}
	return maxi(int(task.get("required_agent_count", 1)), 1)


## The current draft, in slot order. Empty slots are empty strings.
func lineup(task_id: String) -> Array[String]:
	if _state == null or not _drafts.has(task_id):
		return []
	var draft: Array[String] = []
	draft.assign(_drafts[task_id])
	return draft


func row_reason(task_id: String) -> String:
	var label: Variant = _reasons.get(task_id, null)
	if label is Label:
		return (label as Label).text
	return ""


## Opens the inline chooser under one slot. Only one chooser is open at a time.
func open_slot_picker(task_id: String, index: int) -> bool:
	if _state == null or _pack == null or not _pack.missions.has(task_id):
		return false
	if index < 0 or index >= slot_count(task_id):
		return false
	_open_slot = "%s:%d" % [task_id, index]
	refresh(_pack, _state)
	return true


func slot_picker_open(task_id: String, index: int) -> bool:
	return _open_slot == "%s:%d" % [task_id, index]


func slot_choice_button(task_id: String, index: int, agent_id: String) -> Button:
	return _button(_choice_buttons, "%s:%d:%s" % [task_id, index, agent_id])


## Puts `agent_id` in one slot. An empty id clears the slot. Returns false for an
## unknown task or slot, an agent already in another slot, or a deployed agent.
func select_slot_agent(task_id: String, index: int, agent_id: String) -> bool:
	if _state == null or _pack == null or not _pack.missions.has(task_id):
		return false
	var required := slot_count(task_id)
	if index < 0 or index >= required:
		return false
	var draft := _draft_for(task_id)
	if agent_id != "":
		if not _state.agents.has(agent_id):
			return false
		if not AgentRules.is_available(_state.agents[agent_id]):
			return false
		var existing := draft.find(agent_id)
		if existing != -1 and existing != index:
			return false
	draft[index] = agent_id
	_drafts[task_id] = draft
	_edited[task_id] = true
	_open_slot = ""
	refresh(_pack, _state)
	return true


func refresh(pack: GamePack, state: GameState) -> void:
	_pack = pack
	_state = state
	_ensure_built()
	_auto_repeat.refresh(pack, state)
	_clear(_list)
	_deploy_buttons.clear()
	_save_buttons.clear()
	_clear_buttons.clear()
	_slot_buttons.clear()
	_choice_buttons.clear()
	_reasons.clear()

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
	var scroll := TouchScroll.new()
	UILayout.fill(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_root)

	_auto_repeat = AutoRepeatBanner.new()
	_auto_repeat.name = "AutoRepeat"
	_auto_repeat.retry_requested.connect(func() -> void: auto_repeat_retry_requested.emit())
	_root.add_child(_auto_repeat)

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


## The draft for a task. A hand-edited draft is kept (pruned of unknown or
## duplicated ids); an untouched one re-seeds from the saved preset, or from
## auto-selection when no preset exists, so roster changes still flow through.
func _draft_for(task_id: String) -> Array[String]:
	var required := slot_count(task_id)
	if _edited.has(task_id):
		var cached: Array = _drafts.get(task_id, [])
		var clean: Array[String] = []
		for index in required:
			var agent_id := str(cached[index]) if index < cached.size() else ""
			if agent_id != "" and (not _state.agents.has(agent_id) or clean.has(agent_id)):
				agent_id = ""
			clean.append(agent_id)
		_drafts[task_id] = clean
		return clean

	var stored := Squads.member_ids(_state, task_id)
	var draft: Array[String] = []
	if not stored.is_empty():
		for index in required:
			var agent_id := stored[index] if index < stored.size() else ""
			if agent_id != "" and draft.has(agent_id):
				agent_id = ""
			draft.append(agent_id)
	else:
		var suggested := Simulation.auto_select_agents(_state, _pack, task_id, true)
		for index in required:
			draft.append(str(suggested[index]) if index < suggested.size() else "")
	_drafts[task_id] = draft
	return draft


func _squad_row(task_id: String) -> Control:
	var task := _pack.task(task_id)
	var required_count := slot_count(task_id)
	var draft := _draft_for(task_id)
	var stored := Squads.member_ids(_state, task_id)
	var saved := stored.size() == draft.size() and stored == draft
	var evaluation := Simulation.evaluate_assignment(_state, _pack, task_id, draft)
	var complete := _draft_complete(draft)

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

	for index in required_count:
		column.add_child(_slot_row(task_id, index, draft))

	var rating_total := 0.0
	var chosen := 0
	for raw_id in draft:
		var agent_id := str(raw_id)
		var record: Variant = _state.agents.get(agent_id, {})
		if agent_id.is_empty() or not (record is Dictionary):
			continue
		rating_total += TraitRules.rating_value(_pack, record, task)
		chosen += 1

	var required_rating := int(task.get("minimum_rating", 0))
	var average := rating_total / float(maxi(chosen, 1))
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

	var missing := _missing_roles(task, draft)
	if not missing.is_empty():
		var missing_label := Label.new()
		missing_label.text = "%s %s" % [_pack.label("ui.requires", "Needs"), ", ".join(missing)]
		missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		missing_label.add_theme_font_size_override("font_size", 11)
		missing_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
		column.add_child(missing_label)

	# Actions get a full-width row each: three buttons side by side left each one
	# too narrow to hit reliably on a phone, especially once Clear appears.
	var deploy := Button.new()
	deploy.name = "Deploy_%s" % task_id
	deploy.text = _pack.label("ui.deploy", "Deploy")
	deploy.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	deploy.disabled = not complete or not evaluation.get("ok", false)
	deploy.pressed.connect(func() -> void: deploy_requested.emit(task_id, lineup(task_id)))
	column.add_child(deploy)
	_deploy_buttons[task_id] = deploy

	var save := Button.new()
	save.name = "Save_%s" % task_id
	var save_text := _pack.label("ui.save_squad", "Save squad")
	if saved:
		save_text = _pack.label("ui.update_squad", "Update squad")
	save.text = save_text
	save.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
	save.disabled = not complete
	save.pressed.connect(func() -> void: _on_save(task_id))
	column.add_child(save)
	_save_buttons[task_id] = save

	if not Squads.for_task(_state, task_id).is_empty():
		var clear := Button.new()
		clear.name = "Clear_%s" % task_id
		clear.text = _pack.label("ui.clear_squad", "Clear")
		clear.custom_minimum_size = Vector2(0, CHOICE_HEIGHT)
		clear.pressed.connect(func() -> void: _on_clear(task_id))
		column.add_child(clear)
		_clear_buttons[task_id] = clear

	# The reason gets its own full-width line: a wrapping label inside the button
	# row has zero minimum width and collapses into a one-character column.
	if not complete:
		_add_reason(column, task_id, _pack.label("ui.blocked_squad_incomplete", "Fill every slot to deploy"))
	elif not evaluation.get("ok", false):
		var code := str(evaluation.get("code", ""))
		_add_reason(column, task_id, _blocked_text(code, task, evaluation))
	return panel


## One slot: the current agent as a full-width button, plus an inline chooser
## under it while open.
func _slot_row(task_id: String, index: int, draft: Array[String]) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var label := Label.new()
	label.text = _pack.label("ui.squad_slot", "Slot %d") % (index + 1)
	label.custom_minimum_size = Vector2(SLOT_LABEL_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	row.add_child(label)

	var picker := Button.new()
	picker.name = "Slot_%s_%d" % [task_id, index]
	picker.text = _slot_text(draft[index], _pack.task(task_id))
	picker.custom_minimum_size = Vector2(0, SLOT_OPTION_HEIGHT)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.pressed.connect(func() -> void: _toggle_picker(task_id, index))
	row.add_child(picker)
	_slot_buttons["%s:%d" % [task_id, index]] = picker

	if _open_slot == "%s:%d" % [task_id, index]:
		box.add_child(_slot_choices(task_id, index, draft))
	return box


## The inline chooser: Empty first, then every agent by task-adjusted rating.
## Taken or busy agents stay visible but disabled, so the reason for each refusal
## is on screen.
func _slot_choices(task_id: String, index: int, draft: Array[String]) -> Control:
	var task := _pack.task(task_id)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.add_child(_choice_button(task_id, index, "", _pack.label("ui.slot_empty", "Empty")))

	var agent_ids: Array = _state.agents.keys()
	agent_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var agent_a: Dictionary = _state.agents[str(a)]
		var agent_b: Dictionary = _state.agents[str(b)]
		var rating_a := int(roundf(TraitRules.rating_value(_pack, agent_a, task)))
		var rating_b := int(roundf(TraitRules.rating_value(_pack, agent_b, task)))
		if rating_a != rating_b:
			return rating_a > rating_b
		return str(a) < str(b)
	)

	for raw_id in agent_ids:
		var agent_id := str(raw_id)
		var agent: Dictionary = _state.agents[agent_id]
		var taken := draft.has(agent_id) and draft.find(agent_id) != index
		var busy := not AgentRules.is_available(agent)
		var rating := int(roundf(TraitRules.rating_value(_pack, agent, task)))
		var text := "%s · %d" % [_pack.agent_name(agent_id, agent), rating]
		if busy:
			text += " · %s" % _pack.label("ui.slot_busy", "deployed")
		var choice := _choice_button(task_id, index, agent_id, text)
		choice.disabled = taken or busy
		list.add_child(choice)
	return list


func _choice_button(task_id: String, index: int, agent_id: String, text: String) -> Button:
	var choice := Button.new()
	choice.name = "Choice_%s_%d_%s" % [task_id, index, agent_id]
	choice.text = text
	choice.custom_minimum_size = Vector2(0, CHOICE_HEIGHT)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.pressed.connect(func() -> void: _choose_slot(task_id, index, agent_id))
	_choice_buttons["%s:%d:%s" % [task_id, index, agent_id]] = choice
	return choice


func _slot_text(agent_id: String, task: Dictionary) -> String:
	var record: Variant = _state.agents.get(agent_id, null)
	if not (record is Dictionary):
		return _pack.label("ui.slot_empty", "Empty")
	var agent: Dictionary = record
	var rating := int(roundf(TraitRules.rating_value(_pack, agent, task)))
	var text := "%s · %d" % [_pack.agent_name(agent_id, agent), rating]
	if not AgentRules.is_available(agent):
		text += " · %s" % _pack.label("ui.slot_busy", "deployed")
	return text


func _toggle_picker(task_id: String, index: int) -> void:
	var key := "%s:%d" % [task_id, index]
	_open_slot = "" if _open_slot == key else key
	refresh(_pack, _state)


func _choose_slot(task_id: String, index: int, agent_id: String) -> void:
	_open_slot = ""
	if not select_slot_agent(task_id, index, agent_id):
		refresh(_pack, _state)


func _add_reason(column: VBoxContainer, task_id: String, text: String) -> void:
	var reason := Label.new()
	reason.text = text
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.add_theme_font_size_override("font_size", 11)
	reason.add_theme_color_override("font_color", ThemeTokens.color(_pack, "warning"))
	column.add_child(reason)
	_reasons[task_id] = reason


func _draft_complete(draft: Array[String]) -> bool:
	for agent_id in draft:
		if agent_id.is_empty() or not _state.agents.has(agent_id):
			return false
	return true


## Locale text for a block code. A count shortfall states how many agents the
## operation needs, so a one-short squad does not read as "no agent is free".
func _blocked_text(code: String, task: Dictionary, evaluation: Dictionary) -> String:
	if code == Simulation.ERROR_STAGE_LOCKED:
		return CommandProgression.stage_lock_text(_pack, evaluation)
	if code == Simulation.ERROR_AGENT_COUNT:
		return _pack.label("ui.blocked_agent_count", "Needs %d available agents") % maxi(
			int(task.get("required_agent_count", 1)), 1
		)
	return _pack.label("ui.blocked_%s" % code, code)


func _on_save(task_id: String) -> void:
	if Squads.save(_state, task_id, lineup(task_id)).get("ok", false):
		squads_changed.emit()


func _on_clear(task_id: String) -> void:
	if Squads.clear(_state, task_id):
		_drafts.erase(task_id)
		_edited.erase(task_id)
		_open_slot = ""
		squads_changed.emit()


func _button(source: Dictionary, key: String) -> Button:
	var button: Variant = source.get(key, null)
	if button is Button:
		return button
	return null


## Required roles the chosen squad does not cover, as display names.
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

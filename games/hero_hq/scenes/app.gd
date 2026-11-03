extends Control
## HERO//HQ composition root (game layer).
##
## This is the only place allowed to name the title: it loads the hero_hq pack,
## restores or creates the state, settles the time the player was away, and
## builds the HQ screen. Shared behaviour lives in `framework/`.

const PACK_ID := "hero_hq"
const STARTING_SEED := 1
const HOME_TAB := "hq"
const STARTER_ROLE_ORDER := ["vanguard", "striker", "tech", "support", "mystic"]

var _pack: GamePack
var _state: GameState
var _shell: ScreenShell
var _clock: Clock = Clock.new()
var _settled_seconds: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var loaded := GamePackLoader.load_pack(PACK_ID)
	var errors: Array = loaded.get("errors", [])
	if not errors.is_empty():
		_build_error_view(errors)
		return
	_pack = loaded["pack"]
	_state = _restore_or_create_state()
	_settle_absence()
	_build_shell()


func _exit_tree() -> void:
	if _state != null:
		SaveService.save_state(_state)


func _restore_or_create_state() -> GameState:
	var loaded := SaveService.load_state(PACK_ID)
	var existing: Variant = loaded.get("state", null)
	if existing is GameState:
		var state: GameState = existing
		state.pack_content_version = _pack.content_version
		return state
	return Simulation.new_state(_pack, STARTING_SEED, _clock.now_utc())


## Advances the simulation by the time the app was closed. Offline and online
## play share this one code path, so there is a single settlement rule.
func _settle_absence() -> void:
	var elapsed := float(_clock.now_utc() - _state.last_settled_utc)
	var outcome := Simulation.simulate_delta(_state, elapsed, _pack)
	_state = outcome["state"]
	_settled_seconds = float(outcome["applied_seconds"])
	SaveService.save_state(_state)


func _build_shell() -> void:
	_shell = ScreenShell.new()
	_shell.name = "ScreenShell"
	add_child(_shell)
	_shell.build(_pack)
	_shell.refresh(_state)
	_shell.tab_selected.connect(_on_tab_selected)
	_shell.select_tab(HOME_TAB)


func _on_tab_selected(tab_id: String) -> void:
	if tab_id == HOME_TAB:
		_shell.set_content(_build_hq_content())
		return
	_shell.set_content(_build_placeholder(tab_id))


func _build_hq_content() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	column.add_child(_build_network_card())
	column.add_child(_info_row(
		_pack.label("ui.roster_active"),
		"%d / %d" % [_state.agents.size(), int(_pack.manifest.get("roster_capacity", 0))]
	))
	var status_text := _pack.label("ui.idle_status")
	if _settled_seconds > 0.0:
		status_text = "%s (%s s)" % [_pack.label("ui.offline_settled"), str(int(_settled_seconds))]
	column.add_child(_info_row(_pack.label("ui.status"), status_text))
	return scroll


func _build_network_card() -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var title := Label.new()
	title.text = _pack.label("ui.network_title")
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(title)

	var network := HeroNetworkPanel.new()
	var nodes := PackedColorArray()
	var agent_ids: Array = _state.agents.keys()
	agent_ids.sort()
	for agent_id in agent_ids:
		var record: Dictionary = _state.agents[agent_id]
		var role_index := maxi(STARTER_ROLE_ORDER.find(str(record.get("role_id", ""))), 0)
		var token := "accent" if role_index % 2 == 0 else "accent_alt"
		nodes.append(ThemeTokens.color(_pack, token, ThemeTokens.color(_pack, "accent")))
	network.setup(
		ThemeTokens.color(_pack, "success"),
		nodes,
		ThemeTokens.color(_pack, "border"),
		ThemeTokens.color(_pack, "border")
	)
	column.add_child(network)
	return panel


func _info_row(caption: String, value: String) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_label.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	row.add_child(caption_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return panel


func _build_placeholder(tab_id: String) -> Control:
	var panel := PanelContainer.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = _pack.label("tabs.%s" % tab_id, tab_id)
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", ThemeTokens.color(_pack, "accent"))
	column.add_child(heading)

	var note := Label.new()
	note.text = _pack.label("ui.section_placeholder")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", ThemeTokens.color(_pack, "muted"))
	column.add_child(note)
	return panel


func _build_error_view(errors: Array) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = "Content pack failed validation"
	heading.add_theme_font_size_override("font_size", 18)
	column.add_child(heading)

	for error in errors:
		var line := Label.new()
		if error is Dictionary:
			var entry: Dictionary = error
			line.text = "[%s] %s" % [str(entry.get("code", "")), str(entry.get("message", ""))]
		else:
			line.text = str(error)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		column.add_child(line)

	var hint := Label.new()
	hint.text = "godot --headless --path . -s res://tooling/validate_packs.gd"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	column.add_child(hint)

class_name ScreenShell
extends Control
## Game-neutral portrait shell.
##
## Owns the safe-area inset, header (title + resource strip), a content slot and
## a bottom tab bar. Tab ids and labels come from the pack manifest, so a pack
## with different sections renders without touching this file.

signal tab_selected(tab_id: String)

const MIN_TAP_HEIGHT := 48


var _pack: GamePack
var _content_slot: MarginContainer
var _tab_bar: HBoxContainer
var _tab_buttons: Dictionary = {}
var _resource_bar: ResourceBar
var _title_label: Label
var _current_tab: String = ""


func build(pack: GamePack) -> void:
	_pack = pack
	theme = ThemeTokens.build_theme(pack)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	for child in get_children():
		remove_child(child)
		child.queue_free()

	var background := ColorRect.new()
	background.color = ThemeTokens.color(pack, "background")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe_margin := MarginContainer.new()
	safe_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe_margin.name = "SafeArea"
	add_child(safe_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	safe_margin.add_child(column)

	var header := PanelContainer.new()
	header.name = "Header"
	column.add_child(header)
	var header_column := VBoxContainer.new()
	header_column.add_theme_constant_override("separation", 4)
	header.add_child(header_column)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = pack.title()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", ThemeTokens.color(pack, "accent"))
	header_column.add_child(_title_label)

	_resource_bar = ResourceBar.new()
	_resource_bar.name = "ResourceBar"
	header_column.add_child(_resource_bar)

	_content_slot = MarginContainer.new()
	_content_slot.name = "Content"
	_content_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_content_slot)

	var tab_panel := PanelContainer.new()
	tab_panel.name = "TabBar"
	column.add_child(tab_panel)
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 4)
	tab_panel.add_child(_tab_bar)
	_render_tabs()

	_apply_safe_area()


func refresh(state: GameState) -> void:
	if _pack == null:
		return
	if _title_label != null:
		_title_label.text = _pack.title()
	if _resource_bar != null:
		_resource_bar.render(_pack, state)


func set_content(node: Control) -> void:
	if _content_slot == null:
		return
	for child in _content_slot.get_children():
		_content_slot.remove_child(child)
		child.queue_free()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_slot.add_child(node)


func select_tab(tab_id: String) -> void:
	if not _tab_buttons.has(tab_id):
		return
	_current_tab = tab_id
	for key in _tab_buttons.keys():
		var button: Button = _tab_buttons[key]
		button.set_pressed_no_signal(key == tab_id)
	tab_selected.emit(tab_id)


func current_tab() -> String:
	return _current_tab


func tab_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _tab_buttons.keys():
		ids.append(str(key))
	return ids


func _render_tabs() -> void:
	_tab_buttons.clear()
	for entry in _pack.navigation:
		if not (entry is Dictionary):
			continue
		var tab: Dictionary = entry
		var tab_id := str(tab.get("id", ""))
		var button := Button.new()
		button.name = "Tab_%s" % tab_id
		button.text = _pack.label(str(tab.get("label_key", "")), tab_id)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, MIN_TAP_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_tab_pressed.bind(tab_id))
		_tab_bar.add_child(button)
		_tab_buttons[tab_id] = button


func _on_tab_pressed(tab_id: String) -> void:
	select_tab(tab_id)


## Keeps content clear of notches and rounded corners. The safe area is
## reported in screen pixels, so it is converted to the logical canvas size.
func _apply_safe_area() -> void:
	var safe_margin := get_node_or_null("SafeArea") as MarginContainer
	if safe_margin == null:
		return
	if DisplayServer.get_name() == "headless":
		_apply_margins(safe_margin, 0, 0, 0, 0)
		return
	var window_size := size
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	var screen_size := Vector2(DisplayServer.screen_get_size())
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return
	var safe_area := Rect2(DisplayServer.get_display_safe_area())
	var left := (safe_area.position.x / screen_size.x) * window_size.x
	var top := (safe_area.position.y / screen_size.y) * window_size.y
	var right := ((screen_size.x - safe_area.end.x) / screen_size.x) * window_size.x
	var bottom := ((screen_size.y - safe_area.end.y) / screen_size.y) * window_size.y
	_apply_margins(
		safe_margin,
		maxi(int(left), 0),
		maxi(int(top), 0),
		maxi(int(right), 0),
		maxi(int(bottom), 0)
	)


func _apply_margins(margin: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	margin.add_theme_constant_override("margin_left", maxi(left, 8))
	margin.add_theme_constant_override("margin_right", maxi(right, 8))
	margin.add_theme_constant_override("margin_top", maxi(top, 8))
	margin.add_theme_constant_override("margin_bottom", maxi(bottom, 8))

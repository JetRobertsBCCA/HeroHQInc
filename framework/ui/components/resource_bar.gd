class_name ResourceBar
extends HBoxContainer
## Read-only resource strip. Resource ids and labels come from the pack, so the
## same widget serves any title.

var _pack: GamePack


func render(pack: GamePack, state: GameState) -> void:
	_pack = pack
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 14)
	for resource_id in pack.declared_resources():
		add_child(_entry(pack, state, str(resource_id)))


func _entry(pack: GamePack, state: GameState, resource_id: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = pack.label("resources.%s" % resource_id, resource_id)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ThemeTokens.color(pack, "muted"))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(label)

	var value := Label.new()
	value.text = _format_amount(state.resource(resource_id))
	value.add_theme_font_size_override("font_size", 17)
	value.add_theme_color_override("font_color", ThemeTokens.color(pack, "reward"))
	column.add_child(value)
	return column


static func _format_amount(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(int(roundf(amount)))
	return "%.1f" % amount

class_name ThemeTokens
extends RefCounted
## Turns a pack's color tokens into a Godot Theme.
##
## The framework knows token *names* (generic roles like background/accent) and
## nothing about which colors a title picks, so a different pack restyles the
## whole shared UI without editing framework code.

const REQUIRED_TOKENS: Array[String] = [
	"background",
	"panel",
	"border",
	"text",
	"muted",
	"accent",
	"accent_alt",
	"success",
	"reward",
	"warning",
]


static func color(pack: GamePack, token: String, fallback: Color = Color.WHITE) -> Color:
	var value: Variant = pack.theme.get(token, null)
	if value is String:
		return Color.from_string(value, fallback)
	return fallback


static func missing_tokens(pack: GamePack) -> Array[String]:
	var missing: Array[String] = []
	for token in REQUIRED_TOKENS:
		if not pack.theme.has(token):
			missing.append(token)
	return missing


static func build_theme(pack: GamePack) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	var panel := color(pack, "panel", Color(0.07, 0.11, 0.16))
	var border := color(pack, "border", Color(0.15, 0.22, 0.29))
	var text := color(pack, "text", Color(0.9, 0.93, 0.97))
	var accent := color(pack, "accent", Color(0.0, 0.9, 0.96))

	theme.set_color("font_color", "Label", text)
	theme.set_font_size("font_size", "Label", 15)
	theme.set_color("font_color", "Button", text)
	theme.set_font_size("font_size", "Button", 13)
	theme.set_color("font_color", "RichTextLabel", text)

	theme.set_stylebox("normal", "Button", _box(panel, border))
	theme.set_stylebox("hover", "Button", _box(panel.lightened(0.06), accent))
	theme.set_stylebox("pressed", "Button", _box(panel.darkened(0.08), accent))
	theme.set_stylebox("focus", "Button", _box(panel, accent))
	theme.set_stylebox("disabled", "Button", _box(panel.darkened(0.12), border))
	theme.set_stylebox("panel", "PanelContainer", _box(panel, border))
	return theme


static func _box(background: Color, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border_color
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

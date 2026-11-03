class_name HeroNetworkPanel
extends Control
## HERO//HQ-specific decorative operations network.
##
## Draws a flat grid, a central HQ node and one satellite per active agent.
## Purely informational: every action is available from the tab bar, never only
## from this visualization. Cheap `_draw()` only — no shaders, no per-frame work.

var grid_color := Color(0.15, 0.22, 0.29, 0.45)
var line_color := Color(0.15, 0.22, 0.29, 0.9)
var center_color := Color.WHITE
var node_colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	custom_minimum_size = Vector2(0, 180)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func setup(center: Color, nodes: PackedColorArray, grid: Color, lines: Color) -> void:
	center_color = center
	node_colors = nodes
	grid_color = grid
	line_color = lines
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cell := 24.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid_color, 1.0)
		x += cell
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_color, 1.0)
		y += cell
	var center := size * 0.5
	var ring_radius := minf(size.x, size.y) * 0.32
	var count := maxi(node_colors.size(), 1)
	for index in node_colors.size():
		var angle := (TAU * float(index) / float(count)) - (PI * 0.5)
		var node_position := center + Vector2(cos(angle), sin(angle)) * ring_radius
		draw_line(center, node_position, line_color, 1.5)
		draw_circle(node_position, 4.5, node_colors[index])
	draw_circle(center, 7.0, center_color)

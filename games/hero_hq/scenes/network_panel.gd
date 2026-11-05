class_name HeroNetworkPanel
extends Control
## HERO//HQ-specific live operations network.
##
## Draws a flat grid, a central HQ, one numbered satellite per running
## assignment, and small tokens travelling from HQ to the active operation.
## Below the map, compact rows repeat the same information in text: operation,
## crew, percent complete and time left. That keeps the visualization
## informational rather than the only source of state.
##
## Draw-only and cheap on purpose: no scene nodes are created per tick, no
## shaders, and the animation timer runs at 5 Hz only while this panel is
## visible, has a running operation, and reduced motion is off.

const MAX_ACTIVE_NODES := 3
const MIN_HEIGHT := 190.0
const PAD := 10.0
const PAD_TOP := 8.0
const HEADER_HEIGHT := 22.0
const DIAGRAM_HEIGHT := 82.0
const GAP_BEFORE_ROWS := 6.0
const ROW_HEIGHT := 56.0
const ROW_TITLE_TOP := 2.0
const ROW_META_TOP := 22.0
const ROW_BAR_TOP := 48.0
const ROW_BAR_HEIGHT := 4.0
const MORE_HEIGHT := 20.0
const PAD_BOTTOM := 8.0
const HEADER_FONT_SIZE := 14
const ROW_TITLE_FONT_SIZE := 15
const ROW_TIME_FONT_SIZE := 15
const ROW_META_FONT_SIZE := 14
const IDLE_FONT_SIZE := 14
const MORE_FONT_SIZE := 14
const MAP_LABEL_FONT_SIZE := 10
const ANIMATION_INTERVAL := 0.2
const COMPLETION_MS := 2400
const ACTIVE_ANGLES := [-PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]

var grid_color := Color(0.15, 0.22, 0.29, 0.22)
var center_color := Color.WHITE
var text_color := Color.WHITE
var muted_color := Color(0.56, 0.65, 0.73)
var border_color := Color(0.15, 0.22, 0.29)
var panel_color := Color(0.07, 0.11, 0.16)
var accent_color := Color(0.0, 0.9, 0.96)
var team_color := Color(0.85, 0.56, 0.98)
var success_color := Color(0.51, 0.92, 0.69)
var reward_color := Color(0.97, 0.78, 0.33)

var _pack: GamePack
var _activities: Array = []
var _idle_count := 0
var _live_count := 0
var _completion: Dictionary = {}
var _completion_id := ""
var _completion_started_msec := 0
var _reduced_motion := false
var _phase := 0.0
var _font: Font
var _timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_font = get_theme_default_font()
	_timer = Timer.new()
	_timer.name = "ActivityMotion"
	_timer.wait_time = ANIMATION_INTERVAL
	_timer.timeout.connect(_on_animation_tick)
	add_child(_timer)
	visibility_changed.connect(_update_animation_timer)
	resized.connect(queue_redraw)
	custom_minimum_size = Vector2(0, _panel_height())
	_update_animation_timer()


## The app supplies localized text and numeric feed data; this control only
## lays out what it is given. Calling it again updates the same draw state.
func setup(pack: GamePack, feed: Dictionary, reduced_motion: bool = false) -> void:
	_pack = pack
	_reduced_motion = reduced_motion
	_apply_theme(pack)
	_apply_feed(feed)
	custom_minimum_size = Vector2(0, _panel_height())
	_update_animation_timer()
	queue_redraw()


## Per-second refresh from the app. This keeps progress and time-left labels
## current without rebuilding any scene nodes.
func tick(feed: Dictionary) -> void:
	var previous_rows := _visible_row_count()
	_apply_feed(feed)
	if _visible_row_count() != previous_rows:
		custom_minimum_size = Vector2(0, _panel_height())
	if _completion_expired():
		_clear_completion()
	_update_animation_timer()
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_update_animation_timer()
	queue_redraw()


func is_reduced_motion() -> bool:
	return _reduced_motion


func animation_is_running() -> bool:
	return _timer != null and not _timer.is_stopped()


## True when the state calls for motion, whether or not this control happens to
## be on screen. `animation_is_running()` additionally includes visibility and
## timer state, which keeps headless tests independent of a display server.
func motion_should_run() -> bool:
	return not _reduced_motion and (not _activities.is_empty() or completion_visible())


func activity_count() -> int:
	return _activities.size()


func idle_count() -> int:
	return _idle_count


func activity_info(index: int) -> Dictionary:
	if index < 0 or index >= _activities.size():
		return {}
	return (_activities[index] as Dictionary).duplicate(true)


func completion_visible() -> bool:
	return not _completion.is_empty() and not _completion_expired()


func completion_text() -> String:
	if not completion_visible():
		return ""
	return "%s %s" % [
		str(_completion.get("title", "")),
		_pack.label("ui.network_complete", "COMPLETE") if _pack != null else "COMPLETE",
	]


func _apply_theme(pack: GamePack) -> void:
	grid_color = _with_alpha(ThemeTokens.color(pack, "border"), 0.24)
	center_color = ThemeTokens.color(pack, "success")
	text_color = ThemeTokens.color(pack, "text")
	muted_color = ThemeTokens.color(pack, "muted")
	border_color = ThemeTokens.color(pack, "border")
	panel_color = ThemeTokens.color(pack, "panel")
	accent_color = ThemeTokens.color(pack, "accent")
	team_color = ThemeTokens.color(pack, "accent_alt")
	success_color = ThemeTokens.color(pack, "success")
	reward_color = ThemeTokens.color(pack, "reward")


func _apply_feed(feed: Dictionary) -> void:
	_activities.clear()
	var raw_activities: Variant = feed.get("activities", [])
	if raw_activities is Array:
		for entry in raw_activities:
			if entry is Dictionary:
				_activities.append(entry)
	_idle_count = maxi(int(feed.get("idle_count", 0)), 0)
	_live_count = _activities.size()
	var raw_completion: Variant = feed.get("completion", {})
	if raw_completion is Dictionary and not (raw_completion as Dictionary).is_empty():
		var next_id := str((raw_completion as Dictionary).get("id", ""))
		if next_id != _completion_id:
			_completion_id = next_id
			_completion_started_msec = Time.get_ticks_msec()
		_completion = (raw_completion as Dictionary).duplicate(true)
	else:
		_clear_completion()


func _clear_completion() -> void:
	_completion.clear()
	_completion_id = ""
	_completion_started_msec = 0


func _completion_expired() -> bool:
	return not _completion.is_empty() and (
		Time.get_ticks_msec() - _completion_started_msec >= COMPLETION_MS
	)


func _visible_row_count() -> int:
	return mini(_activities.size(), MAX_ACTIVE_NODES)


func _panel_height() -> float:
	var rows := _visible_row_count()
	var more := 1 if _activities.size() > MAX_ACTIVE_NODES else 0
	var needed := PAD_TOP + HEADER_HEIGHT + DIAGRAM_HEIGHT + GAP_BEFORE_ROWS
	needed += float(rows) * ROW_HEIGHT + float(more) * MORE_HEIGHT + PAD_BOTTOM
	return maxf(MIN_HEIGHT, needed)


func _update_animation_timer() -> void:
	if _timer == null:
		return
	var should_run := motion_should_run() and is_visible_in_tree()
	if should_run:
		if _timer.is_stopped():
			_timer.start()
	else:
		_timer.stop()


func _on_animation_tick() -> void:
	_phase = fmod(_phase + ANIMATION_INTERVAL, TAU)
	if _completion_expired():
		_clear_completion()
		_update_animation_timer()
	queue_redraw()


func _draw() -> void:
	if _pack == null or size.x <= 0.0 or size.y <= 0.0:
		return
	if _font == null:
		_font = get_theme_default_font()
	var diagram_top := PAD_TOP + HEADER_HEIGHT
	var rows_top := diagram_top + DIAGRAM_HEIGHT + GAP_BEFORE_ROWS
	_draw_header()
	_draw_grid(diagram_top)
	_draw_map(Vector2(size.x * 0.5, diagram_top + DIAGRAM_HEIGHT * 0.5))
	_draw_rows(rows_top)


func _draw_header() -> void:
	var baseline_top := PAD_TOP
	if completion_visible():
		var reward := str(_completion.get("reward", ""))
		var reward_width := _text_width(reward, HEADER_FONT_SIZE) if not reward.is_empty() else 0.0
		var title := completion_text()
		var available := size.x - PAD * 2.0 - 18.0
		if reward_width > 0.0:
			available -= reward_width + 8.0
		_draw_check(Vector2(PAD + 6.0, baseline_top + 10.0))
		_draw_left(
			_fit_text(title, available, HEADER_FONT_SIZE),
			Vector2(PAD + 18.0, baseline_top),
			HEADER_FONT_SIZE,
			success_color,
		)
		if not reward.is_empty():
			_draw_right(reward, size.x - PAD, baseline_top, HEADER_FONT_SIZE, reward_color)
		return
	var live_text := _pack.label(
		"ui.network_standby",
		"STANDBY",
	) if _live_count == 0 else _pack.label("ui.network_live", "%d LIVE") % _live_count
	var ready_text := _pack.label("ui.network_ready", "%d READY") % _idle_count
	_draw_left(live_text, Vector2(PAD, baseline_top), HEADER_FONT_SIZE, success_color)
	_draw_right(ready_text, size.x - PAD, baseline_top, HEADER_FONT_SIZE, muted_color)


func _draw_grid(top: float) -> void:
	var bottom := top + DIAGRAM_HEIGHT
	var cell := 24.0
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, top), Vector2(x, bottom), grid_color, 1.0)
		x += cell
	var y := top
	while y <= bottom:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_color, 1.0)
		y += cell


func _draw_map(center: Vector2) -> void:
	var radius := Vector2(minf(size.x * 0.25, 78.0), 24.0)
	var idle_radius := Vector2(minf(size.x * 0.35, 108.0), 30.0)
	_draw_idle_nodes(center, idle_radius)
	# The center node sits below the active lines so every spoke reads as
	# connected to HQ rather than passing underneath it.
	for index in _visible_row_count():
		_draw_active_link(center, radius, index)
	draw_circle(center, 12.0, _with_alpha(border_color, 0.95))
	draw_circle(center, 10.0, panel_color)
	draw_arc(center, 12.0, 0.0, TAU, 24, _with_alpha(border_color, 1.0), 1.0, true)
	draw_circle(center, 4.5, center_color)
	_draw_centered("HQ", Vector2(center.x, center.y + 15.0), MAP_LABEL_FONT_SIZE, muted_color)
	if completion_visible():
		_draw_completion_pulse(center)


func _draw_idle_nodes(center: Vector2, radius: Vector2) -> void:
	var count := mini(_idle_count, 8)
	for index in count:
		var angle := -PI * 0.5 + TAU * (float(index) + 0.5) / 8.0
		var point := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		draw_circle(point, 4.0, panel_color)
		draw_arc(point, 4.0, 0.0, TAU, 12, _with_alpha(muted_color, 0.55), 1.0, true)


func _draw_active_link(center: Vector2, radius: Vector2, index: int) -> void:
	var activity: Dictionary = _activities[index]
	var angle: float = ACTIVE_ANGLES[index % ACTIVE_ANGLES.size()]
	var point := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
	var squad := bool(activity.get("squad", false))
	var color := team_color if squad else accent_color
	var progress := clampf(float(activity.get("progress", 0.0)), 0.0, 1.0)

	if not _reduced_motion:
		var halo := 0.05 + 0.05 * (0.5 + 0.5 * sin(_phase * 1.2 + float(index)))
		draw_circle(point, 14.0, _with_alpha(color, halo))
	draw_line(center, point, _with_alpha(color, 0.48), 1.2, true)
	draw_arc(point, 10.0, 0.0, TAU, 24, _with_alpha(border_color, 0.9), 1.5, true)
	if progress > 0.001:
		draw_arc(
			point,
			10.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			24,
			color,
			1.8,
			true,
		)
	_draw_satellite(point, color, squad)
	_draw_travelling_tokens(center, point, color, int(activity.get("agent_count", 1)), index)
	_draw_centered(str(index + 1), Vector2(point.x, point.y - 16.0), MAP_LABEL_FONT_SIZE, color)


func _draw_satellite(point: Vector2, color: Color, squad: bool) -> void:
	if squad:
		var offsets: Array[Vector2] = [Vector2(-3.6, 1.2), Vector2(0.0, -3.2), Vector2(3.6, 1.2)]
		for offset in offsets:
			draw_circle(point + offset, 2.4, color)
		return
	var diamond := PackedVector2Array([
		point + Vector2(0.0, -4.8),
		point + Vector2(4.8, 0.0),
		point + Vector2(0.0, 4.8),
		point + Vector2(-4.8, 0.0),
	])
	draw_colored_polygon(diamond, color)


func _draw_travelling_tokens(
	center: Vector2,
	point: Vector2,
	color: Color,
	agent_count: int,
	index: int
) -> void:
	var count := clampi(agent_count, 1, 3)
	var direction := (point - center).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var travel := 0.58
	if not _reduced_motion:
		travel = 0.5 + 0.5 * sin(_phase + float(index) * 1.7)
	var base := center.lerp(point, 0.3 + travel * 0.48)
	for member in count:
		var lateral := (float(member) - float(count - 1) * 0.5) * 3.6
		draw_circle(base + perpendicular * lateral, 2.2, _with_alpha(color, 0.95))


func _draw_completion_pulse(center: Vector2) -> void:
	var age := float(Time.get_ticks_msec() - _completion_started_msec) / 1000.0
	if age > 1.8:
		return
	if _reduced_motion:
		draw_arc(center, 17.0, 0.0, TAU, 32, _with_alpha(success_color, 0.55), 1.5, true)
		return
	var t := clampf(age / 1.6, 0.0, 1.0)
	var radius := 14.0 + 34.0 * t
	var alpha := (1.0 - t) * 0.7
	draw_arc(center, radius, 0.0, TAU, 32, _with_alpha(success_color, alpha), 2.0, true)
	draw_arc(center, radius + 3.0, 0.0, TAU, 32, _with_alpha(success_color, alpha * 0.4), 1.0, true)


func _draw_rows(top: float) -> void:
	if _visible_row_count() == 0:
		var idle_line := _pack.label("ui.network_idle", "No active operations")
		var idle_hint := _pack.label("ui.network_idle_hint", "Deploy from Missions.")
		_draw_centered(
			idle_line,
			Vector2(size.x * 0.5, top + 2.0),
			IDLE_FONT_SIZE,
			muted_color,
		)
		_draw_centered(
			idle_hint,
			Vector2(size.x * 0.5, top + 22.0),
			IDLE_FONT_SIZE,
			muted_color,
		)
		return
	for index in _visible_row_count():
		_draw_activity_row(index, top + float(index) * ROW_HEIGHT)
	if _activities.size() > MAX_ACTIVE_NODES:
		_draw_left(
			_pack.label("ui.network_more", "+%d more active") % (_activities.size() - MAX_ACTIVE_NODES),
			Vector2(PAD, top + float(MAX_ACTIVE_NODES) * ROW_HEIGHT),
			MORE_FONT_SIZE,
			muted_color,
		)


func _draw_activity_row(index: int, top: float) -> void:
	var activity: Dictionary = _activities[index]
	var squad := bool(activity.get("squad", false))
	var color := team_color if squad else accent_color
	var progress := clampf(float(activity.get("progress", 0.0)), 0.0, 1.0)
	var number := "%02d" % (index + 1)
	var number_width := _text_width(number, ROW_META_FONT_SIZE)
	var content_left := PAD + number_width + 8.0
	if index > 0:
		draw_line(
			Vector2(PAD, top - 7.0),
			Vector2(size.x - PAD, top - 7.0),
			_with_alpha(border_color, 0.65),
			1.0,
		)
	_draw_left(number, Vector2(PAD, top + ROW_TITLE_TOP), ROW_META_FONT_SIZE, color)
	var remaining := str(activity.get("remaining", "0:00"))
	var remaining_width := _text_width(remaining, ROW_TIME_FONT_SIZE)
	_draw_right(
		remaining,
		size.x - PAD,
		top + ROW_TITLE_TOP,
		ROW_TIME_FONT_SIZE,
		reward_color,
	)
	var title_width := maxf(
		size.x - PAD * 2.0 - number_width - 8.0 - remaining_width - 8.0,
		0.0,
	)
	_draw_left(
		_fit_text(str(activity.get("title", "")), title_width, ROW_TITLE_FONT_SIZE),
		Vector2(content_left, top + ROW_TITLE_TOP),
		ROW_TITLE_FONT_SIZE,
		text_color,
	)
	var kind := _pack.label("ui.squad", "Squad") if squad else _pack.label("ui.solo", "Solo")
	if squad:
		kind = "%s %d" % [kind, int(activity.get("agent_count", 1))]
	var crew := str(activity.get("crew", ""))
	var meta := kind if crew.is_empty() else "%s · %s" % [kind, crew]
	var percent := "%d%%" % int(roundf(progress * 100.0))
	var percent_width := _text_width(percent, ROW_META_FONT_SIZE)
	var meta_width := maxf(
		size.x - PAD * 2.0 - number_width - 8.0 - percent_width - 8.0,
		0.0,
	)
	_draw_left(
		_fit_text(meta, meta_width, ROW_META_FONT_SIZE),
		Vector2(content_left, top + ROW_META_TOP),
		ROW_META_FONT_SIZE,
		muted_color,
	)
	_draw_right(
		percent,
		size.x - PAD,
		top + ROW_META_TOP,
		ROW_META_FONT_SIZE,
		color,
	)
	var bar := Rect2(
		PAD,
		top + ROW_BAR_TOP,
		size.x - PAD * 2.0,
		ROW_BAR_HEIGHT,
	)
	draw_rect(bar, _with_alpha(border_color, 0.55))
	if progress > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), color)


func _draw_check(center: Vector2) -> void:
	draw_arc(center, 5.0, 0.0, TAU, 16, _with_alpha(success_color, 0.9), 1.0, true)
	draw_polyline(
		PackedVector2Array([
			center + Vector2(-2.2, 0.1),
			center + Vector2(-0.4, 2.0),
			center + Vector2(2.5, -2.0),
		]),
		success_color,
		1.3,
		true,
	)


func _draw_left(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	draw_string(
		_font,
		Vector2(top_left.x, top_left.y + _font.get_ascent(font_size)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color,
	)


func _draw_centered(text: String, top_center: Vector2, font_size: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var width := _text_width(text, font_size)
	_draw_left(text, Vector2(top_center.x - width * 0.5, top_center.y), font_size, color)


func _draw_right(text: String, right: float, top: float, font_size: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var width := _text_width(text, font_size)
	_draw_left(text, Vector2(right - width, top), font_size, color)


func _text_width(text: String, font_size: int) -> float:
	if _font == null:
		return 0.0
	return _font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
	).x


func _fit_text(text: String, max_width: float, font_size: int) -> String:
	if max_width <= 0.0:
		return ""
	if _text_width(text, font_size) <= max_width:
		return text
	var shortened := text
	while not shortened.is_empty():
		shortened = shortened.left(shortened.length() - 1)
		if _text_width(shortened + "...", font_size) <= max_width:
			return shortened + "..."
	return "..."


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))

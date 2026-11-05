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
const MIN_HEIGHT := 184.0
const PAD := 10.0
const PAD_TOP := 8.0
const HEADER_HEIGHT := 22.0
const DIAGRAM_HEIGHT := 96.0
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
const MAP_LABEL_FONT_SIZE := 9
const MAP_TITLE_FONT_SIZE := 9
const MAP_META_FONT_SIZE := 8
const STAGE_ICON_Y := 32.0
const STAGE_LABEL_Y := 1.0
const STAGE_META_Y := 12.0
const ROUTE_Y := 50.0
const BADGE_TOP := 53.0
const BADGE_HEIGHT := 20.0
const BADGE_WIDTH := 100.0
const HQ_Y := 84.0
const HQ_RADIUS := 11.0
const STAGE_RADIUS := 10.0
const TRAIL_COUNT := 4
const ANIMATION_INTERVAL := 0.2
const COMPLETION_MS := 2400

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
var warning_color := Color(1.0, 0.4, 0.52)

var _pack: GamePack
var _activities: Array = []
var _destinations: Array = []
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


func stage_count() -> int:
	return _destinations.size()


func stage_info(index: int) -> Dictionary:
	if index < 0 or index >= _destinations.size():
		return {}
	return (_destinations[index] as Dictionary).duplicate(true)


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
	warning_color = ThemeTokens.color(pack, "warning")


func _apply_feed(feed: Dictionary) -> void:
	_activities.clear()
	var raw_activities: Variant = feed.get("activities", [])
	if raw_activities is Array:
		for entry in raw_activities:
			if entry is Dictionary:
				_activities.append(entry)
	_destinations.clear()
	var raw_destinations: Variant = feed.get("destinations", [])
	if raw_destinations is Array:
		for entry in raw_destinations:
			if entry is Dictionary:
				_destinations.append((entry as Dictionary).duplicate(true))
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
	_draw_map(diagram_top)
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
	var ready_count_text := _pack.label("ui.network_ready", "%d READY") % _idle_count
	var missions_text := _pack.label("tabs.missions", "Missions").to_upper()
	var live_width := _text_width(live_text, HEADER_FONT_SIZE)
	var missions_width := _text_width(missions_text, HEADER_FONT_SIZE)
	var ready_width := _text_width(ready_count_text, HEADER_FONT_SIZE)
	var max_ready_width := maxf(size.x - PAD * 2.0 - live_width - 10.0, 0.0)
	_draw_left(live_text, Vector2(PAD, baseline_top), HEADER_FONT_SIZE, success_color)
	if ready_width + missions_width + 8.0 <= max_ready_width:
		var right := size.x - PAD
		_draw_right(missions_text, right, baseline_top, HEADER_FONT_SIZE, accent_color)
		_draw_right(
			ready_count_text,
			right - missions_width - 8.0,
			baseline_top,
			HEADER_FONT_SIZE,
			muted_color,
		)
	else:
		_draw_right(
			_fit_text("%s · %s" % [ready_count_text, missions_text], max_ready_width, HEADER_FONT_SIZE),
			size.x - PAD,
			baseline_top,
			HEADER_FONT_SIZE,
			muted_color,
		)


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


func _draw_map(top: float) -> void:
	_draw_grid(top)
	var hq := Vector2(size.x * 0.5, top + HQ_Y)
	var first_locked := _first_locked_stage()
	var active_by_stage: Dictionary = {}
	for index in _visible_row_count():
		var entry: Dictionary = _activities[index]
		var stage_index := _stage_index(str(entry.get("stage_id", "")), index)
		if stage_index >= 0 and not active_by_stage.has(stage_index):
			active_by_stage[stage_index] = entry

	# Quiet route lines keep all three destinations on the map even while idle.
	for stage_index in _destinations.size():
		if active_by_stage.has(stage_index):
			continue
		draw_polyline(
			_route_points(top, hq, stage_index),
			_with_alpha(border_color, 0.62),
			1.0,
			true,
		)

	for index in _visible_row_count():
		var activity: Dictionary = _activities[index]
		var stage_index := _stage_index(str(activity.get("stage_id", "")), index)
		if stage_index < 0:
			continue
		var color := team_color if bool(activity.get("squad", false)) else accent_color
		var path := _route_points(top, hq, stage_index)
		draw_polyline(path, _with_alpha(color, 0.15), 4.0, true)
		draw_polyline(path, color, 1.4, true)
		_draw_dispatch_trail(path, color, int(activity.get("agent_count", 1)), index)

	for stage_index in _destinations.size():
		var active: Dictionary = active_by_stage.get(stage_index, {})
		_draw_stage_node(top, stage_index, active, first_locked)

	for index in _visible_row_count():
		var activity: Dictionary = _activities[index]
		var stage_index := _stage_index(str(activity.get("stage_id", "")), index)
		if stage_index < 0:
			continue
		var color := team_color if bool(activity.get("squad", false)) else accent_color
		_draw_path_badge(top, index, activity, stage_index, color)

	if completion_visible():
		_draw_completion_return(top, hq)
	_draw_hq(hq)
	if completion_visible():
		_draw_completion_pulse(hq)


func _draw_stage_node(
	top: float,
	stage_index: int,
	activity: Dictionary,
	first_locked: int
) -> void:
	var destination: Dictionary = _destinations[stage_index]
	var locked := not bool(destination.get("unlocked", true))
	var active := not activity.is_empty()
	var color := _stage_color(stage_index, active)
	var point := Vector2(_stage_x(stage_index), top + STAGE_ICON_Y)

	if active and not _reduced_motion:
		var halo := 0.05 + 0.05 * (0.5 + 0.5 * sin(_phase * 1.2 + float(stage_index)))
		draw_circle(point, STAGE_RADIUS + 5.0, _with_alpha(color, halo))
	draw_circle(point, STAGE_RADIUS, _with_alpha(panel_color, 0.96))
	draw_arc(
		point,
		STAGE_RADIUS,
		0.0,
		TAU,
		24,
		_with_alpha(color if not locked else border_color, 0.95),
		1.4,
		true,
	)
	if active:
		var progress := clampf(float(activity.get("progress", 0.0)), 0.0, 1.0)
		if progress > 0.001:
			draw_arc(
				point,
				STAGE_RADIUS + 2.0,
				-PI * 0.5,
				-PI * 0.5 + TAU * progress,
				24,
				color,
				1.8,
				true,
			)
	_draw_stage_icon(point, stage_index, color if not locked else muted_color)
	if locked:
		_draw_lock(point + Vector2(10.0, -10.0))

	var label := str(destination.get("label", ""))
	var label_color := muted_color if locked else (color if active else text_color)
	_draw_centered_fit(
		label,
		Vector2(point.x, top + STAGE_LABEL_Y),
		MAP_LABEL_FONT_SIZE,
		label_color,
		BADGE_WIDTH,
	)

	var meta := ""
	var meta_color := muted_color
	if completion_visible() and _completion_stage_index() == stage_index:
		meta = "%s %s" % [
			_pack.label("ui.network_complete", "COMPLETE"),
			str(_completion.get("reward", "")),
		]
		meta_color = success_color
	elif active:
		meta = str(activity.get("payout", ""))
		meta_color = reward_color
	elif locked:
		var unlock_level := int(destination.get("unlock_level", 1))
		meta = "%s · LV %d" % [
			"NEXT" if stage_index == first_locked else "LOCKED",
			unlock_level,
		]
		meta_color = warning_color if stage_index == first_locked else muted_color
	if not meta.is_empty():
		_draw_centered_fit(
			meta,
			Vector2(point.x, top + STAGE_META_Y),
			MAP_META_FONT_SIZE,
			meta_color,
			BADGE_WIDTH,
		)


func _draw_path_badge(
	top: float,
	index: int,
	activity: Dictionary,
	stage_index: int,
	color: Color
) -> void:
	var x := clampf(
		_stage_x(stage_index) - BADGE_WIDTH * 0.5,
		4.0,
		maxf(size.x - BADGE_WIDTH - 4.0, 4.0),
	)
	var y := top + BADGE_TOP
	var badge := Rect2(x, y, BADGE_WIDTH, BADGE_HEIGHT)
	draw_rect(badge, _with_alpha(panel_color, 0.97))
	draw_rect(badge, _with_alpha(color, 0.68), false, 1.0)
	draw_line(Vector2(x, y), Vector2(x, y + BADGE_HEIGHT), color, 2.0)
	var title := "%02d %s" % [index + 1, str(activity.get("title", ""))]
	_draw_left(
		_fit_text(title, BADGE_WIDTH - 8.0, MAP_TITLE_FONT_SIZE),
		Vector2(x + 4.0, y + 1.0),
		MAP_TITLE_FONT_SIZE,
		color,
	)
	var crew := str(activity.get("crew", ""))
	var percent := "%d%%" % int(roundf(clampf(float(activity.get("progress", 0.0)), 0.0, 1.0) * 100.0))
	var meta := percent if crew.is_empty() else "%s · %s" % [crew, percent]
	_draw_left(
		_fit_text(meta, BADGE_WIDTH - 8.0, MAP_META_FONT_SIZE),
		Vector2(x + 4.0, y + 10.0),
		MAP_META_FONT_SIZE,
		muted_color,
	)


func _draw_hq(hq: Vector2) -> void:
	draw_circle(hq, HQ_RADIUS + 5.0, _with_alpha(center_color, 0.07))
	draw_circle(hq, HQ_RADIUS, _with_alpha(panel_color, 0.98))
	draw_arc(hq, HQ_RADIUS, 0.0, TAU, 32, _with_alpha(center_color, 0.9), 1.6, true)
	draw_arc(hq, HQ_RADIUS - 5.0, 0.0, TAU, 32, _with_alpha(center_color, 0.42), 1.0, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_line(
			hq + Vector2(cos(angle), sin(angle)) * (HQ_RADIUS + 1.0),
			hq + Vector2(cos(angle), sin(angle)) * (HQ_RADIUS + 5.0),
			_with_alpha(center_color, 0.55),
			1.0,
			true,
		)
	draw_circle(hq, 5.5, center_color)
	_draw_centered("HQ", Vector2(hq.x, hq.y - 4.0), MAP_META_FONT_SIZE, center_color)


func _draw_stage_icon(point: Vector2, stage_index: int, color: Color) -> void:
	var ink := _with_alpha(color, 0.95)
	match stage_index % 3:
		0:
			# A street sign reads differently from the city skyline at this size.
			draw_rect(Rect2(point + Vector2(-8.0, -7.0), Vector2(16.0, 6.0)), ink, false, 1.3)
			draw_line(point + Vector2(0.0, -1.0), point + Vector2(0.0, 8.0), ink, 1.4, true)
			draw_line(point + Vector2(-5.0, -4.0), point + Vector2(5.0, -4.0), ink, 1.0, true)
		1:
			draw_rect(Rect2(point + Vector2(-10.0, -3.0), Vector2(5.0, 9.0)), ink, false, 1.3)
			draw_rect(Rect2(point + Vector2(-3.0, -8.0), Vector2(6.0, 14.0)), ink, false, 1.3)
			draw_rect(Rect2(point + Vector2(5.0, -5.0), Vector2(5.0, 11.0)), ink, false, 1.3)
			draw_circle(point + Vector2(-0.5, -3.0), 1.1, ink)
			draw_circle(point + Vector2(-0.5, 2.0), 1.1, ink)
		_:
			var shield := PackedVector2Array([
				point + Vector2(0.0, -10.0),
				point + Vector2(9.0, -5.0),
				point + Vector2(7.0, 5.0),
				point + Vector2(0.0, 10.0),
				point + Vector2(-7.0, 5.0),
				point + Vector2(-9.0, -5.0),
				point + Vector2(0.0, -10.0),
			])
			draw_polyline(shield, ink, 1.3, true)
			draw_line(point + Vector2(-5.0, -1.0), point + Vector2(5.0, -1.0), ink, 1.0, true)
			draw_line(point + Vector2(0.0, -5.0), point + Vector2(0.0, 4.0), ink, 1.0, true)


func _draw_lock(point: Vector2) -> void:
	draw_arc(point + Vector2(0.0, -1.0), 3.2, PI, TAU, 10, muted_color, 1.0, true)
	draw_rect(Rect2(point + Vector2(-4.0, -1.0), Vector2(8.0, 6.0)), _with_alpha(panel_color, 0.98))
	draw_rect(Rect2(point + Vector2(-4.0, -1.0), Vector2(8.0, 6.0)), muted_color, false, 1.0)


func _first_locked_stage() -> int:
	for index in _destinations.size():
		if not bool((_destinations[index] as Dictionary).get("unlocked", true)):
			return index
	return -1


func _stage_color(stage_index: int, active: bool) -> Color:
	var destination: Dictionary = _destinations[stage_index]
	if not bool(destination.get("unlocked", true)):
		return muted_color
	if active:
		for index in _visible_row_count():
			var activity: Dictionary = _activities[index]
			if _stage_index(str(activity.get("stage_id", "")), index) == stage_index:
				return team_color if bool(activity.get("squad", false)) else accent_color
	return accent_color


func _stage_x(stage_index: int) -> float:
	var count := _destinations.size()
	if count <= 1:
		return size.x * 0.5
	var fraction := 0.18 + 0.64 * float(stage_index) / float(count - 1)
	return size.x * fraction


func _stage_index(stage_id: String, fallback: int) -> int:
	for index in _destinations.size():
		if str((_destinations[index] as Dictionary).get("id", "")) == stage_id:
			return index
	if _destinations.is_empty():
		return -1
	return mini(maxi(fallback, 0), _destinations.size() - 1)


func _completion_stage_index() -> int:
	if _completion.is_empty():
		return -1
	return _stage_index(str(_completion.get("stage_id", "")), 0)


func _route_points(top: float, hq: Vector2, stage_index: int) -> PackedVector2Array:
	var stage_x := _stage_x(stage_index)
	return PackedVector2Array([
		hq + Vector2(0.0, -HQ_RADIUS + 1.0),
		Vector2(hq.x, top + ROUTE_Y),
		Vector2(stage_x, top + ROUTE_Y),
		Vector2(stage_x, top + STAGE_ICON_Y + STAGE_RADIUS),
	])


func _draw_dispatch_trail(
	path: PackedVector2Array,
	color: Color,
	agent_count: int,
	index: int
) -> void:
	# Offset the first tick so a still capture shows the dispatch stream on the
	# route instead of hiding every dot under the HQ hub.
	var travel := fmod(0.58 + float(index) * 0.08, 1.0)
	if not _reduced_motion:
		travel = fmod(_phase * 0.25 + float(index + 1) * 0.33, 1.0)
	_draw_dot_trail(path, color, travel, agent_count, false)


func _draw_dot_trail(
	path: PackedVector2Array,
	color: Color,
	travel: float,
	agent_count: int,
	reverse: bool
) -> void:
	if path.size() < 2:
		return
	var count := clampi(agent_count, 1, 3)
	var direction := _direction_on_polyline(path, travel)
	if direction.length_squared() < 0.001:
		direction = Vector2(1.0, 0.0)
	var perpendicular := Vector2(-direction.y, direction.x)
	for member in count:
		var lateral := (float(member) - float(count - 1) * 0.5) * 3.2
		for trail in TRAIL_COUNT:
			var offset := float(trail) * 0.035
			var sample := clampf(travel + offset if reverse else travel - offset, 0.0, 1.0)
			var point := _point_on_polyline(path, sample) + perpendicular * lateral
			var alpha := 0.95 if trail == 0 else 0.62 * (1.0 - float(trail) / float(TRAIL_COUNT))
			var radius := 2.4 if trail == 0 else maxf(0.8, 2.4 - float(trail) * 0.42)
			draw_circle(point, radius, _with_alpha(color, alpha))
			if trail == 0:
				draw_circle(point, 0.75, Color(1.0, 1.0, 1.0, 0.9))


func _point_on_polyline(path: PackedVector2Array, t: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		return path[0]
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	if total <= 0.001:
		return path[0]
	var target := clampf(t, 0.0, 1.0) * total
	var walked := 0.0
	for index in range(1, path.size()):
		var segment := path[index - 1].distance_to(path[index])
		if walked + segment >= target:
			var local := (target - walked) / maxf(segment, 0.001)
			return path[index - 1].lerp(path[index], local)
		walked += segment
	return path[path.size() - 1]


func _direction_on_polyline(path: PackedVector2Array, t: float) -> Vector2:
	var before := _point_on_polyline(path, maxf(t - 0.006, 0.0))
	var after := _point_on_polyline(path, minf(t + 0.006, 1.0))
	if before.distance_to(after) <= 0.001:
		before = _point_on_polyline(path, maxf(t - 0.06, 0.0))
		after = _point_on_polyline(path, minf(t + 0.06, 1.0))
	return (after - before).normalized()


func _draw_completion_return(top: float, hq: Vector2) -> void:
	var stage_index := _completion_stage_index()
	if stage_index < 0:
		return
	var path := _route_points(top, hq, stage_index)
	draw_polyline(path, _with_alpha(success_color, 0.32), 2.0, true)
	var travel := 0.52
	if not _reduced_motion:
		var age := float(Time.get_ticks_msec() - _completion_started_msec) / 1000.0
		travel = 1.0 - clampf(age / 1.8, 0.0, 1.0)
	_draw_dot_trail(path, success_color, travel, 1, true)


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


func _draw_centered_fit(
	text: String,
	top_center: Vector2,
	font_size: int,
	color: Color,
	max_width: float
) -> void:
	if _font == null or text.is_empty():
		return
	var fitted := _fit_text(text, max_width, font_size)
	var width := _text_width(fitted, font_size)
	_draw_left(fitted, Vector2(top_center.x - width * 0.5, top_center.y), font_size, color)


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

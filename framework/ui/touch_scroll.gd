class_name TouchScroll
extends ScrollContainer
## A ScrollContainer that also scrolls under a finger.
##
## Godot's ScrollContainer scrolls with the wheel and its scrollbar but ignores
## touch drags, so on a phone any content below the fold is unreachable. The
## Rebirth button sat exactly there.
##
## The drag is handled before the GUI so it works over buttons and labels. A tap
## is left untouched: only a release that followed a real drag is swallowed, so
## scrolling can never press the button it started on.

const DRAG_THRESHOLD := 6.0

var _touch_index: int = -1
var _start_y: float = 0.0
var _dragging: bool = false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index != -1:
				return
			if not get_global_rect().has_point(touch.position):
				return
			_touch_index = touch.index
			_start_y = touch.position.y
			_dragging = false
			return
		if touch.index == _touch_index:
			# Swallow the release so the control under the finger never fires a
			# click for a gesture that was a scroll.
			if _dragging:
				get_viewport().set_input_as_handled()
			_touch_index = -1
			_dragging = false
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_index:
			return
		if not _dragging:
			if absf(drag.position.y - _start_y) < DRAG_THRESHOLD:
				return
			_dragging = true
		scroll_vertical -= int(roundf(drag.relative.y))
		get_viewport().set_input_as_handled()

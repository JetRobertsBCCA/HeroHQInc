class_name UILayout
extends RefCounted
## Small layout helpers shared by the framework screens.
##
## `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` defaults to minimum-size
## mode, so a freshly built control ends up at its minimum size in the middle of
## its parent instead of filling it. Filling therefore needs anchors *and*
## explicit zero offsets.

## Makes `control` fill its parent control's rect.
static func fill(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0

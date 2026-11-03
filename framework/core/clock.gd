class_name Clock
extends RefCounted
## Pluggable time source.
##
## Production code uses `Clock` (wall-clock UTC plus a monotonic tick counter).
## Tests and deterministic replays use `Clock.Manual` so elapsed time is an
## explicit input rather than a property of the machine.

## Wall-clock UTC seconds. Only elapsed *deltas* may be derived from this.
func now_utc() -> int:
	return int(Time.get_unix_time_from_system())

## Monotonic seconds, unaffected by device clock changes.
func monotonic_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


class Manual extends Clock:
	var _now: int = 0
	var _monotonic: float = 0.0

	func _init(start_utc: int = 0) -> void:
		_now = start_utc

	func now_utc() -> int:
		return _now

	func monotonic_seconds() -> float:
		return _monotonic

	func advance(seconds: int) -> void:
		_now += seconds
		_monotonic += float(seconds)

	func set_utc(value: int) -> void:
		_now = value

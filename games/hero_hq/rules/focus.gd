class_name HeroFocus
extends RefCounted
## HERO//HQ Focus: a small active-acceleration resource.
##
## The shared state keeps this module under `extensions["hero_hq.focus"]`.
## Focus regenerates in real time, including while the app is closed, and is
## spent on one running mission. A pulse reduces the current remaining time by
## the configured fraction, capped per solo/squad operation and never below the
## configured minimum. Each assignment has its own cooldown, stored with the
## assignment so it survives a reload.
##
## This is game-specific rule code because the codex defines Focus as a
## HERO//HQ signature mechanic. The shared framework only supplies state,
## assignment and persistence primitives.

const MODULE_ID := "hero_hq.focus"

const CODE_UNKNOWN_ASSIGNMENT := "focus_unknown_assignment"
const CODE_EMPTY := "focus_empty"
const CODE_COOLDOWN := "focus_cooldown"
const CODE_FINISHED := "focus_finished"
const CODE_NO_TIME := "focus_no_time"
const CODE_UNAVAILABLE := "focus_unavailable"

const DEFAULT_MAX := 5
const DEFAULT_REGEN_SECONDS := 60
const DEFAULT_PULSE_FRACTION := 0.15
const DEFAULT_SOLO_CAP_SECONDS := 30
const DEFAULT_SQUAD_CAP_SECONDS := 90
const DEFAULT_PULSE_INTERVAL_SECONDS := 10
const DEFAULT_MINIMUM_REMAINING_SECONDS := 1


static func enabled(pack: GamePack) -> bool:
	return not pack.focus.is_empty()


static func max_focus(pack: GamePack) -> int:
	return maxi(int(pack.focus.get("max", DEFAULT_MAX)), 1)


static func regen_seconds(pack: GamePack) -> int:
	return maxi(int(pack.focus.get("regen_seconds", DEFAULT_REGEN_SECONDS)), 1)


static func pulse_fraction(pack: GamePack) -> float:
	return clampf(float(pack.focus.get("pulse_fraction", DEFAULT_PULSE_FRACTION)), 0.01, 1.0)


static func solo_cap_seconds(pack: GamePack) -> int:
	return maxi(int(pack.focus.get("solo_cap_seconds", DEFAULT_SOLO_CAP_SECONDS)), 1)


static func squad_cap_seconds(pack: GamePack) -> int:
	return maxi(int(pack.focus.get("squad_cap_seconds", DEFAULT_SQUAD_CAP_SECONDS)), 1)


static func pulse_interval_seconds(pack: GamePack) -> int:
	return maxi(
		int(pack.focus.get("pulse_interval_seconds", DEFAULT_PULSE_INTERVAL_SECONDS)),
		0
	)


static func minimum_remaining_seconds(pack: GamePack) -> int:
	return maxi(
		int(pack.focus.get("minimum_remaining_seconds", DEFAULT_MINIMUM_REMAINING_SECONDS)),
		1
	)


## Creates or normalises the module state. A save from before Focus existed
## starts full; a save that already spent Focus keeps its banked value.
static func settle(state: GameState, pack: GamePack, utc_now: int) -> Dictionary:
	if not enabled(pack):
		return {}
	var cap := max_focus(pack)
	var now := maxi(int(utc_now), 0)
	var raw: Variant = state.extensions.get(MODULE_ID, null)
	if not (raw is Dictionary):
		var fresh := {"current": cap, "last_regen_utc": now}
		state.extensions[MODULE_ID] = fresh
		return fresh

	var data: Dictionary = raw
	var current := clampi(int(data.get("current", cap)), 0, cap)
	var last := int(data.get("last_regen_utc", now))
	if last > now:
		# A backwards clock must not create progress or a negative interval.
		last = now
	var regen := regen_seconds(pack)
	if current >= cap:
		# Never bank regeneration while the bar is full; a pulse starts the
		# next interval from the moment the bar leaves full.
		current = cap
		last = now
	else:
		var gained := int((now - last) / regen)
		if gained > 0:
			current = mini(cap, current + gained)
			last += gained * regen
			if current >= cap:
				last = now
	data["current"] = current
	data["last_regen_utc"] = last
	state.extensions[MODULE_ID] = data
	return data


static func current(state: GameState, pack: GamePack, utc_now: int) -> int:
	if not enabled(pack):
		return 0
	return int(settle(state, pack, utc_now).get("current", 0))


## Seconds until the next Focus point, or 0 when full/unavailable.
static func next_in_seconds(state: GameState, pack: GamePack, utc_now: int) -> int:
	if not enabled(pack):
		return 0
	var data := settle(state, pack, utc_now)
	var cap := max_focus(pack)
	if int(data.get("current", 0)) >= cap:
		return 0
	var now := maxi(int(utc_now), 0)
	var last := int(data.get("last_regen_utc", now))
	return maxi(regen_seconds(pack) - maxi(now - last, 0), 0)


## A side-effect-free-enough snapshot used by the UI: it settles due
## regeneration in the state, but never spends Focus or changes an assignment.
static func project(
	state: GameState,
	pack: GamePack,
	assignment_id: String,
	utc_now: int
) -> Dictionary:
	var result := {
		"ok": false,
		"code": CODE_UNAVAILABLE,
		"current": 0,
		"max": max_focus(pack) if enabled(pack) else 0,
		"saved_seconds": 0,
		"remaining_seconds": 0,
		"cooldown_seconds": 0,
	}
	if not enabled(pack):
		return result
	var data := settle(state, pack, utc_now)
	result["current"] = int(data.get("current", 0))
	var assignment_value: Variant = state.assignments.get(assignment_id, null)
	if not (assignment_value is Dictionary):
		result["code"] = CODE_UNKNOWN_ASSIGNMENT
		return result
	var assignment: Dictionary = assignment_value
	var task: Dictionary = pack.task(str(assignment.get("task_id", "")))
	if task.is_empty():
		result["code"] = CODE_UNKNOWN_ASSIGNMENT
		return result

	var now := maxi(int(utc_now), 0)
	var ends_utc := int(assignment.get("ends_utc", 0))
	var remaining := maxi(ends_utc - now, 0)
	result["remaining_seconds"] = remaining
	var minimum_remaining := minimum_remaining_seconds(pack)
	if remaining <= minimum_remaining:
		result["code"] = CODE_FINISHED
		return result
	if int(result["current"]) <= 0:
		result["code"] = CODE_EMPTY
		return result

	var interval := pulse_interval_seconds(pack)
	var last_pulse := int(assignment.get("focus_pulse_utc", -interval))
	var cooldown := maxi(interval - maxi(now - last_pulse, 0), 0)
	result["cooldown_seconds"] = cooldown
	if cooldown > 0:
		result["code"] = CODE_COOLDOWN
		return result

	var raw := maxi(int(floor(float(remaining) * pulse_fraction(pack))), 1)
	var cap := solo_cap_seconds(pack)
	if int(task.get("required_agent_count", 1)) > 1:
		cap = squad_cap_seconds(pack)
	var saved := mini(mini(raw, cap), remaining - minimum_remaining)
	if saved < 1:
		result["code"] = CODE_NO_TIME
		return result

	result["code"] = ""
	result["ok"] = true
	result["saved_seconds"] = saved
	return result


## Spends one Focus on a running assignment. Returns the projection plus the
## updated ends time. A refusal does not spend Focus or move the deadline.
static func spend_on_assignment(
	state: GameState,
	pack: GamePack,
	assignment_id: String,
	utc_now: int
) -> Dictionary:
	if not enabled(pack):
		return {
			"ok": false,
			"code": CODE_UNAVAILABLE,
			"current": 0,
			"max": 0,
			"saved_seconds": 0,
			"remaining_seconds": 0,
			"cooldown_seconds": 0,
		}
	var result := project(state, pack, assignment_id, utc_now)
	if not bool(result.get("ok", false)):
		return result
	var saved := int(result.get("saved_seconds", 0))
	var assignment: Dictionary = state.assignments[assignment_id]
	var now := maxi(int(utc_now), 0)
	assignment["ends_utc"] = int(assignment.get("ends_utc", now)) - saved
	assignment["focus_pulse_utc"] = now
	state.assignments[assignment_id] = assignment

	var data := settle(state, pack, now)
	data["current"] = maxi(int(data.get("current", 0)) - 1, 0)
	state.extensions[MODULE_ID] = data
	result["current"] = int(data.get("current", 0))
	result["remaining_seconds"] = maxi(int(assignment.get("ends_utc", now)) - now, 0)
	result["cooldown_seconds"] = pulse_interval_seconds(pack)
	return result

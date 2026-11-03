class_name Simulation
extends RefCounted
## Deterministic, game-neutral simulation entry points.
##
## M0 establishes the seam only: state creation from a pack and a single
## `simulate_delta` used identically online and after an absence. Training,
## timed tasks, releases and arbitration are added in later milestones; they
## plug into `simulate_delta` so online and offline play share one code path.
##
## Nothing in this file may import a content pack, reference a title-specific
## identifier, or touch platform SDKs.

## Builds a fresh state for a pack. Deterministic for a given
## (pack, seed, utc) triple: no clock reads, no randomness.
static func new_state(pack: GamePack, seed_value: int, utc_now: int) -> GameState:
	var state := GameState.new()
	state.game_id = pack.game_id
	state.pack_content_version = pack.content_version
	state.last_settled_utc = utc_now
	state.resources = pack.starting_resources.duplicate(true)
	for agent_id in pack.starter_agents.keys():
		var record: Variant = pack.starter_agents[agent_id]
		if record is Dictionary:
			state.agents[agent_id] = (record as Dictionary).duplicate(true)
	state.extensions["simulation"] = {"seed": seed_value}
	return state


## Advances `state` by `elapsed_seconds` and returns
## {state, events, requested_seconds, applied_seconds, capped}.
##
## Elapsed time is clamped to `[0, pack.max_offline_seconds]` so a clock that
## jumps backwards cannot subtract progress and a long absence cannot pay out
## more than the pack's offline allowance.
static func simulate_delta(state: GameState, elapsed_seconds: float, pack: GamePack) -> Dictionary:
	var requested := elapsed_seconds
	if is_nan(requested) or is_inf(requested):
		requested = 0.0
	requested = maxf(requested, 0.0)
	var cap := maxf(pack.max_offline_seconds, 0.0)
	var applied := requested
	var capped := false
	if applied > cap:
		applied = cap
		capped = true
	state.last_settled_utc += int(applied)
	# Later milestones settle due events here (training level-ups, task
	# completions, focus regeneration, automation arbitration) and append them
	# to `events` in a fixed deterministic order.
	var events: Array = []
	return {
		"state": state,
		"events": events,
		"requested_seconds": requested,
		"applied_seconds": applied,
		"capped": capped,
	}

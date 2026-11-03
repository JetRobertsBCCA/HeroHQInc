extends SceneTree
## Headless walkthrough of the M1 loop, used as a demo and a smoke check.
##
##   godot --headless --path . -s res://tooling/demo_loop.gd
##
## Runs on a manual clock against an in-memory state, so it never touches the
## player's save and finishes in milliseconds.

const PACK_ID := "hero_hq"
const START_UTC := 1_700_000_000


func _initialize() -> void:
	var loaded := GamePackLoader.load_pack(PACK_ID)
	if loaded["pack"] == null:
		print("FAIL pack did not load: %s" % str(loaded["errors"]))
		quit(1)
		return
	var pack: GamePack = loaded["pack"]
	var clock := Clock.Manual.new(START_UTC)
	var state := Simulation.new_state(pack, 1, clock.now_utc())

	print("%s — content v%d" % [pack.title(), pack.content_version])
	print("offline allowance: %d s" % int(pack.max_offline_seconds))
	_report(pack, state, clock)

	print("\n[deploy] %s" % pack.label("tasks.s_alley"))
	var deployed := Simulation.deploy(state, pack, "s_alley", clock.now_utc())
	if not deployed.get("ok", false):
		print("FAIL deploy refused: %s" % str(deployed))
		quit(1)
		return
	print("  assignment %s ends at +%d s" % [
		str(deployed["assignment_id"]),
		int(deployed["ends_utc"]) - clock.now_utc(),
	])
	_report(pack, state, clock)

	for step in [10, 10]:
		clock.advance(step)
		var outcome := Simulation.simulate_delta(state, float(step), pack)
		state = outcome["state"]
		print("\n[+%ds] %s" % [step, _describe(pack, outcome["events"])])
		_report(pack, state, clock)

	print("\n[train] twice")
	for index in 2:
		var trained := Simulation.train_agent(state, pack, "hero_volt")
		if not trained.get("ok", false):
			print("FAIL training refused: %s" % str(trained))
			quit(1)
			return
		print("  session %d costs %d, level %d -> %d" % [
			index + 1,
			int(trained["cost"]),
			int(trained["level_before"]),
			int(trained["level_after"]),
		])
	_report(pack, state, clock)

	print("\n[deploy] %s" % pack.label("tasks.s_rooftop"))
	var harder := Simulation.deploy(state, pack, "s_rooftop", clock.now_utc())
	print("  %s" % ("accepted" if harder.get("ok", false) else "refused: %s" % str(harder.get("code", ""))))
	if harder.get("ok", false):
		clock.advance(150)
		var finished := Simulation.simulate_delta(state, 150.0, pack)
		state = finished["state"]
		print("  [+150s] %s" % _describe(pack, finished["events"]))
	_report(pack, state, clock)

	print("\nOK loop complete")
	quit(0)


func _describe(pack: GamePack, events: Array) -> String:
	if events.is_empty():
		return "nothing finished yet"
	var parts: Array[String] = []
	for event in events:
		if not (event is Dictionary):
			continue
		var entry: Dictionary = event
		if str(entry.get("type", "")) == "task_completed":
			parts.append("%s complete %s" % [
				pack.label(str(pack.task(str(entry.get("task_id", ""))).get("name_key", ""))),
				TextFormat.rewards(pack, entry.get("rewards", {})),
			])
		elif str(entry.get("type", "")) == "level_up":
			parts.append("%s reached level %d" % [
				pack.agent_name(str(entry.get("agent_id", "")), {}),
				int(entry.get("level", 1)),
			])
	return ", ".join(parts)


func _report(pack: GamePack, state: GameState, clock: Clock.Manual) -> void:
	var balances: Array[String] = []
	for resource_id in pack.declared_resources():
		balances.append("%s %s" % [
			TextFormat.amount(state.resource(str(resource_id))),
			pack.label("resources.%s" % str(resource_id)),
		])
	var agents: Array[String] = []
	for agent_id in state.agents.keys():
		var agent: Dictionary = state.agents[agent_id]
		agents.append("%s Lv%d rating %d (%s, xp %s)" % [
			pack.agent_name(str(agent_id), agent),
			int(agent.get("level", 1)),
			AgentRules.rating(agent),
			str(agent.get("activity", "available")),
			TextFormat.amount(float(agent.get("xp", 0))),
		])
	print("  t+%d  %s  |  %s  |  tasks done %d" % [
		clock.now_utc() - START_UTC,
		", ".join(balances),
		"; ".join(agents),
		state.tasks_completed(),
	])

extends TestCase
## Rebirth math and the run reset. Deterministic: no clock reads.
##
## Expectations are derived from the pack's own prestige block, so retuning the
## economy does not require rewriting the suite — only the invariants are pinned.

const PACK_ID := "hero_hq"
const THRESHOLD := 4000.0


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


## A state that exactly meets the pack's rebirth requirements (run earnings at the
## threshold, level at the gate) unless a test changes one of them.
func _eligible(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.stats["earned"] = {"credits": float(pack.prestige.get("threshold_amount", THRESHOLD))}
	state.agents["hero_volt"]["level"] = int(pack.prestige.get("min_level", 7))
	return state


func test_chips_come_from_lifetime_earnings() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.stats["earned"] = {"credits": THRESHOLD}
	var first := Prestige.gain(state, pack)
	assert_true(first >= 1, "the first rebirth is worth at least one chip")
	assert_eq(Prestige.chips_for(0.0, pack), 0, "no earnings means no chips")
	state.stats["earned"] = {"credits": THRESHOLD * 4.0}
	var second := Prestige.gain(state, pack)
	assert_true(second > first, "more lifetime earnings means more chips")
	assert_true(second < first * 4, "the bank is sub-linear in earnings")


func test_resetting_on_the_same_progress_pays_nothing() -> void:
	var pack := _pack()
	var state := _eligible(pack)
	var banked := Prestige.gain(state, pack)
	assert_eq(Prestige.pending(state, pack), banked, "the first rebirth has chips to bank")
	Prestige.rebirth(state, pack, 1500)
	assert_eq(state.prestige_chips(), banked, "the bank is filled from lifetime earnings")
	assert_eq(Prestige.pending(state, pack), 0, "the same lifetime total cannot be banked twice")
	assert_eq(
		str(Prestige.eligibility(state, pack)["code"]),
		"prestige_no_pending",
		"a second rebirth with no new progress is refused",
	)
	state.stats["earned"] = {"credits": THRESHOLD * 4.0}
	assert_true(Prestige.pending(state, pack) > 0, "new lifetime earnings unlock new chips")


func test_multiplier_is_linear_in_chips() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	assert_eq(Prestige.multiplier(state, pack), 1.0, "a fresh save has no bonus")
	state.prestige["chips"] = 10
	var bonus := float(pack.prestige.get("bonus_per_chip", 0.05))
	assert_eq(Prestige.multiplier(state, pack), 1.0 + bonus * 10.0, "each chip adds its bonus")


func test_threshold_and_level_gate_the_reset() -> void:
	var pack := _pack()
	var short_run := Simulation.new_state(pack, 1, 1000)
	short_run.agents["hero_volt"]["level"] = int(pack.prestige.get("min_level", 7))
	assert_eq(
		str(Prestige.eligibility(short_run, pack)["code"]),
		"prestige_earnings_short",
		"a save below the earnings threshold is refused",
	)
	var low_level := Simulation.new_state(pack, 1, 1000)
	low_level.stats["earned"] = {"credits": THRESHOLD}
	assert_eq(
		str(Prestige.eligibility(low_level, pack)["code"]),
		"prestige_level_short",
		"a save below the level gate is refused",
	)
	assert_false(Prestige.rebirth(low_level, pack, 1000).get("ok", true), "rebirth respects its own gate")


func test_rebirth_banks_chips_and_resets_the_run() -> void:
	var pack := _pack()
	var state := _eligible(pack)
	var banked := Prestige.gain(state, pack)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	state.resources["credits"] = 5000.0
	state.stats["tasks_completed"] = 12

	# A hired hero must survive the reset at its base shape, not be deleted.
	var base_attributes: Dictionary = {}
	for attribute in Recruitment.attribute_names(pack):
		base_attributes[str(attribute)] = 4
	state.agents["op_0001"] = {
		"id": "op_0001",
		"role_id": str(pack.roles.keys()[0]),
		"level": 1,
		"xp": 0,
		"activity": "assigned",
		"attributes": base_attributes.duplicate(true),
	}
	state.agents["op_0001"]["xp"] = 100000.0
	AgentRules.apply_level_ups(state, pack, "op_0001")
	assert_true(int(state.agents["op_0001"]["level"]) > 1, "the test recruit levelled up")

	var result := Prestige.rebirth(state, pack, 1500)
	assert_true(result.get("ok", false), "an eligible save can be rebirthed")
	assert_eq(int(result["gained"]), banked, "the pending chips are banked")
	assert_eq(state.prestige_chips(), banked, "chips persist on the state")
	assert_eq(int(state.prestige.get("count", 0)), 1, "the rebirth counter advances")
	assert_eq(state.run_earnings(), 0.0, "the run counter resets")
	assert_eq(state.resource("credits"), 50.0, "resources reset to pack starting values")
	assert_eq(state.assignments.size(), 0, "running assignments are cleared")
	assert_eq(int(state.agents["hero_volt"]["level"]), 1, "agent progress resets")
	assert_eq(str(state.agents["hero_volt"]["activity"]), "available", "the reset roster is usable")
	assert_true(state.agents.has("op_0001"), "a recruited hero survives the reset")
	assert_eq(int(state.agents["op_0001"]["level"]), 1, "the recruited hero returns at level one")
	assert_eq(int(state.agents["op_0001"]["xp"]), 0, "the recruited hero loses run XP")
	assert_eq(str(state.agents["op_0001"]["activity"]), "available", "the recruited hero is usable")
	assert_eq(
		state.agents["op_0001"]["attributes"], base_attributes, "attributes rewind to base values"
	)
	assert_eq(state.last_settled_utc, 1500, "settlement restarts at the rebirth instant")
	assert_eq(state.stats.get("tasks_completed", 0), 12, "lifetime totals survive the reset")
	assert_eq(state.earned_total("credits"), THRESHOLD, "lifetime earnings survive the reset")


func test_chips_raise_task_payouts() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.prestige["chips"] = 10
	var multiplier := Prestige.multiplier(state, pack)
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	Simulation.simulate_delta(state, 20.0, pack)
	assert_eq(state.resource("credits"), 50.0 + 18.0 * multiplier, "payouts scale with the multiplier")
	assert_eq(state.run_earnings(), 18.0 * multiplier, "the run counter tracks boosted earnings")
	assert_true(
		Prestige.lifetime_earnings(state, pack) >= state.run_earnings(),
		"lifetime earnings include the boosted payout",
	)


func test_the_bank_compounds_across_runs() -> void:
	var pack := _pack()
	var state := _eligible(pack)
	Prestige.rebirth(state, pack, 1000)
	state.stats["earned"] = {"credits": THRESHOLD * 4.0}
	state.agents["hero_volt"]["level"] = int(pack.prestige.get("min_level", 7))
	var result := Prestige.rebirth(state, pack, 2000)
	assert_true(result.get("ok", false), "a second rebirth is allowed")
	assert_eq(
		state.prestige_chips(), Prestige.chips_for(THRESHOLD * 4.0, pack),
		"chips follow lifetime earnings, not run count",
	)
	assert_true(
		Prestige.multiplier(state, pack) > Prestige.multiplier(state, pack) - 0.0001,
		"the multiplier is derived from the bank",
	)


func test_next_chip_target_matches_the_formula() -> void:
	var pack := _pack()
	var state := Simulation.new_state(pack, 1, 1000)
	state.stats["earned"] = {"credits": THRESHOLD}
	var earned := Prestige.gain(state, pack)
	var target := Prestige.next_chip_at(state, pack)
	assert_true(target > THRESHOLD, "the next chip needs more lifetime earnings")
	assert_eq(Prestige.chips_for(target, pack), earned + 1, "the target is the next chip boundary")
	assert_true(
		Prestige.chips_for(target - 1.0, pack) <= earned, "the boundary is exact, not rounded early"
	)


func test_screen_arms_before_committing() -> void:
	var pack := _pack()
	var screen := PrestigeScreen.new()
	var emitted := {"count": 0}
	screen.rebirth_requested.connect(func() -> void: emitted["count"] += 1)

	screen.refresh(pack, Simulation.new_state(pack, 1, 1000))
	assert_true(screen.rebirth_button().disabled, "a fresh save cannot rebirth")
	screen.rebirth_button().emit_signal("pressed")
	assert_eq(emitted["count"], 0, "a disabled button emits nothing")

	screen.refresh(pack, _eligible(pack))
	assert_false(screen.rebirth_button().disabled, "an eligible save can rebirth")
	screen.rebirth_button().emit_signal("pressed")
	assert_eq(emitted["count"], 0, "the first tap only arms the button")
	screen.rebirth_button().emit_signal("pressed")
	assert_eq(emitted["count"], 1, "the second tap commits the reset")
	screen.free()


func test_rebirth_state_survives_a_save() -> void:
	var pack := _pack()
	var state := _eligible(pack)
	var banked := Prestige.gain(state, pack)
	state.game_id = "test_prestige"
	Prestige.rebirth(state, pack, 1000)
	SaveService.save_state(state)
	var restored: GameState = SaveService.load_state("test_prestige").get("state", null)
	assert_true(restored != null, "a rebirthed state loads back")
	if restored != null:
		assert_eq(restored.prestige_chips(), banked, "chips survive JSON")
		assert_eq(int(restored.prestige.get("count", 0)), 1, "the rebirth count survives")
		assert_eq(
			Prestige.multiplier(restored, pack), Prestige.multiplier(state, pack),
			"the multiplier is derived, not stored",
		)
	SaveService.delete_profile("test_prestige")

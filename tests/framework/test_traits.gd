extends TestCase
## Hero traits: pack loading, deterministic assignment, UI labels and modifiers.

const PACK_ID := "hero_hq"


func _pack() -> GamePack:
	return without_stage_gates(GamePackLoader.load_pack(PACK_ID)["pack"])


func _state(pack: GamePack) -> GameState:
	return Simulation.new_state(pack, 1, 1000)


func _agent(agent_id: String, role_id: String) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": 40, "speed": 40, "skill": 40},
	}


func test_pack_declares_ten_traits_and_the_starter_trait() -> void:
	var pack := _pack()
	assert_eq(pack.traits.size(), 10, "the pack declares the ten launch traits")
	assert_eq(pack.trait_ids().size(), 10, "trait ids are unique")
	var starter: Dictionary = pack.starter_agents["hero_volt"]
	assert_eq(str(starter.get("trait_id", "")), "tactical_mind", "Volt starts with Tactical Mind")
	assert_eq(TraitRules.display_name(pack, starter), "Tactical Mind", "the trait label resolves")
	assert_eq(
		TraitRules.description(pack, starter),
		"+8% rating on squad operations.",
		"the trait description resolves",
	)


func test_candidate_traits_are_deterministic_and_declared() -> void:
	var pack := _pack()
	var first := Recruitment.candidate(pack, 42)
	var again := Recruitment.candidate(pack, 42)
	assert_eq(str(first["trait_id"]), str(again["trait_id"]), "a slot keeps its trait")
	assert_true(pack.traits.has(str(first["trait_id"])), "the candidate trait is declared")
	var seen: Dictionary = {}
	for index in range(24):
		var candidate := Recruitment.candidate(pack, index)
		seen[str(candidate["trait_id"])] = true
	assert_true(seen.size() > 1, "the pool does not give every recruit the same trait")


func test_hired_offer_keeps_the_trait_shown_on_its_card() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.resources["credits"] = 1000000.0
	var chosen: Dictionary = Recruitment.offers(state, pack)[0]
	var trait_id := str(chosen.get("trait_id", ""))
	assert_true(pack.traits.has(trait_id), "the visible offer carries a declared trait")
	var result := Recruitment.recruit_offer(state, pack, str(chosen["id"]))
	assert_true(result.get("ok", false), "the visible offer can be hired")
	assert_eq(str(result.get("trait_id", "")), trait_id, "the hire reports the visible trait")
	assert_eq(
		str(state.agents[str(chosen["id"])].get("trait_id", "")),
		trait_id,
		"the roster stores the visible trait",
	)


func test_roster_and_offer_cards_show_trait_name_and_effect() -> void:
	var pack := _pack()
	var state := _state(pack)
	var roster := RosterScreen.new()
	roster.refresh(pack, state)
	var agent_trait := roster.find_child("AgentTrait_hero_volt", true, false) as Label
	assert_true(agent_trait != null, "the roster row shows the starter trait")
	if agent_trait != null:
		assert_true(agent_trait.text.contains("Tactical Mind"), "the row names the trait")
		assert_true(agent_trait.text.contains("squad operations"), "the row explains the effect")
	var offer: Dictionary = Recruitment.offers(state, pack)[0]
	var offer_trait := roster.find_child(
		"OfferTrait_%s" % str(offer["id"]), true, false
	) as Label
	assert_true(offer_trait != null, "the offer card shows its trait")
	if offer_trait != null:
		assert_true(
			offer_trait.text.contains(TraitRules.display_name(pack, offer)),
			"the offer card names its trait",
		)
	roster.free()


func test_quick_learner_boosts_training_xp() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.resources["credits"] = 200.0
	state.agents["hero_volt"]["trait_id"] = "quick_learner"
	var result := Simulation.train_agent(state, pack, "hero_volt")
	assert_true(result.get("ok", false), "training succeeds")
	assert_true(
		abs(float(state.agents["hero_volt"]["xp"]) - 46.0) < 0.001,
		"40 base XP becomes 46 with Quick Learner",
	)


func test_sprinter_shortens_solo_work_only() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.agents["hero_volt"]["trait_id"] = "sprinter"
	var solo := Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	assert_true(solo.get("ok", false), "the solo task starts")
	assert_eq(int(solo.get("ends_utc", 0)), 1018, "20 seconds becomes 18")

	var squad_state := _state(pack)
	squad_state.agents["hero_volt"]["trait_id"] = "sprinter"
	squad_state.agents["test_support"] = _agent("test_support", "support")
	var squad := Simulation.assign_task(
		squad_state, pack, "s_raid", ["hero_volt", "test_support"], 2000
	)
	assert_true(squad.get("ok", false), "the squad task starts")
	assert_eq(int(squad.get("ends_utc", 0)), 2100, "solo speed does not shorten a squad")


func test_credit_and_intel_traits_change_the_visible_payout() -> void:
	var pack := _pack()
	var crowd := _state(pack)
	crowd.agents["hero_volt"]["trait_id"] = "crowd_favorite"
	Simulation.assign_task(crowd, pack, "s_alley", ["hero_volt"], 1000)
	Simulation.simulate_delta(crowd, 20.0, pack)
	assert_true(
		abs(crowd.resource("credits") - 69.8) < 0.001,
		"18 Credits become 19.8 with Crowd Favorite",
	)

	var investigator := _state(pack)
	investigator.agents["hero_volt"]["trait_id"] = "investigator"
	investigator.agents["hero_volt"]["attributes"]["power"] = 10
	Simulation.assign_task(investigator, pack, "s_breakin", ["hero_volt"], 1000)
	Simulation.simulate_delta(investigator, 30.0, pack)
	assert_true(
		abs(investigator.resource("credits") - 95.0) < 0.001,
		"the base Credits still pay",
	)
	assert_true(
		abs(investigator.resource("intel") - 2.2) < 0.001,
		"2 Intel becomes 2.2 with Investigator",
	)


func test_auto_selection_uses_trait_adjusted_rating() -> void:
	var pack := _pack()
	var state := _state(pack)
	# The high-base Support misses the rescue gate; the lower-base Support with
	# Unbreakable clears it. Base-rating ordering would pick the first hero.
	var high := _agent("test_high_support", "support")
	high["attributes"] = {"power": 8, "speed": 8, "skill": 8}
	state.agents["test_high_support"] = high
	var unbreakable := _agent("test_unbreakable_support", "support")
	unbreakable["attributes"] = {"power": 8, "speed": 8, "skill": 7}
	unbreakable["trait_id"] = "unbreakable"
	state.agents["test_unbreakable_support"] = unbreakable
	assert_eq(AgentRules.rating(high), 120, "the high-base Support rates 120 before traits")
	assert_eq(AgentRules.rating(unbreakable), 115, "the trait Support rates 115 before traits")
	assert_true(
		TraitRules.rating_value(pack, unbreakable, pack.task("s_medivac")) >= 125.0,
		"Unbreakable clears the rescue gate",
	)

	var selected := Simulation.auto_select_agents(state, pack, "s_medivac")
	assert_eq(selected.size(), 1, "the rescue operation selects one Support")
	if selected.size() == 1:
		assert_eq(
			str(selected[0]),
			"test_unbreakable_support",
			"auto-selection ranks the trait-adjusted rating",
		)
	var deployed := Simulation.deploy(state, pack, "s_medivac", 1000)
	assert_true(deployed.get("ok", false), "the trait-adjusted lineup deploys")
	var assignment_id := str(deployed.get("assignment_id", ""))
	assert_true(state.assignments.has(assignment_id), "the deployment is scheduled")
	if state.assignments.has(assignment_id):
		assert_eq(
			state.assignments[assignment_id].get("agent_ids", []),
			["test_unbreakable_support"],
			"the automatic lineup keeps the trait-adjusted Support",
		)


func test_tactical_mind_raises_squad_rating_only() -> void:
	var pack := _pack()
	var starter: Dictionary = _state(pack).agents["hero_volt"]
	var base := AgentRules.rating_value(starter)
	var squad_rating := TraitRules.rating_value(pack, starter, pack.task("s_raid"))
	var solo_rating := TraitRules.rating_value(pack, starter, pack.task("s_alley"))
	assert_true(squad_rating > base, "Tactical Mind raises the squad deployment rating")
	assert_true(
		is_equal_approx(solo_rating, base),
		"the squad trait does not change a solo deployment",
	)


func test_efficient_pays_only_on_automatic_work() -> void:
	var pack := _pack()
	var manual := _state(pack)
	manual.agents["hero_volt"]["trait_id"] = "efficient"
	Simulation.assign_task(manual, pack, "s_alley", ["hero_volt"], 1000)
	Simulation.simulate_delta(manual, 20.0, pack)
	assert_true(
		abs(manual.resource("credits") - 68.0) < 0.001,
		"manual work keeps the base 18 Credits",
	)

	var automatic := _state(pack)
	automatic.agents["hero_volt"]["trait_id"] = "efficient"
	Simulation.assign_task(automatic, pack, "s_alley", ["hero_volt"], 1000, true)
	Simulation.simulate_delta(automatic, 20.0, pack)
	assert_true(
		abs(automatic.resource("credits") - 69.44) < 0.001,
		"automatic work gains 8% with Efficient",
	)


func test_saved_agents_get_a_stable_backfilled_trait() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.agents["legacy_agent"] = _agent("legacy_agent", "tech")
	state.agents["legacy_agent"].erase("trait_id")
	assert_eq(TraitRules.backfill_agents(state, pack), 1, "one legacy agent is filled")
	var filled := str(state.agents["legacy_agent"].get("trait_id", ""))
	assert_true(pack.traits.has(filled), "the backfilled trait is declared")
	assert_eq(TraitRules.backfill_agents(state, pack), 0, "a second backfill is a no-op")
	assert_eq(str(state.agents["legacy_agent"]["trait_id"]), filled, "the trait stays stable")

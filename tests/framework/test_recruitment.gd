extends TestCase
## Recruit pool: deterministic slots, named breadth, reserves, purchase limits.

const PACK_ID := "hero_hq"
const CommandProgression = preload("res://framework/core/command_progression.gd")


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.resources["credits"] = 1000000.0
	return state


func test_pool_declares_two_hundred_named_recruits() -> void:
	var pack := _pack()
	assert_true(Recruitment.enabled(pack), "the pack declares a recruit pool")
	assert_eq(Recruitment.named_count(pack), 200, "two hundred named slots")
	assert_true(Recruitment.capacity(pack) >= 200, "the roster can hold the named pool")
	assert_true(bool(Recruitment.candidate(pack, 0).get("named", false)), "slot one is named")
	assert_true(bool(Recruitment.candidate(pack, 199).get("named", false)), "slot 200 is named")
	assert_false(bool(Recruitment.candidate(pack, 200).get("named", true)), "slot 201 is a reserve")


func test_named_slots_have_unique_names() -> void:
	var pack := _pack()
	var seen: Dictionary = {}
	for index in range(200):
		seen[str(Recruitment.candidate(pack, index)["name"])] = true
	assert_eq(seen.size(), 200, "every named slot has a distinct name")


func test_slot_identity_is_deterministic() -> void:
	var pack := _pack()
	var first := Recruitment.candidate(pack, 42)
	var again := Recruitment.candidate(pack, 42)
	assert_eq(str(first["name"]), str(again["name"]), "the name is stable")
	assert_eq(str(first["id"]), str(again["id"]), "the id is stable")
	assert_eq(int(first["rating"]), int(again["rating"]), "the rating is stable")
	assert_true(str(first["name"]) != str(Recruitment.candidate(pack, 43)["name"]), "slots differ")


func test_candidates_use_declared_roles_and_tiers() -> void:
	var pack := _pack()
	var tier_ids: Array = []
	for raw in Recruitment.tier_rules(pack):
		tier_ids.append(str((raw as Dictionary).get("id", "")))
	for index in range(24):
		var rules := Recruitment.candidate(pack, index)
		assert_true(pack.roles.has(str(rules["role_id"])), "the role is declared")
		assert_true(tier_ids.has(str(rules["tier_id"])), "the tier is declared")
		assert_true(int(rules["rating"]) > 0, "the rating is positive")


func test_recruit_spends_and_adds_to_the_roster() -> void:
	var pack := _pack()
	var state := _state(pack)
	var before := state.resource("credits")
	var offer := Recruitment.next_candidate(state, pack)
	var result := Recruitment.recruit(state, pack)
	assert_true(result.get("ok", false), "a funded recruit succeeds")
	assert_eq(state.agents.size(), 2, "the roster grows by one")
	assert_eq(state.resource("credits"), before - float(offer["cost"]), "the price is spent")
	assert_eq(str(state.agents[str(result["agent_id"])]["name"]), str(result["name"]), "the name is stored")
	assert_eq(Recruitment.next_index(state), 1, "the pool advances one slot")


func test_recruit_is_refused_without_funds() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.resources["credits"] = 0.0
	assert_eq(
		str(Recruitment.recruit(state, pack).get("code", "")),
		"insufficient_resource",
		"an empty bank cannot recruit",
	)


func test_recruit_is_refused_when_the_roster_is_full() -> void:
	var pack := _pack()
	pack.roster_capacity = 1
	var state := _state(pack)
	assert_eq(
		str(Recruitment.recruit(state, pack).get("code", "")),
		"roster_full",
		"a full roster cannot recruit",
	)


func test_reserves_are_numbered_beyond_the_named_pool() -> void:
	var pack := _pack()
	var first := str(Recruitment.candidate(pack, 200)["name"])
	var later := str(Recruitment.candidate(pack, 245)["name"])
	assert_true(first.contains("201"), "the first reserve is numbered 201")
	assert_true(later.contains("246"), "later reserves keep counting")
	assert_eq(str(Recruitment.candidate(pack, 200)["id"]), "op_0201", "reserve ids keep counting")


func test_role_targeting_recruits_the_next_matching_slot() -> void:
	var pack := _pack()
	var state := _state(pack)
	var preview := Recruitment.next_candidate_for_role(state, pack, "tech")
	assert_false(preview.is_empty(), "a tech slot exists in the pool")
	var result := Recruitment.recruit(state, pack, "tech")
	assert_true(result.get("ok", false), "a role-targeted recruit succeeds")
	assert_eq(
		str(state.agents[str(result["agent_id"])].get("role_id", "")),
		"tech",
		"the recruit has the requested role",
	)
	assert_eq(str(result["agent_id"]), str(preview["id"]), "the preview matches the recruit")
	assert_eq(int(result["cost"]), int(preview["cost"]), "the preview price matches")


func test_every_declared_role_can_be_targeted() -> void:
	var pack := _pack()
	for raw_role in pack.roles.keys():
		var state := _state(pack)
		var role_id := str(raw_role)
		assert_false(
			Recruitment.next_candidate_for_role(state, pack, role_id).is_empty(),
			"role '%s' is reachable in the pool" % role_id,
		)
	assert_eq(
		str(Recruitment.recruit(_state(pack), pack, "not_a_role").get("code", "")),
		Recruitment.ERROR_ROLE_UNAVAILABLE,
		"an unknown role is refused",
	)


func test_pool_is_optional() -> void:
	var pack := _pack()
	pack.recruit_pool = {}
	assert_false(Recruitment.enabled(pack), "a pack without a pool disables recruitment")
	assert_eq(
		str(Recruitment.recruit(_state(pack), pack).get("code", "")),
		"recruitment_unavailable",
		"recruitment reports unavailability",
	)


func test_offer_pair_is_persistent_distinct_and_precise() -> void:
	var pack := _pack()
	var state := _state(pack)
	var offers := Recruitment.offers(state, pack)
	assert_eq(offers.size(), 2, "the player sees exactly two offers")
	var ids: Array = []
	var roles: Array = []
	for raw_offer in offers:
		var offer: Dictionary = raw_offer
		ids.append(str(offer.get("id", "")))
		roles.append(str(offer.get("role_id", "")))
		assert_true(str(offer.get("name", "")) != "", "the offer has a name")
		assert_true(int(offer.get("rating", 0)) > 0, "the offer has a rating")
		assert_true(not str(offer.get("tier_id", "")).is_empty(), "the offer names its tier")
		assert_true((offer.get("attributes", {}) as Dictionary).size() >= 3, "the offer shows attributes")
		assert_true(int(offer.get("cost", 0)) > 0, "the offer has a real price")
		var slot_rules := Recruitment.candidate(pack, int(offer["slot"]))
		assert_eq(str(slot_rules.get("id", "")), str(offer["id"]), "the offer comes from its deterministic slot")
		assert_eq(int(offer["cost"]), Recruitment.cost(state, pack, int(offer["slot"])), "the offer price matches its deterministic slot")
	assert_eq(ids.size(), 2, "both offers have ids")
	assert_true(ids[0] != ids[1], "the two offers are different people")
	assert_true(roles[0] != roles[1], "the two offers have different roles")
	assert_false(_offer_dominates(offers[0], offers[1]), "the first offer is not a strictly better deal")
	assert_false(_offer_dominates(offers[1], offers[0]), "the second offer is not a strictly better deal")
	var credits := state.resource("credits")
	var again := Recruitment.offers(state, pack)
	assert_eq(str(again[0]["id"]), str(offers[0]["id"]), "reading offers does not reroll the pair")
	assert_eq(str(again[1]["id"]), str(offers[1]["id"]), "the second offer is stable too")
	assert_eq(state.resource("credits"), credits, "merely showing offers is free")


func test_offer_pair_covers_tech_support_and_squad_roles() -> void:
	var pack := _pack()
	var fresh := _state(pack)
	var fresh_roles: Array = []
	for raw_offer in Recruitment.offers(fresh, pack):
		fresh_roles.append(str((raw_offer as Dictionary)["role_id"]))
	assert_true(fresh_roles.has("tech"), "a fresh pair includes the City Tech gate role")
	assert_true(fresh_roles.has("support"), "a fresh pair includes the City Support gate role")
	assert_true(fresh_roles.has("tech") or fresh_roles.has("support"), "either role satisfies the command gate")

	var state := _state(pack)
	state.agents["test_tech"] = _agent("test_tech", "tech")
	var city_roles: Array = []
	for raw_offer in Recruitment.offers(state, pack):
		city_roles.append(str((raw_offer as Dictionary)["role_id"]))
	assert_true(city_roles.has("support"), "a Tech-only roster is offered the missing squad Support")


func test_buying_an_offer_spends_exactly_and_refreshes_once() -> void:
	var pack := _pack()
	var state := _state(pack)
	var before := Recruitment.offers(state, pack)
	var chosen: Dictionary = before[0]
	var credits := state.resource("credits")
	var result := Recruitment.recruit_offer(state, pack, str(chosen["id"]))
	assert_true(result.get("ok", false), "a funded visible offer can be hired")
	assert_eq(state.resource("credits"), credits - float(chosen["cost"]), "only the displayed price is spent")
	assert_true(state.agents.has(str(chosen["id"])), "the chosen hero joins the roster")
	assert_eq(Recruitment.next_index(state), int(chosen["slot"]) + 1, "the pair advances past the hired slot")
	var after := Recruitment.offers(state, pack)
	assert_eq(after.size(), 2, "a fresh pair replaces the hired one")
	assert_true(str(after[0]["id"]) != str(chosen["id"]), "the hired offer is gone")
	assert_true(str(after[1]["id"]) != str(chosen["id"]), "the hired offer does not survive in the second slot")
	assert_eq(state.resource("credits"), credits - float(chosen["cost"]), "the refresh itself costs nothing")


func test_unlisted_offer_is_refused_without_reroll_or_charge() -> void:
	var pack := _pack()
	var state := _state(pack)
	var before := Recruitment.offers(state, pack)
	var credits := state.resource("credits")
	var next_index := Recruitment.next_index(state)
	var result := Recruitment.recruit_offer(state, pack, "op_9999")
	assert_false(result.get("ok", false), "an offer not on screen is refused")
	assert_eq(str(result.get("code", "")), Recruitment.ERROR_OFFER_UNAVAILABLE, "the refusal names the stale offer")
	assert_eq(state.resource("credits"), credits, "a stale offer spends nothing")
	assert_eq(Recruitment.next_index(state), next_index, "a stale offer does not advance the pool")
	var after := Recruitment.offers(state, pack)
	assert_eq(str(after[0]["id"]), str(before[0]["id"]), "a refused hire leaves the pair intact")
	assert_eq(str(after[1]["id"]), str(before[1]["id"]), "both offers remain visible")


func test_offer_pair_survives_save_and_reload() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.game_id = "test_recruit_offers"
	var ids: Array = []
	for raw_offer in Recruitment.offers(state, pack):
		ids.append(str((raw_offer as Dictionary)["id"]))
	var saved := SaveService.save_state(state)
	assert_eq(str(saved.get("error", "")), "", "the offer fixture saves")
	var loaded := SaveService.load_state(state.game_id)
	assert_true(loaded.get("state", null) != null, "the offer fixture reloads")
	var restored: GameState = loaded["state"]
	var restored_ids: Array = []
	for raw_offer in Recruitment.offers(restored, pack):
		restored_ids.append(str((raw_offer as Dictionary)["id"]))
	assert_eq(restored_ids, ids, "the same two offers are visible after reload")
	assert_eq(int(restored.extensions["recruitment"].get("offer_level", -1)), CommandProgression.current_level(restored, pack), "the offer level persists")
	SaveService.delete_profile(state.game_id)


func test_offer_pair_refreshes_free_on_command_level_increase() -> void:
	var pack := _pack()
	var state := _state(pack)
	assert_eq(CommandProgression.current_level(state, pack), 1, "the fixture starts at Command Level 1")
	var before := Recruitment.offers(state, pack)
	var before_ids: Array = []
	var last_slot := -1
	for raw_offer in before:
		var offer: Dictionary = raw_offer
		before_ids.append(str(offer["id"]))
		last_slot = maxi(last_slot, int(offer["slot"]))
	var credits := state.resource("credits")
	state.stats["tasks_completed"] = 6
	state.stats["earned"] = {"credits": 500.0}
	state.agents["test_tech"] = _agent("test_tech", "tech")
	state.agents["test_support"] = _agent("test_support", "support")
	assert_eq(CommandProgression.current_level(state, pack), 2, "the fixture reaches Command Level 2")
	var after := Recruitment.offers(state, pack)
	assert_eq(after.size(), 2, "the free progression refresh still shows two offers")
	var after_ids: Array = []
	for raw_offer in after:
		after_ids.append(str((raw_offer as Dictionary)["id"]))
	assert_true(after_ids[0] != before_ids[0] and after_ids[1] != before_ids[1], "the level-up pair is replaced")
	assert_eq(state.resource("credits"), credits, "the level-up refresh costs nothing")
	assert_true(Recruitment.next_index(state) > last_slot, "the consumed pair is not offered again")


func test_old_save_without_offers_derives_from_next_index() -> void:
	var pack := _pack()
	var state := _state(pack)
	state.extensions["recruitment"] = {"next_index": 37}
	var offers := Recruitment.offers(state, pack)
	assert_eq(offers.size(), 2, "an old save still gets two visible offers")
	assert_eq(Recruitment.next_index(state), 37, "the existing recruit cursor is preserved")
	for raw_offer in offers:
		assert_true(int((raw_offer as Dictionary).get("slot", -1)) >= 37, "old saves derive offers from their cursor")
	assert_true(state.extensions["recruitment"].has("offer_level"), "the derived pair records its progression level")


## Headline dominance is price and rating alone: the two cards show those before
## any roster-fit detail, and a same-price stronger card makes the other a trap.
func _offer_dominates(first: Dictionary, second: Dictionary) -> bool:
	var first_cost := int(first.get("cost", 0))
	var second_cost := int(second.get("cost", 0))
	var first_rating := int(first.get("rating", 0))
	var second_rating := int(second.get("rating", 0))
	return first_cost <= second_cost \
		and first_rating >= second_rating \
		and (first_cost < second_cost or first_rating > second_rating)


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

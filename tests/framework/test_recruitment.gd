extends TestCase
## Recruit pool: deterministic slots, named breadth, reserves, purchase limits.

const PACK_ID := "hero_hq"


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


func test_pool_is_optional() -> void:
	var pack := _pack()
	pack.recruit_pool = {}
	assert_false(Recruitment.enabled(pack), "a pack without a pool disables recruitment")
	assert_eq(
		str(Recruitment.recruit(_state(pack), pack).get("code", "")),
		"recruitment_unavailable",
		"recruitment reports unavailability",
	)

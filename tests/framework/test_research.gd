extends TestCase
## Research ranks: cost curve, purchase contract, effects and persistence.

const PACK_ID := "hero_hq"
const REWARD_BRANCH := "ops_reward"
const TRAINING_BRANCH := "ops_training"
const AUTOMATION_BRANCH := "ops_automation"


func _pack() -> GamePack:
	return GamePackLoader.load_pack(PACK_ID)["pack"]


func _state(pack: GamePack) -> GameState:
	var state := Simulation.new_state(pack, 1, 1000)
	state.resources["intel"] = 500.0
	return state


func test_each_rank_costs_more_until_maxed() -> void:
	var pack := _pack()
	var state := _state(pack)
	var first := Research.cost(state, pack, REWARD_BRANCH)
	assert_true(first > 0, "a fresh branch has a price")
	state.upgrades[REWARD_BRANCH] = 1
	var second := Research.cost(state, pack, REWARD_BRANCH)
	assert_true(second > first, "the next rank costs more")
	state.upgrades[REWARD_BRANCH] = Research.max_rank(pack, REWARD_BRANCH)
	assert_eq(Research.cost(state, pack, REWARD_BRANCH), -1, "a maxed branch has no price")


func test_buying_spends_the_declared_resource() -> void:
	var pack := _pack()
	var state := _state(pack)
	var before := state.resource("intel")
	var price := Research.cost(state, pack, REWARD_BRANCH)
	var result := Research.buy(state, pack, REWARD_BRANCH)
	assert_true(result.get("ok", false), "a funded purchase succeeds")
	assert_eq(Research.rank(state, REWARD_BRANCH), 1, "the rank rises")
	assert_eq(state.resource("intel"), before - float(price), "the resource is spent")
	assert_eq(int(result["cost"]), price, "the receipt reports the price")


func test_unfunded_and_maxed_purchases_are_refused() -> void:
	var pack := _pack()
	var poor := Simulation.new_state(pack, 1, 1000)
	assert_eq(
		str(Research.buy(poor, pack, REWARD_BRANCH).get("code", "")),
		"insufficient_resource",
		"an empty bank cannot buy research",
	)
	var state := _state(pack)
	state.upgrades[REWARD_BRANCH] = Research.max_rank(pack, REWARD_BRANCH)
	assert_eq(
		str(Research.buy(state, pack, REWARD_BRANCH).get("code", "")),
		"research_max_rank",
		"a maxed branch cannot be bought again",
	)


func test_reward_research_raises_payouts() -> void:
	var pack := _pack()
	var state := _state(pack)
	var before := Research.reward_multiplier(state, pack)
	assert_eq(before, 1.0, "no ranks means no bonus")
	state.upgrades[REWARD_BRANCH] = 1
	var after := Research.reward_multiplier(state, pack)
	assert_true(after > before, "a rank raises the payout multiplier")
	Simulation.assign_task(state, pack, "s_alley", ["hero_volt"], 1000)
	Simulation.simulate_delta(state, 20.0, pack)
	assert_true(
		state.resource("credits") > 50.0 + 18.0, "the payout is boosted above base"
	)


func test_training_research_lowers_cost() -> void:
	var pack := _pack()
	var state := _state(pack)
	var before := Simulation.training_cost(state, pack, "hero_volt")
	state.upgrades[TRAINING_BRANCH] = 1
	var after := Simulation.training_cost(state, pack, "hero_volt")
	assert_true(after < before, "the discount applies to the next session")
	assert_true(after >= 1, "training never becomes free")


func test_automation_unlocks_at_the_top_rank() -> void:
	var pack := _pack()
	var state := _state(pack)
	assert_false(
		Research.unlocked(state, pack, Research.EFFECT_AUTO_REPEAT),
		"automation starts locked",
	)
	Research.buy(state, pack, AUTOMATION_BRANCH)
	assert_true(
		Research.unlocked(state, pack, Research.EFFECT_AUTO_REPEAT),
		"buying the branch unlocks automation",
	)


func test_ranks_survive_a_rebirth() -> void:
	var pack := _pack()
	var state := _state(pack)
	Research.buy(state, pack, REWARD_BRANCH)
	var rank := Research.rank(state, REWARD_BRANCH)
	state.stats["earned"] = {"credits": float(pack.prestige.get("threshold_amount", 4000))}
	state.agents["hero_volt"]["level"] = int(pack.prestige.get("min_level", 7))
	assert_true(Prestige.rebirth(state, pack, 1500).get("ok", false), "the run can reset")
	assert_eq(Research.rank(state, REWARD_BRANCH), rank, "research is permanent")
	assert_eq(state.resource("intel"), 0.0, "the run's Intel is spent with the run")
	assert_true(
		Research.reward_multiplier(state, pack) > 1.0, "the effect survives the reset"
	)

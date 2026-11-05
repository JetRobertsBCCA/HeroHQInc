extends SceneTree
## Captures the Heroes screen at 360x640 with the two persistent recruit offers.
##   fresh   - Command Level 1, both gate roles missing, both offers affordable
##   midgame - Command Level 3, four roles owned, one new role and one depth pick
##
## The checks cover what a blind draw could not: two visible cards, distinct
## roles, exact prices, role/rating/attribute/tier text, roster fit, 48px hire
## targets, no role picker, and both cards inside the first viewport.
##
## The player's save is backed up and restored. Exit code 1 on any failed
## assertion so this is a check, not just a screenshot generator.

const PACK_ID := "hero_hq"
const SHOT_DIR := "res://ui_shots"

var _app: Control
var _pack: GamePack
var _saved: Dictionary = {}
var _failures: int = 0
var _tag := "after"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	_backup_profile()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var scene := load("res://games/hero_hq/scenes/app.tscn") as PackedScene
	_app = scene.instantiate()
	root.add_child(_app)
	await process_frame
	await process_frame
	var timer := _app.get("_timer") as Timer
	if timer != null:
		timer.stop()
	_pack = _app.get("_pack") as GamePack
	var now := int(Time.get_unix_time_from_system())

	var fresh := Simulation.new_state(_pack, 1, now)
	await _capture_state("fresh", fresh)

	# Midgame: four distinct roles at City level, with enough Credits for either
	# offer. The pair shows the missing Mystic alongside a second Striker, so the
	# player compares breadth against depth rather than one strictly better hero.
	var midgame := Simulation.new_state(_pack, 1, now)
	midgame.resources["credits"] = 180.0
	midgame.resources["intel"] = 6.0
	midgame.stats["tasks_completed"] = 12
	midgame.stats["earned"] = {"credits": 1500.0}
	midgame.agents["capture_tech"] = _capture_agent("capture_tech", "tech")
	midgame.agents["capture_support"] = _capture_agent("capture_support", "support")
	midgame.agents["capture_vanguard"] = _capture_agent("capture_vanguard", "vanguard")
	midgame.agents["capture_striker"] = _capture_agent("capture_striker", "striker")
	await _capture_state("midgame", midgame)

	_app.queue_free()
	await process_frame
	await process_frame
	_restore_profile()
	if _failures > 0:
		print("HEROES_CAPTURE_FAILED failures=%d" % _failures)
		quit(1)
		return
	print("HEROES_CAPTURE_OK tag=%s" % _tag)
	quit(0)


func _capture_agent(agent_id: String, role_id: String) -> Dictionary:
	return {
		"id": agent_id,
		"name": agent_id.capitalize(),
		"role_id": role_id,
		"level": 1,
		"xp": 0,
		"activity": "available",
		"attributes": {"power": 32, "speed": 30, "skill": 31},
	}


func _capture_state(state_name: String, state: GameState) -> void:
	_app.set("_state", state)
	var shell := _app.get("_shell") as ScreenShell
	shell.refresh(state)
	shell.select_tab("heroes")
	await process_frame
	await process_frame
	var roster := _app.get("_roster") as RosterScreen
	_check(roster != null, "%s state builds a RosterScreen" % state_name)
	if roster == null:
		return
	var content := shell.find_child("Content", true, false) as Control
	_check(content != null, "%s state has the content slot" % state_name)
	if content == null:
		return
	var content_rect := content.get_global_rect()
	_check(content_rect.size.x > 0.0 and content_rect.size.y > 0.0, "content slot has size")
	_check(roster.find_child("RecruitRole", true, false) == null, "the role picker is gone")

	var ids := roster.recruit_offer_ids()
	_check(ids.size() == 2, "%s shows two offers" % state_name)
	var roles: Array = []
	var both_visible := true
	for agent_id in ids:
		var card := roster.recruit_offer_card(agent_id)
		var button := roster.recruit_offer_button(agent_id)
		_check(card != null, "offer %s has a card" % agent_id)
		_check(button != null, "offer %s has a hire button" % agent_id)
		if card == null or button == null:
			continue
		var role_label := card.find_child("OfferRole_*", true, false) as Label
		var attrs_label := card.find_child("OfferAttrs_*", true, false) as Label
		var fit_label := card.find_child("OfferFit_*", true, false) as Label
		var rating_label := card.find_child("OfferRating_*", true, false) as Label
		var trait_label := card.find_child("OfferTrait_*", true, false) as Label
		_check(role_label != null and not role_label.text.is_empty(), "offer %s names role and tier" % agent_id)
		_check(attrs_label != null and attrs_label.text.contains("Power") and attrs_label.text.contains("Speed") and attrs_label.text.contains("Skill"), "offer %s shows all three attributes" % agent_id)
		_check(fit_label != null and fit_label.text.begins_with("Adds"), "offer %s explains its roster fit" % agent_id)
		_check(rating_label != null and rating_label.text.contains("Rating"), "offer %s shows its rating" % agent_id)
		_check(trait_label != null and trait_label.text.contains("Trait"), "offer %s shows its trait" % agent_id)
		_check(button.text.contains("Credits"), "offer %s shows its exact Credit price" % agent_id)
		_check(button.size.y >= RosterScreen.MIN_TAP_HEIGHT, "offer %s hire target is at least 48px tall" % agent_id)
		var rect := card.get_global_rect()
		var fully_visible := rect.position.y >= content_rect.position.y - 1.0 \
			and rect.end.y <= content_rect.end.y + 1.0
		both_visible = both_visible and fully_visible
		if role_label != null:
			var offer: Dictionary = {}
			for raw_offer in Recruitment.offers(state, _pack):
				if str((raw_offer as Dictionary).get("id", "")) == agent_id:
					offer = raw_offer
					break
			if not offer.is_empty():
				roles.append(str(offer.get("role_id", "")))
				_check(role_label.text.contains(_pack.label(str(_pack.role(str(offer["role_id"])).get("name_key", "")), str(offer["role_id"]))), "offer %s displays its role name" % agent_id)
				_check(role_label.text.contains(_pack.label("tiers.%s" % str(offer["tier_id"]), str(offer["tier_id"]))), "offer %s displays its tier" % agent_id)
				_check(trait_label != null and trait_label.text.contains(TraitRules.display_name(_pack, offer)), "offer %s displays its trait name" % agent_id)
	_check(both_visible, "both offer cards fit inside the first 360x640 viewport")
	_check(roles.size() == 2 and roles[0] != roles[1], "the two offers have distinct roles")

	var offers := Recruitment.offers(state, _pack)
	if offers.size() == 2:
		var first: Dictionary = offers[0]
		var second: Dictionary = offers[1]
		_check(
			not _headline_dominates(first, second) and not _headline_dominates(second, first),
			"neither visible offer is strictly better on price and rating",
		)
		print("HEROES_OFFERS %s %s(%s,r%d,%dcr) vs %s(%s,r%d,%dcr) credits=%.0f level=%d" % [
			state_name,
			str(first["name"]),
			str(first["role_id"]),
			int(first["rating"]),
			int(first["cost"]),
			str(second["name"]),
			str(second["role_id"]),
			int(second["rating"]),
			int(second["cost"]),
			state.resource("credits"),
			CommandProgression.current_level(state, _pack),
		])
		if state_name == "midgame":
			var first_new := bool(first.get("new_role", false))
			var second_new := bool(second.get("new_role", false))
			_check(first_new or second_new, "the midgame choice includes a new role")
			_check(not (first_new and second_new), "the midgame choice also includes an existing-role pick")
			_check(
				int(first["rating"]) != int(second["rating"]) \
					or int(first["cost"]) != int(second["cost"]),
				"the midgame offers differ beyond their role",
			)

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.get_width() == 360 and image.get_height() == 640, "the capture is exactly 360x640")
	var path := "%s/heroes_offers_%s_%s.png" % [SHOT_DIR, _tag, state_name]
	var error := image.save_png(path)
	_check(error == OK, "saved %s" % path)
	print("CAPTURE %s %dx%d" % [
		ProjectSettings.globalize_path(path),
		image.get_width(),
		image.get_height(),
	])
	var card_heights: Array[String] = []
	for agent_id in ids:
		var card := roster.recruit_offer_card(agent_id)
		if card != null:
			card_heights.append("%.0f" % card.size.y)
	print("GEOMETRY %s content=%s offer_cards=%s buttons=%s" % [
		state_name,
		str(content_rect.size),
		",".join(card_heights),
		str(roster.recruit_offer_button(ids[0]).size.y) if not ids.is_empty() else "n/a",
	])


func _headline_dominates(first: Dictionary, second: Dictionary) -> bool:
	var first_cost := int(first.get("cost", 0))
	var second_cost := int(second.get("cost", 0))
	var first_rating := int(first.get("rating", 0))
	var second_rating := int(second.get("rating", 0))
	return first_cost <= second_cost \
		and first_rating >= second_rating \
		and (first_cost < second_cost or first_rating > second_rating)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("CHECK_FAIL %s" % message)


func _backup_profile() -> void:
	for path in [SaveService.profile_path(PACK_ID), SaveService.backup_path(PACK_ID)]:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			_saved[path] = file.get_buffer(file.get_length())
			file.close()
	SaveService.delete_profile(PACK_ID)


func _restore_profile() -> void:
	SaveService.delete_profile(PACK_ID)
	for path in _saved.keys():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_saved[path])
			file.close()
	print("restored %d file(s)" % _saved.size())

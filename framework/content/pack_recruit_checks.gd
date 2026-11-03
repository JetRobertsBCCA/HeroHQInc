class_name PackRecruitChecks
extends RefCounted
## Validation for the optional recruit pool.
##
## Split from PackContentChecks so the rules stay reviewable on their own. A
## malformed pool must fail here, not at the 200th recruit: a pool that cannot
## produce every named slot silently repeats names, which defeats the point of
## a 200-strong roster.


## Returns [] when the pack declares no pool, so the block stays optional.
static func check(document: Dictionary, manifest: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var pool: Variant = document.get("recruit_pool", null)
	if pool == null:
		return errors
	if not (pool is Dictionary):
		errors.append(PackValidator.error(
			"invalid_value", "agents", "recruit_pool must be an object.",
		))
		return errors
	var rules: Dictionary = pool
	if str(rules.get("resource_id", "")).is_empty():
		errors.append(PackValidator.error(
			"invalid_value", "agents", "recruit_pool.resource_id must be set.",
		))
	elif not PackValidator.string_set(manifest.get("resources", [])).has(str(rules["resource_id"])):
		errors.append(PackValidator.error(
			"dangling_reference", "agents",
			"recruit_pool.resource_id '%s' is not a declared resource." % str(rules["resource_id"]),
		))
	if int(rules.get("named_count", 0)) < 0:
		errors.append(PackValidator.error(
			"invalid_value", "agents", "recruit_pool.named_count must be >= 0.",
		))
	if float(rules.get("base_cost", 0)) < 0.0:
		errors.append(PackValidator.error(
			"invalid_value", "agents", "recruit_pool.base_cost must be >= 0.",
		))
	if float(rules.get("cost_growth", 1)) < 1.0:
		errors.append(PackValidator.error(
			"invalid_value", "agents", "recruit_pool.cost_growth must be >= 1.",
		))
	errors.append_array(_check_names(rules))
	errors.append_array(_check_tiers(rules))
	return errors


## A named pool larger than its distinct combinations cannot stay unique.
static func _check_names(rules: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var given: Variant = rules.get("given_names", [])
	var signs: Variant = rules.get("call_signs", [])
	var given_count := (given as Array).size() if given is Array else 0
	var sign_count := (signs as Array).size() if signs is Array else 0
	var named := int(rules.get("named_count", 0))
	if named > 0 and (given_count == 0 or sign_count == 0):
		errors.append(PackValidator.error(
			"invalid_value", "agents",
			"recruit_pool needs given_names and call_signs for named slots.",
		))
	elif named > given_count * sign_count:
		errors.append(PackValidator.error(
			"invalid_value", "agents",
			"recruit_pool.named_count %d exceeds the %d distinct name combinations." % [
				named, given_count * sign_count,
			],
		))
	return errors


static func _check_tiers(rules: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var tiers: Variant = rules.get("tiers", [])
	if not (tiers is Array) or (tiers as Array).is_empty():
		errors.append(PackValidator.error(
			"invalid_value", "agents", "recruit_pool.tiers must be a non-empty array.",
		))
		return errors
	var seen: Dictionary = {}
	for raw in tiers:
		if not (raw is Dictionary):
			errors.append(PackValidator.error(
				"invalid_value", "agents", "Recruit tiers must be objects.",
			))
			continue
		var tier: Dictionary = raw
		var id := str(tier.get("id", ""))
		if not PackValidator.matches(id, PackValidator.ID_PATTERN):
			errors.append(PackValidator.error(
				"invalid_id", "agents", "Recruit tier id '%s' is invalid." % id,
			))
		if seen.has(id):
			errors.append(PackValidator.error(
				"duplicate_id", "agents", "Duplicate recruit tier id '%s'." % id,
			))
		seen[id] = true
		if int(tier.get("weight", 0)) <= 0:
			errors.append(PackValidator.error(
				"invalid_value", "agents", "Recruit tier '%s' weight must be > 0." % id,
			))
		if float(tier.get("cost_multiplier", 0)) <= 0.0:
			errors.append(PackValidator.error(
				"invalid_value", "agents", "Recruit tier '%s' cost_multiplier must be > 0." % id,
			))
		if int(tier.get("attribute_base", 0)) < 1:
			errors.append(PackValidator.error(
				"invalid_value", "agents", "Recruit tier '%s' attribute_base must be >= 1." % id,
			))
	return errors

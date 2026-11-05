class_name PackContentChecks
extends RefCounted
## Content-level pack checks: roles, starter agents, tuning rules and tasks.
##
## Split out of PackValidator so each file stays reviewable. Both halves are
## game-neutral: they validate structure and references, never a specific
## title's ids or values. Shared helpers and error construction live in
## PackValidator.


## Returns {ids: role_id -> true, errors: Array[Dictionary]}.
static func check_roles(records: Array, locale: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	var ids: Dictionary = {}
	if records.is_empty():
		errors.append(PackValidator.error("invalid_value", "roles", "A pack must define at least one role."))
		return {"ids": ids, "errors": errors}
	for record in records:
		if not (record is Dictionary):
			errors.append(PackValidator.error("invalid_value", "roles", "Role entries must be objects."))
			continue
		var entry: Dictionary = record
		var id := str(entry.get("id", ""))
		if not PackValidator.matches(id, PackValidator.ID_PATTERN):
			errors.append(PackValidator.error("invalid_id", "roles", "Role id '%s' is invalid." % id))
		if ids.has(id):
			errors.append(PackValidator.error("duplicate_id", "roles", "Duplicate role id '%s'." % id))
		ids[id] = true
		errors.append_array(PackValidator.check_locale_key(entry, "roles", locale, "role %s" % id))
		var growth: Variant = entry.get("growth", null)
		if growth != null and not (growth is Dictionary):
			errors.append(PackValidator.error(
				"invalid_value", "roles", "Role '%s' growth must be an object." % id,
			))
		elif growth is Dictionary:
			for attribute in (growth as Dictionary).keys():
				var amount := float((growth as Dictionary)[attribute])
				if not is_finite(amount) or amount < 0.0:
					errors.append(PackValidator.error(
						"invalid_value", "roles",
						"Role '%s' growth.%s must be finite and >= 0." % [id, str(attribute)],
					))
	return {"ids": ids, "errors": errors}


static func check_agents(
	document: Dictionary,
	role_ids: Dictionary,
	locale: Dictionary,
	manifest: Dictionary = {},
	trait_ids: Dictionary = {}
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var starting: Variant = document.get("starting_agents", [])
	if not (starting is Array):
		return errors
	var seen: Dictionary = {}
	for record in starting:
		if not (record is Dictionary):
			errors.append(PackValidator.error("invalid_value", "agents", "starting_agents entries must be objects."))
			continue
		var agent: Dictionary = record
		var id := str(agent.get("id", ""))
		if not PackValidator.matches(id, PackValidator.ID_PATTERN):
			errors.append(PackValidator.error("invalid_id", "agents", "Agent id '%s' is invalid." % id))
		if seen.has(id):
			errors.append(PackValidator.error("duplicate_id", "agents", "Duplicate agent id '%s'." % id))
		seen[id] = true
		var role_id := str(agent.get("role_id", ""))
		if not role_ids.has(role_id):
			errors.append(PackValidator.error(
				"dangling_reference", "agents",
				"Agent '%s' references unknown role '%s'." % [id, role_id],
			))
		if int(agent.get("level", 1)) < 1:
			errors.append(PackValidator.error("invalid_value", "agents", "Agent '%s' level must be >= 1." % id))
		if float(agent.get("xp", 0)) < 0.0:
			errors.append(PackValidator.error("invalid_value", "agents", "Agent '%s' xp must be >= 0." % id))
		var trait_id := str(agent.get("trait_id", ""))
		if not trait_id.is_empty() and not trait_ids.has(trait_id):
			errors.append(PackValidator.error(
				"dangling_reference", "agents",
				"Agent '%s' references unknown trait '%s'." % [id, trait_id],
			))
		errors.append_array(PackValidator.check_locale_key(agent, "agents", locale, "agent %s" % id))
		var attributes: Variant = agent.get("attributes", null)
		if attributes is Dictionary:
			for attribute in (attributes as Dictionary).keys():
				var amount := float((attributes as Dictionary)[attribute])
				if not is_finite(amount) or amount < 0.0:
					errors.append(PackValidator.error(
						"invalid_value", "agents",
						"Agent '%s' attribute '%s' must be finite and >= 0." % [id, str(attribute)],
					))
	errors.append_array(check_rules(document, manifest))
	return errors


## Optional trait catalogue. Every declared modifier must be one the shared
## simulation understands, and its filters must reference real content.
static func check_traits(
	records: Array,
	role_ids: Dictionary,
	progression: Dictionary,
	manifest: Dictionary,
	locale: Dictionary
) -> Dictionary:
	var errors: Array[Dictionary] = []
	var ids: Dictionary = {}
	if records.is_empty():
		return {"ids": ids, "errors": errors}
	var category_ids := PackValidator.id_set(progression.get("categories", []))
	var resource_ids := PackValidator.string_set(manifest.get("resources", []))
	for record in records:
		if not (record is Dictionary):
			errors.append(PackValidator.error("invalid_value", "traits", "Trait entries must be objects."))
			continue
		var entry: Dictionary = record
		var id := str(entry.get("id", ""))
		if not PackValidator.matches(id, PackValidator.ID_PATTERN):
			errors.append(PackValidator.error("invalid_id", "traits", "Trait id '%s' is invalid." % id))
		if ids.has(id):
			errors.append(PackValidator.error("duplicate_id", "traits", "Duplicate trait id '%s'." % id))
		ids[id] = true
		errors.append_array(PackValidator.check_locale_key(entry, "traits", locale, "trait %s" % id))
		var description_key := str(entry.get("description_key", ""))
		if description_key.is_empty() or not locale.has(description_key):
			errors.append(PackValidator.error(
				"missing_locale_key", "traits",
				"Trait '%s' description_key '%s' is missing from the locale." % [id, description_key],
			))
		var modifiers: Variant = entry.get("modifiers", null)
		if not (modifiers is Array) or (modifiers as Array).is_empty():
			errors.append(PackValidator.error(
				"invalid_value", "traits", "Trait '%s' must declare at least one modifier." % id,
			))
			continue
		for raw in modifiers:
			if not (raw is Dictionary):
				errors.append(PackValidator.error(
					"invalid_value", "traits", "Trait '%s' modifiers must be objects." % id,
				))
				continue
			var modifier: Dictionary = raw
			var modifier_type := str(modifier.get("type", ""))
			if not TraitRules.SUPPORTED_TYPES.has(modifier_type):
				errors.append(PackValidator.error(
					"invalid_value", "traits",
					"Trait '%s' modifier type '%s' is not supported." % [id, modifier_type],
				))
			var value := float(modifier.get("value", 0.0))
			if not is_finite(value):
				errors.append(PackValidator.error(
					"invalid_value", "traits", "Trait '%s' modifier value must be finite." % id,
				))
			elif modifier_type == TraitRules.DURATION:
				if value > 0.0 or value < -0.9:
					errors.append(PackValidator.error(
						"invalid_value", "traits",
						"Trait '%s' duration modifier must be between -0.9 and 0." % id,
					))
			elif value < 0.0 or value > 5.0:
				errors.append(PackValidator.error(
					"invalid_value", "traits",
					"Trait '%s' modifier value must be between 0 and 5." % id,
				))
			var task_kind := str(modifier.get("task_kind", ""))
			if modifier.has("task_kind") and not PackValidator.SUPPORTED_TASK_KINDS.has(task_kind):
				errors.append(PackValidator.error(
					"invalid_value", "traits",
					"Trait '%s' modifier task_kind '%s' is invalid." % [id, task_kind],
				))
			var category_id := str(modifier.get("category_id", ""))
			if modifier.has("category_id") and not category_ids.has(category_id):
				errors.append(PackValidator.error(
					"dangling_reference", "traits",
					"Trait '%s' references unknown category '%s'." % [id, category_id],
				))
			var role_id := str(modifier.get("role_id", ""))
			if modifier.has("role_id") and not role_ids.has(role_id):
				errors.append(PackValidator.error(
					"dangling_reference", "traits",
					"Trait '%s' references unknown role '%s'." % [id, role_id],
				))
			var resource_id := str(modifier.get("resource_id", ""))
			if modifier.has("resource_id") and not resource_ids.has(resource_id):
				errors.append(PackValidator.error(
					"dangling_reference", "traits",
					"Trait '%s' references undeclared resource '%s'." % [id, resource_id],
				))
			if modifier.has("automatic") and not (modifier["automatic"] is bool):
				errors.append(PackValidator.error(
					"invalid_value", "traits",
					"Trait '%s' automatic filter must be a boolean." % id,
				))
	return {"ids": ids, "errors": errors}


## Optional tuning blocks. Absent blocks keep their framework defaults, so a
## minimal pack stays valid; present blocks must be sane and self-consistent.
static func check_rules(document: Dictionary, manifest: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []

	var leveling: Variant = document.get("leveling", null)
	if leveling != null:
		if not (leveling is Dictionary):
			errors.append(PackValidator.error("invalid_value", "agents", "leveling must be an object."))
		else:
			var curve: Dictionary = leveling
			if float(curve.get("xp_base", 0)) <= 0.0:
				errors.append(PackValidator.error(
					"invalid_value", "agents", "leveling.xp_base must be > 0.",
				))
			if float(curve.get("xp_per_level", 0)) < 0.0:
				errors.append(PackValidator.error(
					"invalid_value", "agents", "leveling.xp_per_level must be >= 0.",
				))
			if int(curve.get("attribute_gain_per_level", 0)) < 0:
				errors.append(PackValidator.error(
					"invalid_value", "agents", "leveling.attribute_gain_per_level must be >= 0.",
				))

	errors.append_array(check_prestige(manifest))
	errors.append_array(check_research(manifest))

	var training: Variant = document.get("training", null)
	if training != null:
		if not (training is Dictionary):
			errors.append(PackValidator.error("invalid_value", "agents", "training must be an object."))
			return errors
		var rules: Dictionary = training
		var resource_ids := PackValidator.string_set(manifest.get("resources", []))
		var resource_id := str(rules.get("resource_id", ""))
		if not resource_ids.has(resource_id):
			errors.append(PackValidator.error(
				"dangling_reference", "agents",
				"training.resource_id '%s' is not a declared resource." % resource_id,
			))
		if float(rules.get("base_cost", 0)) < 0.0:
			errors.append(PackValidator.error(
				"invalid_value", "agents", "training.base_cost must be >= 0.",
			))
		if float(rules.get("cost_growth", 1)) < 1.0:
			errors.append(PackValidator.error(
				"invalid_value", "agents", "training.cost_growth must be >= 1.",
			))
		if float(rules.get("xp_per_session", 0)) < 0.0:
			errors.append(PackValidator.error(
				"invalid_value", "agents", "training.xp_per_session must be >= 0.",
			))
	errors.append_array(PackRecruitChecks.check(document, manifest))
	return errors


## Optional rebirth economy. Absent means the pack has no rebirth; present must
## be internally consistent, because its numbers set the long-term pace.
static func check_prestige(manifest: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var prestige: Variant = manifest.get("prestige", null)
	if prestige == null:
		return errors
	if not (prestige is Dictionary):
		errors.append(PackValidator.error("invalid_value", "manifest", "prestige must be an object."))
		return errors
	var rules: Dictionary = prestige
	var resource_ids := PackValidator.string_set(manifest.get("resources", []))
	var resource_id := str(rules.get("resource_id", ""))
	if not resource_id.is_empty() and not resource_ids.has(resource_id):
		errors.append(PackValidator.error(
			"dangling_reference", "manifest",
			"prestige.resource_id '%s' is not a declared resource." % resource_id,
		))
	if float(rules.get("threshold_amount", 0)) < 0.0:
		errors.append(PackValidator.error(
			"invalid_value", "manifest", "prestige.threshold_amount must be >= 0.",
		))
	if float(rules.get("scale", 0)) <= 0.0:
		errors.append(PackValidator.error(
			"invalid_value", "manifest", "prestige.scale must be > 0.",
		))
	var exponent := float(rules.get("exponent", 0.5))
	if exponent <= 0.0 or exponent > 1.0:
		errors.append(PackValidator.error(
			"invalid_value", "manifest",
			"prestige.exponent must be in (0, 1]; a steeper exponent makes late runs trivial.",
		))
	if float(rules.get("gain_factor", 0)) <= 0.0:
		errors.append(PackValidator.error(
			"invalid_value", "manifest", "prestige.gain_factor must be > 0.",
		))
	if float(rules.get("bonus_per_chip", 0)) < 0.0:
		errors.append(PackValidator.error(
			"invalid_value", "manifest", "prestige.bonus_per_chip must be >= 0.",
		))
	if int(rules.get("min_level", 1)) < 1:
		errors.append(PackValidator.error(
			"invalid_value", "manifest", "prestige.min_level must be >= 1.",
		))
	return errors


## Optional permanent research. Absent means no research; present must be
## internally consistent and use only effects the simulation implements.
static func check_research(manifest: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var research: Variant = manifest.get("research", null)
	if research == null:
		return errors
	if not (research is Dictionary):
		errors.append(PackValidator.error("invalid_value", "manifest", "research must be an object."))
		return errors
	var rules: Dictionary = research
	var resource_ids := PackValidator.string_set(manifest.get("resources", []))
	var resource_id := str(rules.get("resource_id", ""))
	if not resource_ids.has(resource_id):
		errors.append(PackValidator.error(
			"dangling_reference", "manifest",
			"research.resource_id '%s' is not a declared resource." % resource_id,
		))
	var branches: Variant = rules.get("branches", null)
	if not (branches is Array) or (branches as Array).is_empty():
		errors.append(PackValidator.error(
			"invalid_value", "manifest", "research.branches must be a non-empty array.",
		))
		return errors
	var seen: Dictionary = {}
	for raw in branches:
		if not (raw is Dictionary):
			errors.append(PackValidator.error(
				"invalid_value", "manifest", "Research branches must be objects.",
			))
			continue
		var branch: Dictionary = raw
		var id := str(branch.get("id", ""))
		if not PackValidator.matches(id, PackValidator.ID_PATTERN):
			errors.append(PackValidator.error(
				"invalid_id", "manifest", "Research id '%s' is invalid." % id,
			))
		if seen.has(id):
			errors.append(PackValidator.error(
				"duplicate_id", "manifest", "Duplicate research id '%s'." % id,
			))
		seen[id] = true
		if int(branch.get("max_rank", 0)) < 1:
			errors.append(PackValidator.error(
				"invalid_value", "manifest", "Research '%s' max_rank must be >= 1." % id,
			))
		if float(branch.get("base_cost", 0)) < 0.0:
			errors.append(PackValidator.error(
				"invalid_value", "manifest", "Research '%s' base_cost must be >= 0." % id,
			))
		if float(branch.get("cost_growth", 1)) < 1.0:
			errors.append(PackValidator.error(
				"invalid_value", "manifest", "Research '%s' cost_growth must be >= 1." % id,
			))
		if not Research.SUPPORTED_EFFECTS.has(str(branch.get("effect", ""))):
			errors.append(PackValidator.error(
				"invalid_value", "manifest",
				"Research '%s' effect must be one of %s." % [id, str(Research.SUPPORTED_EFFECTS)],
			))
		if float(branch.get("per_rank", 0)) < 0.0:
			errors.append(PackValidator.error(
				"invalid_value", "manifest", "Research '%s' per_rank must be >= 0." % id,
			))
	return errors


static func check_tasks(
	tasks: Array,
	role_ids: Dictionary,
	locale: Dictionary,
	progression: Dictionary,
	manifest: Dictionary
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if tasks.is_empty():
		errors.append(PackValidator.error("invalid_value", "missions", "A pack must define at least one task."))
		return errors
	var stage_ids := PackValidator.id_set(progression.get("stages", []))
	var category_ids := PackValidator.id_set(progression.get("categories", []))
	var resource_ids := PackValidator.string_set(manifest.get("resources", []))
	var seen: Dictionary = {}
	for record in tasks:
		if not (record is Dictionary):
			errors.append(PackValidator.error("invalid_value", "missions", "Task entries must be objects."))
			continue
		var task: Dictionary = record
		var id := str(task.get("id", ""))
		if not PackValidator.matches(id, PackValidator.ID_PATTERN):
			errors.append(PackValidator.error("invalid_id", "missions", "Task id '%s' is invalid." % id))
		if seen.has(id):
			errors.append(PackValidator.error("duplicate_id", "missions", "Duplicate task id '%s'." % id))
		seen[id] = true
		errors.append_array(PackValidator.check_locale_key(task, "missions", locale, "task %s" % id))
		if not PackValidator.SUPPORTED_TASK_KINDS.has(str(task.get("kind", ""))):
			errors.append(PackValidator.error(
				"invalid_value", "missions",
				"Task '%s' kind '%s' is not one of %s." % [
					id, str(task.get("kind", "")), str(PackValidator.SUPPORTED_TASK_KINDS),
				],
			))
		var stage_id := str(task.get("stage_id", ""))
		if not stage_ids.has(stage_id):
			errors.append(PackValidator.error(
				"dangling_reference", "missions",
				"Task '%s' references unknown stage '%s'." % [id, stage_id],
			))
		var category_id := str(task.get("category_id", ""))
		if not category_ids.has(category_id):
			errors.append(PackValidator.error(
				"dangling_reference", "missions",
				"Task '%s' references unknown category '%s'." % [id, category_id],
			))
		var base_seconds := float(task.get("base_seconds", 0))
		if not is_finite(base_seconds) or base_seconds < 1.0:
			errors.append(PackValidator.error("invalid_value", "missions", "Task '%s' base_seconds must be >= 1." % id))
		if int(task.get("required_agent_count", 0)) < 1:
			errors.append(PackValidator.error(
				"invalid_value", "missions", "Task '%s' required_agent_count must be >= 1." % id,
			))
		var minimum_rating := float(task.get("minimum_rating", 0))
		if not is_finite(minimum_rating) or minimum_rating < 0.0:
			errors.append(PackValidator.error("invalid_value", "missions", "Task '%s' minimum_rating must be >= 0." % id))
		if task.has("xp"):
			var xp := float(task.get("xp", 0))
			if not is_finite(xp) or xp < 0.0:
				errors.append(PackValidator.error(
					"invalid_value", "missions", "Task '%s' xp must be finite and >= 0." % id,
				))
		var required_roles: Variant = task.get("required_role_ids", [])
		if not (required_roles is Array):
			errors.append(PackValidator.error("invalid_value", "missions", "Task '%s' required_role_ids must be an array." % id))
		else:
			for role_id in required_roles:
				if not role_ids.has(str(role_id)):
					errors.append(PackValidator.error(
						"dangling_reference", "missions",
						"Task '%s' requires unknown role '%s'." % [id, str(role_id)],
					))
		var rewards: Variant = task.get("rewards", null)
		if not (rewards is Dictionary) or (rewards as Dictionary).is_empty():
			errors.append(PackValidator.error("invalid_value", "missions", "Task '%s' must declare rewards." % id))
		else:
			for resource_id in (rewards as Dictionary).keys():
				if not resource_ids.has(str(resource_id)):
					errors.append(PackValidator.error(
						"dangling_reference", "missions",
						"Task '%s' rewards undeclared resource '%s'." % [id, str(resource_id)],
					))
				var amount := float((rewards as Dictionary)[resource_id])
				if not is_finite(amount) or amount < 0.0:
					errors.append(PackValidator.error(
						"invalid_value", "missions",
						"Task '%s' reward '%s' must be finite and >= 0." % [id, str(resource_id)],
					))
	return errors

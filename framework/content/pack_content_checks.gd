class_name PackContentChecks
extends RefCounted
## Content-level pack checks: roles, starter agents and tasks.
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
	locale: Dictionary
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
	return errors

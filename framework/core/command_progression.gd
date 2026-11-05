class_name CommandProgression
extends RefCounted
## Explicit command milestones and stage access.
##
## Levels are derived from aggregate saved state: roster size, tasks completed,
## lifetime earnings, owned roles and completed squad operations. No command-
## level field is written to the save, so a profile from an earlier content build
## evaluates immediately without a migration. Levels are contiguous: a later
## level cannot count until every earlier level is satisfied.

const TYPE_OWN_AGENTS := "own_agents"
const TYPE_COMPLETE_TASKS := "complete_tasks"
const TYPE_EARN_RESOURCE_LIFETIME := "earn_resource_lifetime"
const TYPE_OWN_ROLE_ANY := "own_role_any"
const TYPE_OWN_DISTINCT_ROLES := "own_distinct_roles"
const TYPE_COMPLETE_SQUAD_TASKS := "complete_squad_tasks"
const TYPE_BUY_UPGRADE := "buy_upgrade"

const SUPPORTED_REQUIREMENT_TYPES: Array[String] = [
	TYPE_OWN_AGENTS,
	TYPE_COMPLETE_TASKS,
	TYPE_EARN_RESOURCE_LIFETIME,
	TYPE_OWN_ROLE_ANY,
	TYPE_OWN_DISTINCT_ROLES,
	TYPE_COMPLETE_SQUAD_TASKS,
	TYPE_BUY_UPGRADE,
]


static func levels(pack: GamePack) -> Array:
	var raw: Variant = pack.progression.get("command_levels", [])
	var result: Array = []
	if raw is Array:
		for entry in raw:
			if entry is Dictionary and int((entry as Dictionary).get("level", 0)) >= 1:
				result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("level", 0)) < int(b.get("level", 0))
	)
	return result


static func level_record(pack: GamePack, level: int) -> Dictionary:
	for raw in levels(pack):
		var entry: Dictionary = raw
		if int(entry.get("level", 0)) == level:
			return entry
	return {}


## Highest contiguous level whose requirements are all met. A profile with no
## command-level data is treated as the starting level rather than an error.
static func current_level(state: GameState, pack: GamePack) -> int:
	var all := levels(pack)
	if all.is_empty():
		return 1
	var expected := 1
	var achieved := 0
	for raw in all:
		var entry: Dictionary = raw
		var number := int(entry.get("level", 0))
		if number < expected:
			continue
		if number > expected:
			break
		if not requirements_met(state, pack, entry):
			break
		achieved = number
		expected += 1
	return maxi(achieved, 1)


static func next_level(state: GameState, pack: GamePack) -> Dictionary:
	var current := current_level(state, pack)
	for raw in levels(pack):
		var entry: Dictionary = raw
		if int(entry.get("level", 0)) > current:
			return entry
	return {}


static func requirements_met(state: GameState, pack: GamePack, level: Dictionary) -> bool:
	var raw: Variant = level.get("requirements", [])
	if not (raw is Array):
		return false
	for entry in raw:
		if not (entry is Dictionary):
			return false
		if not requirement_met(state, pack, entry):
			return false
	return true


static func requirement_met(
	state: GameState,
	pack: GamePack,
	requirement: Dictionary
) -> bool:
	var requirement_type := str(requirement.get("type", ""))
	match requirement_type:
		TYPE_OWN_AGENTS:
			return state.agents.size() >= maxi(int(requirement.get("count", 0)), 0)
		TYPE_COMPLETE_TASKS:
			return state.tasks_completed() >= maxi(int(requirement.get("count", 0)), 0)
		TYPE_EARN_RESOURCE_LIFETIME:
			var resource_id := str(requirement.get("resource_id", ""))
			return state.earned_total(resource_id) + 0.0001 >= maxf(
				float(requirement.get("amount", 0.0)),
				0.0,
			)
		TYPE_OWN_ROLE_ANY:
			var roles := _string_array(requirement.get("role_ids", []))
			return _count_roles(state, roles) >= maxi(int(requirement.get("count", 1)), 1)
		TYPE_OWN_DISTINCT_ROLES:
			return _count_distinct_roles(state) >= maxi(int(requirement.get("count", 1)), 1)
		TYPE_COMPLETE_SQUAD_TASKS:
			return state.squad_tasks_completed() >= maxi(int(requirement.get("count", 1)), 1)
		TYPE_BUY_UPGRADE:
			return _purchased_upgrades(state) >= maxi(int(requirement.get("count", 0)), 0)
	return false


## Structured rows for the HQ card. The label already includes the target; the
## progress field is the current/target pair. Keeping numbers separate means the
## UI never relies on colour to show whether a requirement is complete.
static func requirement_rows(
	pack: GamePack,
	state: GameState,
	level: Dictionary
) -> Array:
	var rows: Array = []
	var raw: Variant = level.get("requirements", [])
	if not (raw is Array):
		return rows
	for entry in raw:
		if entry is Dictionary:
			rows.append(_requirement_row(pack, state, entry))
	return rows


static func _requirement_row(
	pack: GamePack,
	state: GameState,
	requirement: Dictionary
) -> Dictionary:
	var requirement_type := str(requirement.get("type", ""))
	var current := 0.0
	var target := 0.0
	var label := ""
	match requirement_type:
		TYPE_OWN_AGENTS:
			target = float(maxi(int(requirement.get("count", 0)), 0))
			current = float(state.agents.size())
			label = pack.label("ui.command_req_agents", "Own %d agents") % int(target)
		TYPE_COMPLETE_TASKS:
			target = float(maxi(int(requirement.get("count", 0)), 0))
			current = float(state.tasks_completed())
			label = pack.label("ui.command_req_tasks", "Complete %d tasks") % int(target)
		TYPE_EARN_RESOURCE_LIFETIME:
			var resource_id := str(requirement.get("resource_id", ""))
			target = maxf(float(requirement.get("amount", 0.0)), 0.0)
			current = state.earned_total(resource_id)
			label = pack.label("ui.command_req_earn", "Earn %s lifetime %s") % [
				_amount_text(target),
				pack.label("resources.%s" % resource_id, resource_id),
			]
		TYPE_OWN_ROLE_ANY:
			var roles := _string_array(requirement.get("role_ids", []))
			target = float(maxi(int(requirement.get("count", 1)), 1))
			current = float(_count_roles(state, roles))
			var names := _role_names(pack, roles)
			var separator := " %s " % pack.label("ui.command_or", "or")
			label = pack.label("ui.command_req_role_any", "Own a %s agent") % separator.join(names)
		TYPE_OWN_DISTINCT_ROLES:
			target = float(maxi(int(requirement.get("count", 1)), 1))
			current = float(_count_distinct_roles(state))
			label = pack.label("ui.command_req_roles", "Own agents in %d roles") % int(target)
		TYPE_COMPLETE_SQUAD_TASKS:
			target = float(maxi(int(requirement.get("count", 1)), 1))
			current = float(state.squad_tasks_completed())
			label = pack.label("ui.command_req_squads", "Complete %d squad operations") % int(target)
		TYPE_BUY_UPGRADE:
			target = float(maxi(int(requirement.get("count", 0)), 0))
			current = float(_purchased_upgrades(state))
			label = pack.label("ui.command_req_upgrades", "Buy %d upgrades") % int(target)
		_:
			label = pack.label("ui.command_req_unknown", "Unknown requirement")
	var met := current + 0.0001 >= target
	return {
		"type": requirement_type,
		"label": label,
		"progress": "%s / %s" % [
			_progress_text(current, requirement_type),
			_progress_text(target, requirement_type),
		],
		"current": current,
		"target": target,
		"met": met,
	}


## Stage unlock level declared by the pack. Stages without the field are open,
## which preserves older packs that predate explicit stage gating.
static func stage_unlock_level(pack: GamePack, stage_id: String) -> int:
	var raw: Variant = pack.progression.get("stages", [])
	if raw is Array:
		for entry in raw:
			if not (entry is Dictionary):
				continue
			var stage: Dictionary = entry
			if str(stage.get("id", "")) != stage_id:
				continue
			return maxi(int(stage.get("unlock_command_level", 1)), 1)
	return 1


static func stage_unlocked(state: GameState, pack: GamePack, stage_id: String) -> bool:
	return current_level(state, pack) >= stage_unlock_level(pack, stage_id)


static func stage_lock_details(state: GameState, pack: GamePack, stage_id: String) -> Dictionary:
	var required := stage_unlock_level(pack, stage_id)
	var current := current_level(state, pack)
	return {
		"stage_id": stage_id,
		"required_command_level": required,
		"current_command_level": current,
		"locked": current < required,
	}


## Stage labels unlocked by a specific command level, used by the HQ card.
static func unlocked_stage_labels(pack: GamePack, level: int) -> Array[String]:
	var labels: Array[String] = []
	var raw: Variant = pack.progression.get("stages", [])
	if raw is Array:
		for entry in raw:
			if not (entry is Dictionary):
				continue
			var stage: Dictionary = entry
			if int(stage.get("unlock_command_level", 0)) != level:
				continue
			labels.append(pack.label(
				str(stage.get("name_key", "")),
				str(stage.get("id", "")),
			))
	return labels


static func stage_lock_text(pack: GamePack, details: Dictionary) -> String:
	var stage_id := str(details.get("stage_id", ""))
	var required := int(details.get("required_command_level", 1))
	var current := int(details.get("current_command_level", 1))
	return pack.label(
		"ui.stage_locked",
		"%s requires Command Level %d (current %d).",
	) % [pack.stage_label(stage_id), required, current]


static func _count_roles(state: GameState, role_ids: Array[String]) -> int:
	if role_ids.is_empty():
		return 0
	var count := 0
	for raw in state.agents.values():
		if raw is Dictionary:
			var role_id := str((raw as Dictionary).get("role_id", ""))
			if role_ids.has(role_id):
				count += 1
	return count


static func _count_distinct_roles(state: GameState) -> int:
	var roles: Dictionary = {}
	for raw in state.agents.values():
		if raw is Dictionary:
			var role_id := str((raw as Dictionary).get("role_id", ""))
			if not role_id.is_empty():
				roles[role_id] = true
	return roles.size()


static func _purchased_upgrades(state: GameState) -> int:
	var count := 0
	for raw in state.upgrades.values():
		if int(raw) > 0:
			count += 1
	return count


static func _role_names(pack: GamePack, role_ids: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for role_id in role_ids:
		names.append(pack.label(str(pack.role(role_id).get("name_key", "")), role_id))
	return names


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	return result


static func _progress_text(value: float, requirement_type: String) -> String:
	if requirement_type == TYPE_EARN_RESOURCE_LIFETIME:
		return _amount_text(value)
	return str(int(roundf(value)))


static func _amount_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value

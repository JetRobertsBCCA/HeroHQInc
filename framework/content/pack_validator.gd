class_name PackValidator
extends RefCounted
## Game-neutral content-pack validation.
##
## Every check here is structural or generic: unique ids, resolvable
## references, finite and non-negative numbers, safe paths, present locale keys
## and theme tokens. No specific title, role, task or resource id appears here.
##
## This module owns the manifest, theme, progression, navigation and locale
## checks plus the shared helpers. Role, agent and task checks live in
## PackContentChecks so each file stays reviewable.

const SUPPORTED_PACK_SCHEMA_VERSION := 1

const REQUIRED_MANIFEST_KEYS: Array[String] = [
	"pack_schema_version",
	"game_id",
	"content_version",
	"display_name_key",
	"default_locale",
	"data_paths",
	"locale_path",
	"theme_path",
]

const REQUIRED_DATA_PATHS: Array[String] = ["roles", "missions"]

const REQUIRED_THEME_TOKENS: Array[String] = [
	"background",
	"panel",
	"border",
	"text",
	"muted",
	"accent",
	"accent_alt",
	"success",
	"reward",
	"warning",
]

const SUPPORTED_MECHANICS: Array[String] = [
	"agents",
	"training",
	"recruitment",
	"squads",
	"timed_tasks",
	"automation",
	"focus",
	"traits",
]

const SUPPORTED_TASK_KINDS: Array[String] = ["solo", "squad"]

const SUPPORTED_REQUIREMENT_TYPES: Array[String] = [
	"own_agents",
	"complete_tasks",
	"earn_resource_lifetime",
	"buy_upgrade",
	"own_role_any",
	"own_distinct_roles",
	"complete_squad_tasks",
]

const FOCUS_NUMERIC_KEYS: Array[String] = [
	"max",
	"regen_seconds",
	"pulse_fraction",
	"solo_cap_seconds",
	"squad_cap_seconds",
	"pulse_interval_seconds",
	"minimum_remaining_seconds",
]

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const HEX_COLOR_PATTERN := "^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"


## Validates a pack directory. Returns [] when the pack is usable, otherwise a
## list of {code, path, message} dictionaries with stable machine-readable codes.
static func validate_pack_root(root: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var normalized := root.trim_suffix("/")
	var manifest_path := normalized.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		errors.append(error("manifest_missing", manifest_path, "Pack has no manifest.json."))
		return errors
	var parsed: Variant = _read_json(manifest_path)
	if not (parsed is Dictionary):
		errors.append(error("manifest_invalid", manifest_path, "manifest.json is not a JSON object."))
		return errors
	var manifest: Dictionary = parsed
	errors.append_array(_check_manifest_fields(normalized, manifest, manifest_path))
	if not errors.is_empty():
		return errors

	var locale := _read_json_object(normalized.path_join(str(manifest["locale_path"])))
	var theme := _read_json_object(normalized.path_join(str(manifest["theme_path"])))
	var roles := _read_json_array(normalized.path_join(data_path(manifest, "roles")))
	var tasks := _read_json_array(normalized.path_join(data_path(manifest, "missions")))
	var agents_document := _read_json_object(normalized.path_join(data_path(manifest, "agents")))
	var progression := _read_json_object(normalized.path_join(data_path(manifest, "progression")))
	var traits: Array = []
	var traits_path := data_path(manifest, "traits")
	if not traits_path.is_empty():
		traits = _read_json_array(normalized.path_join(traits_path))

	errors.append_array(_check_theme(theme, normalized.path_join(str(manifest["theme_path"]))))
	errors.append_array(_check_progression(progression, locale))

	var role_result := PackContentChecks.check_roles(roles, locale)
	errors.append_array(role_result["errors"])
	var role_ids: Dictionary = role_result["ids"]
	var trait_result := PackContentChecks.check_traits(
		traits, role_ids, progression, manifest, locale
	)
	errors.append_array(trait_result["errors"])
	var trait_ids: Dictionary = trait_result["ids"]
	errors.append_array(
		PackContentChecks.check_agents(agents_document, role_ids, locale, manifest, trait_ids)
	)
	errors.append_array(
		PackContentChecks.check_tasks(tasks, role_ids, locale, progression, manifest)
	)
	errors.append_array(_check_navigation(manifest, locale))
	errors.append_array(_check_locale_references(manifest, locale))
	return errors


static func _check_manifest_fields(root: String, manifest: Dictionary, manifest_path: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for key in REQUIRED_MANIFEST_KEYS:
		if not manifest.has(key):
			errors.append(error("missing_required_key", manifest_path, "Manifest is missing '%s'." % key))
	if not errors.is_empty():
		return errors

	if int(manifest["pack_schema_version"]) != SUPPORTED_PACK_SCHEMA_VERSION:
		errors.append(error(
			"unsupported_schema_version",
			manifest_path,
			"pack_schema_version %d is not supported (expected %d)." % [
				int(manifest["pack_schema_version"]), SUPPORTED_PACK_SCHEMA_VERSION,
			]
		))

	var game_id := str(manifest["game_id"])
	if not matches(game_id, ID_PATTERN):
		errors.append(error("invalid_id", manifest_path, "game_id '%s' is not lowercase snake_case." % game_id))
	if game_id != root.get_file():
		errors.append(error(
			"game_id_mismatch",
			manifest_path,
			"game_id '%s' does not match pack directory '%s'." % [game_id, root.get_file()],
		))

	if int(manifest["content_version"]) < 1:
		errors.append(error("invalid_value", manifest_path, "content_version must be >= 1."))
	if str(manifest["display_name_key"]).is_empty():
		errors.append(error("invalid_value", manifest_path, "display_name_key must not be empty."))
	if str(manifest["default_locale"]).is_empty():
		errors.append(error("invalid_value", manifest_path, "default_locale must not be empty."))
	if manifest.has("max_offline_seconds"):
		var offline := float(manifest["max_offline_seconds"])
		if not is_finite(offline) or offline <= 0.0:
			errors.append(error("invalid_value", manifest_path, "max_offline_seconds must be finite and > 0."))

	var mechanics: Variant = manifest.get("mechanics", [])
	var focus_declared := false
	if not (mechanics is Array):
		errors.append(error("invalid_value", manifest_path, "mechanics must be an array."))
	else:
		for mechanic in mechanics:
			if str(mechanic) == "focus":
				focus_declared = true
			if not SUPPORTED_MECHANICS.has(str(mechanic)):
				errors.append(error(
					"unsupported_mechanic",
					manifest_path,
					"Mechanic '%s' is not implemented by this framework version." % str(mechanic),
				))
	if focus_declared or manifest.has("focus"):
		errors.append_array(_check_focus(manifest, manifest_path))

	var resources: Variant = manifest.get("resources", [])
	if not (resources is Array) or (resources as Array).is_empty():
		errors.append(error("invalid_value", manifest_path, "resources must be a non-empty array."))
	else:
		var seen: Dictionary = {}
		for resource_id in resources:
			var id := str(resource_id)
			if not matches(id, ID_PATTERN):
				errors.append(error("invalid_id", manifest_path, "Resource id '%s' is not lowercase snake_case." % id))
			if seen.has(id):
				errors.append(error("duplicate_id", manifest_path, "Duplicate resource id '%s'." % id))
			seen[id] = true

	var data_paths: Variant = manifest["data_paths"]
	if not (data_paths is Dictionary):
		errors.append(error("invalid_value", manifest_path, "data_paths must be an object."))
		return errors
	var paths: Dictionary = data_paths
	for required_key in REQUIRED_DATA_PATHS:
		if not paths.has(required_key):
			errors.append(error(
				"missing_data_path",
				manifest_path,
				"data_paths must define '%s'." % required_key,
			))
	for key in paths.keys():
		var relative := str(paths[key])
		if not is_safe_relative_path(relative):
			errors.append(error(
				"data_path_escape",
				manifest_path,
				"data_paths.%s ('%s') must be a relative path inside the pack." % [str(key), relative],
			))
			continue
		if not FileAccess.file_exists(root.path_join(relative)):
			errors.append(error(
				"data_path_missing",
				root.path_join(relative),
				"data_paths.%s points at a missing file." % str(key),
			))
	for scalar_key in ["locale_path", "theme_path"]:
		var relative := str(manifest[scalar_key])
		if not is_safe_relative_path(relative):
			errors.append(error(
				"data_path_escape", manifest_path,
				"%s ('%s') must be a relative path inside the pack." % [scalar_key, relative],
			))
		elif not FileAccess.file_exists(root.path_join(relative)):
			errors.append(error(
				"data_path_missing", root.path_join(relative),
				"%s points at a missing file." % scalar_key,
			))
	if manifest.has("navigation"):
		var navigation: Variant = manifest["navigation"]
		if not (navigation is Array) or (navigation as Array).is_empty():
			errors.append(error("invalid_value", manifest_path, "navigation must be a non-empty array."))
		else:
			var seen_tabs: Dictionary = {}
			for entry in navigation:
				if not (entry is Dictionary):
					errors.append(error("invalid_value", manifest_path, "navigation entries must be objects."))
					continue
				var tab: Dictionary = entry
				var tab_id := str(tab.get("id", ""))
				if not matches(tab_id, ID_PATTERN):
					errors.append(error("invalid_id", manifest_path, "Navigation id '%s' is invalid." % tab_id))
				if seen_tabs.has(tab_id):
					errors.append(error("duplicate_id", manifest_path, "Duplicate navigation id '%s'." % tab_id))
				seen_tabs[tab_id] = true
				if str(tab.get("label_key", "")).is_empty():
					errors.append(error("invalid_value", manifest_path, "Navigation '%s' has no label_key." % tab_id))
	return errors


static func _check_focus(manifest: Dictionary, path: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var raw: Variant = manifest.get("focus", null)
	if raw == null:
		errors.append(error(
			"missing_required_key",
			path,
			"mechanics declares focus but manifest has no focus tuning.",
		))
		return errors
	if not (raw is Dictionary):
		errors.append(error("invalid_value", path, "focus must be an object."))
		return errors
	var focus: Dictionary = raw
	for key in FOCUS_NUMERIC_KEYS:
		if not focus.has(key):
			errors.append(error(
				"missing_required_key", path, "focus is missing '%s'." % key,
			))
			continue
		var value := float(focus[key])
		if not is_finite(value) or value <= 0.0:
			errors.append(error(
				"invalid_value", path, "focus.%s must be finite and > 0." % key,
			))
	if focus.has("pulse_fraction"):
		var fraction := float(focus["pulse_fraction"])
		if is_finite(fraction) and fraction > 1.0:
			errors.append(error("invalid_value", path, "focus.pulse_fraction must be <= 1.0."))
	return errors


static func _check_theme(theme: Dictionary, path: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if theme.is_empty():
		errors.append(error("theme_invalid", path, "Theme file is missing or not a JSON object."))
		return errors
	for token in REQUIRED_THEME_TOKENS:
		if not theme.has(token):
			errors.append(error("invalid_theme_token", path, "Theme is missing token '%s'." % token))
			continue
		var value := str(theme[token])
		if not matches(value, HEX_COLOR_PATTERN):
			errors.append(error(
				"invalid_theme_token", path,
				"Theme token '%s' ('%s') is not a #RRGGBB or #RRGGBBAA value." % [token, value],
			))
	return errors


static func _check_progression(progression: Dictionary, locale: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	for section in ["stages", "categories"]:
		var records: Variant = progression.get(section, null)
		if records == null:
			errors.append(error("invalid_value", "progression", "Progression document has no '%s'." % section))
			continue
		if not (records is Array) or (records as Array).is_empty():
			errors.append(error("invalid_value", "progression", "'%s' must be a non-empty array." % section))
			continue
		var seen: Dictionary = {}
		for record in records:
			if not (record is Dictionary):
				errors.append(error("invalid_value", "progression", "'%s' entries must be objects." % section))
				continue
			var entry: Dictionary = record
			var id := str(entry.get("id", ""))
			if not matches(id, ID_PATTERN):
				errors.append(error("invalid_id", "progression", "'%s' id '%s' is invalid." % [section, id]))
			if seen.has(id):
				errors.append(error("duplicate_id", "progression", "Duplicate %s id '%s'." % [section, id]))
			seen[id] = true
			errors.append_array(check_locale_key(entry, "progression", locale, "%s.%s" % [section, id]))
	var levels: Variant = progression.get("command_levels", [])
	if levels is Array:
		var seen_levels: Dictionary = {}
		for record in levels:
			if not (record is Dictionary):
				errors.append(error("invalid_value", "progression", "command_levels entries must be objects."))
				continue
			var level: Dictionary = record
			var number := int(level.get("level", 0))
			if number < 1:
				errors.append(error("invalid_value", "progression", "command_levels entry needs level >= 1."))
			if seen_levels.has(number):
				errors.append(error("duplicate_id", "progression", "Duplicate command level %d." % number))
			seen_levels[number] = true
			var requirements: Variant = level.get("requirements", [])
			if requirements is Array:
				for requirement in requirements:
					if not (requirement is Dictionary):
						errors.append(error("invalid_value", "progression", "Requirement entries must be objects."))
						continue
					var requirement_type := str((requirement as Dictionary).get("type", ""))
					if not SUPPORTED_REQUIREMENT_TYPES.has(requirement_type):
						errors.append(error(
							"unsupported_requirement",
							"progression",
							"Requirement type '%s' is not implemented." % requirement_type,
						))
	return errors


static func _check_navigation(manifest: Dictionary, locale: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var navigation: Variant = manifest.get("navigation", [])
	if not (navigation is Array):
		return errors
	for entry in navigation:
		if entry is Dictionary:
			errors.append_array(check_locale_key(entry, "manifest", locale, "navigation"))
	return errors


static func _check_locale_references(manifest: Dictionary, locale: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	errors.append_array(check_locale_key(manifest, "manifest", locale, "game title"))
	var resources: Variant = manifest.get("resources", [])
	if resources is Array:
		for resource_id in resources:
			if not locale.has("resources.%s" % str(resource_id)):
				errors.append(error(
					"missing_locale_key", "locale",
					"Locale has no label for resource '%s' (expected 'resources.%s')." % [
						str(resource_id), str(resource_id),
					],
				))
	return errors


## Shared with PackContentChecks: a record's label key must exist in the locale.
static func check_locale_key(
	record: Dictionary,
	_label: String,
	locale: Dictionary,
	context: String
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var key := str(record.get("name_key", record.get("label_key", "")))
	if key.is_empty():
		return errors
	if not locale.has(key):
		errors.append(error(
			"missing_locale_key", "locale",
			"%s references locale key '%s', which no locale file defines." % [context, key],
		))
	return errors


static func data_path(manifest: Dictionary, key: String) -> String:
	var paths: Variant = manifest.get("data_paths", {})
	if paths is Dictionary:
		return str((paths as Dictionary).get(key, ""))
	return ""


static func is_safe_relative_path(path: String) -> bool:
	if path.is_empty():
		return false
	if path.begins_with("/") or path.begins_with("\\"):
		return false
	if path.contains("://"):
		return false
	if path.contains(".."):
		return false
	return true


static func matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(value) != null


## Resource ids are plain strings in a manifest.
static func string_set(values: Variant) -> Dictionary:
	var set: Dictionary = {}
	if values is Array:
		for value in values:
			set[str(value)] = true
	return set


## Stage/category ids live in {id: ...} records.
static func id_set(records: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if records is Array:
		for record in records:
			if record is Dictionary:
				ids[str((record as Dictionary).get("id", ""))] = true
	return ids


static func error(code: String, path: String, message: String) -> Dictionary:
	return {"code": code, "path": path, "message": message}


static func _read_json(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)


static func _read_json_object(path: String) -> Dictionary:
	var parsed: Variant = _read_json(path)
	if parsed is Dictionary:
		return parsed
	return {}


static func _read_json_array(path: String) -> Array:
	var parsed: Variant = _read_json(path)
	if parsed is Array:
		return parsed
	return []

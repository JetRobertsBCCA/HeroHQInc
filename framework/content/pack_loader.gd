class_name GamePackLoader
extends RefCounted
## Loads and validates content packs.
##
## Contract: relative paths in a manifest resolve inside the pack root only,
## and a pack is never used unless it passed validation. Ids are the only way
## to reference content, so packs stay swappable without code changes.

const GAMES_ROOT := "res://games"


static func pack_root(game_id: String) -> String:
	return "%s/%s" % [GAMES_ROOT, game_id]


static func list_pack_ids() -> Array[String]:
	var ids: Array[String] = []
	var directory := DirAccess.open(GAMES_ROOT)
	if directory == null:
		return ids
	for entry in directory.get_directories():
		ids.append(entry)
	ids.sort()
	return ids


## Loads a pack by id from the standard games directory.
## Returns {pack, errors}. `pack` is null when validation failed.
static func load_pack(game_id: String) -> Dictionary:
	return load_pack_from_root(pack_root(game_id), game_id)


## Loads a pack from an explicit root (test fixtures, future tooling).
## Returns {pack, errors}. `pack` is null when validation failed.
static func load_pack_from_root(root: String, expected_game_id: String = "") -> Dictionary:
	var normalized := root.trim_suffix("/")
	var errors: Array = PackValidator.validate_pack_root(normalized)
	if not errors.is_empty():
		return {"pack": null, "errors": errors}
	var manifest: Dictionary = _read_json_dictionary(normalized.path_join("manifest.json"))
	if expected_game_id != "" and str(manifest.get("game_id", "")) != expected_game_id:
		return {
			"pack": null,
			"errors": [{
				"code": "game_id_mismatch",
				"path": normalized.path_join("manifest.json"),
				"message": "Manifest declares '%s' but '%s' was requested." % [
					str(manifest.get("game_id", "")), expected_game_id,
				],
			}],
		}
	var pack := GamePack.new()
	pack.root_path = normalized
	pack.manifest = manifest
	pack.game_id = str(manifest.get("game_id", ""))
	pack.content_version = int(manifest.get("content_version", 1))
	pack.max_offline_seconds = float(manifest.get("max_offline_seconds", 28800))
	pack.starting_resources = _typed_dictionary(manifest.get("starting_resources"))
	pack.navigation = _typed_array(manifest.get("navigation"))
	pack.locale = _read_json_dictionary(normalized.path_join(str(manifest.get("locale_path", "locale/en.json"))))
	pack.theme = _read_json_dictionary(normalized.path_join(str(manifest.get("theme_path", "ui/theme.json"))))
	pack.progression = _read_json_dictionary(normalized.path_join(str(_data_path(manifest, "progression"))))
	pack.roles = _index_by_id(_read_json_array(normalized.path_join(str(_data_path(manifest, "roles")))))
	pack.missions = _index_by_id(_read_json_array(normalized.path_join(str(_data_path(manifest, "missions")))))
	var agents_document := _read_json_dictionary(normalized.path_join(str(_data_path(manifest, "agents"))))
	pack.starter_agents = _index_by_id(_typed_array(agents_document.get("starting_agents")))
	pack.leveling = _typed_dictionary(agents_document.get("leveling"))
	pack.training = _typed_dictionary(agents_document.get("training"))
	pack.roster_capacity = int(manifest.get("roster_capacity", agents_document.get("roster_capacity", 0)))
	return {"pack": pack, "errors": []}


static func _data_path(manifest: Dictionary, key: String) -> String:
	var data_paths := _typed_dictionary(manifest.get("data_paths"))
	return str(data_paths.get(key, ""))


static func _index_by_id(records: Array) -> Dictionary:
	var index: Dictionary = {}
	for record in records:
		if record is Dictionary:
			var entry: Dictionary = record
			index[str(entry.get("id", ""))] = entry
	return index


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)


static func _read_json_dictionary(path: String) -> Dictionary:
	var parsed: Variant = _read_json(path)
	if parsed is Dictionary:
		return parsed
	return {}


static func _read_json_array(path: String) -> Array:
	var parsed: Variant = _read_json(path)
	if parsed is Array:
		return parsed
	return []


static func _typed_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _typed_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []

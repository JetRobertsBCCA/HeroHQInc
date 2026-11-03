class_name SaveService
extends RefCounted
## Atomic, per-game save storage.
##
## Profile path is derived from `game_id`, so one title can never load another
## title's progress. Writes go to a temporary file that is then renamed into
## place, and the previous profile is retained as a backup.

const SAVE_ROOT := "user://saves"


static func profile_path(game_id: String) -> String:
	return "%s/%s/profile.json" % [SAVE_ROOT, game_id]


static func backup_path(game_id: String) -> String:
	return "%s/%s/profile.backup.json" % [SAVE_ROOT, game_id]


static func has_save(game_id: String) -> bool:
	return FileAccess.file_exists(profile_path(game_id))


static func save_state(state: GameState) -> Dictionary:
	if state.game_id.is_empty():
		return _failure("missing_game_id", "State has no game_id; refusing to write a shared save.")
	var directory := "%s/%s" % [SAVE_ROOT, state.game_id]
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if directory_error != OK:
		return _failure("directory_failed", error_string(directory_error))
	var target := profile_path(state.game_id)
	var temporary := target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("write_failed", error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()
	if FileAccess.file_exists(target):
		var backup := backup_path(state.game_id)
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(target),
			ProjectSettings.globalize_path(backup)
		)
		if backup_error != OK:
			return _failure("backup_failed", error_string(backup_error))
	var commit_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(target)
	)
	if commit_error != OK:
		return _failure("commit_failed", error_string(commit_error))
	return {"state": state, "error": "", "details": ""}


## Returns {state, error, details}. `state` is null when nothing could be loaded.
## Falls back to the backup profile when the primary is missing or unreadable.
static func load_state(game_id: String) -> Dictionary:
	var primary := _read_profile(game_id, profile_path(game_id))
	if primary.get("state") != null:
		return primary
	if primary.get("error") == "game_id_mismatch":
		return primary
	var backup := _read_profile(game_id, backup_path(game_id))
	if backup.get("state") != null:
		return backup
	return primary


static func _read_profile(game_id: String, path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"state": null, "error": "not_found", "details": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"state": null, "error": "read_failed", "details": error_string(FileAccess.get_open_error())}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"state": null, "error": "corrupt_save", "details": path}
	var data: Dictionary = parsed
	var state := GameState.from_dict(data)
	if state.game_id != game_id:
		return {
			"state": null,
			"error": "game_id_mismatch",
			"details": "Save declares '%s' but was requested as '%s'." % [state.game_id, game_id],
		}
	if state.save_schema_version > GameState.SAVE_SCHEMA_VERSION:
		return {
			"state": null,
			"error": "newer_schema",
			"details": "Save schema %d is newer than supported %d." % [
				state.save_schema_version, GameState.SAVE_SCHEMA_VERSION,
			],
		}
	if state.save_schema_version < GameState.SAVE_SCHEMA_VERSION:
		# Migration slots in here once schema 2 exists; schema 1 is the first.
		return {
			"state": null,
			"error": "unsupported_schema",
			"details": "No migration path from schema %d." % state.save_schema_version,
		}
	return {"state": state, "error": "", "details": ""}


static func delete_profile(game_id: String) -> void:
	for path in [profile_path(game_id), backup_path(game_id)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _failure(code: String, details: String) -> Dictionary:
	return {"state": null, "error": code, "details": details}

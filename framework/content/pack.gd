class_name GamePack
extends RefCounted
## A validated content pack loaded from `res://games/<game_id>/`.
##
## Framework code only reads generic fields: ids, numeric tuning, locale keys,
## theme tokens. It never looks up a specific title's ids.

var game_id: String = ""
var content_version: int = 1
var root_path: String = ""
var manifest: Dictionary = {}
var locale: Dictionary = {}
var theme: Dictionary = {}
## id -> role definition
var roles: Dictionary = {}
## id -> task definition
var missions: Dictionary = {}
## id -> starter agent record
var starter_agents: Dictionary = {}
## Declaration document: stages, categories, command levels.
var progression: Dictionary = {}
var starting_resources: Dictionary = {}
var max_offline_seconds: float = 28800.0
## [{id, label_key}] bottom navigation, in display order.
var navigation: Array = []


## Localized text for `key`. Falls back to `fallback`, then to the key itself,
## so a missing translation degrades visibly instead of crashing.
func label(key: String, fallback: String = "") -> String:
	var value: Variant = locale.get(key, null)
	if value is String and not (value as String).is_empty():
		return value
	if not fallback.is_empty():
		return fallback
	return key


func title() -> String:
	return label(str(manifest.get("display_name_key", "game.title")), game_id)


func declared_resources() -> Array:
	var resources: Variant = manifest.get("resources", [])
	if resources is Array:
		return resources
	return []


func stage_ids() -> Array:
	var stages: Variant = progression.get("stages", [])
	var ids: Array = []
	if stages is Array:
		for stage in stages:
			if stage is Dictionary:
				ids.append(str((stage as Dictionary).get("id", "")))
	return ids


func task_ids() -> Array:
	var ids: Array = missions.keys()
	ids.sort()
	return ids

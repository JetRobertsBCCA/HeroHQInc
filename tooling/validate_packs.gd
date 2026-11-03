extends SceneTree
## Validates every content pack under res://games.
##
##   godot --headless --path . -s res://tooling/validate_packs.gd
##
## Exits 1 if any pack is invalid, so it can gate CI.

func _initialize() -> void:
	var failures := 0
	var directory := DirAccess.open(GamePackLoader.GAMES_ROOT)
	if directory == null:
		print("ERROR no %s directory to validate" % GamePackLoader.GAMES_ROOT)
		quit(1)
		return
	var pack_ids: Array[String] = []
	for entry in directory.get_directories():
		pack_ids.append(entry)
	pack_ids.sort()
	if pack_ids.is_empty():
		print("ERROR no packs found under %s" % GamePackLoader.GAMES_ROOT)
		quit(1)
		return
	for pack_id in pack_ids:
		var root := GamePackLoader.pack_root(pack_id)
		var errors := PackValidator.validate_pack_root(root)
		if errors.is_empty():
			print("OK    %s" % pack_id)
			continue
		failures += 1
		print("FAIL  %s (%d problem(s))" % [pack_id, errors.size()])
		for error in errors:
			print("        [%s] %s" % [str(error["code"]), str(error["message"])])
		print("        at %s" % str(error_path_hint(errors)))
	print("%d pack(s) checked, %d invalid" % [pack_ids.size(), failures])
	quit(1 if failures > 0 else 0)


func error_path_hint(errors: Array) -> String:
	if errors.is_empty():
		return ""
	return str((errors[0] as Dictionary).get("path", ""))

extends Node
## Versioned JSON save files with atomic writes and a backup fallback.
## Files: user://saves/slot_<n>.json (+ .bak of the previous save).

signal before_save
signal saved(slot: int)
signal loaded(slot: int)

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := 0

var last_error: String = ""


func slot_path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json" % slot)


func has_save(slot: int = AUTOSAVE_SLOT) -> bool:
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(slot_path(slot) + ".bak")


func save_game(slot: int = AUTOSAVE_SLOT) -> bool:
	before_save.emit()
	var data := GameState.to_dict()
	data["save_version"] = SAVE_VERSION
	data["game_version"] = ProjectSettings.get_setting("application/config/version", "0")
	data["saved_at"] = Time.get_datetime_string_from_system()
	data["summary"] = {
		"level": GameState.get_level(),
		"play_time": GameState.play_time,
		"quest": GameState.tracked_quest,
	}
	var dir_err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if dir_err != OK and not DirAccess.dir_exists_absolute(SAVE_DIR):
		return _fail("could not create save folder (%s)" % error_string(dir_err))
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("could not write save (%s)" % error_string(FileAccess.get_open_error()))
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# Verify the temp file before replacing the real save.
	if typeof(JSON.parse_string(FileAccess.get_file_as_string(tmp))) != TYPE_DICTIONARY:
		DirAccess.remove_absolute(tmp)
		return _fail("save verification failed")
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return _fail("could not finalise save (%s)" % error_string(err))
	last_error = ""
	saved.emit(slot)
	return true


func load_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var path := slot_path(slot)
	var data := _read(path)
	if data.is_empty():
		push_warning("SaveManager: main save unreadable, trying backup")
		data = _read(path + ".bak")
	if data.is_empty():
		return _fail("no readable save in slot %d" % slot)
	data = migrate(data)
	if data.is_empty():
		return _fail("save is from a newer version of Velicia")
	GameState.from_dict(data)
	last_error = ""
	loaded.emit(slot)
	return true


func read_summary(slot: int = AUTOSAVE_SLOT) -> Dictionary:
	var data := _read(slot_path(slot))
	if data.is_empty():
		data = _read(slot_path(slot) + ".bak")
	if data.is_empty():
		return {}
	var s: Dictionary = data.get("summary", {})
	s["saved_at"] = data.get("saved_at", "")
	return s


func delete_save(slot: int) -> void:
	for p in [slot_path(slot), slot_path(slot) + ".bak", slot_path(slot) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Upgrades older save dictionaries to SAVE_VERSION. Returns {} if unsupported.
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version > SAVE_VERSION:
		return {}
	if version < 1:
		# Pre-release saves had no version; fill in fields added in v1.
		if not data.has("world"):
			data["world"] = {"opened": [], "defeated": [], "collected": []}
		version = 1
	data["save_version"] = version
	return data


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _fail(message: String) -> bool:
	last_error = message
	push_warning("SaveManager: " + message)
	return false

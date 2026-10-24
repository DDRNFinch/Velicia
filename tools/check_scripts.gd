extends Node
## Compiles every GDScript and loads every scene/resource in the project to
## catch parse errors and broken references. Runs as a scene so autoloads exist:
##   godot --headless res://tools/check_scripts.tscn
## Exit code = number of files that failed.

var failures := 0
var checked := 0


func _ready() -> void:
	_scan("res://")
	print("check_scripts: %d files checked, %d failed" % [checked, failures])
	get_tree().quit(failures)


func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		if d.begins_with(".") or d == "addons" or d == "build":
			continue
		_scan(path.path_join(d))
	for f in dir.get_files():
		var full := path.path_join(f)
		if f.ends_with(".gd"):
			checked += 1
			var s := load(full) as GDScript
			if s == null or not s.can_instantiate() and not _is_static_only(s):
				print("FAILED: ", full)
				failures += 1
		elif f.ends_with(".tscn") or f.ends_with(".tres"):
			checked += 1
			var r := ResourceLoader.load(full, "", ResourceLoader.CACHE_MODE_REUSE)
			if r == null:
				print("FAILED: ", full)
				failures += 1


func _is_static_only(s: GDScript) -> bool:
	return s != null and s.get_instance_base_type() != &""

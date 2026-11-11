extends Node
## Player settings persisted to user://settings.cfg and applied live.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"audio": {
		"master": 1.0,
		"music": 0.6,
		"sfx": 0.9,
		"ambient": 0.7,
		"ui": 0.8,
	},
	"graphics": {
		"quality": "medium", # low / medium / high
		"render_scale": 1.0,
		"shadows": true,
		"view_distance": 150.0,
		"fps_cap": 60,
		"show_fps": false,
		"day_night": true,
	},
	"controls": {
		"look_sensitivity": 1.0,
		"invert_y": false,
		"touch_mode": "auto", # auto / on / off
		"button_scale": 1.0,
		"button_opacity": 0.75,
		"toggle_block": false,
		"auto_target": true,
	},
	"accessibility": {
		"screen_shake": true,
		"hitstop": true,
		"combat_assist": false, # wider parry window, stronger soft-targeting
		"telegraph_color": "red", # red / yellow / magenta
		"ui_scale": 1.0,
	},
}

const TELEGRAPH_COLORS := {
	"red": Color(1.0, 0.25, 0.15),
	"yellow": Color(1.0, 0.85, 0.1),
	"magenta": Color(1.0, 0.2, 0.9),
}

var _values: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = DEFAULTS.duplicate(true)
	if OS.has_feature("mobile") and not FileAccess.file_exists(PATH):
		# First run on a phone: start on the lightest settings (no grass, no
		# shadows, lower resolution). Raise them in Settings if it runs well.
		_values["graphics"]["quality"] = "low"
		_values["graphics"]["shadows"] = false
		_values["graphics"]["render_scale"] = 0.75
		_values["graphics"]["view_distance"] = 100.0
	load_settings()
	apply_all.call_deferred()


func get_value(section: String, key: String):
	if _values.has(section) and _values[section].has(key):
		return _values[section][key]
	return DEFAULTS.get(section, {}).get(key)


func set_value(section: String, key: String, value) -> void:
	if not _values.has(section):
		_values[section] = {}
	_values[section][key] = value
	save_settings()
	_apply(section, key)
	changed.emit(section, key)


func telegraph_color() -> Color:
	return TELEGRAPH_COLORS.get(get_value("accessibility", "telegraph_color"), Color.RED)


## True while the player is using a gamepad (any pad button or stick); a
## screen touch switches back. The HUD hides the touch buttons meanwhile.
var using_gamepad := false
var gamepad_id := 0


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if pad and not using_gamepad:
		using_gamepad = true
		gamepad_id = event.device
		changed.emit("controls", "device")
	elif event is InputEventScreenTouch and using_gamepad:
		using_gamepad = false
		changed.emit("controls", "device")


func touch_controls_enabled() -> bool:
	match String(get_value("controls", "touch_mode")):
		"on":
			return true
		"off":
			return false
	if using_gamepad:
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if cfg.has_section_key(section, key):
				var v = cfg.get_value(section, key)
				# Ignore values of the wrong type from older/corrupt files.
				if typeof(v) == typeof(DEFAULTS[section][key]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(DEFAULTS[section][key]) in [TYPE_INT, TYPE_FLOAT]):
					_values[section][key] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in _values:
		for key in _values[section]:
			cfg.set_value(section, key, _values[section][key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	save_settings()
	apply_all()
	changed.emit("", "")


func apply_all() -> void:
	for section in _values:
		for key in _values[section]:
			_apply(section, key)


func _apply(section: String, key: String) -> void:
	match section:
		"audio":
			AudioManager.set_bus_volume(key, float(get_value(section, key)))
		"graphics":
			if key == "fps_cap":
				Engine.max_fps = int(get_value(section, key))
			elif key == "render_scale":
				# Render the 3D world at a lower resolution (UI stays sharp).
				get_tree().root.scaling_3d_scale = clampf(float(get_value(section, key)), 0.5, 1.0)
		"accessibility":
			if key == "ui_scale":
				get_tree().root.content_scale_factor = clampf(float(get_value(section, key)), 0.75, 1.5)

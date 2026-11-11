class_name SettingsPanel
extends ScrollContainer
## Audio, graphics, control and accessibility settings. Shared by the main
## menu and the in-game menu. Every row writes straight to Settings.

const ROWS := [
	["Audio"],
	["audio", "master", "Master volume", "slider", 0.0, 1.0],
	["audio", "music", "Music", "slider", 0.0, 1.0],
	["audio", "sfx", "Effects", "slider", 0.0, 1.0],
	["audio", "ambient", "Ambience", "slider", 0.0, 1.0],
	["audio", "ui", "Interface sounds", "slider", 0.0, 1.0],
	["Graphics"],
	["graphics", "quality", "Quality preset (applies on region load)", "options", ["low", "medium", "high"]],
	["graphics", "shadows", "Shadows", "toggle"],
	["graphics", "view_distance", "View distance", "slider", 80.0, 260.0],
	["graphics", "fps_cap", "Frame rate cap", "options", [30, 60, 90, 120]],
	["graphics", "day_night", "Day and night cycle", "toggle"],
	["graphics", "show_fps", "Show FPS", "toggle"],
	["Controls"],
	["controls", "look_sensitivity", "Camera sensitivity", "slider", 0.2, 3.0],
	["controls", "invert_y", "Invert camera Y", "toggle"],
	["controls", "touch_mode", "Touch controls", "options", ["auto", "on", "off"]],
	["controls", "button_scale", "Touch button size", "slider", 0.7, 1.4],
	["controls", "button_opacity", "Touch button opacity", "slider", 0.25, 1.0],
	["controls", "toggle_block", "Block: tap to toggle (instead of hold)", "toggle"],
	["controls", "auto_target", "Auto-face nearby enemies when attacking", "toggle"],
	["Accessibility"],
	["accessibility", "combat_assist", "Combat assist (wider parry window, stronger targeting)", "toggle"],
	["accessibility", "screen_shake", "Screen shake", "toggle"],
	["accessibility", "hitstop", "Impact pause (hitstop)", "toggle"],
	["accessibility", "telegraph_color", "Enemy attack warning colour", "options", ["red", "yellow", "magenta"]],
	["accessibility", "ui_scale", "Interface scale", "slider", 0.75, 1.4],
]


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	for row in ROWS:
		if row.size() == 1:
			v.add_child(UiTheme.label(row[0], 24, UiTheme.GOLD))
			continue
		v.add_child(_make_row(row))
	v.add_child(UiTheme.button("Reset to defaults", func():
		Settings.reset_to_defaults()
		_rebuild()))


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_ready()


func _make_row(row: Array) -> Control:
	var section: String = row[0]
	var key: String = row[1]
	var h := HBoxContainer.new()
	var l := UiTheme.label(row[2], 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var value = Settings.get_value(section, key)
	match String(row[3]):
		"slider":
			var s := HSlider.new()
			s.min_value = row[4]
			s.max_value = row[5]
			s.step = (float(row[5]) - float(row[4])) / 100.0
			s.value = float(value)
			s.custom_minimum_size = Vector2(260, 44)
			var readout := UiTheme.label("", 18, UiTheme.TEXT_DIM)
			readout.custom_minimum_size = Vector2(64, 0)
			readout.text = _fmt(s.value, float(row[5]))
			s.value_changed.connect(func(x):
				readout.text = _fmt(x, float(row[5]))
				Settings.set_value(section, key, x))
			h.add_child(s)
			h.add_child(readout)
		"toggle":
			var c := CheckButton.new()
			c.button_pressed = bool(value)
			c.custom_minimum_size = Vector2(80, 44)
			c.toggled.connect(func(on): Settings.set_value(section, key, on))
			h.add_child(c)
		"options":
			var o := OptionButton.new()
			var opts: Array = row[4]
			for i in opts.size():
				o.add_item(str(opts[i]).capitalize())
				if str(opts[i]) == str(value):
					o.select(i)
			o.custom_minimum_size = Vector2(200, 48)
			o.item_selected.connect(func(i): Settings.set_value(section, key, opts[i]))
			h.add_child(o)
	return h


static func _fmt(v: float, max_v: float) -> String:
	if max_v <= 1.0:
		return "%d%%" % roundi(v * 100.0)
	if max_v <= 3.0:
		return "%.2f" % v
	return "%d" % roundi(v)

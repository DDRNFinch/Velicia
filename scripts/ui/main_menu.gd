extends Control
## Title screen: continue, new game (with Emoria warrior customisation),
## settings and about/credits.

var _main: VBoxContainer
var _creator: Control
var _settings: Control
var _about: Control
var _appearance: Dictionary = GameState.default_appearance()
var _preview_body: PlaceholderBody
var _preview_pivot: Node3D
var _labels: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameState.session_active = false
	get_tree().paused = false
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.09)
	add_child(bg)
	_add_backdrop()
	var title := UiTheme.label("VELICIA", 84, UiTheme.GOLD)
	title.custom_minimum_size = Vector2(440, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.place(title, Control.PRESET_CENTER_TOP, Vector2(-220, 40))
	add_child(title)
	var sub := UiTheme.label("Rings of the Emoria Guild  ·  prototype build", 22, UiTheme.TEXT_DIM)
	sub.custom_minimum_size = Vector2(600, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.place(sub, Control.PRESET_CENTER_TOP, Vector2(-300, 140))
	add_child(sub)

	_main = VBoxContainer.new()
	_main.custom_minimum_size = Vector2(340, 0)
	UiTheme.place(_main, Control.PRESET_CENTER, Vector2(-170, -60))
	add_child(_main)
	var cont := UiTheme.button("Continue", _on_continue)
	cont.disabled = not SaveManager.has_save()
	if cont.disabled:
		cont.text = "Continue (no save)"
	else:
		var s := SaveManager.read_summary()
		if not s.is_empty():
			cont.text = "Continue · Lv %d" % int(s.get("level", 1))
	_main.add_child(cont)
	_main.add_child(UiTheme.button("New game", _show_creator))
	_main.add_child(UiTheme.button("Settings", func(): _show(_settings)))
	_main.add_child(UiTheme.button("About", func(): _show(_about)))
	if not OS.has_feature("web"):
		_main.add_child(UiTheme.button("Quit", func(): get_tree().quit()))

	_build_creator()
	_build_settings()
	_build_about()
	AudioManager.play_music("exploration")
	AudioManager.stop_ambient()
	if not cont.disabled:
		cont.grab_focus.call_deferred()


func _add_backdrop() -> void:
	# A slowly turning ring motif behind the title.
	var ring := Control.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func():
		var c := ring.size * 0.5 + Vector2(0, 40)
		var t := Time.get_ticks_msec() / 1000.0
		for i in 3:
			var r := 230.0 + i * 46.0
			draw_ring(ring, c, r, t * (0.15 + i * 0.07) * (1 if i % 2 == 0 else -1), Color(UiTheme.GOLD, 0.12 - i * 0.03)))
	add_child(ring)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(ring.queue_redraw)
	add_child(timer)


static func draw_ring(ci: CanvasItem, c: Vector2, r: float, rot: float, col: Color) -> void:
	ci.draw_arc(c, r, rot, rot + TAU * 0.8, 64, col, 4.0, true)
	for k in 12:
		var a := rot + TAU * k / 12.0
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * r, 5.0, col)


func _show(panel: Control) -> void:
	for p in [_main, _creator, _settings, _about]:
		p.visible = p == panel


func _on_continue() -> void:
	if not GameState.continue_game():
		_main.add_child(UiTheme.label("Could not load save: " + SaveManager.last_error, 18, UiTheme.DANGER))


func _show_creator() -> void:
	_show(_creator)


# ---------------------------------------------------------- Character creator

func _build_creator() -> void:
	_creator = PanelContainer.new()
	_creator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_creator.offset_left = 40
	_creator.offset_right = -40
	_creator.offset_top = 190
	_creator.offset_bottom = -30
	_creator.visible = false
	add_child(_creator)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	_creator.add_child(h)

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.custom_minimum_size = Vector2(360, 420)
	h.add_child(vpc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vpc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, 3.2)
	cam.rotation.x = -0.12
	cam.fov = 45
	vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	_preview_pivot = Node3D.new()
	vp.add_child(_preview_pivot)
	_preview_body = PlaceholderBody.new()
	_preview_pivot.add_child(_preview_body)
	_preview_pivot.rotation.y = PI

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiTheme.title("Your Emoria warrior"))
	var intro := UiTheme.label("You are a sworn warrior of the ancient Emoria Guild, keeper of the rings. Choose how you appear; your story is your own.", 18, UiTheme.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	_option_row(v, "skin", "Skin tone", PlayerAppearance.SKIN_TONES.size())
	_option_row(v, "hair", "Hair colour", PlayerAppearance.HAIR_COLORS.size())
	_option_row(v, "hair_style", "Hair style", PlayerAppearance.HAIR_STYLES.size())
	_option_row(v, "cloak", "Guild cloak", PlayerAppearance.CLOAK_COLORS.size())
	_option_row(v, "build", "Build", PlayerAppearance.BUILDS.size())
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(UiTheme.button("Back", func(): _show(_main), 160))
	var begin := UiTheme.button("Begin your watch", func(): GameState.start_new_game(_appearance), 320)
	row.add_child(begin)
	if SaveManager.has_save():
		v.add_child(UiTheme.label("Starting a new game replaces your current save when you next save.", 16, UiTheme.DANGER))
	_refresh_preview()


func _option_row(parent: Control, key: String, title_text: String, count: int) -> void:
	var row := HBoxContainer.new()
	var l := UiTheme.label(title_text, 20)
	l.custom_minimum_size = Vector2(180, 0)
	row.add_child(l)
	row.add_child(UiTheme.button("◀", func(): _step(key, -1, count), 60))
	var value := UiTheme.label("", 20, UiTheme.GOLD)
	value.custom_minimum_size = Vector2(150, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	_labels[key] = value
	row.add_child(UiTheme.button("▶", func(): _step(key, 1, count), 60))
	parent.add_child(row)


func _step(key: String, d: int, count: int) -> void:
	_appearance[key] = posmod(int(_appearance.get(key, 0)) + d, count)
	_refresh_preview()


func _refresh_preview() -> void:
	_preview_body.build(PlayerAppearance.to_body_params(_appearance, Color(0.45, 0.38, 0.3), &"sword"))
	for key in _labels:
		var idx := int(_appearance.get(key, 0))
		var text := "%d" % (idx + 1)
		if key == "build":
			text = PlayerAppearance.BUILDS[idx].name
		elif key == "hair_style":
			text = PlayerAppearance.HAIR_STYLE_NAMES[idx]
		(_labels[key] as Label).text = text


func _process(delta: float) -> void:
	if _preview_pivot and _creator.visible:
		_preview_pivot.rotation.y += delta * 0.6
		_preview_body.animate(delta, 0.0, 5.0, true)


# ------------------------------------------------------------------ Other

func _build_settings() -> void:
	_settings = PanelContainer.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.offset_left = 120
	_settings.offset_right = -120
	_settings.offset_top = 190
	_settings.offset_bottom = -30
	_settings.visible = false
	add_child(_settings)
	var v := VBoxContainer.new()
	_settings.add_child(v)
	v.add_child(SettingsPanel.new())
	v.add_child(UiTheme.button("Back", func(): _show(_main), 200))


func _build_about() -> void:
	_about = PanelContainer.new()
	_about.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_about.offset_left = 120
	_about.offset_right = -120
	_about.offset_top = 190
	_about.offset_bottom = -30
	_about.visible = false
	add_child(_about)
	var v := VBoxContainer.new()
	_about.add_child(v)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 19)
	text.text = "[color=#dbb55c][b]Velicia[/b][/color] — an original fantasy action RPG.\n\nThis is an early prototype. Characters, creatures and buildings are [b]placeholder art[/b] built from simple shapes; the temporary test creatures will be replaced by the official creature roster. Story text marked as draft is awaiting approval.\n\nBuilt with Godot Engine (MIT licence). All sounds and music in this build are procedurally generated originals. See docs/ASSET_LICENSES.md for details.\n\nVersion %s" % ProjectSettings.get_setting("application/config/version", "0")
	v.add_child(text)
	v.add_child(UiTheme.button("Back", func(): _show(_main), 200))

class_name HUD
extends CanvasLayer
## In-game interface: health/stamina, companion and target bars, boss bar,
## quest tracker, notifications, interaction prompt, ring slots and capture
## button, dialogue box, shrine/training/lore panels and the death screen.
## Built in code from UiTheme so artwork can be swapped in one place.

signal menu_requested(tab: String)

var player: Player
var game: Node
var touch: TouchControls
var dialogue: DialogueRunner

var _root: Control
var _health: ProgressBar
var _hearts: HeartsDisplay
var _stamina: ProgressBar
var _level_label: Label
var _companion_box: VBoxContainer
var _companion_label: Label
var _companion_bar: ProgressBar
var _target_box: VBoxContainer
var _target_label: Label
var _target_bar: ProgressBar
var _boss_box: VBoxContainer
var _boss_label: Label
var _boss_bar: ProgressBar
var _boss: Node
var _quest_box: VBoxContainer
var _quest_title: Label
var _quest_lines: Label
var _notes: VBoxContainer
var _prompt: Button
var _capture_button: Button
var _ring_row: HBoxContainer
var _ring_buttons: Array[Button] = []
var _menu_button: Button
var _dialogue_panel: PanelContainer
var _dialogue_speaker: Label
var _dialogue_text: RichTextLabel
var _dialogue_choices: VBoxContainer
var _modal: PanelContainer
var _modal_title: Label
var _modal_body: RichTextLabel
var _modal_buttons: VBoxContainer
var _death: Control
var _fps: Label
var _hint: Label
var _capture_progress: ProgressBar
var _skill_label: Label
var _dialogue_speaker_node: Node


func setup(p: Player, g: Node) -> void:
	player = p
	game = g
	player.stats.health_changed.connect(_on_health)
	player.stats.stamina_changed.connect(_on_stamina)
	player.interactable_changed.connect(_on_interactable)
	player.target_changed.connect(_on_target)
	player.rings.changed.connect(_refresh_rings)
	_on_health(player.stats.health, player.stats.max_health)
	_on_stamina(player.stats.stamina, player.stats.max_stamina)
	_refresh_rings()
	_refresh_quest()
	_refresh_level()


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_status()
	_build_target()
	_build_quest()
	_build_notes()
	_build_prompt()
	_build_rings()
	touch = TouchControls.new()
	_root.add_child(touch)
	touch.register_target(_menu_button, func(): menu_requested.emit("inventory"))
	touch.register_target(_prompt, _on_prompt_pressed)
	touch.register_target(_capture_button, _on_capture_pressed)
	for i in _ring_buttons.size():
		var slot := i
		touch.register_target(_ring_buttons[i], func(): _on_ring_pressed(slot))
	_build_dialogue()
	_build_modal()
	_build_death()
	_fps = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	_fps.position = Vector2(14, 6)
	_root.add_child(_fps)
	_hint = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	UiTheme.place(_hint, Control.PRESET_BOTTOM_LEFT, Vector2(16, -60))
	_root.add_child(_hint)

	EventBus.notify.connect(show_note)
	EventBus.quest_updated.connect(_on_quest_updated)
	EventBus.creatures_changed.connect(_refresh_rings)
	EventBus.boss_engaged.connect(_on_boss)
	EventBus.request_dialogue.connect(start_dialogue)
	EventBus.request_panel.connect(open_panel)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_stats_changed.connect(_refresh_level)
	EventBus.level_up.connect(_on_level_up)
	Settings.changed.connect(_on_settings_changed)
	_apply_touch_mode()


func _on_quest_updated(_q: StringName) -> void:
	_refresh_quest()


func _on_level_up(_l: int) -> void:
	_refresh_level()


func _on_settings_changed(_section: String, _key: String) -> void:
	_apply_touch_mode()


func _apply_touch_mode() -> void:
	var on := Settings.touch_controls_enabled()
	touch.visible = on and not _dialogue_panel.visible and not _modal.visible and not _death.visible
	for c in [_prompt, _capture_button, _menu_button] + _ring_buttons:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	_hint.visible = not on
	_hint.text = "WASD move · J attack · K heavy (hold to charge) · Q shield (tap to parry) · C roll · R spin\nE talk · G summon ring creature · F bind creature · V next ring · H command · Tab lock-on · 1 heal · Esc menu"


# ------------------------------------------------------------------ Build

func _build_status() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 28)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_hearts = HeartsDisplay.new()
	box.add_child(_hearts)
	_health = UiTheme.make_bar(UiTheme.HEALTH, 300, 20)
	_health.visible = false
	box.add_child(_health)
	_stamina = UiTheme.make_bar(UiTheme.STAMINA, 180, 8)
	box.add_child(_stamina)
	_level_label = UiTheme.label("Emoria Warrior · Lv 1", 16, UiTheme.GOLD)
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_level_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_level_label)
	_skill_label = UiTheme.label("", 15, UiTheme.TEXT_DIM)
	box.add_child(_skill_label)
	_companion_box = VBoxContainer.new()
	_companion_box.add_theme_constant_override("separation", 2)
	_companion_box.visible = false
	box.add_child(_companion_box)
	_companion_label = UiTheme.label("", 16, UiTheme.RING)
	_companion_box.add_child(_companion_label)
	_companion_bar = UiTheme.make_bar(UiTheme.RING, 220, 10)
	_companion_box.add_child(_companion_bar)


func _build_target() -> void:
	_target_box = VBoxContainer.new()
	_target_box.custom_minimum_size = Vector2(320, 0)
	_target_box.add_theme_constant_override("separation", 2)
	_target_box.visible = false
	UiTheme.place(_target_box, Control.PRESET_CENTER_TOP, Vector2(-160, 24))
	_root.add_child(_target_box)
	_target_label = UiTheme.label("", 18)
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_box.add_child(_target_label)
	_target_bar = UiTheme.make_bar(UiTheme.DANGER, 320, 10)
	_target_box.add_child(_target_bar)
	_boss_box = VBoxContainer.new()
	_boss_box.custom_minimum_size = Vector2(600, 0)
	_boss_box.visible = false
	UiTheme.place(_boss_box, Control.PRESET_CENTER_TOP, Vector2(-300, 86))
	_root.add_child(_boss_box)
	_boss_label = UiTheme.label("", 22, UiTheme.GOLD)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_label)
	_boss_bar = UiTheme.make_bar(Color(0.7, 0.15, 0.12), 600, 18)
	_boss_box.add_child(_boss_bar)


func _build_quest() -> void:
	_menu_button = Button.new()
	_menu_button.text = "☰"
	_menu_button.custom_minimum_size = Vector2(64, 64)
	_menu_button.pressed.connect(func(): menu_requested.emit("inventory"))
	UiTheme.place(_menu_button, Control.PRESET_TOP_RIGHT, Vector2(-80, 16))
	_root.add_child(_menu_button)
	_quest_box = VBoxContainer.new()
	_quest_box.custom_minimum_size = Vector2(330, 0)
	_quest_box.add_theme_constant_override("separation", 2)
	UiTheme.place(_quest_box, Control.PRESET_TOP_RIGHT, Vector2(-420, 22))
	_root.add_child(_quest_box)
	_quest_title = UiTheme.label("", 19, UiTheme.GOLD)
	_quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_title.custom_minimum_size = Vector2(330, 0)
	_quest_box.add_child(_quest_title)
	_quest_lines = UiTheme.label("", 16)
	_quest_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quest_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_lines.custom_minimum_size = Vector2(330, 0)
	_quest_box.add_child(_quest_lines)


func _build_notes() -> void:
	_notes = VBoxContainer.new()
	_notes.custom_minimum_size = Vector2(420, 0)
	_notes.add_theme_constant_override("separation", 4)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.place(_notes, Control.PRESET_CENTER_LEFT, Vector2(16, -60))
	_root.add_child(_notes)


func _build_prompt() -> void:
	_prompt = Button.new()
	_prompt.custom_minimum_size = Vector2(320, 60)
	_prompt.visible = false
	_prompt.pressed.connect(_on_prompt_pressed)
	UiTheme.place(_prompt, Control.PRESET_CENTER_BOTTOM, Vector2(-160, -190))
	_root.add_child(_prompt)
	_capture_button = Button.new()
	_capture_button.custom_minimum_size = Vector2(250, 64)
	_capture_button.add_theme_stylebox_override("normal", UiTheme.button_style(Color(0.1, 0.25, 0.3, 0.9), UiTheme.RING))
	_capture_button.visible = false
	_capture_button.pressed.connect(_on_capture_pressed)
	UiTheme.place(_capture_button, Control.PRESET_TOP_RIGHT, Vector2(-336, 232))
	_root.add_child(_capture_button)
	_capture_progress = UiTheme.make_bar(UiTheme.RING, 300, 14)
	_capture_progress.visible = false
	UiTheme.place(_capture_progress, Control.PRESET_CENTER, Vector2(-150, 80))
	_root.add_child(_capture_progress)


func _build_rings() -> void:
	_ring_row = HBoxContainer.new()
	_ring_row.custom_minimum_size = Vector2(244, 64)
	_ring_row.add_theme_constant_override("separation", 8)
	UiTheme.place(_ring_row, Control.PRESET_TOP_RIGHT, Vector2(-336, 156))
	_root.add_child(_ring_row)
	for i in GameState.MAX_RING_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(76, 64)
		b.add_theme_font_size_override("font_size", 15)
		var slot := i
		b.pressed.connect(func(): _on_ring_pressed(slot))
		_ring_row.add_child(b)
		_ring_buttons.append(b)


func _build_dialogue() -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue_panel.offset_left = 40
	_dialogue_panel.offset_right = -40
	_dialogue_panel.offset_top = -330
	_dialogue_panel.offset_bottom = -12
	_dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue_panel.visible = false
	_root.add_child(_dialogue_panel)
	var v := VBoxContainer.new()
	_dialogue_panel.add_child(v)
	_dialogue_speaker = UiTheme.label("", 24, UiTheme.GOLD)
	v.add_child(_dialogue_speaker)
	_dialogue_text = RichTextLabel.new()
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.fit_content = true
	_dialogue_text.scroll_active = false
	_dialogue_text.add_theme_font_size_override("normal_font_size", 22)
	_dialogue_text.custom_minimum_size = Vector2(0, 70)
	v.add_child(_dialogue_text)
	_dialogue_choices = VBoxContainer.new()
	_dialogue_choices.add_theme_constant_override("separation", 6)
	v.add_child(_dialogue_choices)


func _build_modal() -> void:
	_modal = PanelContainer.new()
	_modal.custom_minimum_size = Vector2(620, 0)
	_modal.visible = false
	UiTheme.place(_modal, Control.PRESET_CENTER, Vector2(-310, -250))
	_root.add_child(_modal)
	var v := VBoxContainer.new()
	_modal.add_child(v)
	_modal_title = UiTheme.title("")
	v.add_child(_modal_title)
	_modal_body = RichTextLabel.new()
	_modal_body.bbcode_enabled = true
	_modal_body.fit_content = true
	_modal_body.custom_minimum_size = Vector2(580, 60)
	_modal_body.add_theme_font_size_override("normal_font_size", 20)
	v.add_child(_modal_body)
	_modal_buttons = VBoxContainer.new()
	v.add_child(_modal_buttons)


func _build_death() -> void:
	_death = ColorRect.new()
	(_death as ColorRect).color = Color(0.05, 0.0, 0.0, 0.7)
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.visible = false
	_root.add_child(_death)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(400, 0)
	UiTheme.place(v, Control.PRESET_CENTER, Vector2(-200, -90))
	_death.add_child(v)
	var t := UiTheme.label("You have fallen", 42, Color(0.9, 0.35, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UiTheme.label("The Ring Stone will restore you.", 20, UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UiTheme.button("Rise again", func():
		_death.visible = false
		_apply_touch_mode()
		if game and game.has_method("respawn_player"):
			game.respawn_player()))


# ---------------------------------------------------------------- Update

func _process(_delta: float) -> void:
	if player == null:
		return
	if Settings.get_value("graphics", "show_fps"):
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	else:
		_fps.text = ""
	_update_target_bar()
	_update_companion()
	_update_capture()
	_update_skill()
	if _boss and is_instance_valid(_boss) and _boss.global_position.distance_to(player.global_position) < 55.0 and not _boss.is_dead():
		_boss_box.visible = true
		_boss_bar.value = _boss.stats.health_fraction() * 100.0
		var phase := int(_boss.phase_index) + 1
		_boss_label.text = "%s%s" % [_boss.definition.display_name, "  ·  Phase %d" % phase if _boss.definition.phases.size() > 1 else ""]
	elif _boss_box.visible:
		_boss_box.visible = false
	touch.labels_override["summon"] = "DISMISS" if player.rings.companion else "SUMMON"
	touch.dimmed["companion_command"] = player.rings.companion == null
	touch.dimmed["skill"] = player.skill_cooldown() > 0.0
	if Engine.get_process_frames() % 6 == 0:
		touch.queue_redraw()


func _on_health(h: float, m: float) -> void:
	_health.max_value = m
	_health.value = h
	_hearts.set_health(h, m)


func _on_stamina(s: float, m: float) -> void:
	_stamina.max_value = m
	_stamina.value = s


func _refresh_level() -> void:
	_level_label.text = "Emoria Warrior · Lv %d" % GameState.get_level()
	if int(GameState.player.stat_points) > 0:
		_level_label.text += "  (+%d points)" % int(GameState.player.stat_points)


func _update_skill() -> void:
	var ab := Database.ability(GameState.player.get("equipped_skill", ""))
	if ab == null:
		_skill_label.text = ""
		return
	if not GameState.has_ability(ab.id):
		_skill_label.text = "Skill: %s (Lv %d)" % [ab.display_name, ab.unlock_level]
	elif player.skill_cooldown() > 0.0:
		_skill_label.text = "Skill: %s  %.0fs" % [ab.display_name, ceilf(player.skill_cooldown())]
	else:
		_skill_label.text = "Skill: %s  ready" % ab.display_name


func _on_target(_t) -> void:
	_update_target_bar()


func _update_target_bar() -> void:
	var t := player.current_target()
	if t == null or t == _boss or not ("stats" in t):
		_target_box.visible = false
		return
	_target_box.visible = true
	var title_text := ""
	if t is Enemy:
		title_text = (t as Enemy).definition.display_name
	elif t is CreatureActor:
		var c := t as CreatureActor
		title_text = "%s  Lv %d%s" % [c.definition.display_name, c.level, "  (wild)" if c.mode == CreatureActor.Mode.WILD else ""]
	if player.lock_target:
		title_text = "◎ " + title_text
	_target_label.text = title_text
	_target_bar.value = t.stats.health_fraction() * 100.0


func _update_companion() -> void:
	var c := player.rings.companion
	if c and is_instance_valid(c) and c.instance:
		_companion_box.visible = true
		_companion_label.text = "%s · Lv %d%s" % [c.instance.display_name(), c.level, " · holding" if c.is_holding() else ""]
		_companion_bar.value = c.stats.health_fraction() * 100.0
	else:
		_companion_box.visible = false


func _update_capture() -> void:
	var rc := player.rings
	if rc.is_capturing():
		_capture_progress.visible = true
		_capture_progress.value = rc.capture_progress() * 100.0
		_capture_button.visible = false
		return
	_capture_progress.visible = false
	var c := rc.capture_candidate() if player.state == Player.State.MOVE else null
	if c:
		_capture_button.visible = true
		var reason := rc.can_capture_reason(c)
		if reason.is_empty():
			_capture_button.text = "✦ CAPTURE  %d%%" % roundi(rc.capture_chance(c) * 100.0)
		else:
			_capture_button.text = reason
	else:
		_capture_button.visible = false


func _refresh_rings() -> void:
	if player == null:
		return
	for i in _ring_buttons.size():
		var b := _ring_buttons[i]
		if i >= GameState.ring_slots.size():
			b.visible = false
			continue
		b.visible = true
		var inst := GameState.creature_in_slot(i)
		var selected := i == GameState.active_ring
		var col := UiTheme.GOLD_DIM
		var text := "Empty"
		if inst:
			var def := inst.definition()
			col = def.accent_color if def else UiTheme.RING
			text = inst.display_name().substr(0, 9)
			if inst.is_exhausted():
				text += "\n(rest)"
				col = col.darkened(0.5)
			elif player.rings.companion and player.rings.companion.instance == inst:
				text += "\n★ out"
		b.text = text
		var bg := Color(0.12, 0.14, 0.2, 0.9) if not selected else Color(0.22, 0.2, 0.12, 0.95)
		b.add_theme_stylebox_override("normal", UiTheme.button_style(bg, col if selected else col.darkened(0.3)))
		b.add_theme_stylebox_override("hover", UiTheme.button_style(bg.lightened(0.1), col))


func _on_ring_pressed(slot: int) -> void:
	if slot == GameState.active_ring and GameState.creature_in_slot(slot):
		player.rings.toggle_summon()
	else:
		player.rings.select_ring(slot)
	AudioManager.play_ui()


func _on_capture_pressed() -> void:
	var c := player.rings.capture_candidate()
	if c:
		player.rings.try_capture(c)


func _on_interactable(n: Node) -> void:
	if n and is_instance_valid(n) and n.has_method("get_prompt"):
		_prompt.text = ("[E]  " if not Settings.touch_controls_enabled() else "") + n.get_prompt()
		_prompt.visible = not _dialogue_panel.visible
	else:
		_prompt.visible = false


func _on_prompt_pressed() -> void:
	player.interact()


func _refresh_quest() -> void:
	var id := GameState.tracked_quest
	var def := Database.quest(id)
	if def == null or not QuestManager.is_active(id):
		_quest_title.text = ""
		_quest_lines.text = ""
		return
	_quest_title.text = ("◆ " if def.is_main else "◇ ") + def.title
	_quest_lines.text = "\n".join(QuestManager.objective_lines(id))


func show_note(text: String) -> void:
	var l := UiTheme.label(text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.06, 0.08, 0.78), UiTheme.GOLD_DIM))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
	_notes.add_child(panel)
	while _notes.get_child_count() > 4:
		_notes.get_child(0).queue_free()
		_notes.remove_child(_notes.get_child(0))
	var tw := panel.create_tween()
	tw.tween_interval(3.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(panel.queue_free)


func _on_boss(boss: Node) -> void:
	_boss = boss
	_boss_box.visible = boss != null and is_instance_valid(boss)


func _on_player_died() -> void:
	await get_tree().create_timer(1.6).timeout
	close_dialogue()
	close_modal()
	_death.visible = true
	_apply_touch_mode()


func is_blocking_ui() -> bool:
	return _dialogue_panel.visible or _modal.visible or _death.visible


# --------------------------------------------------------------- Dialogue

func start_dialogue(id: String, speaker: Node) -> void:
	dialogue = DialogueRunner.new()
	_dialogue_speaker_node = speaker
	if not dialogue.start(id, speaker):
		dialogue = null
		if speaker and speaker.has_method("end_talk"):
			speaker.end_talk()
		return
	player.input_enabled = false
	_dialogue_panel.visible = true
	_prompt.visible = false
	_apply_touch_mode()
	_show_dialogue_node()


func _show_dialogue_node() -> void:
	if dialogue == null or dialogue.finished:
		close_dialogue()
		return
	_dialogue_speaker.text = dialogue.speaker_name()
	_dialogue_text.text = dialogue.text()
	for c in _dialogue_choices.get_children():
		_dialogue_choices.remove_child(c)
		c.queue_free()
	var choices := dialogue.choices()
	if choices.is_empty():
		var label := "Continue" if String(dialogue.current().get("next", "end")) != "end" else "Farewell"
		_dialogue_choices.add_child(UiTheme.button(label, func():
			dialogue.advance()
			_show_dialogue_node()))
	else:
		for i in choices.size():
			var idx := i
			var b := UiTheme.button("%d. %s" % [i + 1, choices[i].get("text", "...")], func():
				dialogue.choose(idx)
				_show_dialogue_node())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size.y = 50
			b.add_theme_font_size_override("font_size", 20)
			_dialogue_choices.add_child(b)
	if not Settings.touch_controls_enabled() and _dialogue_choices.get_child_count() > 0:
		(_dialogue_choices.get_child(0) as Button).grab_focus.call_deferred()


func close_dialogue() -> void:
	if not _dialogue_panel.visible:
		return
	_dialogue_panel.visible = false
	var panels := dialogue.pending_panels if dialogue else PackedStringArray()
	var id := dialogue.dialogue_id if dialogue else ""
	dialogue = null
	if player:
		player.input_enabled = true
	if _dialogue_speaker_node and is_instance_valid(_dialogue_speaker_node):
		if _dialogue_speaker_node.has_method("end_talk"):
			_dialogue_speaker_node.end_talk()
		var npc_id = _dialogue_speaker_node.get("npc_id")
		if npc_id != null:
			EventBus.talked_to.emit(StringName(npc_id))
	_dialogue_speaker_node = null
	_apply_touch_mode()
	for p in panels:
		open_panel(p, {"player": player})
	if id.is_empty():
		return


func dialogue_active() -> bool:
	return _dialogue_panel.visible


## Test/automation helper: choose a dialogue option by index.
func dialogue_choose(index: int) -> void:
	if dialogue == null:
		return
	if dialogue.choices().is_empty():
		dialogue.advance()
	else:
		dialogue.choose(index)
	_show_dialogue_node()


# ------------------------------------------------------------------ Panels

func open_panel(panel_id: String, context: Dictionary) -> void:
	match panel_id:
		"shrine":
			_open_shrine(context)
		"training":
			_open_training()
		"lore":
			_open_lore(String(context.get("id", "")))


func _show_modal(title_text: String, body: String) -> void:
	_modal_title.text = title_text
	_modal_body.text = body
	for c in _modal_buttons.get_children():
		_modal_buttons.remove_child(c)
		c.queue_free()
	_modal.visible = true
	_prompt.visible = false
	if player:
		player.input_enabled = false
	_apply_touch_mode()


func close_modal() -> void:
	if not _modal.visible:
		return
	_modal.visible = false
	if player and not _dialogue_panel.visible:
		player.input_enabled = true
	_apply_touch_mode()


func modal_active() -> bool:
	return _modal.visible


func _open_shrine(context: Dictionary) -> void:
	var shrine: SaveShrine = context.get("shrine")
	_show_modal(shrine.display_name if shrine else "Ring Stone", "The stone hums with old Emoria magic. Resting restores you and your creatures, and saves your journey.")
	_modal_buttons.add_child(UiTheme.button("Rest and save", func():
		if shrine:
			shrine.rest(player)
		_refresh_rings()
		close_modal()))
	_modal_buttons.add_child(UiTheme.button("Manage rings and vault", func():
		close_modal()
		GameState.set_meta("at_shrine", true)
		menu_requested.emit("creatures")))
	_modal_buttons.add_child(UiTheme.button("Leave", close_modal))


func _open_training() -> void:
	_show_modal("Ring Training", "")
	_fill_training()


func _fill_training() -> void:
	for c in _modal_buttons.get_children():
		_modal_buttons.remove_child(c)
		c.queue_free()
	var rations := GameState.count_item("training_ration")
	_modal_body.text = "Spend a [color=#dbb55c]Training Ration[/color] to train a creature: +40 experience and +3 bond.\nRations: %d" % rations
	if GameState.creatures.is_empty():
		_modal_body.text += "\n\nYou have no creatures yet. Capture one first."
	for c in GameState.creatures:
		var inst: CreatureInstance = c
		var text := "%s · Lv %d · Bond %d (%d%%)" % [inst.display_name(), inst.level, inst.bond_level(), roundi(inst.bond_progress() * 100.0)]
		var b := UiTheme.button(text, func():
			if GameState.remove_item("training_ration", 1):
				var leveled := inst.add_xp(40)
				var bonded := inst.add_bond(3)
				EventBus.notify.emit("%s trained.%s%s" % [inst.display_name(), " Level up!" if leveled else "", " Bond deepened!" if bonded else ""])
				EventBus.creatures_changed.emit()
				Fx.ring_burst(player.global_position + Vector3.UP, inst.definition().accent_color, 2.0)
				AudioManager.play_sfx("magic", player.global_position)
			_fill_training())
		b.disabled = rations <= 0
		_modal_buttons.add_child(b)
	_modal_buttons.add_child(UiTheme.button("Done", close_modal))


func _open_lore(id: String) -> void:
	var entry := Database.lore_entry(id)
	var body := String(entry.get("text", "The inscription is too worn to read."))
	if entry.get("draft", false):
		body += "\n\n[color=#8a8578][i]Draft lore — pending author approval.[/i][/color]"
	_show_modal(String(entry.get("title", "Inscription")), body)
	_modal_buttons.add_child(UiTheme.button("Close", close_modal))


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			var idx := int(k - KEY_1)
			if dialogue and idx < dialogue.choices().size():
				dialogue_choose(idx)
				get_viewport().set_input_as_handled()
	if _modal.visible and event.is_action_pressed("pause"):
		close_modal()
		get_viewport().set_input_as_handled()

class_name TouchControls
extends Control
## Two-thumb touch layout. Left thumb: floating joystick (push to the edge to
## sprint). Right thumb: action buttons in an arc at the bottom-right (the
## camera is fixed, so there is no look control). Everything presses the same InputMap actions as the
## keyboard and gamepad, so gameplay code has a single input path.
## Multi-touch is handled here directly; HUD buttons register as touch
## targets so they work while another finger holds the joystick.

const STICK_RADIUS := 78.0
const KNOB_RADIUS := 34.0
const SPRINT_THRESHOLD := 0.93

## id = InputMap action. pos = offset from the bottom-right corner (unscaled).
const BUTTONS := [
	{"id": "attack_light", "label": "ATTACK", "r": 66.0, "pos": Vector2(-120, -120)},
	{"id": "dodge", "label": "ROLL", "r": 46.0, "pos": Vector2(-95, -262)},
	{"id": "block", "label": "SHIELD", "r": 44.0, "pos": Vector2(-248, -92)},
	{"id": "attack_heavy", "label": "HEAVY", "r": 40.0, "pos": Vector2(-236, -218)},
	{"id": "summon", "label": "RING", "r": 42.0, "pos": Vector2(-178, -350)},
	{"id": "skill", "label": "SPIN", "r": 34.0, "pos": Vector2(-370, -88)},
	{"id": "companion_command", "label": "CMD", "r": 28.0, "pos": Vector2(-322, -300)},
	{"id": "quick_heal", "label": "HEAL", "r": 28.0, "pos": Vector2(-382, -196)},
	{"id": "lock_on", "label": "LOCK", "r": 30.0, "pos": Vector2(-50, -395)},
]

var labels_override: Dictionary = {}
var dimmed: Dictionary = {}

var _fingers: Dictionary = {} # index -> {kind, id, origin}
var _action_counts: Dictionary = {}
var _stick_center := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _stick_active := false
var _targets: Array = [] # [{control, callback}]
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	Settings.changed.connect(_on_settings_changed)
	visibility_changed.connect(_on_visibility_changed)


func _on_settings_changed(_section: String, _key: String) -> void:
	queue_redraw()


func register_target(control: Control, callback: Callable) -> void:
	_targets.append({"control": control, "callback": callback})


func _scale() -> float:
	return float(Settings.get_value("controls", "button_scale"))


func button_center(index: int) -> Vector2:
	var b: Dictionary = BUTTONS[index]
	return size + b.pos * _scale()


func button_index(id: String) -> int:
	for i in BUTTONS.size():
		if BUTTONS[i].id == id:
			return i
	return -1


func _button_at(pos: Vector2) -> int:
	var s := _scale()
	for i in BUTTONS.size():
		var r: float = BUTTONS[i].r * s + 10.0
		if pos.distance_to(button_center(i)) <= r:
			return i
	return -1


func _target_at(pos: Vector2) -> Dictionary:
	for t in _targets:
		var c: Control = t.control
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return t
	return {}


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var local := make_input_local(event) as InputEventScreenTouch
		if local.pressed:
			_on_down(local.index, local.position)
		else:
			_on_up(local.index)
	elif event is InputEventScreenDrag:
		var local_drag := make_input_local(event) as InputEventScreenDrag
		_on_drag(local_drag.index, local_drag.position, local_drag.relative)


func _on_down(index: int, pos: Vector2) -> void:
	var target := _target_at(pos)
	if not target.is_empty():
		_fingers[index] = {"kind": "ui"}
		(target.callback as Callable).call()
		return
	var b := _button_at(pos)
	if b >= 0:
		var id: String = BUTTONS[b].id
		_fingers[index] = {"kind": "button", "id": id}
		_press(id)
		queue_redraw()
		return
	if pos.x < size.x * 0.45 and pos.y > size.y * 0.28 and not _stick_active:
		_fingers[index] = {"kind": "stick"}
		_stick_active = true
		_stick_center = pos
		_stick_knob = pos
		queue_redraw()
		return
	_fingers[index] = {"kind": "look"}


func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _fingers.has(index):
		return
	match String(_fingers[index].kind):
		"stick":
			_update_stick(pos)
		"look":
			pass
		"button":
			# Sliding off a button releases it; sliding onto another doesn't press.
			var id: String = _fingers[index].id
			var b := button_index(id)
			if pos.distance_to(button_center(b)) > BUTTONS[b].r * _scale() * 1.6:
				_release(id)
				_fingers[index] = {"kind": "look"}
				queue_redraw()


func _on_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var f: Dictionary = _fingers[index]
	_fingers.erase(index)
	match String(f.kind):
		"stick":
			_stick_active = false
			_set_move(Vector2.ZERO)
			queue_redraw()
		"button":
			_release(f.id)
			queue_redraw()


func _update_stick(pos: Vector2) -> void:
	var r := STICK_RADIUS * _scale()
	var off := pos - _stick_center
	if off.length() > r:
		# Let the stick base follow the thumb so it never "runs out".
		_stick_center = pos - off.normalized() * r
		off = pos - _stick_center
	_stick_knob = _stick_center + off
	_set_move(off / r)
	queue_redraw()


func _set_move(v: Vector2) -> void:
	_apply_axis("move_left", maxf(0.0, -v.x))
	_apply_axis("move_right", maxf(0.0, v.x))
	_apply_axis("move_forward", maxf(0.0, -v.y))
	_apply_axis("move_back", maxf(0.0, v.y))
	if v.length() >= SPRINT_THRESHOLD:
		if not Input.is_action_pressed("sprint"):
			Input.action_press("sprint")
	elif Input.is_action_pressed("sprint") and int(_action_counts.get("sprint", 0)) == 0:
		Input.action_release("sprint")


func _apply_axis(action: String, strength: float) -> void:
	if strength > 0.05:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func stick_vector() -> Vector2:
	if not _stick_active:
		return Vector2.ZERO
	return (_stick_knob - _stick_center) / (STICK_RADIUS * _scale())


func _press(id: String) -> void:
	_action_counts[id] = int(_action_counts.get(id, 0)) + 1
	Input.action_press(id)


func _release(id: String) -> void:
	var n := int(_action_counts.get(id, 0)) - 1
	if n <= 0:
		_action_counts.erase(id)
		Input.action_release(id)
	else:
		_action_counts[id] = n


func is_button_held(id: String) -> bool:
	return int(_action_counts.get(id, 0)) > 0


func release_all() -> void:
	for id in _action_counts.keys():
		Input.action_release(id)
	_action_counts.clear()
	_fingers.clear()
	_stick_active = false
	_set_move(Vector2.ZERO)
	Input.action_release("sprint")
	queue_redraw()


func _on_visibility_changed() -> void:
	if not visible:
		release_all()


func _draw() -> void:
	var s := _scale()
	var alpha := float(Settings.get_value("controls", "button_opacity"))
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var c := button_center(i)
		var r: float = b.r * s
		var held := is_button_held(b.id)
		var dim := bool(dimmed.get(b.id, false))
		var fill := Color(0.08, 0.09, 0.12, 0.55 * alpha)
		var edge := Color(UiTheme.GOLD, (0.95 if held else 0.7) * alpha * (0.45 if dim else 1.0))
		if held:
			fill = Color(0.35, 0.28, 0.12, 0.75 * alpha)
		if b.id == "attack_light":
			fill = Color(0.28, 0.12, 0.1, (0.85 if held else 0.6) * alpha)
		draw_circle(c, r * (0.94 if held else 1.0), fill)
		draw_arc(c, r * (0.94 if held else 1.0), 0.0, TAU, 40, edge, 3.0 * s, true)
		var text: String = labels_override.get(b.id, b.label)
		var fs := int((20.0 if r > 50.0 else 15.0) * s)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, c + Vector2(-tw * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha * (0.5 if dim else 1.0)))
	if _stick_active:
		var r := STICK_RADIUS * s
		draw_circle(_stick_center, r, Color(0.08, 0.09, 0.12, 0.35 * alpha))
		draw_arc(_stick_center, r, 0.0, TAU, 48, Color(UiTheme.GOLD, 0.5 * alpha), 3.0, true)
		var sprinting := stick_vector().length() >= SPRINT_THRESHOLD
		draw_circle(_stick_knob, KNOB_RADIUS * s, Color(UiTheme.GOLD if sprinting else Color(0.9, 0.88, 0.82), 0.75 * alpha))
	else:
		# Hint where the joystick lives.
		var hint := Vector2(150, size.y - 150)
		draw_arc(hint, STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.15 * alpha), 2.0, true)
		var t := "MOVE"
		var tw2 := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
		draw_string(_font, hint + Vector2(-tw2 * 0.5, 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.3 * alpha))

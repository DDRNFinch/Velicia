extends SceneTree
## Regenerates the [input] section of project.godot.
## Run from the project folder:  godot --headless -s res://tools/setup_input_map.gd
## Keyboard, mouse and gamepad bindings live here so they stay reviewable.
## Touch controls press these same actions (see scripts/ui/touch_controls.gd).


func _init() -> void:
	var actions := {
		"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"sprint": [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_STICK)],
		"jump": [_key(KEY_SPACE), _joy(JOY_BUTTON_A)],
		"attack_light": [_key(KEY_J), _mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_X)],
		"attack_heavy": [_key(KEY_K), _mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_Y)],
		"block": [_key(KEY_Q), _key(KEY_L), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"dodge": [_key(KEY_C), _key(KEY_CTRL), _joy(JOY_BUTTON_B)],
		"skill": [_key(KEY_R), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"interact": [_key(KEY_E), _joy(JOY_BUTTON_DPAD_UP)],
		"lock_on": [_key(KEY_TAB), _mouse(MOUSE_BUTTON_MIDDLE), _joy(JOY_BUTTON_RIGHT_STICK)],
		"capture": [_key(KEY_F), _joy(JOY_BUTTON_DPAD_LEFT)],
		"summon": [_key(KEY_G), _joy(JOY_BUTTON_DPAD_DOWN)],
		"ring_next": [_key(KEY_V), _joy(JOY_BUTTON_DPAD_RIGHT)],
		"ring_prev": [_key(KEY_Z)],
		"companion_command": [_key(KEY_H), _joy(JOY_BUTTON_BACK)],
		"quick_heal": [_key(KEY_1), _key(KEY_X)],
		"pause": [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)],
		"open_inventory": [_key(KEY_I)],
		"open_map": [_key(KEY_M)],
	}
	for action_name in actions:
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": 0.2,
			"events": actions[action_name],
		})
	var err := ProjectSettings.save()
	print("Input map written: ", error_string(err))
	quit()


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e

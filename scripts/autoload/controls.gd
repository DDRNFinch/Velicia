extends Node
## Game Boy-style buttons: D-pad, A, B, START, SELECT. Keyboard, gamepad and
## the on-screen touch pad all press these same actions.

const ACTIONS := {
	"up": [KEY_W, KEY_UP],
	"down": [KEY_S, KEY_DOWN],
	"left": [KEY_A, KEY_LEFT],
	"right": [KEY_D, KEY_RIGHT],
	"a": [KEY_Z, KEY_J, KEY_ENTER, KEY_SPACE],
	"b": [KEY_X, KEY_K, KEY_BACKSPACE],
	"start": [KEY_ESCAPE, KEY_TAB],
	"select": [KEY_SHIFT],
}
const PAD := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "start": JOY_BUTTON_START, "select": JOY_BUTTON_BACK,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
}
const DIRS := {"up": Vector2i.UP, "down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT}


func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.4)
		for key in ACTIONS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
		if PAD.has(action):
			var b := InputEventJoypadButton.new()
			b.button_index = PAD[action]
			InputMap.action_add_event(action, b)
	for pair in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = pair[1]
		m.axis_value = pair[2]
		InputMap.action_add_event(pair[0], m)


## The held direction (last pressed wins, like a real D-pad), or "" if none.
var _order: Array[String] = []


func _process(_delta: float) -> void:
	for d in DIRS:
		var held := Input.is_action_pressed(d)
		if held and not _order.has(d):
			_order.append(d)
		elif not held and _order.has(d):
			_order.erase(d)


func held_direction() -> String:
	return _order[-1] if not _order.is_empty() else ""

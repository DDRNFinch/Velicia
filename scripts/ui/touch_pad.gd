class_name TouchPad
extends GBox
## On-screen Game Boy controls: D-pad bottom-left, A and B bottom-right,
## START and SELECT in between. Multi-touch; each button holds its action.

var opacity := 0.55
var _held: Dictionary = {}        # touch index -> action
var _pads: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or force_visible
	GBox.side_margin = 58.0 if visible else 0.0


var force_visible := false


func _layout() -> void:
	var s := get_viewport_rect().size
	var c := Vector2(28, s.y - 30)
	_pads = {
		"up": Rect2(c + Vector2(-8, -24), Vector2(16, 18)),
		"down": Rect2(c + Vector2(-8, 6), Vector2(16, 18)),
		"left": Rect2(c + Vector2(-26, -8), Vector2(18, 16)),
		"right": Rect2(c + Vector2(8, -8), Vector2(18, 16)),
		"a": Rect2(Vector2(s.x - 26, s.y - 44), Vector2(22, 22)),
		"b": Rect2(Vector2(s.x - 50, s.y - 30), Vector2(22, 22)),
		"start": Rect2(Vector2(s.x - 40, 4), Vector2(36, 12)),
	}


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if _pads.is_empty():
		_layout()
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * e.position
		var idx: int = e.index
		var hit := ""
		for a in _pads:
			if (_pads[a] as Rect2).grow(5).has_point(p):
				hit = a
				break
		if e is InputEventScreenTouch and not e.pressed:
			_release(idx)
		elif hit != "":
			if _held.get(idx, "") != hit:
				_release(idx)
				_held[idx] = hit
				Input.action_press(hit)
				if not (hit in ["up", "down", "left", "right"]):
					var ev := InputEventAction.new()
					ev.action = hit
					ev.pressed = true
					Input.parse_input_event(ev)
			get_viewport().set_input_as_handled()
		elif e is InputEventScreenDrag and _held.has(idx) and String(_held[idx]) in ["up", "down", "left", "right"]:
			_release(idx)
		queue_redraw()


func _release(idx: int) -> void:
	if _held.has(idx):
		Input.action_release(String(_held[idx]))
		_held.erase(idx)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


func _draw() -> void:
	if _pads.is_empty():
		_layout()
	var held := _held.values()
	var body := Color("303040")
	var hi := Color("585870")
	# D-pad: a chunky plastic cross with arrow nubs, like the real thing.
	var c: Vector2 = (_pads.up as Rect2).get_center() + Vector2(0, 15)
	draw_rect(Rect2(c - Vector2(9, 26), Vector2(18, 52)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(c - Vector2(26, 9), Vector2(52, 18)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(c - Vector2(8, 25), Vector2(16, 50)), body)
	draw_rect(Rect2(c - Vector2(25, 8), Vector2(50, 16)), body)
	for a in ["up", "down", "left", "right"]:
		var r: Rect2 = _pads[a]
		if a in held:
			draw_rect(r.grow(-1), hi)
		var d: Vector2 = Vector2(Controls.DIRS[a])
		var tip := c + d * 19.0
		var side := Vector2(-d.y, d.x) * 3.0
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 4.0 + side, tip - d * 4.0 - side]), Color(1, 1, 1, 0.45))
	draw_circle(c, 4, Color(0, 0, 0, 0.25))
	# A / B: round magenta buttons with letters.
	for a in ["a", "b"]:
		var r: Rect2 = _pads[a]
		var ctr := r.get_center()
		draw_circle(ctr + Vector2(0, 1.5), r.size.x / 2.0, Color(0, 0, 0, 0.35))
		draw_circle(ctr, r.size.x / 2.0, Color("b02858") if not a in held else Color("e04080"))
		draw_circle(ctr - Vector2(2, 3), r.size.x / 5.0, Color(1, 1, 1, 0.18))
		PixelFont.draw(self, (ctr - Vector2(3, 4)).round(), a.to_upper(), Color(1, 1, 1, 0.95))
	var sr: Rect2 = _pads.start
	draw_rect(sr, body if not "start" in held else hi)
	PixelFont.draw(self, sr.position + Vector2(3, 2), "START", Color(1, 1, 1, 0.85))

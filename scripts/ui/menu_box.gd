class_name MenuBox
extends GBox
## A framed list with the @ cursor. await choose(options, anchor) returns the
## picked index, or -1 when B is pressed (if cancellable).

signal _picked(index: int)

var options: Array = []
var index := 0
var anchor := "right"        # right | left | bottom_right | battle
var cancellable := true
var rect := Rect2()
var scripted: Array = []     # tests: queued picks


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func choose(opts: Array, where: String = "right", can_cancel: bool = true, start: int = 0) -> int:
	options = opts
	anchor = where
	cancellable = can_cancel
	index = clampi(start, 0, maxi(0, opts.size() - 1))
	_layout()
	visible = true
	queue_redraw()
	if not scripted.is_empty():
		await get_tree().process_frame
		visible = false
		return int(scripted.pop_front())
	var i: int = await _picked
	visible = false
	return i


func _layout() -> void:
	var s := get_viewport_rect().size
	var w := 0
	for o in options:
		w = maxi(w, String(o).length())
	var size := Vector2(w * PixelFont.CELL.x + 24, options.size() * 12 + 12)
	match anchor:
		"left":
			rect = Rect2(Vector2(0, 0), size)
		"above_box", "battle":
			var st := stage_rect()
			rect = Rect2(Vector2(st.end.x - size.x, s.y - 48 - size.y), size)
		_:
			var st2 := stage_rect()
			rect = Rect2(Vector2(st2.end.x - size.x, 0), size)


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("down"):
		index = (index + 1) % options.size()
		Audio.play("pickup", 2.4)
	elif e.is_action_pressed("up"):
		index = (index - 1 + options.size()) % options.size()
		Audio.play("pickup", 2.4)
	elif e.is_action_pressed("a"):
		Audio.play("pickup", 2.0)
		_picked.emit(index)
	elif e.is_action_pressed("b") and cancellable:
		_picked.emit(-1)
	elif e is InputEventScreenTouch and e.pressed:
		var p := get_global_transform_with_canvas().affine_inverse() * (e as InputEventScreenTouch).position
		if rect.has_point(p):
			var i := int((p.y - rect.position.y - 6) / 12)
			if i >= 0 and i < options.size():
				index = i
				Audio.play("pickup", 2.0)
				_picked.emit(i)
		elif cancellable:
			_picked.emit(-1)
	else:
		return
	get_viewport().set_input_as_handled()
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_frame(rect)
	for i in options.size():
		var y := rect.position.y + 8 + i * 12
		if i == index:
			text(Vector2(rect.position.x + 6, y), "@")
		text(Vector2(rect.position.x + 14, y), String(options[i]))

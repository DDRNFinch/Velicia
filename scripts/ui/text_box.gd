class_name TextBox
extends GBox
## The bottom text box: typewriter text, two lines per page, a blinking
## arrow when there is more, and A (or a tap) to continue.

signal _next

const CHARS_PER_SEC := 45.0
const LINE_H := 12

var _pages: Array = []
var _page := ""
var _shown := 0.0
var _waiting := false
var _t := 0.0
var auto_advance := false        # tests
var instant := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func box_rect() -> Rect2:
	var st := stage_rect()
	return Rect2(st.position.x, st.size.y - 48, st.size.x, 48)


func cols() -> int:
	return int((box_rect().size.x - 16) / PixelFont.CELL.x)


func say(t: String) -> void:
	visible = true
	var lines := PixelFont.wrap(t, cols()).split("\n")
	_pages.clear()
	for i in range(0, lines.size(), 2):
		_pages.append("\n".join(lines.slice(i, i + 2)))
	for p in _pages:
		_page = p
		_shown = 0.0 if not instant else 999.0
		_waiting = true
		queue_redraw()
		if auto_advance:
			await get_tree().process_frame
			continue
		await _next


func close() -> void:
	visible = false


func is_typing() -> bool:
	return _shown < _page.length()


func press() -> void:
	if not visible or not _waiting:
		return
	if is_typing():
		_shown = _page.length()
		queue_redraw()
		return
	_waiting = false
	Audio.play("pickup", 2.0)
	_next.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if is_typing():
		_shown += delta * CHARS_PER_SEC
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if visible and _waiting and (e.is_action_pressed("a") or e.is_action_pressed("b")):
		get_viewport().set_input_as_handled()
		press()
	elif visible and _waiting and e is InputEventScreenTouch and e.pressed:
		press()


func _draw() -> void:
	if not visible:
		return
	var r := box_rect()
	draw_frame(r)
	text(r.position + Vector2(8, 10), _page, INK, int(_shown))
	if not is_typing() and int(_t * 2.5) % 2 == 0:
		text(r.position + Vector2(r.size.x - 14, r.size.y - 12), "~")

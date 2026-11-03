class_name TitleScreen
extends GBox
## Title: the VELICIA logo, a parade of ring creatures, NEW GAME / CONTINUE.

signal done(pick: String)

var _t := 0.0
var _opts: Array = []
var _i := 0
var _tex: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opts = ["CONTINUE", "NEW GAME"] if Game.has_save() else ["NEW GAME"]
	for k in ["alpha", "beta", "gamma", "delta", "epsilon"]:
		_tex.append(load("res://art/battle/%s_front.png" % k))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("down") or e.is_action_pressed("up"):
		_i = (_i + 1) % _opts.size()
	elif e.is_action_pressed("a") or e.is_action_pressed("start"):
		_pick()
	elif e is InputEventScreenTouch and e.pressed:
		var p := get_global_transform_with_canvas().affine_inverse() * (e as InputEventScreenTouch).position
		var s := get_viewport_rect().size
		for k in _opts.size():
			if Rect2(s.x / 2 - 40, s.y - 40 + k * 14, 80, 12).has_point(p):
				_i = k
				_pick()
	else:
		return
	get_viewport().set_input_as_handled()


func _pick() -> void:
	Audio.play("level_up")
	done.emit("continue" if _opts[_i] == "CONTINUE" else "new")


func _draw() -> void:
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color("f8f0d8"))
	draw_rect(Rect2(0, 0, s.x, 54), Color("3868c8"))
	draw_rect(Rect2(0, 54, s.x, 2), Color("181818"))
	# Big logo: the pixel font drawn at 3x.
	var title_text := "VELICIA"
	var w := PixelFont.width(title_text) * 3
	draw_set_transform(Vector2((s.x - w) / 2.0 + 2, 14), 0.0, Vector2(3, 3))
	PixelFont.draw(self, Vector2.ZERO, title_text, Color("181818"))
	draw_set_transform(Vector2((s.x - w) / 2.0, 12), 0.0, Vector2(3, 3))
	PixelFont.draw(self, Vector2.ZERO, title_text, Color("f0c040"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	text(Vector2((s.x - PixelFont.width("RINGS OF THE EMORIA GUILD")) / 2.0, 42), "RINGS OF THE EMORIA GUILD", PAPER)
	# Creature parade
	var k := int(_t * 0.5) % _tex.size()
	var tex: Texture2D = _tex[k]
	draw_texture(tex, Vector2((s.x - 48) / 2.0, 58 + sin(_t * 3.0) * 2.0))
	for j in _opts.size():
		var y := s.y - 40 + j * 14
		if j == _i and int(_t * 3.0) % 2 == 0:
			text(Vector2(s.x / 2 - 40, y), "@")
		text(Vector2(s.x / 2 - 32, y), _opts[j])
	text(Vector2(4, s.y - 10), "PROTOTYPE", Color("888898"))

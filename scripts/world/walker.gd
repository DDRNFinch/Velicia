class_name Walker
extends Node2D
## A character on the tile grid: 16 px steps, 4 facings, 3-frame walk
## (stand / step A / step B) from a sheet laid out rows down, up, left, right.

const T := 16
const ROWS := {"down": 0, "up": 1, "left": 2, "right": 3}
const STEP_TIME := 0.24

var tile := Vector2i.ZERO
var facing := "down"
var moving := false
var sprite: Sprite2D
var grass_top: Sprite2D
var sheet_name := ""
var _alt := false
var frame_h := 16


func setup(sheet: String) -> void:
	sheet_name = sheet
	sprite = Sprite2D.new()
	sprite.texture = load("res://art/chars/%s.png" % sheet)
	sprite.hframes = 3
	sprite.vframes = 4
	sprite.centered = false
	frame_h = int(sprite.texture.get_height() / 4.0)
	sprite.offset = Vector2(-8, -frame_h - 1)
	add_child(sprite)
	grass_top = Sprite2D.new()
	grass_top.texture = _grass_top_texture()
	grass_top.centered = false
	grass_top.offset = Vector2(-8, -16)
	grass_top.visible = false
	add_child(grass_top)
	refresh_frame(0)


static var _gt: Texture2D


static func _grass_top_texture() -> Texture2D:
	if _gt == null:
		var a := AtlasTexture.new()
		a.atlas = load("res://art/tiles.png")
		var i := Data.tile_index("tallgrass")
		a.region = Rect2((i % 16) * T, (i / 16) * T + 8, T, 8)
		_gt = a
	return _gt


func place(t: Vector2i) -> void:
	tile = t
	position = tile_pos(t)


static func tile_pos(t: Vector2i) -> Vector2:
	return Vector2(t.x * T + T / 2.0, t.y * T + T)


func face(dir: String) -> void:
	facing = dir
	refresh_frame(0)


func refresh_frame(col: int) -> void:
	if sprite:
		sprite.frame = ROWS.get(facing, 0) * 3 + col


## Walks one tile (or `tiles` for ledge hops). Awaitable.
func step(dir: String, tiles: int = 1) -> void:
	facing = dir
	moving = true
	var to: Vector2i = tile + Controls.DIRS[dir] * tiles
	var from_pos := position
	var to_pos := tile_pos(to)
	tile = to
	_alt = not _alt
	var dur := STEP_TIME * tiles
	var t := 0.0
	while t < dur:
		var dt := get_process_delta_time()
		t += dt
		var k := clampf(t / dur, 0.0, 1.0)
		position = from_pos.lerp(to_pos, k).round()
		if tiles > 1:
			position.y -= sin(k * PI) * 8.0
		refresh_frame((2 if _alt else 1) if k < 0.6 else 0)
		await get_tree().process_frame
	position = to_pos
	refresh_frame(0)
	moving = false


func set_in_grass(on: bool) -> void:
	grass_top.visible = on

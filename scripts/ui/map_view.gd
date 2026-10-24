class_name MapView
extends Control
## Top-down region map generated from the terrain height function. Shows
## discovered locations, Ring Stones, the tracked quest marker and the player.

var player: Node3D
var _texture: ImageTexture
var _font: Font
static var _cached: Dictionary = {}

const RES := 160


func _ready() -> void:
	custom_minimum_size = Vector2(420, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_font = ThemeDB.fallback_font
	_texture = _make_texture()


func _make_texture() -> ImageTexture:
	var key := "%s_%d" % [GameState.region, int(VeliciaTerrain.size)]
	if _cached.has(key):
		return _cached[key]
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var half := VeliciaTerrain.size * 0.5
	for y in RES:
		for x in RES:
			var wx := -half + (x + 0.5) / RES * VeliciaTerrain.size
			var wz := -half + (y + 0.5) / RES * VeliciaTerrain.size
			var h := VeliciaTerrain.height_at(wx, wz)
			var c := Color(0.36, 0.5, 0.3)
			if h < VeliciaTerrain.water_level:
				c = Color(0.25, 0.42, 0.55)
			elif h > 30.0:
				c = Color(0.85, 0.85, 0.86)
			elif h > 18.0:
				c = Color(0.5, 0.47, 0.43)
			else:
				c = c.lerp(Color(0.62, 0.6, 0.4), clampf(h / 18.0, 0.0, 1.0))
			# Simple hill shading.
			var e := VeliciaTerrain.height_at(wx + 2.0, wz + 2.0) - h
			c = c.darkened(clampf(e * 0.06, -0.15, 0.25))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cached[key] = tex
	return tex


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _world_to_map(p: Vector3, rect: Rect2) -> Vector2:
	var half := VeliciaTerrain.size * 0.5
	return rect.position + Vector2((p.x + half) / VeliciaTerrain.size, (p.z + half) / VeliciaTerrain.size) * rect.size


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2(Vector2((size.x - side) * 0.5, (size.y - side) * 0.5), Vector2(side, side))
	draw_texture_rect(_texture, rect, false)
	draw_rect(rect, UiTheme.GOLD_DIM, false, 3.0)
	var marker := QuestManager.marker_location(GameState.tracked_quest)
	for n in get_tree().get_nodes_in_group("locations"):
		var lt := n as LocationTrigger
		var known := lt.location_id in GameState.discovered
		var pos := _world_to_map(lt.global_position, rect)
		if lt.location_id == marker:
			draw_circle(pos, 14.0, Color(1.0, 0.8, 0.2, 0.35))
			draw_arc(pos, 14.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.2), 3.0)
		if known:
			draw_circle(pos, 6.0, UiTheme.GOLD)
			draw_string(_font, pos + Vector2(9, 5), lt.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))
		else:
			draw_string(_font, pos + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
	for n in get_tree().get_nodes_in_group("shrines"):
		var pos := _world_to_map((n as Node3D).global_position, rect)
		draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), UiTheme.RING)
	if player and is_instance_valid(player):
		var pos := _world_to_map(player.global_position, rect)
		var fwd := -player.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		var side_v := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([pos + dir * 12.0, pos - dir * 7.0 + side_v * 7.0, pos - dir * 7.0 - side_v * 7.0])
		draw_colored_polygon(pts, Color(1, 0.3, 0.25))
	draw_string(_font, rect.position + Vector2(10, 24), "Gold dot: discovered · ? unexplored · Blue: Ring Stone · Ring: quest", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))

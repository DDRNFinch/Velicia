class_name HeartsDisplay
extends Control
## Zelda-style hearts: one heart per 20 health, filled in quarters, with a
## little pulse when health is low and a flash when you get hurt.

const HP_PER_HEART := 20.0
const SIZE := 26.0
const GAP := 4.0

var health := 100.0
var max_health := 100.0
var _flash := 0.0
var _t := 0.0


func set_health(h: float, m: float) -> void:
	if h < health - 0.5:
		_flash = 0.35
	health = h
	max_health = m
	var hearts := ceili(max_health / HP_PER_HEART)
	var per_row := 10
	custom_minimum_size = Vector2(mini(hearts, per_row) * (SIZE + GAP), ceili(float(hearts) / per_row) * (SIZE + GAP))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	elif health <= HP_PER_HEART and health > 0.0:
		queue_redraw()


func _heart_points(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		# Classic heart curve, scaled to fit an s x s box.
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * (s / 34.0))
	return pts


func _draw() -> void:
	var hearts := ceili(max_health / HP_PER_HEART)
	for i in hearts:
		var col := i % 10
		var row := i / 10
		var c := Vector2(col * (SIZE + GAP) + SIZE * 0.5, row * (SIZE + GAP) + SIZE * 0.5)
		var fill := clampf((health - i * HP_PER_HEART) / HP_PER_HEART, 0.0, 1.0)
		fill = floorf(fill * 4.0 + 0.001) / 4.0
		var s := SIZE
		if health <= HP_PER_HEART and i == 0 and health > 0.0:
			s *= 1.0 + 0.08 * sin(_t * 9.0)
		var outline := _heart_points(c, s + 4.0)
		draw_colored_polygon(outline, Color(0.12, 0.06, 0.08, 0.9))
		var pts := _heart_points(c, s)
		draw_colored_polygon(pts, Color(0.32, 0.16, 0.2))
		if fill > 0.0:
			# Fill from the left in quarters (clip the heart polygon).
			var clip := PackedVector2Array([c + Vector2(-s, -s), c + Vector2(-s + s * 2.0 * fill, -s), c + Vector2(-s + s * 2.0 * fill, s), c + Vector2(-s, s)])
			var red := Color(0.92, 0.18, 0.2).lerp(Color.WHITE, clampf(_flash * 2.0, 0.0, 0.7))
			for poly in Geometry2D.intersect_polygons(pts, clip):
				draw_colored_polygon(poly, red)
			draw_circle(c + Vector2(-s * 0.2, -s * 0.18), s * 0.09, Color(1, 0.75, 0.75, 0.9))

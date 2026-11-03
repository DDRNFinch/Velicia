class_name GBox
extends Control
## Shared drawing for GB-style boxes: the double-border frame (art/ui/frame.png
## as a 9-slice) and pixel text.

const INK := Color("181818")
const PAPER := Color("f8f8f8")

static var _frame: Texture2D
## Horizontal space reserved on each side for the touch controls.
static var side_margin := 0.0


## The central "screen" area (GB-like column) inside the touch margins.
func stage_rect(max_w: float = 240.0) -> Rect2:
	var s := get_viewport_rect().size
	var w := minf(s.x - side_margin * 2.0, max_w)
	w = maxf(w, minf(s.x, 160.0))
	return Rect2((s.x - w) * 0.5, 0, w, s.y)


static func frame_tex() -> Texture2D:
	if _frame == null:
		_frame = load("res://art/ui/frame.png")
	return _frame


func draw_frame(r: Rect2) -> void:
	var t := frame_tex()
	var c := 8.0
	var s := t.get_size()
	r = Rect2(r.position.round(), r.size.round())
	# corners
	draw_texture_rect_region(t, Rect2(r.position, Vector2(c, c)), Rect2(0, 0, c, c))
	draw_texture_rect_region(t, Rect2(r.position + Vector2(r.size.x - c, 0), Vector2(c, c)), Rect2(s.x - c, 0, c, c))
	draw_texture_rect_region(t, Rect2(r.position + Vector2(0, r.size.y - c), Vector2(c, c)), Rect2(0, s.y - c, c, c))
	draw_texture_rect_region(t, Rect2(r.end - Vector2(c, c), Vector2(c, c)), Rect2(s.x - c, s.y - c, c, c))
	# edges
	draw_texture_rect_region(t, Rect2(r.position + Vector2(c, 0), Vector2(r.size.x - 2 * c, c)), Rect2(c, 0, s.x - 2 * c, c))
	draw_texture_rect_region(t, Rect2(r.position + Vector2(c, r.size.y - c), Vector2(r.size.x - 2 * c, c)), Rect2(c, s.y - c, s.x - 2 * c, c))
	draw_texture_rect_region(t, Rect2(r.position + Vector2(0, c), Vector2(c, r.size.y - 2 * c)), Rect2(0, c, c, s.y - 2 * c))
	draw_texture_rect_region(t, Rect2(r.position + Vector2(r.size.x - c, c), Vector2(c, r.size.y - 2 * c)), Rect2(s.x - c, c, c, s.y - 2 * c))
	draw_rect(Rect2(r.position + Vector2(c, c), r.size - Vector2(2 * c, 2 * c)), PAPER)


func text(pos: Vector2, s: String, col: Color = INK, max_chars: int = -1) -> void:
	PixelFont.draw(self, pos.round(), s, col, max_chars)


## A GB-style HP bar: black frame, green/yellow/red fill.
func hp_bar(pos: Vector2, w: float, frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(pos, Vector2(w, 4)), INK)
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(w - 2, 2)), PAPER)
	var col := Color("48c048") if frac > 0.5 else (Color("f0c030") if frac > 0.2 else Color("e83828"))
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2((w - 2) * frac, 2)), col)

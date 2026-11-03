class_name PixelFont
extends RefCounted
## The 5x7 pixel font (art/font.png, 6x8 cells) drawn glyph by glyph, so text
## stays crisp and authentic at any screen scale. Special glyphs:
## @ cursor, ~ more-text arrow, ` ring, | heart, $ money.

const CELL := Vector2i(6, 8)
const COLUMNS := 16
const FIRST := 32

static var _tex: Texture2D


static func texture() -> Texture2D:
	if _tex == null:
		_tex = load("res://art/font.png")
	return _tex


static func draw(item: CanvasItem, pos: Vector2, text: String, color: Color = Color("181818"), max_chars: int = -1) -> void:
	var tex := texture()
	var x := pos.x
	var y := pos.y
	var n := 0
	for ch in text:
		if max_chars >= 0 and n >= max_chars:
			return
		n += 1
		if ch == "\n":
			x = pos.x
			y += 12
			continue
		var code := ch.unicode_at(0)
		if code < FIRST or code > 126:
			code = 63
		var i := code - FIRST
		item.draw_texture_rect_region(tex, Rect2(x, y, CELL.x, CELL.y), Rect2((i % COLUMNS) * CELL.x, (i / COLUMNS) * CELL.y, CELL.x, CELL.y), color)
		x += CELL.x


static func width(text: String) -> int:
	var best := 0
	for line in text.split("\n"):
		best = maxi(best, line.length() * CELL.x)
	return best


## Word-wraps to `cols` characters per line.
static func wrap(text: String, cols: int) -> String:
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" "):
			if line.is_empty():
				line = word
			elif line.length() + 1 + word.length() <= cols:
				line += " " + word
			else:
				out.append(line)
				line = word
		out.append(line)
	return "\n".join(out)

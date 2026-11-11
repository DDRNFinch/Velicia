class_name UiTheme
extends RefCounted
## Original Velicia interface style: dark slate panels, Emoria gold trim and
## large touch-friendly controls. PLACEHOLDER: swap fonts/textures here once
## final UI artwork exists; every screen uses this theme.

const GOLD := Color(0.86, 0.71, 0.36)
const GOLD_DIM := Color(0.55, 0.45, 0.25)
const INK := Color(0.07, 0.08, 0.11, 0.92)
const INK_LIGHT := Color(0.13, 0.15, 0.2, 0.95)
const TEXT := Color(0.94, 0.91, 0.84)
const TEXT_DIM := Color(0.7, 0.68, 0.62)
const HEALTH := Color(0.78, 0.2, 0.18)
const STAMINA := Color(0.36, 0.72, 0.36)
const RING := Color(0.4, 0.85, 0.95)
const DANGER := Color(0.85, 0.25, 0.2)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("normal", "Button", button_style(INK_LIGHT, GOLD_DIM))
	t.set_stylebox("hover", "Button", button_style(Color(0.18, 0.2, 0.27), GOLD))
	t.set_stylebox("pressed", "Button", button_style(Color(0.24, 0.2, 0.12), GOLD))
	t.set_stylebox("focus", "Button", button_style(Color(0.18, 0.2, 0.27, 0.0), GOLD))
	t.set_stylebox("disabled", "Button", button_style(Color(0.1, 0.1, 0.12, 0.8), Color(0.3, 0.3, 0.3)))
	t.set_stylebox("background", "ProgressBar", bar_style(Color(0.05, 0.05, 0.07, 0.85)))
	t.set_stylebox("fill", "ProgressBar", bar_style(GOLD))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	var tab_sel := button_style(Color(0.24, 0.2, 0.12), GOLD)
	var tab_un := button_style(INK_LIGHT, GOLD_DIM)
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_un)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_un)
	t.set_stylebox("panel", "TabContainer", panel_style())
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_font_size("font_size", "TabContainer", 22)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = GOLD
	grabber.set_corner_radius_all(10)
	t.set_stylebox("slider", "HSlider", bar_style(Color(0.2, 0.2, 0.25)))
	t.set_stylebox("grabber_area", "HSlider", bar_style(GOLD_DIM))
	t.set_stylebox("grabber_area_highlight", "HSlider", bar_style(GOLD))
	_theme = t
	return t


## Anchors a control to a screen preset and positions its top-left corner at
## `offset` relative to that anchor point. Containers grow away from the edge.
static func place(c: Control, preset: int, offset: Vector2) -> void:
	c.set_anchors_preset(preset)
	var sz := c.custom_minimum_size
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + sz.x
	c.offset_bottom = offset.y + sz.y
	c.grow_horizontal = _grow(c.anchor_left)
	c.grow_vertical = _grow(c.anchor_top)


static func _grow(anchor: float) -> Control.GrowDirection:
	if anchor >= 1.0:
		return Control.GROW_DIRECTION_BEGIN
	if anchor > 0.0:
		return Control.GROW_DIRECTION_BOTH
	return Control.GROW_DIRECTION_END


static func panel_style(bg: Color = INK, border: Color = GOLD_DIM) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func bar_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(6)
	return s


static func make_bar(color: Color, width: float, height: float = 16.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", bar_style(color))
	bar.max_value = 100.0
	bar.value = 100.0
	return bar


static func label(text: String, size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.pressed.connect(func():
		AudioManager.play_ui()
		callback.call())
	return b


static func title(text: String) -> Label:
	var l := label(text, 30, GOLD)
	return l

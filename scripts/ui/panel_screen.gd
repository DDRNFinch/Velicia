class_name PanelScreen
extends GBox
## Full-screen menus: party, creature summary, bag, the warrior's stats,
## the quartermaster's shop and the starter choice.

signal _key(k: String)

var mode := ""
var cursor := 0
var items: Array = []
var data: Dictionary = {}
var scripted: Array = []          # tests: queued keys
var _tex_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	for k in ["up", "down", "left", "right", "a", "b"]:
		if e.is_action_pressed(k):
			get_viewport().set_input_as_handled()
			_key.emit(k)
			return
	if e is InputEventScreenTouch and e.pressed:
		get_viewport().set_input_as_handled()
		_tap(get_global_transform_with_canvas().affine_inverse() * (e as InputEventScreenTouch).position)


func _tap(p: Vector2) -> void:
	# Touch: tap a row to select it (tap it again to confirm); tap the top bar to go back.
	if p.y < 14:
		_key.emit("b")
		return
	p.x -= stage_rect(300.0).position.x
	var row := int((p.y - _list_top()) / _row_h())
	if mode == "starter":
		var w := stage_rect(300.0).size.x / 3.0
		var col := clampi(int(p.x / w), 0, 2)
		if col == cursor:
			_key.emit("a")
		else:
			cursor = col
			queue_redraw()
		return
	if row >= 0 and row < items.size():
		if row == cursor:
			_key.emit("a")
		else:
			cursor = row
			queue_redraw()


func _list_top() -> float:
	return 18.0


func _row_h() -> float:
	return 22.0 if mode == "party" else 12.0


func _wait_key() -> String:
	if not scripted.is_empty():
		await get_tree().process_frame
		return String(scripted.pop_front())
	var k: String = await _key
	return k


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## Generic list loop: returns the chosen index or -1.
func _run_list(m: String, list: Array, start: int = 0) -> int:
	mode = m
	items = list
	cursor = clampi(start, 0, maxi(0, list.size() - 1))
	visible = true
	queue_redraw()
	while true:
		var k := await _wait_key()
		match k:
			"up":
				cursor = (cursor - 1 + maxi(1, items.size())) % maxi(1, items.size())
			"down":
				cursor = (cursor + 1) % maxi(1, items.size())
			"a":
				if not items.is_empty():
					Audio.play("pickup", 2.0)
					return cursor
			"b":
				return -1
		queue_redraw()
	return -1


func close() -> void:
	visible = false
	mode = ""


# ------------------------------------------------------------------ party

func party(pick_for_battle: bool = false) -> int:
	while true:
		var i := await _run_list("party", Game.party, cursor)
		if i < 0 or pick_for_battle:
			close()
			return i
		var c: Dictionary = Game.party[i]
		await summary(c)
		if Game.party.size() > 1 and i > 0:
			# Move the chosen creature to the front (it battles first).
			Game.party.remove_at(i)
			Game.party.insert(0, c)
			Events.party_changed.emit()
			cursor = 0
	return -1


func summary(c: Dictionary) -> void:
	mode = "summary"
	data = c
	visible = true
	queue_redraw()
	await _wait_key()
	mode = "party"


# ------------------------------------------------------------------ bag

func bag(in_battle: bool) -> String:
	while true:
		var ids: Array = []
		for k in Game.inventory:
			if int(Game.inventory[k]) > 0 and (in_battle or Data.item(k).get("kind", "") != "capture"):
				ids.append(k)
		ids.append("")
		var i := await _run_list("bag", ids, 0)
		if i < 0 or ids[i] == "":
			close()
			return ""
		var id: String = ids[i]
		if in_battle:
			close()
			return id
		var kind := String(Data.item(id).get("kind", ""))
		if kind == "heal_creature" and not Game.party.is_empty():
			var who := await _run_list("party", Game.party, 0)
			if who >= 0 and Game.take_item(id):
				Creatures.heal(Game.party[who], int(Data.item(id).get("amount", 25)))
				Audio.play("ring_summon")
		elif kind == "heal_player":
			if Game.take_item(id):
				Game.player.hp = Game.trainer_max_hp()
				Audio.play("ring_summon")
	return ""


# ------------------------------------------------------------------ warrior & shop

func warrior() -> void:
	mode = "warrior"
	visible = true
	queue_redraw()
	await _wait_key()
	close()


const SHOP_STOCK := ["binding_ring", "silver_ring", "tonic", "elixir"]


func shop() -> void:
	while true:
		var list: Array = SHOP_STOCK.duplicate()
		list.append("")
		var i := await _run_list("shop", list, cursor)
		if i < 0 or list[i] == "":
			break
		var id: String = list[i]
		var price := int(Data.item(id).get("price", 0))
		if Game.coins >= price:
			Game.add_coins(-price)
			Game.give_item(id, 1)
			Audio.play("pickup")
		else:
			Audio.play("ring_fail")
	close()


# ------------------------------------------------------------------ starter

func starter_picker(ids: Array) -> int:
	mode = "starter"
	items = ids
	cursor = 1
	visible = true
	queue_redraw()
	while true:
		var k := await _wait_key()
		if k == "left":
			cursor = (cursor + 2) % 3
		elif k == "right":
			cursor = (cursor + 1) % 3
		elif k == "a":
			close()
			return cursor
		queue_redraw()
	return 0


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if not visible:
		return
	var full := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, full), PAPER)
	# Lay content out in the central column between the touch controls.
	var st := stage_rect(300.0)
	draw_rect(Rect2(0, 0, full.x, 14), Color("3868c8"))
	draw_set_transform(Vector2(st.position.x, 0))
	var s := Vector2(st.size.x, full.y)
	match mode:
		"party":
			_draw_party(s)
		"summary":
			_draw_summary(s)
		"bag":
			_draw_bag(s, "BAG")
		"shop":
			_draw_bag(s, "BRANNOCH'S STORE")
		"warrior":
			_draw_warrior(s)
		"starter":
			_draw_starter(s)


func _header(t: String, _s: Vector2) -> void:
	text(Vector2(6, 3), t, PAPER)


func _draw_party(s: Vector2) -> void:
	_header("PARTY  (A: summary/lead  B: back)", s)
	for i in items.size():
		var c: Dictionary = items[i]
		var y := _list_top() + i * _row_h()
		if i == cursor:
			text(Vector2(2, y + 6), "@")
		var tex := _tex("res://art/battle/%s_small.png" % String(Creatures.species_data(c).get("sprite", c.species)))
		if tex:
			draw_texture_rect_region(tex, Rect2(10, y + 2, 16, 16), Rect2(0, 0, 16, 16))
		text(Vector2(30, y + 1), Creatures.display_name(c).to_upper().substr(0, 14))
		text(Vector2(s.x - 50, y + 1), "L%d" % int(c.level))
		hp_bar(Vector2(30, y + 12), 60, float(c.hp) / Creatures.max_hp(c))
		text(Vector2(96, y + 10), "%d/%d" % [int(c.hp), Creatures.max_hp(c)])
	if items.is_empty():
		text(Vector2(8, 24), "No ring creatures yet.")


func _draw_summary(s: Vector2) -> void:
	var c := data
	_header(Creatures.display_name(c).to_upper(), s)
	var sp := String(Creatures.species_data(c).get("sprite", c.species))
	var tex := _tex("res://art/battle/%s_front.png" % sp)
	if tex:
		draw_texture(tex, Vector2(4, 18))
	var x := 58.0
	text(Vector2(x, 20), "L%d  %s" % [int(c.level), Data.element_name(Creatures.element(c)).to_upper()])
	text(Vector2(x, 32), "HP  %d/%d" % [int(c.hp), Creatures.max_hp(c)])
	text(Vector2(x, 44), "ATK %d  DEF %d" % [Creatures.stat(c, "atk"), Creatures.stat(c, "def")])
	text(Vector2(x, 56), "SPD %d  BOND %d" % [Creatures.stat(c, "spd"), int(c.get("bond", 0))])
	text(Vector2(4, 72), "MOVES")
	var mv: Array = c.get("moves", [])
	for i in mv.size():
		var m := Data.move(String(mv[i]))
		text(Vector2(10, 84 + i * 12), "%s  %s" % [String(m.name).to_upper(), "" if int(m.power) == 0 else "PWR %d" % int(m.power)])
	text(Vector2(4, s.y - 12), "NEXT LV: %d XP" % Creatures.xp_to_next(c))


func _draw_bag(s: Vector2, title_text: String) -> void:
	_header(title_text, s)
	for i in items.size():
		var y := _list_top() + i * _row_h()
		var id: String = items[i]
		if i == cursor:
			text(Vector2(2, y), "@")
		if id == "":
			text(Vector2(10, y), "CANCEL")
			continue
		var it := Data.item(id)
		text(Vector2(10, y), String(it.name).to_upper().substr(0, 16))
		if mode == "shop":
			text(Vector2(s.x - 40, y), "$%d" % int(it.price))
		else:
			text(Vector2(s.x - 28, y), "x%d" % int(Game.inventory.get(id, 0)))
	if cursor < items.size() and String(items[cursor]) != "":
		var desc := String(Data.item(String(items[cursor])).get("desc", ""))
		var r := Rect2(0, s.y - 40, s.x, 40)
		draw_frame(r)
		text(r.position + Vector2(8, 8), PixelFont.wrap(desc, int((s.x - 16) / 6)))
	if mode == "shop":
		text(Vector2(s.x - 70, 3), "$%d" % Game.coins, PAPER)


func _draw_warrior(s: Vector2) -> void:
	_header("%s  -  EMORIA WARRIOR" % Game.player.name, s)
	var tex := _tex("res://art/chars/player.png")
	if tex:
		draw_texture_rect_region(tex, Rect2(8, 22, 32, 32), Rect2(0, 0, 16, 16))
	var p := Game.player
	text(Vector2(50, 20), "LEVEL %d" % int(p.level))
	text(Vector2(50, 32), "HP %d/%d" % [int(p.hp), Game.trainer_max_hp()])
	hp_bar(Vector2(50, 42), 70, float(p.hp) / Game.trainer_max_hp())
	text(Vector2(8, 60), "ATK %d  DEF %d  SPD %d" % [Game.trainer_stat("atk"), Game.trainer_stat("def"), Game.trainer_stat("spd")])
	text(Vector2(8, 74), "MARKS $%d" % Game.coins)
	text(Vector2(8, 86), "RING CREATURES %d" % (Game.party.size() + Game.vault.size()))
	var mins := int(Game.play_time / 60.0)
	text(Vector2(8, 98), "TIME %d:%02d" % [mins / 60, mins % 60])
	text(Vector2(8, 116), "The warrior fights beside")
	text(Vector2(8, 128), "their creatures in battle.")


func _draw_starter(s: Vector2) -> void:
	_header("CHOOSE YOUR FIRST RING CREATURE", s)
	var w := s.x / 3.0
	for i in items.size():
		var id: String = items[i]
		var c := Data.creature(id)
		var x := i * w + (w - 48) / 2.0
		if i == cursor:
			draw_rect(Rect2(i * w + 2, 18, w - 4, 84), Color("d8e0f0"))
		var tex := _tex("res://art/battle/%s_front.png" % id)
		if tex:
			draw_texture(tex, Vector2(x, 22))
		var name_t := String(c.get("name", id)).to_upper().replace("TEST CREATURE ", "")
		text(Vector2(i * w + 6, 74), name_t.substr(0, 10))
		text(Vector2(i * w + 6, 86), Data.element_name(String(c.get("element", ""))).to_upper())
	var desc := String(Data.creature(String(items[cursor])).get("blurb", ""))
	var r := Rect2(0, s.y - 40, s.x, 40)
	draw_frame(r)
	text(r.position + Vector2(8, 8), PixelFont.wrap(desc, int((s.x - 16) / 6)))

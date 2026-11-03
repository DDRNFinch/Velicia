class_name Overworld
extends Node2D
## A map: tiles, buildings, people, trainers, signs, items, Ring Stones,
## warps and wild-creature grass, with grid movement for the player.
## Game flow (dialogue, battles, menus) is run by GameRoot through `root`.

const T := 16
const SOLID := "~TF#^WNCKBPtAX"

var root: Node                  # GameRoot
var map_id := ""
var meta: Dictionary = {}
var rows: PackedStringArray = []
var width := 0
var height := 0
var ground: TileMapLayer
var entities: Node2D
var player: Walker
var camera: Camera2D
var people: Dictionary = {}     # id -> {walker, data}
var things: Array = []          # signs, items, stones, lore: {kind, tile, data, node}
var _solid_extra: Dictionary = {}  # Vector2i -> true (buildings, props)
var busy := false               # true while a dialogue / battle / menu runs
var _anim_t := 0.0
var _anims: Array = []
var _turn_delay := 0.0


func _ready() -> void:
	add_to_group("overworld")


# ------------------------------------------------------------------ building

func load_map(id: String) -> void:
	map_id = id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id))
	meta = parsed if parsed is Dictionary else {}
	rows = PackedStringArray(meta.get("rows", []))
	width = int(meta.get("width", 0))
	height = int(meta.get("height", 0))
	_build_ground()
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	_build_objects()
	_build_things()
	_build_people()
	player = Walker.new()
	player.setup("player")
	entities.add_child(player)
	camera = Camera2D.new()
	player.add_child(camera)
	camera.offset = Vector2(0, -8)
	_fit_camera()
	camera.make_current()


func cell(t: Vector2i) -> String:
	if t.y < 0 or t.y >= rows.size() or t.x < 0 or t.x >= rows[t.y].length():
		return "X"
	return rows[t.y][t.x]


func _tile_name(t: Vector2i) -> String:
	var ch := cell(t)
	var h := absi((t.x * 73856093) ^ (t.y * 19349663))
	match ch:
		".":
			return "grass" if h % 5 else "grass2"
		",":
			return "grass2"
		"*":
			return "flowers"
		"\"":
			return "tallgrass"
		"=":
			return "path"
		":":
			return "path2"
		"s":
			return "sand"
		"~":
			return "water0_%d" % _water_mask(t)
		"T":
			return "tree"
		"L":
			return "ledge"
		"F":
			return "fence"
		"#":
			return "rock"
		"^":
			return "rock_top"
		"o":
			return "stone"
		"w":
			return "floor"
		"W":
			return "inwall"
		"N":
			return "inwall_window"
		"M":
			return "mat"
		"C":
			return "counter"
		"K":
			return "shelf"
		"B":
			return "bed"
		"P":
			return "plant"
		"t":
			return "table"
		"A":
			return "altar"
		"r":
			return "rug"
		"S":
			return "stairs"
		"c":
			return "cave"
	return "black"


func _water_mask(t: Vector2i) -> int:
	var m := 0
	for k in 4:
		var d: Vector2i = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][k]
		var n := cell(t + d)
		if n == "~" or n == "X":
			m |= 1 << k
	return m


func _build_ground() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://art/tiles.png")
	src.texture_region_size = Vector2i(T, T)
	var names: Dictionary = Data.tiles.get("tiles", {})
	var skip := {}
	for m in 16:
		skip[int(names.get("water1_%d" % m, -1))] = true
	for n in names:
		var i := int(names[n])
		if not skip.has(i):
			src.create_tile(Vector2i(i % 16, i / 16))
	for m in 16:
		var i := int(names.get("water0_%d" % m, -1))
		var at := Vector2i(i % 16, i / 16)
		src.set_tile_animation_columns(at, 1)
		src.set_tile_animation_frames_count(at, 2)
		src.set_tile_animation_frame_duration(at, 0, 0.55)
		src.set_tile_animation_frame_duration(at, 1, 0.55)
	ts.add_source(src, 0)
	ground = TileMapLayer.new()
	ground.tile_set = ts
	ground.z_index = -10
	add_child(ground)
	for y in height:
		for x in width:
			var i := int(names.get(_tile_name(Vector2i(x, y)), 0))
			ground.set_cell(Vector2i(x, y), 0, Vector2i(i % 16, i / 16))
	# Black surround for maps smaller than the screen (interiors).
	RenderingServer.set_default_clear_color(Color("101018"))


func _sprite(path: String, at_tile: Vector2i, size_tiles: Vector2i = Vector2i(1, 1)) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = false
	var tw := s.texture.get_width()
	var th := s.texture.get_height()
	# Anchor: bottom-centre of the footprint.
	s.position = Vector2(at_tile.x * T + size_tiles.x * T / 2.0, (at_tile.y + size_tiles.y) * T)
	s.offset = Vector2(-tw / 2.0, -th)
	entities.add_child(s)
	return s


func _build_objects() -> void:
	for o in meta.get("objects", []):
		var sp := String(o.sprite)
		var at := Vector2i(int(o.x), int(o.y))
		var size := Vector2i(int(o.get("w", 1)), int(o.get("h", 1)))
		if sp == "campfire":
			var f := _sprite("res://art/objects/campfire0.png", at)
			_anims.append([f, "res://art/objects/campfire%d.png", 2])
		else:
			_sprite("res://art/objects/%s.png" % sp, at, size)
		var door: Array = o.get("door", [])
		var solid := bool(o.get("solid", size.x > 1 or size.y > 1 or o.has("door") or sp == "campfire" or sp == "banner"))
		if solid:
			for yy in size.y:
				for xx in size.x:
					if door.size() == 2 and xx == int(door[0]) and yy == int(door[1]):
						continue
					_solid_extra[at + Vector2i(xx, yy)] = true


func _build_things() -> void:
	for s in meta.get("signs", []):
		var t := Vector2i(int(s.x), int(s.y))
		var node: Sprite2D = null
		if not "WNKtAC".contains(cell(t)):
			node = _sprite("res://art/objects/sign.png", t)
			_solid_extra[t] = true
		things.append({"kind": "sign", "tile": t, "data": s, "node": node})
	for s in meta.get("stones", []):
		var t := Vector2i(int(s.x), int(s.y))
		var node := _sprite("res://art/objects/ring_stone0.png", t)
		_anims.append([node, "res://art/objects/ring_stone%d.png", 2])
		_solid_extra[t] = true
		things.append({"kind": "stone", "tile": t, "data": s, "node": node})
	for s in meta.get("lore", []):
		var t := Vector2i(int(s.x), int(s.y))
		var node := _sprite("res://art/objects/lore_stone.png", t)
		_solid_extra[t] = true
		things.append({"kind": "lore", "tile": t, "data": s, "node": node})
	for s in meta.get("items", []):
		if Game.done.has(String(s.id)):
			continue
		var t := Vector2i(int(s.x), int(s.y))
		var node := _sprite("res://art/objects/item.png", t)
		things.append({"kind": "item", "tile": t, "data": s, "node": node})


func _build_people() -> void:
	for n in meta.get("npcs", []):
		_add_person(n, false)
	for tr in meta.get("trainers", []):
		if tr.has("flag") and Game.has_flag(String(tr.flag)):
			continue
		_add_person(tr, true)


func _add_person(d: Dictionary, trainer: bool) -> void:
	var w := Walker.new()
	w.setup(String(d.sprite))
	w.place(Vector2i(int(d.x), int(d.y)))
	w.face(String(d.get("facing", "down")))
	entities.add_child(w)
	people[String(d.id)] = {"walker": w, "data": d, "trainer": trainer, "home": w.tile, "wait": randf_range(1.0, 3.0)}


func _fit_camera() -> void:
	var vs := get_viewport_rect().size
	var mw := width * T
	var mh := height * T
	if mw <= vs.x:
		camera.limit_left = -int((vs.x - mw) / 2)
		camera.limit_right = camera.limit_left + int(vs.x)
	else:
		camera.limit_left = 0
		camera.limit_right = mw
	if mh <= vs.y:
		camera.limit_top = -int((vs.y - mh) / 2)
		camera.limit_bottom = camera.limit_top + int(vs.y)
	else:
		camera.limit_top = 0
		camera.limit_bottom = mh


# ------------------------------------------------------------------ queries

func person_at(t: Vector2i) -> Dictionary:
	for id in people:
		var p: Dictionary = people[id]
		if (p.walker as Walker).tile == t:
			return p
	return {}


func thing_at(t: Vector2i) -> Dictionary:
	for th in things:
		if th.tile == t:
			return th
	return {}


func is_blocked(t: Vector2i) -> bool:
	if SOLID.contains(cell(t)) or _solid_extra.has(t):
		return true
	if not person_at(t).is_empty():
		return true
	var th := thing_at(t)
	if not th.is_empty() and th.kind == "item":
		return true
	if player and player.tile == t:
		return true
	return false


func warp_at(t: Vector2i) -> Dictionary:
	for w in meta.get("warps", []):
		if int(w.x) == t.x and int(w.y) == t.y:
			return w
	return {}


func in_grass(t: Vector2i) -> bool:
	return cell(t) == "\""


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	_anim_t += delta
	var f := int(_anim_t * 4.0)
	for a in _anims:
		(a[0] as Sprite2D).texture = load(String(a[1]) % (f % int(a[2])))
	_wander(delta)
	if player:
		player.set_in_grass(in_grass(player.tile) and not player.moving)
	if busy or player == null or player.moving:
		return
	if Input.is_action_just_pressed("start") and root:
		root.call("open_start_menu")
		return
	if Input.is_action_just_pressed("a"):
		_interact()
		return
	var dir := Controls.held_direction()
	if dir == "":
		_turn_delay = 0.0
		return
	if dir != player.facing and _turn_delay <= 0.0:
		# Tapping a new direction turns on the spot first, like the classics.
		player.face(dir)
		_turn_delay = 0.09
		return
	_turn_delay -= delta
	if _turn_delay > 0.0:
		return
	_try_move(dir)


func _try_move(dir: String) -> void:
	var to: Vector2i = player.tile + Controls.DIRS[dir]
	if cell(to) == "L" and dir == "down":
		await player.step(dir, 2)
		Audio.play("dodge", 1.4)
		await _after_step()
		return
	if cell(to) == "L" or is_blocked(to):
		player.face(dir)
		if not warp_at(to).is_empty():
			await _warp(warp_at(to))
		return
	await player.step(dir)
	await _after_step()


func _after_step() -> void:
	Game.tile = player.tile
	Game.facing = player.facing
	var w := warp_at(player.tile)
	if not w.is_empty() and String(cell(player.tile)) != "M":
		await _warp(w)
		return
	if not w.is_empty() and cell(player.tile) == "M" and player.facing == "down":
		await _warp(w)
		return
	if await _check_trainers():
		return
	if in_grass(player.tile) and Game.has_creature():
		var enc: Dictionary = meta.get("encounters", {})
		if not enc.is_empty() and randf() < float(enc.get("rate", 0.1)):
			busy = true
			await root.call("wild_battle", roll_wild(enc.get("table", [])))
			busy = false


static func roll_wild(table: Array) -> Dictionary:
	var total := 0.0
	for e in table:
		total += float(e[3])
	var r := randf() * total
	for e in table:
		r -= float(e[3])
		if r <= 0.0:
			return Creatures.create(String(e[0]), randi_range(int(e[1]), int(e[2])))
	return Creatures.create(String(table[0][0]), int(table[0][1]))


func _warp(w: Dictionary) -> void:
	# The map change frees this node, so start it deferred and never await it here.
	busy = true
	Audio.play("dodge", 0.8)
	root.call_deferred("change_map", String(w.to), Vector2i(int(w.tx), int(w.ty)), String(w.get("facing", "down")))


func _interact() -> void:
	var front: Vector2i = player.tile + Controls.DIRS[player.facing]
	var p := person_at(front)
	if p.is_empty() and "C".contains(cell(front)):
		p = person_at(front + Controls.DIRS[player.facing])   # talk across a counter
	if not p.is_empty():
		busy = true
		var w: Walker = p.walker
		w.face(_opposite(player.facing))
		await root.call("talk", p)
		busy = false
		return
	var th := thing_at(front)
	if not th.is_empty():
		busy = true
		await root.call("use_thing", th)
		busy = false


static func _opposite(d: String) -> String:
	return {"up": "down", "down": "up", "left": "right", "right": "left"}[d]


## Trainers who can see you walk over and challenge you.
func _check_trainers() -> bool:
	for id in people:
		var p: Dictionary = people[id]
		if not p.trainer or Game.done.has(id):
			continue
		var w: Walker = p.walker
		var dir: Vector2i = Controls.DIRS[w.facing]
		var sight := int(p.data.get("sight", 3))
		for k in range(1, sight + 1):
			var t := w.tile + dir * k
			if t == player.tile:
				busy = true
				await root.call("trainer_spotted", p)
				busy = false
				return true
			if is_blocked(t):
				break
	return false


func remove_person(id: String) -> void:
	if people.has(id):
		(people[id].walker as Walker).queue_free()
		people.erase(id)


func remove_thing(th: Dictionary) -> void:
	if th.node:
		(th.node as Node).queue_free()
	things.erase(th)


func _wander(delta: float) -> void:
	if busy:
		return
	for id in people:
		var p: Dictionary = people[id]
		var radius := int(p.data.get("wander", 0))
		if radius <= 0 or p.trainer:
			continue
		var w: Walker = p.walker
		if w.moving:
			continue
		p.wait = float(p.wait) - delta
		if p.wait > 0.0:
			continue
		p.wait = randf_range(1.2, 3.5)
		var dir: String = ["up", "down", "left", "right"].pick_random()
		var to: Vector2i = w.tile + Controls.DIRS[dir]
		var home: Vector2i = p.home
		if absi(to.x - home.x) > radius or absi(to.y - home.y) > radius or is_blocked(to) or in_grass(to) or not warp_at(to).is_empty():
			w.face(dir)
			continue
		w.step(dir)

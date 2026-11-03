extends Node
## Headless test suite: data integrity, overworld movement and warps,
## dialogue + quests, battle maths, full battles (wild, Gyria warband,
## capture, blackout), saving, and the touch pad.
##   godot --headless res://tests/test_runner.tscn

var passed := 0
var failed := 0
var root: GameRoot


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("=== Velicia test suite ===")
	Game.delete_save()
	_test_data()
	_test_maps()
	_test_battle_math()
	await _test_game()
	print("=== %d passed, %d failed ===" % [passed, failed])
	Game.delete_save()
	get_tree().quit(1 if failed > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ------------------------------------------------------------------ data

func _test_data() -> void:
	print("[data]")
	check(Data.creatures.size() >= 5, "test creatures loaded (%d)" % Data.creatures.size())
	for id in Data.creatures:
		var c: Dictionary = Data.creatures[id]
		check(String(c.name).begins_with("Test"), "%s is a labelled test creature" % id)
		for e in c.learnset:
			check(Data.moves.has(String(e[1])), "%s learns a real move (%s)" % [id, e[1]])
		check(ResourceLoader.exists("res://art/battle/%s_front.png" % id) and ResourceLoader.exists("res://art/battle/%s_back.png" % id), "%s has battle sprites" % id)
	for f in BattleLogic.FIGHTERS:
		for m in BattleLogic.FIGHTERS[f].moves:
			check(Data.moves.has(String(m)), "fighter %s move %s exists" % [f, m])
	check(Data.dialogue.size() >= 9, "dialogue files loaded (%d)" % Data.dialogue.size())
	check(Data.tiles.get("tiles", {}).size() > 40, "tile atlas index loaded")
	check(ResourceLoader.exists("res://art/font.png"), "pixel font present")


func _load_map(id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % id))
	return parsed if parsed is Dictionary else {}


func _test_maps() -> void:
	print("[maps]")
	var ids := ["home", "emoria", "guild", "shop", "route1", "ashfen"]
	for id in ids:
		var m := _load_map(id)
		check(not m.is_empty(), "map %s loads" % id)
		var rows: Array = m.rows
		var ok := true
		for r in rows:
			ok = ok and String(r).length() == int(m.width)
		check(ok and rows.size() == int(m.height), "map %s rows are rectangular" % id)
		for w in m.get("warps", []):
			var target := _load_map(String(w.to))
			var row: String = target.rows[int(w.ty)] if not target.is_empty() else ""
			var ch := row[int(w.tx)] if row.length() > int(w.tx) else "X"
			check(not target.is_empty() and not Overworld.SOLID.contains(ch), "warp %s(%d,%d) -> %s(%d,%d) lands on open ground" % [id, int(w.x), int(w.y), w.to, int(w.tx), int(w.ty)])
		for n in m.get("npcs", []):
			check(Data.dialogue.has(String(n.dialogue)), "%s: %s has dialogue" % [id, n.id])
			check(ResourceLoader.exists("res://art/chars/%s.png" % n.sprite), "%s: %s sprite exists" % [id, n.id])
		for t in m.get("trainers", []):
			check((t.team as Array).size() > 0, "%s: trainer %s has a team" % [id, t.id])


# ------------------------------------------------------------------ battle maths

func _test_battle_math() -> void:
	print("[battle maths]")
	var a := BattleLogic.actor_from_creature(Creatures.create("alpha", 10))
	var g := BattleLogic.actor_from_creature(Creatures.create("gamma", 10))
	var b := BattleLogic.actor_from_creature(Creatures.create("beta", 10))
	var ember := Data.move("ember_spit")
	var strong := BattleLogic.damage(a, g, ember, 1.0, 0)
	var weak := BattleLogic.damage(a, b, ember, 1.0, 0)
	check(int(strong.damage) > int(weak.damage), "ember beats verdant, not tide (%d vs %d)" % [strong.damage, weak.damage])
	var w := BattleLogic.actor_warrior()
	var hit := BattleLogic.damage(a, w, Data.move("scratch"), 1.0, 0)
	w.guarding = true
	var guarded := BattleLogic.damage(a, w, Data.move("scratch"), 1.0, 0)
	check(int(guarded.damage) < int(hit.damage), "guarding halves damage to the warrior (%d -> %d)" % [hit.damage, guarded.damage])
	var wild := Creatures.create("delta", 4)
	var full := BattleLogic.capture_chance(wild)
	wild.hp = 1
	check(BattleLogic.capture_chance(wild) > full, "weakened creatures are easier to bind")
	var f := BattleLogic.actor_fighter("gyria_boss", "Vorga", 9)
	check(int(f.max_hp) > int(BattleLogic.actor_fighter("gyria", "Scout", 9).max_hp), "the Warchief is tougher than a scout")
	var c := Creatures.create("alpha", 5)
	var ev := Creatures.gain_xp(c, 2000)
	check(int(c.level) > 5 and ev.size() > 0, "creatures level up and learn moves (%s)" % str(ev))


# ------------------------------------------------------------------ the game

func _test_game() -> void:
	print("[game]")
	root = GameRoot.new()
	root.skip_title = true
	add_child(root)
	root.set_meta("auto_text", true)
	root.box.auto_advance = true
	root.box.instant = true
	Game.new_game("TESTER")
	await root.change_map("home", Vector2i(3, 4), "down", false)
	var ow := root.world
	check(ow.map_id == "home" and ow.player.tile == Vector2i(3, 4), "starts in the lodging")
	# Walls block, open floor allows movement.
	await ow._try_move("left")
	check(ow.player.tile == Vector2i(2, 4), "walks one tile")
	await ow._try_move("up")
	await ow._try_move("up")
	await ow._try_move("up")
	check(ow.player.tile.y >= 1, "walls stop the player (y=%d)" % ow.player.tile.y)
	# Door mat warps to town.
	await root.change_map("home", Vector2i(3, 6), "down", false)
	await root.world._try_move("down")
	await frames(30)
	check(root.world.map_id == "emoria", "the door mat leads into town")
	# Dialogue + starter
	await root.change_map("guild", Vector2i(2, 4), "up", false)
	root._choice_script = [1]        # "Where do I get a ring?"
	await root.run_dialogue("warden")
	check(Game.quest_stage_id("emoria_watch") == "get_ring", "the Warden sends you to the ring-sage")
	root._choice_script = [0]        # confirm YES
	root.screen.scripted = ["a"]     # the picker starts on TEST B
	await root.run_dialogue("oddrin")
	check(Game.party.size() == 1, "a starter creature is bound")
	check(Game.has_item("binding_ring", 5), "Oddrin gives Binding Rings")
	check(Game.quest_stage_id("emoria_watch") == "scout", "quest moves on to the scout")
	# Wild battle: creature move + warrior strike every turn until it ends.
	Game.party[0].level = 12
	Game.party[0].hp = Creatures.max_hp(Game.party[0])
	var lvl_before := int(Game.player.level)
	var xp_before := int(Game.party[0].xp)
	root._choice_script = []
	for i in 40:
		root._choice_script.append_array([0, 0])
	var res: String = await root.battle.run_wild(Creatures.create("gamma", 3))
	check(res == "win", "wild battle won with creature + warrior (%s)" % res)
	check(int(Game.party[0].xp) > xp_before, "the creature gains XP")
	check(int(Game.player.xp) > Creatures.xp_for_level(lvl_before), "the warrior gains XP too")
	# Capture: weaken, then RING (warrior action 3) with a forced success.
	root.set_meta("force_capture", 1)
	root._choice_script = [0, 3]
	var before := Game.party.size()
	res = await root.battle.run_wild(Creatures.create("delta", 2))
	check(res == "caught" and Game.party.size() == before + 1, "a Binding Ring binds a wild creature (%s)" % res)
	root.remove_meta("force_capture")
	root._check_quest_hooks()
	check(Game.quest_stage_id("first_bond") == "report", "binding a creature advances 'A Ring Is a Promise'")
	# Gyria warband: two enemies at once, coins on victory.
	await root.change_map("route1", Vector2i(2, 9), "right", false)
	var tr: Dictionary = {}
	for x in root.world.meta.trainers:
		if x.id == "scout_c":
			tr = x
	root._choice_script = []
	for i in 80:
		root._choice_script.append_array([0, 0, 0, 0])
	Game.party[0].hp = Creatures.max_hp(Game.party[0])
	Game.player.hp = Game.trainer_max_hp()
	var coins := Game.coins
	var p: Dictionary = root.world.people.get("scout_c", {})
	if not p.is_empty():
		await root.trainer_spotted(p, true)
	check(Game.done.has("scout_c") and Game.coins > coins, "beating a Gyria warband pays marks and marks them done")
	# Guard: enemies all hit the warrior.
	var bt := root.battle
	bt.warrior = BattleLogic.actor_warrior()
	bt.ally = BattleLogic.actor_from_creature(Game.party[0])
	bt.enemies = [BattleLogic.actor_fighter("gyria", "X", 5)]
	bt.warrior.guarding = true
	var tgts := bt._targets_for(bt.enemies[0], "creature", Data.move("slash"))
	check(tgts.size() == 1 and tgts[0] == bt.warrior, "a guarding warrior shields the creature")
	# Blackout: the warrior falls -> lose -> back to the last Ring Stone.
	Game.respawn = {"map": "emoria", "x": 16, "y": 10}
	Game.player.hp = 1
	root._choice_script = []
	for i in 40:
		root._choice_script.append_array([0, 1])   # creature attacks, warrior guards (takes every hit)
	res = await root.battle.run_trainer({"name": "Test Warband", "team": [{"fighter": "gyria_boss", "name": "Big", "level": 30}]})
	check(res == "lose", "losing your warrior loses the battle (%s)" % res)
	await root.blackout()
	check(root.world.map_id == "emoria" and Game.player.hp == Game.trainer_max_hp(), "blackout returns you to the Ring Stone, healed")
	# Save / load
	Game.set_flag("test_flag")
	check(Game.save_game(), "game saves")
	var party_n := Game.party.size()
	Game.reset()
	check(Game.load_game() and Game.has_flag("test_flag") and Game.party.size() == party_n, "game loads with flags and creatures")
	# Touch pad: tapping A presses the action.
	var pad := root.touch
	pad.visible = true
	pad._layout()
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = pad.get_global_transform_with_canvas() * (pad._pads.a as Rect2).get_center()
	pad._input(ev)
	check(Input.is_action_pressed("a"), "touching A presses the A button")
	ev.pressed = false
	pad._input(ev)
	check(not Input.is_action_pressed("a"), "lifting the finger releases A")

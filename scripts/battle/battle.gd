class_name Battle
extends GBox
## Turn-based battles in the classic handheld style, with one twist: your
## warrior fights too. Each turn you give your ring creature a command
## (a move or SWAP) and your warrior one (STRIKE, GUARD, RING, BAG or RUN).
## Enemies attack either of you. Gyria warbands field a fighter and a
## creature at once. Lose your warrior and you black out.

var root: Node                       # GameRoot (text box & menus)
var warrior: Dictionary = {}
var ally: Dictionary = {}           # active creature actor ({} if none)
var ally_index := -1
var enemies: Array = []              # actors on the field (max 2)
var reserve: Array = []              # trainer team members waiting
var is_wild := false
var trainer: Dictionary = {}
var participants: Dictionary = {}    # creature uid -> true (share XP)
var _shake := 0.0
var _flash: Dictionary = {}          # actor -> time
var _lunge: Dictionary = {}          # actor -> time
var _shown_hp: Dictionary = {}
var _ring_anim := -1.0
var _ring_wobble := 0.0
var _intro := 0.0
var _t := 0.0
var _tex: Dictionary = {}
var result := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


# ------------------------------------------------------------------ entry points

func run_wild(c: Dictionary) -> String:
	is_wild = true
	trainer = {}
	enemies = [BattleLogic.actor_from_creature(c, true)]
	reserve = []
	return await _run(["A wild %s appeared!" % enemies[0].name])


func run_trainer(d: Dictionary) -> String:
	is_wild = false
	trainer = d
	var team: Array = []
	for e in d.get("team", []):
		if e.has("fighter"):
			team.append(BattleLogic.actor_fighter(String(e.fighter), String(e.get("name", "Gyria")), int(e.level)))
		else:
			team.append(BattleLogic.actor_from_creature(Creatures.create(String(e.species), int(e.level))))
	enemies = team.slice(0, 2)
	reserve = team.slice(2)
	var names: Array = []
	for e in enemies:
		names.append(String(e.name))
	return await _run(["%s wants to fight!" % String(d.get("name", "Gyria")).to_upper(), " and ".join(names) + " step up!"])


func _run(intro_lines: Array) -> String:
	result = ""
	warrior = BattleLogic.actor_warrior()
	ally_index = Game.first_able_index()
	ally = BattleLogic.actor_from_creature(Game.party[ally_index]) if ally_index >= 0 else {}
	participants.clear()
	if ally_index >= 0:
		participants[int(Game.party[ally_index].uid)] = true
	_shown_hp.clear()
	visible = true
	_intro = 0.0
	Audio.music("battle")
	Events.battle_started.emit()
	for l in intro_lines:
		await _say(l)
	if not ally.is_empty():
		await _say("Go, %s! %s draws a blade beside it." % [ally.name, warrior.name])
	while result == "":
		await _turn()
	_sync_back()
	box().close()
	visible = false
	Events.battle_ended.emit(result)
	return result


func box() -> TextBox:
	return root.box if root else null


func _say(t: String) -> void:
	if root:
		await root.box.say(t)


## Shows a prompt without waiting for A (the menu appears beside it).
func _prompt(t: String) -> void:
	if root:
		root.box.instant = true
		root.box.auto_advance = true
		await root.box.say(t)
		root.box.instant = false
		root.box.auto_advance = root.has_meta("auto_text")


func _choose(opts: Array, can_cancel: bool = true) -> int:
	if root and not root._choice_script.is_empty():
		await get_tree().process_frame
		return int(root._choice_script.pop_front())
	return await root.menu.choose(opts, "battle", can_cancel)


# ------------------------------------------------------------------ a turn

func _turn() -> void:
	var actions: Array = []   # {actor, kind, move, target}
	# 1) Your creature's command
	if not ally.is_empty():
		while true:
			var opts: Array = []
			for m in ally.moves:
				opts.append(String(Data.move(String(m)).name).to_upper())
			if Game.party.size() > 1:
				opts.append("SWAP")
			await _prompt("What will %s do?" % ally.name)
			var i: int = await _choose(opts, false)
			if i < ally.moves.size():
				var mid := String(ally.moves[i])
				actions.append({"actor": ally, "kind": "move", "move": mid, "target": await _pick_target(Data.move(mid))})
				break
			var sw := await _pick_swap()
			if sw >= 0:
				actions.append({"actor": ally, "kind": "swap", "index": sw})
				break
	# 2) Your warrior's command
	while true:
		var wopts := ["STRIKE", "GUARD", "BAG", "RING" if is_wild else "-", "RUN" if is_wild else "-"]
		await _prompt("And %s?" % warrior.name)
		var w: int = await _choose(wopts, false)
		match w:
			0:
				actions.append({"actor": warrior, "kind": "move", "move": "strike", "target": await _pick_target(Data.move("strike"))})
				break
			1:
				actions.append({"actor": warrior, "kind": "guard"})
				break
			2:
				var item: String = await root.screen.bag(true)
				if item == "":
					continue
				var use := await _prepare_item(item)
				if use.is_empty():
					continue
				actions.append(use)
				break
			3:
				if not is_wild:
					continue
				var ring := _best_ring()
				if ring == "":
					await _say("You have no Binding Rings!")
					continue
				actions.append({"actor": warrior, "kind": "ring", "item": ring})
				break
			4:
				if not is_wild:
					continue
				actions.append({"actor": warrior, "kind": "run"})
				break
	# Guard is instant (it protects for the whole turn).
	warrior.guarding = false
	for a in actions:
		if a.kind == "guard":
			warrior.guarding = true
	# 3) Enemy commands
	for e in enemies:
		var mid := BattleLogic.ai_move(e)
		var tgt := BattleLogic.ai_target(e, not ally.is_empty())
		actions.append({"actor": e, "kind": "move", "move": mid, "target": tgt})
	# 4) Resolve in speed order (special actions first)
	actions.sort_custom(_order)
	for a in actions:
		if result != "":
			return
		if int(a.actor.hp) <= 0:
			continue
		if not _on_field(a.actor):
			continue
		await _resolve(a)
		await _check_faints()
	warrior.guarding = false


func _on_field(actor: Dictionary) -> bool:
	var id := int(actor.bid)
	if id == int(warrior.bid) or (not ally.is_empty() and id == int(ally.bid)):
		return true
	for e in enemies:
		if int(e.bid) == id:
			return true
	return false


func _is_enemy(actor: Dictionary) -> bool:
	for e in enemies:
		if int(e.bid) == int(actor.bid):
			return true
	return false


func _order(a: Dictionary, b: Dictionary) -> bool:
	var pr := {"run": 5, "swap": 4, "item": 4, "ring": 3, "guard": 3}
	var pa := int(pr.get(a.kind, 0))
	var pb := int(pr.get(b.kind, 0))
	if pa != pb:
		return pa > pb
	var ma := Data.move(String(a.get("move", ""))) if a.kind == "move" else {}
	var mb := Data.move(String(b.get("move", ""))) if b.kind == "move" else {}
	return BattleLogic.goes_first(a.actor, ma, b.actor, mb)


func _pick_target(m: Dictionary) -> Variant:
	if String(m.get("kind", "attack")) != "attack" or bool(m.get("all", false)) or enemies.size() <= 1:
		return 0
	var opts: Array = []
	for e in enemies:
		opts.append(String(e.name).substr(0, 14))
	var i: int = await _choose(opts, false)
	return clampi(i, 0, enemies.size() - 1)


func _pick_swap() -> int:
	var i: int = await root.screen.party(true)
	if i < 0 or i == ally_index or Creatures.is_fainted(Game.party[i]):
		return -1
	return i


func _best_ring() -> String:
	for id in ["silver_ring", "binding_ring"]:
		if Game.has_item(id):
			return id
	return ""


func _prepare_item(item: String) -> Dictionary:
	var kind := String(Data.item(item).get("kind", ""))
	match kind:
		"heal_creature":
			if ally.is_empty():
				await _say("No creature to heal!")
				return {}
			return {"actor": warrior, "kind": "item", "item": item, "on": "creature"}
		"heal_player":
			return {"actor": warrior, "kind": "item", "item": item, "on": "warrior"}
		"capture":
			if not is_wild:
				await _say("You can't bind a creature that serves another!")
				return {}
			return {"actor": warrior, "kind": "ring", "item": item}
	await _say("That can't be used now.")
	return {}


# ------------------------------------------------------------------ resolving

func _resolve(a: Dictionary) -> void:
	var actor: Dictionary = a.actor
	match String(a.kind):
		"guard":
			await _say("%s raises a shield to guard!" % actor.name)
		"swap":
			await _swap_to(int(a.index))
		"item":
			await _use_item(a)
		"ring":
			await _throw_ring(String(a.item))
		"run":
			var mine := float(ally.spd) if not ally.is_empty() else float(warrior.spd)
			if randf() < BattleLogic.run_chance(mine, float(enemies[0].spd)):
				Audio.play("dodge")
				await _say("Got away safely!")
				result = "ran"
			else:
				await _say("Couldn't get away!")
		"move":
			await _use_move(actor, String(a.move), a.target)


func _targets_for(actor: Dictionary, target: Variant, m: Dictionary) -> Array:
	var on_player := not _is_enemy(actor)
	if not on_player:
		# Enemy attacking us: a guarding warrior takes every blow.
		if warrior.guarding:
			return [warrior]
		if bool(m.get("all", false)):
			return [warrior] + ([ally] if not ally.is_empty() else [])
		if String(target) == "creature" and not ally.is_empty():
			return [ally]
		return [warrior]
	if bool(m.get("all", false)):
		return enemies.duplicate()
	if enemies.is_empty():
		return []
	return [enemies[clampi(int(target), 0, enemies.size() - 1)]]


func _use_move(actor: Dictionary, mid: String, target: Variant) -> void:
	var m := Data.move(mid)
	await _say("%s used %s!" % [actor.name, String(m.name).to_upper()])
	var kind := String(m.get("kind", "attack"))
	if kind == "buff":
		var st := String(m.get("stat", "atk"))
		actor.stages[st] = clampi(int(actor.stages.get(st, 0)) + int(m.get("stages", 1)), -6, 6)
		await _say("%s's %s rose!" % [actor.name, st.to_upper()])
		return
	if kind == "heal":
		var amt := int(float(actor.max_hp) * float(m.get("amount", 0.4)))
		actor.hp = mini(int(actor.max_hp), int(actor.hp) + amt)
		Audio.play("ring_summon")
		await _say("%s recovered health!" % actor.name)
		return
	var targets := _targets_for(actor, target, m)
	if kind == "debuff":
		for t in targets:
			var st := String(m.get("stat", "atk"))
			t.stages[st] = clampi(int(t.stages.get(st, 0)) + int(m.get("stages", -1)), -6, 6)
			await _say("%s's %s fell!" % [t.name, st.to_upper()])
		return
	_lunge[int(actor.bid)] = 0.25
	Audio.play("creature_attack" if actor.kind == "creature" else "hit", 1.0)
	for t in targets:
		if int(t.hp) <= 0:
			continue
		if not BattleLogic.hits(m):
			await _say("%s missed!" % actor.name)
			continue
		var r := BattleLogic.damage(actor, t, m)
		t.hp = maxi(0, int(t.hp) - int(r.damage))
		_flash[int(t.bid)] = 0.5
		if bool(r.crit) or int(t.bid) == int(warrior.bid):
			_shake = 0.3
		Audio.play("hit", 0.8 if bool(r.crit) else 1.1)
		await _animate_hp(t)
		if bool(r.crit):
			await _say("A critical hit!")
		if float(r.mult) > 1.5:
			await _say("It's super effective!")
		elif float(r.mult) < 0.75:
			await _say("It's not very effective...")


func _animate_hp(t: Dictionary) -> void:
	var start := float(_shown_hp.get(int(t.bid), t.hp))
	var goal := float(t.hp)
	var k := 0.0
	while k < 1.0:
		k += get_process_delta_time() * 2.5
		_shown_hp[int(t.bid)] = lerpf(start, goal, minf(k, 1.0))
		await get_tree().process_frame
	_shown_hp[int(t.bid)] = goal


func _use_item(a: Dictionary) -> void:
	var item := String(a.item)
	if not Game.take_item(item):
		return
	var it := Data.item(item)
	Audio.play("ring_summon")
	if String(a.on) == "creature" and not ally.is_empty():
		ally.hp = mini(int(ally.max_hp), int(ally.hp) + int(it.get("amount", 25)))
		await _animate_hp(ally)
		await _say("%s used a %s on %s!" % [warrior.name, String(it.name).to_upper(), ally.name])
	else:
		warrior.hp = int(warrior.max_hp)
		await _animate_hp(warrior)
		await _say("%s drank a %s and feels strong!" % [warrior.name, String(it.name).to_upper()])


func _throw_ring(ring: String) -> void:
	if not Game.take_item(ring):
		return
	var wild: Dictionary = enemies[0]
	await _say("%s threw a %s!" % [warrior.name, String(Data.item(ring).name).to_upper()])
	_ring_anim = 0.0
	Audio.play("ring_summon")
	await get_tree().create_timer(0.5).timeout
	var c: Dictionary = wild.ref
	c.hp = int(wild.hp)
	var chance := BattleLogic.capture_chance(c, float(Data.item(ring).get("bonus", 1.0)))
	var caught := randf() < chance
	if root and root.has_meta("force_capture"):
		caught = int(root.get_meta("force_capture")) == 1
	var wobbles := 3 if caught else randi_range(0, 2)
	for i in wobbles:
		_ring_wobble = 0.4
		Audio.play("block", 1.4)
		await get_tree().create_timer(0.5).timeout
	if caught:
		Audio.play("ring_capture")
		_ring_anim = 99.0
		await _say("Bound! %s is now in a ring." % wild.name)
		var where := Game.add_creature(c)
		if where == "vault":
			await _say("Your rings are full. %s went to the Guild vault." % wild.name)
		Events.creature_bound.emit(c)
		result = "caught"
	else:
		_ring_anim = -1.0
		Audio.play("ring_fail")
		await _say(["Oh no! It broke free!", "Almost had it!", "Argh! So close!"][clampi(wobbles, 0, 2)])


func _swap_to(i: int) -> void:
	if not ally.is_empty():
		_store_ally()
		await _say("Come back, %s!" % ally.name)
	ally_index = i
	ally = BattleLogic.actor_from_creature(Game.party[i])
	participants[int(Game.party[i].uid)] = true
	await _say("Go, %s!" % ally.name)


func _store_ally() -> void:
	if ally.is_empty():
		return
	var c: Dictionary = ally.ref
	c.hp = int(ally.hp)


func _check_faints() -> void:
	for e in enemies.duplicate():
		if int(e.hp) > 0:
			continue
		await _say("%s fainted!" % e.name if e.kind == "creature" else "%s is defeated!" % e.name)
		enemies.erase(e)
		await _award_xp(e)
		if not reserve.is_empty():
			var nxt: Dictionary = reserve.pop_front()
			enemies.append(nxt)
			await _say("%s joins the fight!" % nxt.name)
	if enemies.is_empty():
		Audio.music("victory")
		result = "win"
		return
	if not ally.is_empty() and int(ally.hp) <= 0:
		await _say("%s fainted!" % ally.name)
		_store_ally()
		ally = {}
		var nxt := Game.first_able_index()
		if nxt >= 0:
			await _say("Choose your next creature!")
			var pick := -1
			while pick < 0:
				pick = await root.screen.party(true)
				if pick >= 0 and Creatures.is_fainted(Game.party[pick]):
					pick = -1
			await _swap_to(pick)
		else:
			await _say("%s fights on alone!" % warrior.name)
	if int(warrior.hp) <= 0:
		await _say("%s collapses!" % warrior.name)
		result = "lose"


func _award_xp(defeated: Dictionary) -> void:
	var base := int(float(defeated.level) * (60.0 if defeated.kind == "creature" else 75.0) / 5.0) + 6
	if not is_wild:
		base = int(base * 1.4)
	if not ally.is_empty():
		var c: Dictionary = ally.ref
		c.hp = int(ally.hp)
		var events := Creatures.gain_xp(c, base)
		await _say("%s gained %d XP!" % [ally.name, base])
		for ev in events:
			var parts := String(ev).split(":")
			if parts[0] == "level":
				Audio.play("level_up")
				var hp_gain := Creatures.max_hp(c) - int(ally.max_hp)
				ally.max_hp = Creatures.max_hp(c)
				ally.hp = int(ally.hp) + maxi(0, hp_gain)
				ally.atk = Creatures.stat(c, "atk")
				ally.def = Creatures.stat(c, "def")
				ally.spd = Creatures.stat(c, "spd")
				await _say("%s grew to level %s!" % [ally.name, parts[1]])
			elif parts[0] == "learn":
				ally.moves = c.moves.duplicate()
				await _say("%s learned %s!" % [ally.name, String(Data.move(parts[1]).name).to_upper()])
	var wxp := int(base * 0.6)
	var ups := Game.trainer_gain_xp(wxp)
	if ups > 0:
		Audio.play("level_up")
		warrior.level = int(Game.player.level)
		warrior.max_hp = Game.trainer_max_hp()
		warrior.hp = int(warrior.hp) + 5 * ups
		warrior.atk = Game.trainer_stat("atk")
		warrior.def = Game.trainer_stat("def")
		warrior.spd = Game.trainer_stat("spd")
		await _say("%s grew to level %d!" % [warrior.name, int(Game.player.level)])


func _sync_back() -> void:
	_store_ally()
	Game.player.hp = clampi(int(warrior.hp), 0, Game.trainer_max_hp())
	if result == "lose":
		Game.player.hp = 0
	for c in Game.party:
		if participants.has(int(c.uid)):
			c.bond = int(c.get("bond", 0)) + (1 if result in ["win", "caught"] else 0)
	Events.party_changed.emit()


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_intro = minf(1.0, _intro + delta * 2.5)
	_shake = maxf(0.0, _shake - delta)
	_ring_wobble = maxf(0.0, _ring_wobble - delta)
	if _ring_anim >= 0.0 and _ring_anim < 1.0:
		_ring_anim = minf(1.0, _ring_anim + delta * 2.0)
	for d in [_flash, _lunge]:
		for k in d.keys():
			d[k] = float(d[k]) - delta
			if float(d[k]) <= 0.0:
				d.erase(k)
	queue_redraw()


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


func _stage() -> Rect2:
	return stage_rect()


func _draw() -> void:
	if not visible:
		return
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color("f8f8f0"))
	var st := _stage()
	var off := Vector2(randf_range(-2, 2), randf_range(-1, 1)) if _shake > 0.0 else Vector2.ZERO
	var x0 := st.position.x + off.x
	var w := st.size.x
	# Platforms
	var enemy_floor := Vector2(x0 + w - 66, 62 + off.y)
	var ally_floor := Vector2(x0 + 58, 110 + off.y)
	_ellipse(enemy_floor, Vector2(46, 7), Color("d0e0a8"), Color("88a860"))
	_ellipse(ally_floor, Vector2(54, 8), Color("d0e0a8"), Color("88a860"))
	var slide := (1.0 - _intro) * 120.0
	# Enemies (front sprites, standing on the right platform)
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var base := enemy_floor + Vector2((i - (enemies.size() - 1) * 0.5) * 46.0 + slide, 2 + i * 3)
		_draw_actor(e, base, false)
	# Your side (back sprites): warrior on the left, creature beside them
	_draw_actor(warrior, ally_floor + Vector2(-28 - slide, 4), true)
	if not ally.is_empty():
		_draw_actor(ally, ally_floor + Vector2(24 - slide, 4), true)
	# Status boxes
	var ey := 4.0
	for e in enemies:
		_status(Vector2(x0 + 4, ey), e, false)
		ey += 22.0
	var py := 64.0
	if not ally.is_empty():
		_status(Vector2(x0 + w - 86, py), ally, true)
		py += 24.0
	_status(Vector2(x0 + w - 86, py), warrior, true)
	# Ring throw
	if _ring_anim >= 0.0 and _ring_anim <= 1.0 and not enemies.is_empty():
		var target := enemy_floor + Vector2(0, -20)
		var p := (ally_floor + Vector2(-20, -40)).lerp(target, _ring_anim) + Vector2(0, -sin(_ring_anim * PI) * 30.0)
		p.x += sin(_t * 40.0) * 3.0 * (1.0 if _ring_wobble > 0.0 else 0.0)
		var r := tex("res://art/ui/ring.png")
		if r:
			draw_texture(r, p - Vector2(8, 8))


func _ellipse(c: Vector2, r: Vector2, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(c + Vector2(cos(TAU * i / 24.0) * r.x, sin(TAU * i / 24.0) * r.y))
	draw_colored_polygon(pts, edge)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * Vector2(0.94, 0.8) - Vector2(0, 1))
	draw_colored_polygon(inner, fill)


func _draw_actor(a: Dictionary, feet: Vector2, back: bool) -> void:
	if int(a.hp) <= 0 and not _flash.has(int(a.bid)):
		return
	if _flash.has(int(a.bid)) and int(float(_flash[int(a.bid)]) * 16.0) % 2 == 0:
		return
	if a.kind == "creature" and a.get("wild", false) and _ring_anim >= 0.99:
		return
	var path := ""
	var scale := 1.0
	match String(a.kind):
		"creature":
			path = "res://art/battle/%s_%s.png" % [a.sprite, "back" if back else "front"]
		"warrior":
			path = "res://art/battle/trainer.png"
			scale = 2.0
		"fighter":
			path = "res://art/battle/%s.png" % a.sprite
			scale = 2.0
	var t := tex(path)
	if t == null:
		return
	var size := t.get_size() * scale
	var lunge := 0.0
	if _lunge.has(int(a.bid)):
		lunge = sin((0.25 - float(_lunge[int(a.bid)])) / 0.25 * PI) * 8.0 * (1.0 if back else -1.0)
	var pos := feet - Vector2(size.x / 2.0, size.y) + Vector2(lunge, -lunge * 0.4)
	if a.kind == "creature" and not back:
		pos.y += sin(_t * 3.0) * 1.0
	draw_texture_rect(t, Rect2(pos.round(), size), false)


func _status(p: Vector2, a: Dictionary, mine: bool) -> void:
	var w := 84.0
	var h := 20.0 if not mine else 22.0
	draw_rect(Rect2(p, Vector2(w, h)), Color("f8f8f0"))
	draw_rect(Rect2(p + Vector2(0, h - 2), Vector2(w, 2)), INK)
	draw_rect(Rect2(p + Vector2(w - 2, 2), Vector2(2, h - 2)), INK)
	var label := String(a.name).substr(0, 9)
	if a.kind == "warrior":
		label = "|" + label.substr(0, 8)
	text(p + Vector2(2, 1), label)
	text(p + Vector2(w - 26, 1), "L%d" % int(a.level))
	var shown := float(_shown_hp.get(int(a.bid), a.hp))
	var frac := shown / float(maxi(1, int(a.max_hp)))
	if mine:
		hp_bar(p + Vector2(2, 12), 36, frac)
		text(p + Vector2(42, 10), "%d/%d" % [roundi(shown), int(a.max_hp)])
	else:
		text(p + Vector2(2, 10), "HP")
		hp_bar(p + Vector2(16, 11), w - 22, frac)

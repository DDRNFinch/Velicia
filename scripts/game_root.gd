class_name GameRoot
extends Node
## Runs the game: title screen, maps, dialogue, trainers, battles, the START
## menu, the starter choice, the shop and blackouts. The Overworld calls back
## into these (awaitable) flows.

var world: Overworld
var ui: CanvasLayer
var box: TextBox
var menu: MenuBox
var screen: PanelScreen
var battle: Battle
var touch: TouchPad
var fade: ColorRect
var title: TitleScreen
var _choice_script: Array = []    # tests: picks for dialogue choices
var skip_title := false           # tests / screenshots start straight in
var force_touch := false          # show the touch pad on desktop (screenshots)


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("101018"))
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	battle = Battle.new()
	battle.root = self
	ui.add_child(battle)
	screen = PanelScreen.new()
	ui.add_child(screen)
	box = TextBox.new()
	ui.add_child(box)
	menu = MenuBox.new()
	ui.add_child(menu)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(fade)
	touch = TouchPad.new()
	touch.force_visible = force_touch
	var tl := CanvasLayer.new()
	tl.layer = 20
	add_child(tl)
	tl.add_child(touch)
	if not skip_title:
		show_title()


# ------------------------------------------------------------------ title

func show_title() -> void:
	title = TitleScreen.new()
	ui.add_child(title)
	ui.move_child(title, 0)
	Audio.music("title")
	var pick: String = await title.done
	title.queue_free()
	title = null
	if pick == "continue" and Game.load_game():
		start_session()
	else:
		Game.new_game("WARDEN")
		start_session()
		await say_lines(["Welcome to the Emoria Guild, warden.", "Your ring is empty, your road is long. Report to Warden Aldren in the Guild Hall."])


func start_session() -> void:
	await change_map(Game.map_id, Game.tile, Game.facing, false)


# ------------------------------------------------------------------ maps

func change_map(id: String, at: Vector2i, facing: String, with_fade: bool = true) -> void:
	if with_fade:
		await _fade(1.0)
	if world:
		world.queue_free()
		await get_tree().process_frame
	world = Overworld.new()
	world.root = self
	add_child(world)
	move_child(world, 0)
	world.load_map(id)
	world.player.place(at)
	world.player.face(facing)
	Game.map_id = id
	Game.tile = at
	Game.facing = facing
	Audio.music(String(world.meta.get("music", "route")))
	if with_fade:
		await _fade(0.0)
	world.busy = false


func _fade(to: float) -> void:
	var t := create_tween()
	t.tween_property(fade, "color:a", to, 0.18)
	await t.finished


# ------------------------------------------------------------------ text helpers

func say(t: String) -> void:
	await box.say(t)
	box.close()


func say_lines(lines: Array) -> void:
	for l in lines:
		await box.say(String(l))
	box.close()


func ask(question: String, options: Array) -> int:
	if not question.is_empty():
		await box.say(question)
	var i: int
	if not _choice_script.is_empty():
		i = int(_choice_script.pop_front())
	else:
		i = await menu.choose(options, "above_box", false)
	box.close()
	return i


# ------------------------------------------------------------------ people & things

func talk(p: Dictionary) -> void:
	var d: Dictionary = p.data
	if p.trainer and not Game.done.has(String(d.id)):
		await trainer_spotted(p, true)
		return
	if p.trainer:
		await say(String(d.get("lose", "...")))
		return
	await run_dialogue(String(d.get("dialogue", d.id)))
	_check_quest_hooks()


func run_dialogue(id: String) -> void:
	var r := DialogueRunner.new()
	var pending: Array = []
	var notes: Array = []
	r.request.connect(func(kind: String) -> void: pending.append(kind))
	var on_toast := func(t: String) -> void: notes.append(t)
	Events.toast.connect(on_toast)
	var nid := r.start(id)
	var guard := 0
	while nid != "" and guard < 60:
		guard += 1
		var n := r.node(nid)
		if n.is_empty():
			break
		for line in r.lines(n):
			await box.say(String(line))
		r.apply(n)
		while not notes.is_empty():
			await box.say("%s %s!" % [Game.player.name, String(notes.pop_front()).replace("Received", "received")])
		while not pending.is_empty():
			box.close()
			await handle_request(String(pending.pop_front()))
		var ch := r.choices(n)
		if ch.is_empty():
			nid = String(n.get("next", ""))
			continue
		var labels: Array = []
		for c in ch:
			labels.append(String(c.text).to_upper().substr(0, 20))
		var pick := 0
		if not _choice_script.is_empty():
			pick = int(_choice_script.pop_front())
		else:
			pick = await menu.choose(labels, "above_box", false)
		nid = String(ch[clampi(pick, 0, ch.size() - 1)].get("next", ""))
	Events.toast.disconnect(on_toast)
	box.close()


func handle_request(kind: String) -> void:
	match kind:
		"starter":
			await choose_starter()
		"shop":
			await screen.shop()


func use_thing(th: Dictionary) -> void:
	var d: Dictionary = th.data
	match String(th.kind):
		"sign":
			await say(String(d.text))
		"stone":
			Game.heal_all()
			Game.respawn = {"map": world.map_id, "x": world.player.tile.x, "y": world.player.tile.y}
			Audio.play("ring_summon")
			await say("The Ring Stone hums. Your warrior and creatures are fully restored!")
		"lore":
			Game.set_flag(String(d.id))
			await say_lines([String(d.title).to_upper(), String(d.text)])
			if String(d.id) == "lore_glassmere" and Game.quest_active("ilith_stone"):
				Game.set_quest_stage("ilith_stone", "report")
		"item":
			Game.give_item(String(d.item), int(d.get("count", 1)))
			Game.done[String(d.id)] = true
			world.remove_thing(th)
			Audio.play("pickup")
			await say("%s found %s x%d!" % [Game.player.name, String(Data.item(String(d.item)).get("name", d.item)).to_upper(), int(d.get("count", 1))])


func trainer_spotted(p: Dictionary, talked: bool = false) -> void:
	var w: Walker = p.walker
	var d: Dictionary = p.data
	if not talked:
		var ex := Sprite2D.new()
		ex.texture = load("res://art/ui/exclaim.png")
		ex.position = Vector2(0, -w.frame_h - 10)
		w.add_child(ex)
		Audio.play("alert")
		await get_tree().create_timer(0.6).timeout
		ex.queue_free()
		# Walk up to the player.
		var dir: Vector2i = Controls.DIRS[w.facing]
		while w.tile + dir != world.player.tile:
			await w.step(w.facing)
		world.player.face(Overworld._opposite(w.facing))
	await say(String(d.get("intro", "Fight me!")))
	var result: String = await battle.run_trainer(d)
	_resume_music()
	if result == "win":
		Game.done[String(d.id)] = true
		var reward := int(d.get("reward", 50))
		Game.add_coins(reward)
		if d.has("flag") and not String(d.flag).is_empty():
			Game.set_flag(String(d.flag))
		await say_lines([String(d.get("lose", "...")), "%s got %d marks for winning!" % [Game.player.name, reward]])
		_check_quest_hooks()
		if bool(d.get("boss", false)):
			world.remove_person(String(d.id))
	elif result == "lose":
		await blackout()


func wild_battle(c: Dictionary) -> void:
	var result: String = await battle.run_wild(c)
	_resume_music()
	if result == "lose":
		await blackout()
	_check_quest_hooks()


func _resume_music() -> void:
	if world:
		Audio.music(String(world.meta.get("music", "route")))


func blackout() -> void:
	await say_lines(["%s has no strength left to fight..." % Game.player.name, "%s hurried back to the last Ring Stone!" % Game.player.name])
	Game.add_coins(-Game.coins / 2)
	Game.heal_all()
	var r: Dictionary = Game.respawn
	await change_map(String(r.map), Vector2i(int(r.x), int(r.y)), "down")


func _check_quest_hooks() -> void:
	if Game.has_flag("warchief_defeated") and Game.quest_stage_id("emoria_watch") == "warchief":
		Game.set_quest_stage("emoria_watch", "return")
	if Game.quest_stage_id("first_bond") == "catch" and (Game.party.size() + Game.vault.size()) > 1:
		Game.set_quest_stage("first_bond", "report")


# ------------------------------------------------------------------ starter

func choose_starter() -> void:
	var ids := ["alpha", "beta", "gamma"]
	while true:
		var pick: int = await screen.starter_picker(ids)
		var c := Data.creature(ids[pick])
		var yes := await ask("So, %s, the %s creature?" % [String(c.name).to_upper(), Data.element_name(String(c.element)).to_upper()], ["YES", "NO"])
		if yes == 0:
			var inst := Creatures.create(ids[pick], 5)
			Game.add_creature(inst)
			Audio.play("ring_capture")
			await say("%s bound %s to a ring!" % [Game.player.name, String(c.name).to_upper()])
			return


# ------------------------------------------------------------------ START menu

func open_start_menu() -> void:
	world.busy = true
	while true:
		var i: int = await menu.choose(["PARTY", "BAG", Game.player.name, "QUEST", "SAVE", "EXIT"], "right", true)
		match i:
			0:
				await screen.party()
			1:
				await screen.bag(false)
			2:
				await screen.warrior()
			3:
				var obj := Game.current_objective()
				await say(obj if not obj.is_empty() else "No quest right now. Explore!")
			4:
				Game.tile = world.player.tile
				Game.facing = world.player.facing
				if Game.save_game():
					Audio.play("level_up")
					await say("%s saved the game." % Game.player.name)
				else:
					await say("Saving failed!")
			_:
				break
	world.busy = false

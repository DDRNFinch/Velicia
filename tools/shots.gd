extends Node
## Renders review screenshots of the real game (needs a display):
##   godot --rendering-driver opengl3 res://tools/shots.tscn -- <out_dir>

var out := "user://shots"
var root: GameRoot


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1200, 540)   # a 20:9 phone-like window (scale 3)
	await _frames(2)
	# Title
	var probe := TouchPad.new()
	probe.force_visible = true
	add_child(probe)
	probe.queue_free()
	var t := TitleScreen.new()
	add_child(t)
	await _frames(5)
	await _snap("01_title")
	t.queue_free()
	# Game
	root = GameRoot.new()
	root.skip_title = true
	root.force_touch = true
	add_child(root)
	Game.new_game("WARDEN")
	await root.change_map("home", Vector2i(3, 4), "down", false)
	await _frames(5)
	await _snap("02_home")
	await root.change_map("emoria", Vector2i(9, 7), "down", false)
	await _frames(5)
	await _snap("03_town")
	await root.change_map("guild", Vector2i(2, 5), "up", false)
	await _frames(3)
	root.box.say("So the Guild finally sent me someone. Welcome to the Emoria Watch, warrior.")
	await _frames(90)
	await _snap("04_guild_dialogue")
	root.box.close()
	root.screen.starter_picker(["alpha", "beta", "gamma"])
	await _frames(5)
	await _snap("05_starter")
	root.screen.close()
	Game.add_creature(Creatures.create("alpha", 6))
	Game.add_creature(Creatures.create("beta", 5))
	Game.give_item("binding_ring", 5)
	await root.change_map("route1", Vector2i(2, 9), "right", false)
	await _frames(5)
	await _snap("06_route_grass")
	root.battle.run_wild(Creatures.create("gamma", 4))
	await _frames(120)
	await _snap("07_wild_battle")
	await _frames(40)
	await _snap("08_wild_menu")
	root.battle.visible = false
	root.menu.visible = false
	root.box.close()
	var tr: Dictionary = {}
	for x in root.world.meta.trainers:
		if x.id == "scout_c":
			tr = x
	root.battle.run_trainer(tr)
	await _frames(160)
	await _snap("09_gyria_battle")
	root.battle.visible = false
	root.menu.visible = false
	root.box.close()
	await root.change_map("ashfen", Vector2i(10, 6), "up", false)
	await _frames(5)
	await _snap("10_ashfen")
	root.screen.party()
	await _frames(5)
	await _snap("11_party")
	root.screen.close()
	root.menu.choose(["PARTY", "BAG", "WARDEN", "QUEST", "SAVE", "EXIT"], "right")
	await _frames(5)
	await _snap("12_start_menu")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))

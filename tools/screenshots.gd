extends Node
## Captures reference screenshots of the game for visual review.
##   xvfb-run godot --rendering-driver opengl3 res://tools/screenshots.tscn -- <out_dir>
## (Needs a display; uses the Compatibility renderer like Android.)

var out_dir := "user://screenshots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	Settings.set_value("controls", "touch_mode", "on")
	await _shoot_menu()
	await _shoot_game()
	Settings.set_value("controls", "touch_mode", "auto")
	get_tree().quit()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _report_render_stats(label: String) -> void:
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("render stats [%s]: %d draw calls, %d primitives, %d objects" % [label, calls, prims, objs])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shoot_menu() -> void:
	var menu: Control = (load("res://scenes/main/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(10)
	await _snap("01_main_menu")
	menu.call("_show_creator")
	await _frames(20)
	await _snap("02_character_creator")
	menu.queue_free()
	await _frames(2)


func _shoot_game() -> void:
	GameState.reset()
	for id in GameState.STARTING_ITEMS:
		GameState.inventory[id] = GameState.STARTING_ITEMS[id]
	GameState.equip_item("guild_longsword")
	GameState.equip_item("guild_leathers")
	GameState.equip_ring("apprentice_ring")
	GameState.player.health = GameState.get_max_health()
	QuestManager.start_quest(&"the_emoria_watch", false)
	GameState.session_active = true
	var game: Node3D = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await _frames(40)
	var player: Player = game.player
	# Keep the camera subject alive for the whole tour (survives stat refreshes).
	GameState.player.attributes["vitality"] = 10000
	player.refresh_stats()
	player.stats.set_health(player.stats.max_health)
	var rig: CameraRig = game.camera_rig
	await _snap("03_outpost_spawn")
	_report_render_stats("outpost")

	# Peoples of Velicia lined up for a silhouette check.
	var npcs := ["NPCs/Warden", "NPCs/AmirScout", "NPCs/Quartermaster", "NPCs/Messenger", "NPCs/RingSage"]
	var base := player.global_position + Vector3(0, 0, -6)
	for i in npcs.size():
		var n: NPC = game.region.get_node(npcs[i])
		n.routine_points = PackedVector3Array()
		n.global_position = base + Vector3(-5.0 + i * 2.6, 0.3, 0)
		n.rotation.y = 0.0
	var gy := Enemy.new()
	gy.definition = Database.enemy("gyria_skirmisher")
	game.add_child(gy)
	gy.global_position = base + Vector3(8.0, 0.5, 0)
	gy.wait_for_engage = true
	await _frames(30)
	for i in npcs.size():
		var n: NPC = game.region.get_node(npcs[i])
		n.rotation.y = PI
	gy.rotation.y = PI
	player.global_position = base + Vector3(0, 0.5, 7.0)
	player.rotation.y = 0.0
	rig.global_position = player.global_position + Vector3.UP * 1.55
	await _frames(20)
	await _snap("04_peoples_lineup")
	gy.queue_free()

	# Close-up of every people's placeholder body, front and back, compared
	# against docs/reference/peoples_of_velicia.jpg.
	await _shoot_closeup(game, Vector3(33, 0, 36))

	# Landmark view toward the Sentinel Spire.
	player.global_position = Vector3(0, 6.0, -10.0)
	var to_spire := Vector3(35, 0, -75) - player.global_position
	player.rotation.y = atan2(-to_spire.x, -to_spire.z)
	rig.global_position = player.global_position + Vector3.UP * 1.55
	await _frames(30)
	await _snap("05_landmark_spire")

	# Combat at the Spire with the Gyria scouts.
	var scout: Enemy = game.region.get_node("Enemies/SpireScout1")
	player.global_position = scout.global_position + Vector3(0, 0.5, 4.0)
	player.rotation.y = 0.0
	rig.global_position = player.global_position + Vector3.UP * 1.55
	await _frames(70)
	await _snap("06_combat_spire")

	# Archer and shield-warden at the Gyria camp.
	var camp_archer: Enemy = game.region.get_node("Enemies/CampArcher")
	var camp_shield: Enemy = game.region.get_node("Enemies/CampShield")
	player.global_position = camp_shield.global_position + Vector3(-6, 0.5, 3)
	var to_camp := camp_shield.global_position - player.global_position
	player.rotation.y = atan2(-to_camp.x, -to_camp.z)
	rig.global_position = player.global_position + Vector3.UP * 1.55
	await _frames(90)
	await _snap("06b_archer_shield_camp")
	_report_render_stats("gyria camp")

	# Wild creatures and the capture marker.
	var wild := CreatureActor.new()
	wild.definition = Database.creature("test_creature_alpha")
	game.add_child(wild)
	player.global_position = Vector3(28, 6, 30)
	await _frames(10)
	wild.global_position = player.global_position + Vector3(0, 0.5, -3)
	var wild2 := CreatureActor.new()
	wild2.definition = Database.creature("test_creature_beta")
	game.add_child(wild2)
	wild2.global_position = player.global_position + Vector3(2.5, 0.5, -4)
	player.rotation.y = 0.0
	rig.global_position = player.global_position + Vector3.UP * 1.55
	await _frames(15)
	wild.stats.set_health(wild.stats.max_health * 0.3)
	wild._update_label()
	await _frames(10)
	await _snap("07_creature_capturable")
	player.rings.force_capture_result = 1
	player.rings.try_capture(wild)
	await _frames(40)
	await _snap("08_capturing")
	await get_tree().create_timer(1.5).timeout
	player.rings.summon(0)
	await _frames(40)
	await _snap("09_companion_summoned")

	# Night falls
	game.region.day_night.set_hour(21.3)
	await _frames(10)
	await _snap("09b_night")
	game.region.day_night.set_hour(17.8)
	await _frames(10)
	await _snap("09c_dusk")
	game.region.day_night.set_hour(10.0)

	# Boss
	var boss: Enemy = game.region.get_node("Enemies/Warchief")
	# Level-ups during the tour reset max health; keep the subject alive.
	player.stats.max_health = 100000.0
	player.stats.set_health(100000.0)
	player.global_position = boss.global_position + Vector3(0, 0.5, 7.0)
	player.rotation.y = 0.0
	rig.global_position = player.global_position + Vector3.UP * 1.55
	await _frames(60)
	await _snap("10_boss_warchief")

	# Dialogue and menu screens
	var warden: NPC = game.region.get_node("NPCs/Warden")
	player.global_position = warden.global_position + Vector3(0, 0.5, 2.5)
	await _frames(20)
	game.hud.start_dialogue("warden", warden)
	await _frames(10)
	await _snap("11_dialogue")
	game.hud.close_dialogue()
	game.open_menu("creatures")
	await _frames(10)
	await _snap("12_menu_rings")
	game.menu.open("map")
	await _frames(10)
	await _snap("13_menu_map")
	game.menu.open("character")
	await _frames(10)
	await _snap("14_menu_character")
	game.menu.close()
	game.queue_free()
	await _frames(5)


func _shoot_closeup(game: Node3D, base: Vector3) -> void:
	var peoples := [&"human", &"amir", &"burrok", &"vapouriun", &"gouran", &"gyria", &"gyria_boss"]
	var stage := Node3D.new()
	game.add_child(stage)
	var x := -6.6
	for p in peoples:
		var body := PlaceholderBody.new()
		stage.add_child(body)
		body.build(PlaceholderBody.preset(p, 0))
		x += 0.9 if p == &"burrok" or p == &"gyria_boss" else 0.0
		body.global_position = Vector3(base.x + x, _ground_y(base.x + x, base.z), base.z)
		body.rotation.y = PI
		x += 2.2 if p == &"burrok" or p == &"gyria_boss" else 1.6
	var old_cam := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.fov = 38.0
	game.hud.visible = false
	if game.region.day_night:
		game.region.day_night.set_hour(10.0)
	var mid := Vector3(base.x + 0.5, stage.get_child(0).global_position.y, base.z)
	# The morning sun shines toward -Z, so the camera stands on the +Z side.
	cam.global_position = mid + Vector3(0, 1.5, 13.0)
	cam.look_at(mid + Vector3(0, 1.15, 0))
	cam.current = true
	await _frames(10)
	await _snap("04b_peoples_front")
	for b in stage.get_children():
		if b is PlaceholderBody:
			b.rotation.y = 0.0
	await _frames(4)
	await _snap("04c_peoples_back")
	cam.current = false
	if old_cam:
		old_cam.current = true
	game.hud.visible = true
	stage.queue_free()


func _ground_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -50, z))
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0

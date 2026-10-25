extends Node
## Development probe: lists what the renderer would draw at the spawn point,
## grouped by category. Run: godot --headless res://tests/probe_draw.tscn


func _ready() -> void:
	GameState.reset()
	for id in GameState.STARTING_ITEMS:
		GameState.inventory[id] = GameState.STARTING_ITEMS[id]
	GameState.equip_item("guild_longsword")
	GameState.session_active = true
	var game: Node3D = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 40:
		await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	var counts := {}
	var surfs := {}
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		if g.visibility_range_end > 0.0 and not (g is MultiMeshInstance3D) and g.global_position.distance_to(cam.global_position) > g.visibility_range_end:
			continue
		var cat := _category(g)
		counts[cat] = int(counts.get(cat, 0)) + 1
		var sc := 1
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			sc = (g as MeshInstance3D).mesh.get_surface_count()
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh.mesh:
			sc = (g as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
		surfs[cat] = int(surfs.get(cat, 0)) + sc
	for k in counts:
		print("  %-26s objects %4d  surfaces %4d" % [k, counts[k], surfs[k]])
	get_tree().quit()


func _category(g: Node) -> String:
	var p := g.get_parent()
	while p:
		if p is PlaceholderBody:
			return "character"
		if p is CreatureBody:
			return "creature"
		if String(p.name).begins_with("Structure_"):
			return "structure"
		if p is GrassField:
			return "grass"
		if String(p.name) == "Fx":
			return "fx"
		if p is TreasureChest or p is LoreStone or p is SaveShrine or p is LootPickup:
			return "props"
		p = p.get_parent()
	if g is MultiMeshInstance3D:
		return "multimesh trees/rocks"
	return g.get_class()

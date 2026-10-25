extends Node3D
## Development preview: poses a PlaceholderBody (with its realistic model)
## through walk, attack, block, dodge and stagger, saving a frame of each.
##   godot --rendering-driver opengl3 res://tools/anim_preview.tscn -- <out_dir> [people]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://anim"
	var people := StringName(args[1]) if args.size() > 1 else &"human"
	if people == &"lineup":
		await _lineup(out_dir)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	add_child(sun)
	var body := PlaceholderBody.new()
	add_child(body)
	var p := PlaceholderBody.preset(people, 0)
	p.has_cloak = people == &"human"
	if people == &"player":
		p = PlayerAppearance.to_body_params({}, Color(0.45, 0.38, 0.3), &"sword")
	body.build(p)
	var h: float = body.height
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 32.0
	cam.global_position = Vector3(-h * 1.6, h * 0.65, (h if people == &"player" else -h) * 1.6)
	cam.look_at(Vector3(0, h * 0.5, 0))
	cam.current = true
	var shots := []
	for i in 4:
		shots.append(["walk%d" % i, func() -> void:
			body.clear_pose()
			for k in 12:
				body.animate(0.016, 5.0, 5.0, true)])
	for kind in [&"slash", &"thrust", &"slam", &"sweep"]:
		shots.append([String(kind) + "_windup", func() -> void: body.pose_attack(kind, 0, 1.0)])
		shots.append([String(kind) + "_hit", func() -> void: body.pose_attack(kind, 1, 1.0)])
	shots.append(["block", func() -> void: body.pose_block()])
	shots.append(["dodge", func() -> void: body.pose_dodge()])
	shots.append(["stagger", func() -> void: body.pose_stagger(0.5)])
	for s in shots:
		(s[1] as Callable).call()
		for k in 20:
			body.animate(0.05, 0.0 if not String(s[0]).begins_with("walk") else 5.0, 5.0, true)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [people, s[0]]))
	get_tree().quit()


func _lineup(out_dir: String) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = LowPoly.c("grass")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.6, 0.78)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.92
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18
	e.adjustment_contrast = 1.12
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = LowPoly.mat(LowPoly.c("grass"))
	add_child(ground)
	var x := -6.5
	for p in [&"human", &"amir", &"burrok", &"vapouriun", &"gouran", &"gyria", &"gyria_boss"]:
		var body := PlaceholderBody.new()
		add_child(body)
		var params := PlaceholderBody.preset(p, 0)
		if p == &"human":
			params = PlayerAppearance.to_body_params({}, Color(0.45, 0.38, 0.3), &"sword")
		body.build(params)
		var w := 2.4 if p in [&"burrok", &"gyria_boss"] else 1.7
		x += w * 0.5
		body.position = Vector3(x, 0, 0)
		x += w * 0.5
		for k in 3:
			body.animate(0.016, 0.0, 5.0, true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 30.0
	for view in [["front", Vector3(0.3, 7.5, -12.0)], ["top", Vector3(0.3, 12.5, -10.0)]]:
		cam.global_position = view[1]
		cam.look_at(Vector3(0.3, 1.1, 0))
		cam.current = true
		for i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("lineup_%s.png" % view[0]))
	get_tree().quit()

extends Node3D
## Development preview: poses a PlaceholderBody (with its realistic model)
## through walk, attack, block, dodge and stagger, saving a frame of each.
##   godot --rendering-driver opengl3 res://tools/anim_preview.tscn -- <out_dir> [people]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://anim"
	var people := StringName(args[1]) if args.size() > 1 else &"human"
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

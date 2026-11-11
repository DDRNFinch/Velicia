extends Node3D
## Development preview: renders every character model in models/characters
## from the front, side and back.  Run with a display:
##   godot --rendering-driver opengl3 res://tools/model_preview.tscn -- <out_dir> [name ...]

var out_dir := "user://preview"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var names: Array = args.slice(1)
	if names.is_empty():
		for f in DirAccess.get_files_at("res://models/characters"):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for n in names:
		var people := StringName("human" if n.begins_with("human") else n)
		var params := PlaceholderBody.preset(people, 0)
		params["has_cloak"] = n == "human"
		var model := CharacterModel.create(StringName(n), params)
		add_child(model)
		var h: float = model.model_height
		for view in [["front", 0.0], ["side", PI * 0.5], ["back", PI]]:
			model.rotation.y = view[1]
			cam.fov = 30.0
			var dist := h * 2.3 + 0.6
			cam.global_position = Vector3(0, h * 0.55, -dist)
			cam.look_at(Vector3(0, h * 0.5, 0))
			await _frames(3)
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [n, view[0]]))
		# Face close-up
		model.rotation.y = 0.0
		cam.fov = 22.0
		var hc: Vector3 = model.head_center
		cam.global_position = hc + Vector3(0, 0.02, -0.75 * h / 1.78)
		cam.look_at(hc)
		await _frames(3)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_face.png" % n))
		cam.global_position = hc + Vector3(-0.45 * h / 1.78, 0.05, -0.45 * h / 1.78)
		cam.look_at(hc)
		await _frames(3)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_face34.png" % n))
		model.queue_free()
		await _frames(1)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

class_name RegionBuilder
extends Node3D
## Builds a region at runtime from its scene: terrain (mesh + collision),
## forests, rocks, paths, water, sky/lighting and structure kits placed at
## each LocationTrigger. Gameplay entities placed in the scene (NPCs,
## enemies, chests, shrines...) are snapped onto the terrain.
## PLACEHOLDER ART: structures are primitive kits until modular art exists.

@export var region_id: String = "hollow_march"
@export var region_name: String = "The Hollow March"
@export var terrain_seed: int = 1337
@export var region_size: float = 360.0
@export var cell_size: float = 3.0
## Pairs of location ids joined by dirt roads.
@export var paths: Array[PackedStringArray] = []
## Lakes: x, z, radius, depth
@export var lakes: Array[Vector4] = []
## Forest focus: x, z, radius, density boost
@export var forests: Array[Vector4] = []

const CHUNK := 120.0

var _path_segments: Array = []
var _locations: Dictionary = {}
var _tree_colliders: StaticBody3D
var _detail_noise: FastNoiseLite
var _forest_noise: FastNoiseLite
var _quality := "medium"
var _rng := RandomNumberGenerator.new()
var _sun: DirectionalLight3D
var _sky_material: ShaderMaterial
var day_night: DayNight
var grass: GrassField


func _enter_tree() -> void:
	# Configure terrain before children run _ready, so they can snap to it.
	var zones := []
	_locations.clear()
	for t in find_children("*", "LocationTrigger", true, false):
		var lt := t as LocationTrigger
		_locations[lt.location_id] = lt
		var offset := (lt.get_parent() as Node3D).position if lt.get_parent() is Node3D and lt.get_parent() != self else Vector3.ZERO
		if lt.flatten_radius > 0.0:
			zones.append({"center": Vector2(lt.position.x + offset.x, lt.position.z + offset.z), "radius": lt.flatten_radius, "height": lt.flatten_height, "falloff": lt.flatten_falloff})
	var lake_list := []
	for l in lakes:
		lake_list.append({"center": Vector2(l.x, l.y), "radius": l.z, "depth": l.w, "falloff": 12.0})
	VeliciaTerrain.configure(terrain_seed, region_size, zones, lake_list)
	_snap_children()


func _snap_children() -> void:
	for container in get_children():
		if not (container is Node3D):
			continue
		var cp := (container as Node3D).position
		if container.get_child_count() == 0 or container is Marker3D:
			var m := container as Node3D
			m.position.y = VeliciaTerrain.height_at(cp.x, cp.z) + float(m.get_meta("snap_offset", 0.05))
			continue
		for c in container.get_children():
			if c is Node3D and not c.has_meta("no_snap"):
				var n := c as Node3D
				var lift := float(n.get_meta("snap_offset", 0.05))
				n.position.y = VeliciaTerrain.height_at(cp.x + n.position.x, cp.z + n.position.z) - cp.y + lift


func _ready() -> void:
	_quality = String(Settings.get_value("graphics", "quality"))
	_rng.seed = terrain_seed + 21
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = terrain_seed + 5
	_detail_noise.frequency = 0.05
	_forest_noise = FastNoiseLite.new()
	_forest_noise.seed = terrain_seed + 9
	_forest_noise.frequency = 0.012
	_build_paths()
	_build_environment()
	_build_terrain()
	_build_water()
	_build_bounds()
	for id in _locations:
		var lt: LocationTrigger = _locations[id]
		if not lt.structure.is_empty():
			_build_structure(lt)
	_build_trees()
	_build_rocks()
	grass = GrassField.new()
	grass.name = "Grass"
	grass.weight_func = ground_weights
	grass.configure(_quality)
	add_child(grass)


func get_location(id: String) -> LocationTrigger:
	return _locations.get(id)


# -------------------------------------------------------------- Environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_material = VeliciaMaterials.sky()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.7, 0.76)
	env.fog_density = 0.0032 if _quality != "low" else 0.006
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.0
	sun.shadow_enabled = bool(Settings.get_value("graphics", "shadows")) and _quality != "low"
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 50.0 if _quality == "high" else 32.0
	add_child(sun)
	_sun = sun
	day_night = DayNight.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(sun, env, _sky_material)
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics" and key == "shadows" and _sun:
		_sun.shadow_enabled = bool(Settings.get_value("graphics", "shadows"))


# ------------------------------------------------------------------ Terrain

func _build_terrain() -> void:
	var half := region_size * 0.5
	var n := int(region_size / cell_size)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize((n + 1) * (n + 1))
	normals.resize(verts.size())
	colors.resize(verts.size())
	uvs.resize(verts.size())
	for iz in n + 1:
		for ix in n + 1:
			var x := -half + ix * cell_size
			var z := -half + iz * cell_size
			var i := iz * (n + 1) + ix
			verts[i] = Vector3(x, VeliciaTerrain.height_at(x, z), z)
			normals[i] = VeliciaTerrain.normal_at(x, z)
			colors[i] = ground_weights(x, z)
			uvs[i] = Vector2(x, z) * 0.1
	for iz in n:
		for ix in n:
			var a := iz * (n + 1) + ix
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Tangents are needed for the terrain normal maps.
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_tangents()
	mesh = st.commit()
	mesh.surface_set_material(0, VeliciaMaterials.terrain())
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = CombatUtil.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


## Ground material weights at a point: r = dirt, g = rock, b = sand, a = snow
## (grass is whatever remains). Shared by the terrain shader, grass and trees.
func ground_weights(x: float, z: float) -> Color:
	var h := VeliciaTerrain.height_at(x, z)
	var nrm := VeliciaTerrain.normal_at(x, z)
	var slope := 1.0 - nrm.y
	var dirt := 0.0
	if VeliciaTerrain.in_flat_zone(x, z, -3.0):
		dirt = 0.7
	elif VeliciaTerrain.in_flat_zone(x, z, 2.0):
		dirt = 0.35
	var pd := _path_distance(x, z)
	dirt = maxf(dirt, 1.0 - smoothstep(1.4, 3.2, pd))
	dirt = maxf(dirt, clampf(_detail_noise.get_noise_2d(x * 0.6, z * 0.6) - 0.35, 0.0, 1.0) * 1.2)
	var rock := maxf(smoothstep(0.22, 0.42, slope), smoothstep(17.0, 25.0, h))
	var sand := 1.0 - smoothstep(VeliciaTerrain.water_level + 0.4, VeliciaTerrain.water_level + 1.6, h)
	var snow := smoothstep(38.0, 46.0, h) * (1.0 - smoothstep(0.35, 0.6, slope))
	rock *= 1.0 - snow
	dirt *= 1.0 - rock
	return Color(clampf(dirt, 0.0, 1.0), clampf(rock, 0.0, 1.0), clampf(sand, 0.0, 1.0), clampf(snow, 0.0, 1.0))


func _build_paths() -> void:
	_path_segments.clear()
	for pair in paths:
		if pair.size() < 2:
			continue
		var a: LocationTrigger = _locations.get(pair[0])
		var b: LocationTrigger = _locations.get(pair[1])
		if a and b:
			_path_segments.append([Vector2(a.position.x, a.position.z), Vector2(b.position.x, b.position.z)])


func _path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for seg in _path_segments:
		var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
		best = minf(best, p.distance_to(q))
	return best


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(region_size, region_size)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = VeliciaMaterials.water()
	mi.position = Vector3(0, VeliciaTerrain.water_level, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_bounds() -> void:
	var half := region_size * 0.5 - 6.0
	var body := StaticBody3D.new()
	body.name = "Bounds"
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 200, region_size) if side.x != 0.0 else Vector3(region_size, 200, 2)
		shape.shape = box
		shape.position = side * half + Vector3.UP * 50.0
		body.add_child(shape)
	add_child(body)


# -------------------------------------------------------------- Vegetation

func _build_trees() -> void:
	var density: float = {"low": 0.45, "medium": 0.75, "high": 1.0}.get(_quality, 0.75)
	var half := region_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	var step := 6.5
	var chunks := {}
	_tree_colliders = StaticBody3D.new()
	_tree_colliders.name = "TreeColliders"
	add_child(_tree_colliders)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.36
	trunk_shape.height = 4.0
	var x := -half + 10.0
	while x < half - 10.0:
		var z := -half + 10.0
		while z < half - 10.0:
			var px := x + rng.randf_range(-2.8, 2.8)
			var pz := z + rng.randf_range(-2.8, 2.8)
			z += step
			var chance := 0.05 + clampf(_forest_noise.get_noise_2d(px, pz) + 0.15, 0.0, 1.0) * 0.55
			for f in forests:
				var d := Vector2(px, pz).distance_to(Vector2(f.x, f.y))
				chance += (1.0 - smoothstep(f.z * 0.4, f.z, d)) * f.w
			if rng.randf() > chance * density:
				continue
			if VeliciaTerrain.in_flat_zone(px, pz, 5.0) or VeliciaTerrain.in_lake(px, pz, 2.0) or _path_distance(px, pz) < 4.0:
				continue
			var h := VeliciaTerrain.height_at(px, pz)
			if h > 30.0 or VeliciaTerrain.normal_at(px, pz).y < 0.82:
				continue
			var key := Vector2i(floori(px / CHUNK), floori(pz / CHUNK))
			if not chunks.has(key):
				chunks[key] = {}
			var is_pine := rng.randf() < 0.5 or h > 15.0
			var variant := ("pine%d" if is_pine else "broad%d") % rng.randi_range(0, 1)
			if not chunks[key].has(variant):
				chunks[key][variant] = []
			var s := rng.randf_range(0.8, 1.25)
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(px, h - 0.15, pz))
			chunks[key][variant].append([t, rng.randf()])
			var col := CollisionShape3D.new()
			col.shape = trunk_shape
			col.position = Vector3(px, h + 2.0, pz)
			_tree_colliders.add_child(col)
		x += step
	var view := float(Settings.get_value("graphics", "view_distance"))
	for key in chunks:
		for variant in chunks[key]:
			var v := int(String(variant).right(1))
			var mesh: Mesh = Vegetation.pine(v) if String(variant).begins_with("pine") else Vegetation.broadleaf(v)
			var tint := Color(0.85, 0.95, 0.85) if String(variant).begins_with("pine") else Color(1.0, 1.0, 0.9)
			_multimesh(mesh, null, chunks[key][variant], Vector3.ZERO, view, tint, true)


func _multimesh(mesh: Mesh, material: Material, entries: Array, offset: Vector3, view: float, base_color: Color, tint: bool) -> void:
	if entries.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tint
	mm.mesh = mesh
	mm.instance_count = entries.size()
	for i in entries.size():
		var t: Transform3D = entries[i][0]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin + t.basis * offset))
		if tint:
			var v: float = entries[i][1]
			mm.set_instance_color(i, base_color.lerp(base_color.lightened(0.18), v).darkened(0.12 * (1.0 - v)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material:
		mmi.material_override = material
	mmi.visibility_range_end = view
	add_child(mmi)


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 3
	var half := region_size * 0.5
	var entries := [[], [], []]
	var body := StaticBody3D.new()
	body.name = "RockColliders"
	add_child(body)
	for i in 190:
		var x := rng.randf_range(-half + 12.0, half - 12.0)
		var z := rng.randf_range(-half + 12.0, half - 12.0)
		if VeliciaTerrain.in_flat_zone(x, z, 3.0) or _path_distance(x, z) < 3.5:
			continue
		var h := VeliciaTerrain.height_at(x, z)
		var s := rng.randf_range(0.35, 2.4)
		var t := Transform3D(Basis.from_euler(Vector3(rng.randf() * 0.3, rng.randf() * TAU, rng.randf() * 0.3)).scaled(Vector3(s * rng.randf_range(0.9, 1.5), s * rng.randf_range(0.7, 1.1), s)), Vector3(x, h + s * 0.15, z))
		entries[i % 3].append([t, rng.randf()])
		if s > 1.0:
			var col := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = s * 0.85
			col.shape = sphere
			col.position = Vector3(x, h + s * 0.15, z)
			body.add_child(col)
	var view := float(Settings.get_value("graphics", "view_distance"))
	for v in 3:
		_multimesh(Vegetation.rock(v), null, entries[v], Vector3.ZERO, view, Color.WHITE, false)


# --------------------------------------------------------- Structure kits

func _solid(parent: Node3D, mesh_size: Vector3, pos: Vector3, rot_y: float, material: Material, collide: bool = true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = PlaceholderBody.box_mesh(mesh_size)
	mi.material_override = material
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation.y = rot_y
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh_size
		shape.shape = box
		body.add_child(shape)
		parent.add_child(body)


func _column(parent: Node3D, radius_top: float, radius_bottom: float, h: float, pos: Vector3, material: Material, collide: bool = true, sides: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = PlaceholderBody.cylinder_mesh(radius_top, radius_bottom, h, sides)
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(radius_top, radius_bottom)
		cyl.height = h
		shape.shape = cyl
		body.add_child(shape)
		parent.add_child(body)
	return mi


func _build_structure(lt: LocationTrigger) -> void:
	var root := Node3D.new()
	root.name = "Structure_" + lt.location_id
	root.position = Vector3(lt.position.x, VeliciaTerrain.height_at(lt.position.x, lt.position.z), lt.position.z)
	add_child(root)
	match lt.structure:
		"outpost":
			_kit_outpost(root, lt)
		"spire":
			_kit_spire(root)
		"gyria_camp":
			_kit_gyria_camp(root)
		"fort":
			_kit_fort(root)
		"grotto":
			_kit_grotto(root)
		"battlefield":
			_kit_battlefield(root)
		"lake_ruin":
			_kit_lake_ruin(root)
		"glade":
			_kit_glade(root)
	merge_static_meshes(root)


## Combines every static MeshInstance3D under `root` into one mesh with a
## surface per material (draw calls drop from dozens to a handful per kit).
## Nodes tagged with the "dynamic" meta are left alone.
static func merge_static_meshes(root: Node3D) -> void:
	var by_mat := {}
	var victims: Array[MeshInstance3D] = []
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.has_meta("dynamic") or mi.mesh == null or mi.get_parent().has_meta("dynamic"):
			continue
		var xf := _relative_transform(mi, root)
		for surf in mi.mesh.get_surface_count():
			var m: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(surf)
			if not by_mat.has(m):
				by_mat[m] = []
			by_mat[m].append([mi.mesh, surf, xf])
		victims.append(mi)
	if victims.size() < 2:
		return
	var mesh := ArrayMesh.new()
	for m in by_mat:
		var st := SurfaceTool.new()
		for e in by_mat[m]:
			st.append_from(e[0], e[1], e[2])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	for mi in victims:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var merged := MeshInstance3D.new()
	merged.name = "MergedMesh"
	merged.mesh = mesh
	root.add_child(merged)


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _ground(root: Node3D, local: Vector3) -> Vector3:
	var gx := root.position.x + local.x
	var gz := root.position.z + local.z
	return Vector3(local.x, VeliciaTerrain.height_at(gx, gz) - root.position.y + local.y, local.z)


func _tent(root: Node3D, pos: Vector3, rot: float, color: Color, scale_f: float = 1.0) -> void:
	var t := Node3D.new()
	t.position = _ground(root, pos)
	t.rotation.y = rot
	root.add_child(t)
	var cloth := VeliciaMaterials.surface("fabric", color.lightened(0.15), 0.8, 0.95)
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		panel.mesh = PlaceholderBody.box_mesh(Vector3(2.6, 0.06, 3.4) * scale_f)
		panel.material_override = cloth
		panel.position = Vector3(side * 0.9, 1.05, 0) * scale_f
		panel.rotation.z = side * -0.85
		t.add_child(panel)
	var body := StaticBody3D.new()
	body.position = Vector3(0, 0.9, 0) * scale_f
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 1.8, 3.4) * scale_f
	shape.shape = box
	body.add_child(shape)
	t.add_child(body)


func _campfire(root: Node3D, pos: Vector3) -> void:
	var p := _ground(root, pos)
	for i in 6:
		var ang := TAU * i / 6.0
		var stone := MeshInstance3D.new()
		stone.mesh = PlaceholderBody.sphere_mesh(0.22)
		stone.material_override = VeliciaMaterials.surface("rock", Color(0.8, 0.78, 0.75), 1.5)
		stone.position = p + Vector3(cos(ang) * 0.7, 0.1, sin(ang) * 0.7)
		root.add_child(stone)
	var fire := MeshInstance3D.new()
	fire.mesh = PlaceholderBody.cylinder_mesh(0.0, 0.45, 1.0, 6)
	fire.material_override = PlaceholderBody.mat(Color(1.0, 0.55, 0.15), 0.2, 3.0)
	fire.position = p + Vector3(0, 0.5, 0)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fire)
	if _quality != "low":
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.65, 0.3)
		light.light_energy = 1.6
		light.omni_range = 8.0
		light.position = p + Vector3(0, 1.2, 0)
		root.add_child(light)


func _banner(root: Node3D, pos: Vector3, color: Color, accent: Color) -> void:
	var p := _ground(root, pos)
	_column(root, 0.07, 0.09, 4.5, p + Vector3(0, 2.25, 0), VeliciaMaterials.surface("bark", Color.WHITE, 1.2, 0.95, false), false, 6)
	var cloth := MeshInstance3D.new()
	cloth.mesh = PlaceholderBody.box_mesh(Vector3(0.9, 1.8, 0.04))
	cloth.material_override = VeliciaMaterials.surface("fabric", color.lightened(0.1), 1.2)
	cloth.position = p + Vector3(0.48, 3.4, 0)
	root.add_child(cloth)
	var emblem := MeshInstance3D.new()
	emblem.mesh = PlaceholderBody.box_mesh(Vector3(0.4, 0.4, 0.05))
	emblem.material_override = PlaceholderBody.mat(accent, 0.4, 0.6)
	emblem.position = p + Vector3(0.48, 3.6, 0)
	emblem.rotation.z = PI * 0.25
	root.add_child(emblem)


func _kit_outpost(root: Node3D, lt: LocationTrigger) -> void:
	var log_mat := VeliciaMaterials.surface("bark", Color(1.05, 0.95, 0.85), 0.7, 0.95, false)
	var plank_mat := VeliciaMaterials.surface("planks", Color.WHITE, 0.5)
	var r := lt.flatten_radius - 3.0
	var count := 56
	for i in count:
		var ang := TAU * i / count
		var deg := rad_to_deg(ang)
		# Gates facing the spire (north) and the east road.
		if (deg > 255.0 and deg < 285.0) or (deg < 12.0 or deg > 348.0):
			continue
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var h := 3.2 + (i % 3) * 0.25
		_column(root, 0.0 if i % 2 == 0 else 0.22, 0.26, h, _ground(root, p) + Vector3(0, h * 0.5 - 0.2, 0), log_mat, true, 5)
	# Watchtower
	var tw := _ground(root, Vector3(-r + 3.0, 0, -r + 5.0))
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		_column(root, 0.15, 0.18, 7.0, tw + corner * 1.2 + Vector3(0, 3.5, 0), log_mat, true, 5)
	_solid(root, Vector3(3.4, 0.25, 3.4), tw + Vector3(0, 7.0, 0), 0.0, plank_mat)
	_solid(root, Vector3(3.6, 1.0, 0.12), tw + Vector3(0, 7.6, -1.7), 0.0, plank_mat, false)
	var roof := MeshInstance3D.new()
	roof.mesh = PlaceholderBody.cylinder_mesh(0.0, 2.8, 1.6, 4)
	roof.material_override = VeliciaMaterials.surface("fabric", Color(0.35, 0.45, 0.65), 0.8)
	roof.position = tw + Vector3(0, 9.0, 0)
	roof.rotation.y = PI * 0.25
	root.add_child(roof)
	# Tents in guild blue, campfire, banners and training dummies.
	_tent(root, Vector3(6, 0, 6), 0.4, Color(0.22, 0.32, 0.5))
	_tent(root, Vector3(-10, 0, 6), -0.3, Color(0.3, 0.36, 0.5))
	_tent(root, Vector3(8, 0, -5), 1.2, Color(0.5, 0.42, 0.28))
	_tent(root, Vector3(11, 0, 10), 0.6, Color(0.22, 0.32, 0.5), 1.3)
	_campfire(root, Vector3(0, 0, 2))
	for p in [Vector3(-3.5, 0, -r + 1.0), Vector3(3.5, 0, -r + 1.0), Vector3(r - 1.0, 0, 3.0), Vector3(r - 1.0, 0, -3.0)]:
		_banner(root, p, Color(0.2, 0.3, 0.5), Color(0.9, 0.75, 0.3))
	for p in [Vector3(-9, 0, -4), Vector3(-10.5, 0, -6)]:
		var gp := _ground(root, p)
		_column(root, 0.18, 0.22, 1.7, gp + Vector3(0, 0.85, 0), VeliciaMaterials.surface("planks", Color(1.1, 1.0, 0.85), 1.0), true, 6)
		_solid(root, Vector3(1.2, 0.15, 0.15), gp + Vector3(0, 1.3, 0), 0.0, log_mat, false)
	# Supply crates
	for p in [Vector3(4, 0, -9), Vector3(5, 0, -8.2), Vector3(4.5, 0.8, -8.6)]:
		_solid(root, Vector3(0.8, 0.8, 0.8), _ground(root, p) + Vector3(0, 0.4, 0), 0.3, VeliciaMaterials.surface("planks", Color.WHITE, 1.0))


func _kit_spire(root: Node3D) -> void:
	var stone := VeliciaMaterials.surface("stone_wall", Color(1.15, 1.12, 1.05), 0.35)
	var dark := VeliciaMaterials.surface("stone_wall", Color(0.85, 0.84, 0.8), 0.35)
	var glow := PlaceholderBody.mat(Color(0.45, 0.95, 1.0), 0.2, 3.0)
	_column(root, 8.0, 9.0, 1.2, Vector3(0, 0.4, 0), dark, true, 12)
	# Tapering tower: the region's landmark, visible from the outpost.
	var y := 1.0
	var radii := [3.6, 3.2, 2.8, 2.4, 2.0, 1.7]
	for i in radii.size():
		var h := 6.0
		var mi := _column(root, radii[i] * 0.92, radii[i], h, Vector3(0.15 * (i % 2), y + h * 0.5, 0), stone if i % 2 == 0 else dark, true, 10)
		mi.rotation.z = 0.01 * (i % 3)
		_column(root, radii[i] + 0.25, radii[i] + 0.25, 0.4, Vector3(0, y + h, 0), dark, false, 10)
		y += h
	# Broken crown with a floating ring-crystal.
	for i in 5:
		var ang := TAU * i / 5.0
		_solid(root, Vector3(0.6, 2.6 - (i % 2) * 1.2, 0.6), Vector3(cos(ang) * 1.5, y + 1.0, sin(ang) * 1.5), ang, stone, false)
	var crystal := MeshInstance3D.new()
	crystal.mesh = PlaceholderBody.cylinder_mesh(0.0, 0.9, 3.0, 4)
	crystal.material_override = glow
	crystal.position = Vector3(0, y + 4.0, 0)
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crystal)
	var crystal2 := MeshInstance3D.new()
	crystal2.mesh = PlaceholderBody.cylinder_mesh(0.9, 0.0, 2.0, 4)
	crystal2.material_override = glow
	crystal2.position = Vector3(0, y + 1.5, 0)
	root.add_child(crystal2)
	var halo := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.4
	torus.outer_radius = 2.7
	torus.rings = 28
	torus.ring_segments = 6
	halo.mesh = torus
	halo.material_override = glow
	halo.position = Vector3(0, y + 3.0, 0)
	halo.set_meta("dynamic", true)
	halo.rotation.x = 0.3
	root.add_child(halo)
	var spin := create_tween().set_loops()
	spin.tween_property(halo, "rotation:y", TAU, 12.0).from(0.0)
	# Ruined arches around the base.
	for i in 6:
		var ang := TAU * i / 6.0 + 0.3
		var p := Vector3(cos(ang) * 11.0, 0, sin(ang) * 11.0)
		var gp := _ground(root, p)
		var tall := 4.5 if i % 3 != 0 else 2.0
		_column(root, 0.55, 0.65, tall, gp + Vector3(0, tall * 0.5, 0), stone, true, 6)
		if i % 2 == 0:
			var p2 := Vector3(cos(ang + 0.35) * 11.0, 0, sin(ang + 0.35) * 11.0)
			var gp2 := _ground(root, p2)
			_column(root, 0.55, 0.65, 4.5, gp2 + Vector3(0, 2.25, 0), stone, true, 6)
			var mid := (gp + gp2) * 0.5
			_solid(root, Vector3(4.6, 0.7, 1.0), mid + Vector3(0, 4.7, 0), -(ang + 0.175) + PI * 0.5, stone, false)
	for i in 8:
		var ang := _rng.randf() * TAU
		var p := Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(5.0, 14.0)
		_solid(root, Vector3(_rng.randf_range(0.8, 1.8), _rng.randf_range(0.5, 1.0), _rng.randf_range(0.8, 1.8)), _ground(root, p) + Vector3(0, 0.3, 0), _rng.randf() * TAU, dark)


func _kit_gyria_camp(root: Node3D) -> void:
	var hide := Color(0.45, 0.36, 0.28)
	_tent(root, Vector3(5, 0, 3), 0.8, hide)
	_tent(root, Vector3(-5, 0, 4), -0.6, hide.darkened(0.2))
	_tent(root, Vector3(0, 0, -7), 0.1, hide, 1.2)
	_tent(root, Vector3(8, 0, -4), 1.7, Color(0.4, 0.3, 0.26))
	_campfire(root, Vector3(0, 0, 0))
	var stake := VeliciaMaterials.surface("bark", Color(0.9, 0.85, 0.8), 0.8, 0.95, false)
	for i in 26:
		var ang := TAU * i / 26.0
		if i % 6 == 0:
			continue
		var p := Vector3(cos(ang) * 13.0, 0, sin(ang) * 13.0)
		var gp := _ground(root, p)
		var m := _column(root, 0.0, 0.16, 2.2, gp + Vector3(0, 0.9, 0), stake, true, 4)
		m.rotation = Vector3(cos(ang) * 0.35, 0, -sin(ang) * 0.35)
	# Clan banners: the Gyria are a people, not monsters; their sigils are a
	# draft design (see docs/STORY_DRAFT.md).
	for p in [Vector3(3, 0, -10), Vector3(-9, 0, -2), Vector3(10, 0, 6)]:
		_banner(root, p, Color(0.5, 0.2, 0.16), Color(0.85, 0.7, 0.45))
	for p in [Vector3(-3, 0, 8), Vector3(-2, 0, 9), Vector3(-2.5, 0.8, 8.5)]:
		_solid(root, Vector3(0.9, 0.8, 0.9), _ground(root, p) + Vector3(0, 0.4, 0), 0.5, VeliciaMaterials.surface("planks", Color(0.85, 0.8, 0.75), 1.0))
	# Weapon racks
	for p in [Vector3(6, 0, -9)]:
		var gp := _ground(root, p)
		_solid(root, Vector3(2.0, 0.12, 0.12), gp + Vector3(0, 1.4, 0), 0.0, stake, false)
		for k in 3:
			var blade := MeshInstance3D.new()
			blade.mesh = PlaceholderBody.box_mesh(Vector3(0.07, 1.4, 0.02))
			blade.material_override = PlaceholderBody.mat(Color(0.5, 0.48, 0.45), 0.5)
			blade.position = gp + Vector3(-0.6 + k * 0.6, 0.8, 0.05)
			blade.rotation.z = 0.15
			root.add_child(blade)


func _kit_fort(root: Node3D) -> void:
	var stone := VeliciaMaterials.surface("stone_wall", Color(1.0, 0.97, 0.9), 0.3)
	var dark := VeliciaMaterials.surface("stone_wall", Color(0.78, 0.76, 0.72), 0.3)
	var r := 17.0
	var segs := 20
	for i in segs:
		var ang := TAU * (i + 0.5) / segs
		if i == 5 or i == 6 or i == 14:
			continue # breaches; i 5-6 face the approach from the outpost
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var h := 5.5 if i % 4 != 2 else 3.0
		var gp := _ground(root, p)
		_solid(root, Vector3(5.6, h, 1.4), gp + Vector3(0, h * 0.5 - 0.3, 0), -ang + PI * 0.5, stone if i % 2 == 0 else dark)
	for ang in [0.6, 3.6]:
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		_column(root, 2.2, 2.6, 9.0, _ground(root, p) + Vector3(0, 4.3, 0), dark, true, 8)
	# Broken central dais
	_column(root, 4.0, 4.4, 0.5, Vector3(0, 0.1, 0), dark, true, 10)
	for i in 10:
		var ang := _rng.randf() * TAU
		var p := Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(7.0, 14.0)
		_solid(root, Vector3(_rng.randf_range(0.6, 1.5), _rng.randf_range(0.4, 1.0), _rng.randf_range(0.6, 1.5)), _ground(root, p) + Vector3(0, 0.25, 0), _rng.randf() * TAU, stone)
	for p in [Vector3(-4, 0, -12), Vector3(4, 0, -12)]:
		_banner(root, p, Color(0.45, 0.16, 0.12), Color(0.8, 0.6, 0.35))


func _kit_grotto(root: Node3D) -> void:
	var rock := VeliciaMaterials.surface("rock", Color(0.85, 0.85, 0.85), 0.35)
	for i in 14:
		var ang := TAU * i / 14.0
		if i == 0:
			continue # the narrow way in
		var p := Vector3(cos(ang) * 7.0, 0, sin(ang) * 7.0)
		var s := 2.4 + (i % 3) * 0.6
		var m := MeshInstance3D.new()
		m.mesh = PlaceholderBody.sphere_mesh(s)
		m.material_override = rock
		m.position = _ground(root, p) + Vector3(0, s * 0.5, 0)
		m.scale = Vector3(1.0, 1.3, 1.0)
		root.add_child(m)
		var body := StaticBody3D.new()
		body.position = m.position
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = s * 1.05
		shape.shape = sphere
		body.add_child(shape)
		root.add_child(body)
	_solid(root, Vector3(12.0, 1.2, 10.0), Vector3(0.5, 6.5, 0), 0.2, rock)
	var glow := MeshInstance3D.new()
	glow.mesh = PlaceholderBody.sphere_mesh(0.3)
	glow.material_override = PlaceholderBody.mat(Color(0.5, 1.0, 0.7), 0.2, 2.5)
	glow.position = Vector3(-2, 1.0, -2)
	root.add_child(glow)


func _kit_battlefield(root: Node3D) -> void:
	var wood := VeliciaMaterials.surface("bark", Color.WHITE, 1.5, 0.95, false)
	var steel := PlaceholderBody.mat(Color(0.5, 0.5, 0.5), 0.5)
	for i in 26:
		var p := Vector3(_rng.randf_range(-16, 16), 0, _rng.randf_range(-16, 16))
		var gp := _ground(root, p)
		var blade := MeshInstance3D.new()
		blade.mesh = PlaceholderBody.box_mesh(Vector3(0.06, 1.3, 0.02) if i % 2 == 0 else Vector3(0.04, 2.0, 0.04))
		blade.material_override = steel if i % 2 == 0 else wood
		blade.position = gp + Vector3(0, 0.5, 0)
		blade.rotation = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf() * TAU, _rng.randf_range(-0.5, 0.5))
		root.add_child(blade)
	for p in [Vector3(-6, 0, 4), Vector3(7, 0, -3), Vector3(0, 0, 10)]:
		var gp := _ground(root, p)
		for k in 4:
			var stone := MeshInstance3D.new()
			stone.mesh = PlaceholderBody.sphere_mesh(0.5 - k * 0.08)
			stone.material_override = VeliciaMaterials.surface("rock", Color.WHITE, 1.2)
			stone.position = gp + Vector3(0, 0.4 + k * 0.6, 0)
			root.add_child(stone)
	_banner(root, Vector3(-10, 0, -8), Color(0.2, 0.3, 0.5), Color(0.9, 0.75, 0.3))
	_banner(root, Vector3(11, 0, 7), Color(0.5, 0.2, 0.16), Color(0.85, 0.7, 0.45))


func _kit_lake_ruin(root: Node3D) -> void:
	var stone := VeliciaMaterials.surface("stone_wall", Color(0.85, 0.98, 1.05), 0.45)
	var glow := PlaceholderBody.mat(Color(0.35, 0.85, 0.8), 0.2, 1.8)
	for i in 7:
		var ang := TAU * i / 7.0
		var p := Vector3(cos(ang) * 6.0, 0, sin(ang) * 6.0)
		var h := 3.5 - (i % 3) * 1.0
		_column(root, 0.4, 0.5, h, _ground(root, p) + Vector3(0, h * 0.5, 0), stone, true, 6)
	var pool := MeshInstance3D.new()
	pool.mesh = PlaceholderBody.cylinder_mesh(1.6, 1.8, 0.4, 12)
	pool.material_override = glow
	pool.position = _ground(root, Vector3.ZERO) + Vector3(0, 0.2, 0)
	root.add_child(pool)


func _kit_glade(root: Node3D) -> void:
	var bark := VeliciaMaterials.surface("bark", Color.WHITE, 0.6, 0.95, false)
	_column(root, 0.9, 1.5, 3.0, _ground(root, Vector3.ZERO) + Vector3(0, 1.2, 0), bark, true, 8)
	var giant := MeshInstance3D.new()
	giant.mesh = Vegetation.broadleaf(7)
	giant.position = _ground(root, Vector3.ZERO) - Vector3(0, 0.3, 0)
	giant.scale = Vector3.ONE * 2.6
	root.add_child(giant)
	var cap := PlaceholderBody.mat(Color(0.85, 0.5, 0.65), 0.6, 0.6)
	for i in 14:
		var ang := _rng.randf() * TAU
		var p := Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(3.0, 10.0)
		var gp := _ground(root, p)
		var m := MeshInstance3D.new()
		m.mesh = PlaceholderBody.sphere_mesh(0.3)
		m.material_override = cap
		m.position = gp + Vector3(0, 0.25, 0)
		m.scale = Vector3(1, 0.5, 1)
		root.add_child(m)

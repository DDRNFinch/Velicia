class_name GrassField
extends Node3D
## Dense grass around the player, built in chunks on demand and freed when
## far away. Density and radius follow the graphics quality setting; grass
## is skipped on paths, rock, sand, snow, water and inside settlements.

const CHUNK := 12.0

## Returns Color(dirt, rock, sand, snow) ground weights at a world position.
var weight_func: Callable
var radius := 24.0
var density := 1.2 # clumps per square metre
var _chunks: Dictionary = {}
var _timer := 0.0
var _mesh: ArrayMesh
var _material: ShaderMaterial


func configure(quality: String) -> void:
	match quality:
		"low":
			radius = 0.0
		"high":
			radius = 34.0
			density = 2.0
		_:
			radius = 24.0
			density = 1.15
	_mesh = Vegetation.grass_clump()
	_material = VeliciaMaterials.grass(radius)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or radius <= 0.0:
		return
	_timer = 0.4
	var p := CombatDirector.player
	if p == null or not is_instance_valid(p):
		return
	var center := Vector2i(floori(p.global_position.x / CHUNK), floori(p.global_position.z / CHUNK))
	var reach := ceili(radius / CHUNK)
	var wanted := {}
	var built := 0
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := center + Vector2i(dx, dz)
			var mid := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK
			if mid.distance_to(Vector2(p.global_position.x, p.global_position.z)) > radius + CHUNK * 0.75:
				continue
			wanted[key] = true
			if not _chunks.has(key) and built < 3:
				_chunks[key] = _build_chunk(key)
				built += 1
	for key in _chunks.keys():
		if not wanted.has(key):
			var n: Node = _chunks[key]
			if is_instance_valid(n):
				n.queue_free()
			_chunks.erase(key)


func _build_chunk(key: Vector2i) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var count := int(CHUNK * CHUNK * density)
	var transforms: Array[Transform3D] = []
	for i in count:
		var x := (key.x + rng.randf()) * CHUNK
		var z := (key.y + rng.randf()) * CHUNK
		var h := VeliciaTerrain.height_at(x, z)
		if h < VeliciaTerrain.water_level + 0.3:
			continue
		if weight_func.is_valid():
			var w: Color = weight_func.call(x, z)
			if w.r > 0.45 or w.g > 0.35 or w.b > 0.3 or w.a > 0.2:
				continue
		var s := rng.randf_range(0.7, 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
		transforms.append(Transform3D(b, Vector3(x, h - 0.03, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func chunk_count() -> int:
	return _chunks.size()

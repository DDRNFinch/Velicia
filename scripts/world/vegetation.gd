class_name Vegetation
extends RefCounted
## Procedural meshes for trees, pines, rocks and grass clumps. Each is built
## once per variant and drawn with MultiMesh. Trees have two surfaces: bark
## (textured) and foliage (alpha-cutout leaf cards with wind).

static var _cache: Dictionary = {}


static func broadleaf(variant: int) -> ArrayMesh:
	var key := "broad%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := rng.randf_range(3.6, 5.0)
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized()
	var top := _tube(bark, Vector3.ZERO, lean, height, 0.32, 0.13, 8, 4, rng)
	var crown := top + Vector3.UP * 0.9
	var ends: Array[Vector3] = [top]
	var branches := rng.randi_range(5, 7)
	for i in branches:
		var h := rng.randf_range(height * 0.45, height * 0.92)
		var start := lean * h
		var ang := TAU * i / branches + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), rng.randf_range(0.45, 0.9), sin(ang)).normalized()
		var length := rng.randf_range(1.4, 2.4)
		var end := _tube(bark, start, dir, length, 0.11, 0.035, 5, 2, rng)
		ends.append(end)
		ends.append(start + (end - start) * 0.55)
	for e in ends:
		var n := rng.randi_range(1, 2)
		for k in n:
			var c := e + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.5, 0.5))
			_leaf_cluster(leaves, c, rng.randf_range(1.7, 2.5), crown, rng)
	for k in 4:
		var c := crown + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.4, 0.8), rng.randf_range(-1.2, 1.2))
		_leaf_cluster(leaves, c, rng.randf_range(2.0, 2.7), crown, rng)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, VeliciaMaterials.surface("bark", Color.WHITE, 0.9, 0.95, false))
	mesh.surface_set_material(1, VeliciaMaterials.foliage("leaves"))
	_cache[key] = mesh
	return mesh


static func pine(variant: int) -> ArrayMesh:
	var key := "pine%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := rng.randf_range(8.0, 11.5)
	_tube(bark, Vector3.ZERO, Vector3.UP, height, 0.3, 0.05, 7, 5, rng)
	var tiers := 9
	for t in tiers:
		var f := float(t) / tiers
		var y := lerpf(1.6, height - 0.6, f)
		var radius := lerpf(2.6, 0.5, f) * rng.randf_range(0.9, 1.1)
		var cards := 7 if t < tiers - 2 else 5
		for i in cards:
			var ang := TAU * i / cards + t * 0.6 + rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(ang), 0, sin(ang))
			var droop := rng.randf_range(0.25, 0.55)
			var root := Vector3(0, y, 0) + out * 0.1
			var tip := root + out * radius - Vector3.UP * radius * droop
			_branch_card(needles, root, tip, radius * 0.95, Vector3(0, y - 0.5, 0))
	var mesh := bark.commit()
	needles.commit(mesh)
	mesh.surface_set_material(0, VeliciaMaterials.surface("bark", Color(0.85, 0.8, 0.78), 0.9, 0.95, false))
	mesh.surface_set_material(1, VeliciaMaterials.foliage("needles"))
	_cache[key] = mesh
	return mesh


static func rock(variant: int) -> ArrayMesh:
	var key := "rock%d" % variant
	if _cache.has(key):
		return _cache[key]
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 3000 + variant
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v * 1.3) * 0.45
		v *= d
		v.y = v.y * 0.7 if v.y > 0.0 else v.y * 0.35
		verts[i] = v
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	a[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, VeliciaMaterials.surface("rock", Color(0.95, 0.93, 0.9), 0.35, 0.95, true))
	_cache[key] = mesh
	return mesh


static func grass_clump() -> ArrayMesh:
	if _cache.has("grass"):
		return _cache.grass
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 9:
		var ang := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.22, 0.22), 0, rng.randf_range(-0.22, 0.22))
		var h := rng.randf_range(0.2, 0.48)
		var w := rng.randf_range(0.018, 0.032)
		var side := Vector3(cos(ang), 0, sin(ang)) * w
		var bend := Vector3(-sin(ang), 0, cos(ang)) * rng.randf_range(0.05, 0.22)
		var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.8, 1.0))
		var p0 := off - side
		var p1 := off + side
		var p2 := off - side * 0.6 + Vector3.UP * h * 0.55 + bend * 0.35
		var p3 := off + side * 0.6 + Vector3.UP * h * 0.55 + bend * 0.35
		var tip := off + Vector3.UP * h + bend
		var pts := [p0, p1, p3, p0, p3, p2, p2, p3, tip]
		var hs := [0.0, 0.0, 0.55, 0.0, 0.55, 0.55, 0.55, 0.55, 1.0]
		for i in pts.size():
			st.set_normal(Vector3.UP)
			st.set_color(Color(tint.r, tint.g, tint.b, hs[i]))
			st.add_vertex(pts[i])
	var mesh := st.commit()
	_cache.grass = mesh
	return mesh


## Tapered, slightly wavy tube. Returns the end point.
static func _tube(st: SurfaceTool, start: Vector3, dir: Vector3, length: float, r0: float, r1: float, sides: int, rings: int, rng: RandomNumberGenerator) -> Vector3:
	dir = dir.normalized()
	var side_a := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var side_b := dir.cross(side_a).normalized()
	var centers: Array[Vector3] = []
	var p := start
	for r in rings + 1:
		var f := float(r) / rings
		var wobble := (side_a * rng.randf_range(-1, 1) + side_b * rng.randf_range(-1, 1)) * 0.06 * length * f
		centers.append(start + dir * length * f + (wobble if r > 0 else Vector3.ZERO))
	for r in rings:
		var ra := lerpf(r0, r1, float(r) / rings)
		var rb := lerpf(r0, r1, float(r + 1) / rings)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var n0 := side_a * cos(a0) + side_b * sin(a0)
			var n1 := side_a * cos(a1) + side_b * sin(a1)
			var v0 := centers[r] + n0 * ra
			var v1 := centers[r] + n1 * ra
			var v2 := centers[r + 1] + n1 * rb
			var v3 := centers[r + 1] + n0 * rb
			var u0 := float(s) / sides
			var u1 := float(s + 1) / sides
			var w0 := float(r) / rings * length * 0.6
			var w1 := float(r + 1) / rings * length * 0.6
			_vtx(st, v0, n0, Vector2(u0, w0))
			_vtx(st, v2, n1, Vector2(u1, w1))
			_vtx(st, v1, n1, Vector2(u1, w0))
			_vtx(st, v0, n0, Vector2(u0, w0))
			_vtx(st, v3, n0, Vector2(u0, w1))
			_vtx(st, v2, n1, Vector2(u1, w1))
	p = centers[-1]
	return p


static func _vtx(st: SurfaceTool, v: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(v)


## Three crossed leaf cards with normals pointing away from the canopy centre.
static func _leaf_cluster(st: SurfaceTool, center: Vector3, size: float, canopy_center: Vector3, rng: RandomNumberGenerator) -> void:
	var base_rot := rng.randf() * PI
	for k in 3:
		var basis := Basis(Vector3.UP, base_rot + k * PI / 3.0) * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		var right := basis.x * size * 0.5
		var up := basis.y * size * 0.5
		var corners := [center - right - up, center + right - up, center + right + up, center - right + up]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			var n: Vector3 = (corners[idx] - canopy_center).normalized()
			n = (n + Vector3.UP * 0.4).normalized()
			_vtx(st, corners[idx], n, uvs[idx])


## Pine branch card from trunk (root) to tip, textured with the needle twig.
static func _branch_card(st: SurfaceTool, root: Vector3, tip: Vector3, width: float, canopy_center: Vector3) -> void:
	var along := (tip - root)
	var side := along.cross(Vector3.UP).normalized() * width * 0.5
	var lift := Vector3.UP * width * 0.12
	var corners := [root - side, root + side, tip + side + lift, tip - side + lift]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 2, 1, 0, 3, 2]:
		var n: Vector3 = ((corners[idx] - canopy_center).normalized() + Vector3.UP * 0.8).normalized()
		_vtx(st, corners[idx], n, uvs[idx])

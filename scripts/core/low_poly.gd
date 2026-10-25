class_name LowPoly
extends RefCounted
## The game's art style in one place: faceted (flat-shaded) low-poly meshes
## coloured per vertex from a hand-picked palette, lit by strong sun and soft
## fog. No textures and no custom shaders, so it is light on phones.

const PALETTE := {
	"grass": Color("6fae4a"), "grass_dark": Color("4f8f3e"), "grass_light": Color("93c95c"), "grass_dry": Color("a8b85a"),
	"dirt": Color("c9a26a"), "dirt_dark": Color("a4804e"), "sand": Color("e6d29a"), "rock": Color("9a958c"),
	"rock_dark": Color("6e6a66"), "rock_light": Color("bdb6aa"), "moss": Color("6f9a48"), "snow": Color("eef2f4"),
	"bark": Color("7a5236"), "bark_dark": Color("553722"), "leaf": Color("4e9a3e"), "leaf_dark": Color("357a34"),
	"leaf_light": Color("86c254"), "leaf_autumn": Color("d6913a"), "pine": Color("2f7350"), "pine_dark": Color("215a40"),
	"water": Color("3f8fc4"), "water_deep": Color("2a6aa0"), "wood": Color("b5844e"), "wood_dark": Color("80562f"),
	"stone": Color("c2bcb0"), "stone_dark": Color("8e897f"), "cloth_blue": Color("35588e"), "cloth_red": Color("9a3a2c"),
	"cloth_hide": Color("8a6a48"), "gold": Color("e0b040"), "glow": Color("7ae8ff"), "fire": Color("ff9a30"),
	"flower_white": Color("f4f0ea"), "flower_yellow": Color("f2cc40"), "flower_pink": Color("e8789a"), "flower_blue": Color("7aa8f0"),
	"mushroom": Color("d65a4a"), "roof_red": Color("b04a3a"), "roof_blue": Color("3a5a9a"), "plaster": Color("e8dcc0"),
}

static var _mats: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func c(name: String) -> Color:
	return PALETTE.get(name, Color.MAGENTA)


## Shared vertex-colour material (one per roughness/emission combo).
static func vcol_mat(roughness: float = 0.95, emission: float = 0.0, double_sided: bool = false) -> StandardMaterial3D:
	var key := "v|%.2f|%.2f|%s" % [roughness, emission, double_sided]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = roughness
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		if emission > 0.0:
			m.emission_enabled = true
			m.emission_energy_multiplier = emission
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission = Color.WHITE
		if double_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


## Plain colour material (structures, props, characters).
static func mat(color: Color, roughness: float = 0.9, emission: float = 0.0, alpha: float = 1.0, rim: float = 0.0) -> StandardMaterial3D:
	var key := "c|%s|%.2f|%.2f|%.2f|%.2f" % [color.to_html(), roughness, emission, alpha, rim]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(color, alpha)
		m.roughness = roughness
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emission
		if rim > 0.0:
			m.rim_enabled = true
			m.rim = rim
			m.rim_tint = 0.4
		_mats[key] = m
	return _mats[key]


# ------------------------------------------------------------------ faceting

## Returns a copy of `mesh` with every triangle unshared and given its own
## face normal: the faceted low-poly look. Vertex colours are kept.
static func flat(mesh: Mesh, color: Color = Color.WHITE, use_color: bool = false) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var tri_count := (idx.size() if idx.size() > 0 else verts.size()) / 3
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nc := PackedColorArray()
		nv.resize(tri_count * 3)
		nn.resize(tri_count * 3)
		nc.resize(tri_count * 3)
		for t in tri_count:
			var ia := idx[t * 3] if idx.size() > 0 else t * 3
			var ib := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
			var ic := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
			var a := verts[ia]
			var b := verts[ib]
			var cc := verts[ic]
			var n := (cc - a).cross(b - a).normalized()
			nv[t * 3] = a
			nv[t * 3 + 1] = b
			nv[t * 3 + 2] = cc
			for k in 3:
				nn[t * 3 + k] = n
			if cols.size() > 0 and not use_color:
				nc[t * 3] = cols[ia]
				nc[t * 3 + 1] = cols[ib]
				nc[t * 3 + 2] = cols[ic]
			else:
				for k in 3:
					nc[t * 3 + k] = color
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = nv
		arrays[Mesh.ARRAY_NORMAL] = nn
		arrays[Mesh.ARRAY_COLOR] = nc
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := mesh.surface_get_material(s)
		if m:
			out.surface_set_material(out.get_surface_count() - 1, m)
	return out


# ------------------------------------------------------------------ builder

## Accumulates coloured, faceted triangles and returns one ArrayMesh.
class Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (c - a).cross(b - a).normalized()
		verts.append_array([a, b, c])
		norms.append_array([n, n, n])
		cols.append_array([col, col, col])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	## Appends a primitive mesh (transformed, single colour, faceted).
	func add_mesh(mesh: Mesh, xf: Transform3D, col: Color, shade_jitter: float = 0.0, rng: RandomNumberGenerator = null) -> void:
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := (idx.size() if idx.size() > 0 else v.size()) / 3
			for t in count:
				var ia := idx[t * 3] if idx.size() > 0 else t * 3
				var ib := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
				var ic := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
				var cc := col
				if shade_jitter > 0.0 and rng:
					var j := rng.randf_range(-shade_jitter, shade_jitter)
					cc = col.lightened(j) if j > 0.0 else col.darkened(-j)
				tri(xf * v[ia], xf * v[ib], xf * v[ic], cc)

	func commit(material: Material = null) -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, material if material else LowPoly.vcol_mat())
		return m


# ------------------------------------------------------------------ primitives

static func ico(radius: float, rng: RandomNumberGenerator = null, jitter: float = 0.0) -> ArrayMesh:
	## Low-poly blob: a sphere with few segments and optional lumpy vertices.
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 7
	s.rings = 4
	if rng == null or jitter <= 0.0:
		return _prim_to_array(s)
	var arr := s.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	# Jitter shared positions identically so the blob stays closed.
	var moved := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 1000.0), roundi(v[i].y * 1000.0), roundi(v[i].z * 1000.0))
		if not moved.has(key):
			moved[key] = v[i] * (1.0 + rng.randf_range(-jitter, jitter))
		v[i] = moved[key]
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _prim_to_array(p: PrimitiveMesh) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p.get_mesh_arrays())
	return m


static func cone(r_top: float, r_bottom: float, h: float, sides: int = 6) -> ArrayMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bottom
	cyl.height = h
	cyl.radial_segments = sides
	cyl.rings = 1
	return _prim_to_array(cyl)


static func box(size: Vector3) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = size
	return _prim_to_array(b)


# ------------------------------------------------------------------ props

static func tree(variant: int, autumn: bool = false) -> ArrayMesh:
	var key := "tree%d%s" % [variant, autumn]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var b := Builder.new()
	var trunk_h := rng.randf_range(1.8, 2.4)
	b.add_mesh(cone(0.2, 0.32, trunk_h, 5), Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0)), c("bark"), 0.08, rng)
	# A branch fork
	b.add_mesh(cone(0.06, 0.12, 1.0, 4), Transform3D(Basis(Vector3.FORWARD, 0.7), Vector3(0.3, trunk_h * 0.8, 0)), c("bark_dark"))
	var leaf := c("leaf_autumn") if autumn else c("leaf")
	var blobs := [[Vector3(0, trunk_h + 1.0, 0), 1.55], [Vector3(0.9, trunk_h + 0.5, 0.3), 1.05],
			[Vector3(-0.8, trunk_h + 0.6, -0.2), 1.1], [Vector3(0.1, trunk_h + 1.9, -0.1), 1.0],
			[Vector3(0.3, trunk_h + 0.7, -0.9), 0.95]]
	for i in blobs.size():
		var bl: Array = blobs[i]
		var col := leaf.lightened(0.12) if i == 3 else (leaf.darkened(0.12) if i == 2 else leaf)
		b.add_mesh(ico(float(bl[1]), rng, 0.16), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), bl[0]), col, 0.07, rng)
	_mesh_cache[key] = b.commit()
	return _mesh_cache[key]


static func pine(variant: int) -> ArrayMesh:
	var key := "pine%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 200 + variant
	var b := Builder.new()
	b.add_mesh(cone(0.14, 0.24, 1.4, 5), Transform3D(Basis(), Vector3(0, 0.7, 0)), c("bark"))
	var y := 1.0
	var tiers := 3 + variant % 2
	for i in tiers:
		var r := 1.6 - i * 0.38
		var h := 1.5 - i * 0.12
		var col := c("pine").lightened(0.05 * i)
		b.add_mesh(cone(0.0, r, h, 7), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, y + h * 0.5, 0)), col, 0.06, rng)
		y += h * 0.55
	_mesh_cache[key] = b.commit()
	return _mesh_cache[key]


static func rock(variant: int) -> ArrayMesh:
	var key := "rock%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant
	var b := Builder.new()
	var m := ico(1.0, rng, 0.28)
	b.add_mesh(m, Transform3D(Basis().scaled(Vector3(1.2, 0.75, 1.0)), Vector3(0, 0.35, 0)), c("rock"), 0.1, rng)
	# Mossy cap
	b.add_mesh(ico(0.62, rng, 0.2), Transform3D(Basis().scaled(Vector3(1.3, 0.35, 1.1)), Vector3(0.05, 0.95, 0)), c("moss"), 0.06, rng)
	_mesh_cache[key] = b.commit()
	return _mesh_cache[key]


static func bush(variant: int) -> ArrayMesh:
	var key := "bush%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + variant
	var b := Builder.new()
	for i in 3:
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0.4 + rng.randf() * 0.15, rng.randf_range(-0.35, 0.35))
		b.add_mesh(ico(rng.randf_range(0.42, 0.6), rng, 0.15), Transform3D(Basis(), p), c("leaf_dark").lightened(0.08 * i), 0.07, rng)
	if variant % 2 == 1:
		for i in 4:
			var p := Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(0.55, 0.85), rng.randf_range(-0.45, 0.45))
			b.add_mesh(ico(0.07), Transform3D(Basis(), p), c("flower_pink") if i % 2 else c("flower_white"))
	_mesh_cache[key] = b.commit()
	return _mesh_cache[key]


static func grass_tuft(variant: int) -> ArrayMesh:
	var key := "tuft%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + variant
	var b := Builder.new()
	for i in 5:
		var ang := rng.randf() * TAU
		var base := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var side := Vector3(cos(ang), 0, sin(ang)) * 0.06
		var tip := base + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.28, 0.5), rng.randf_range(-0.12, 0.12))
		var col := c("grass_light") if i % 2 == 0 else c("grass")
		b.tri(base - side, tip, base + side, col)
		b.tri(base + side, tip, base - side, col.darkened(0.1))
	_mesh_cache[key] = b.commit(vcol_mat(0.95, 0.0, false))
	return _mesh_cache[key]


static func flower(variant: int) -> ArrayMesh:
	var key := "flower%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cols := [c("flower_white"), c("flower_yellow"), c("flower_pink"), c("flower_blue")]
	var b := Builder.new()
	var stem := Vector3(0, 0.28, 0)
	b.tri(Vector3(-0.02, 0, 0), stem, Vector3(0.02, 0, 0), c("grass_dark"))
	b.tri(Vector3(0.02, 0, 0), stem, Vector3(-0.02, 0, 0), c("grass_dark"))
	var pc: Color = cols[variant % cols.size()]
	for k in 5:
		var a := k * TAU / 5.0
		var p := stem + Vector3(cos(a), 0, sin(a)) * 0.09
		b.tri(stem + Vector3(0, 0.01, 0), p + Vector3(cos(a + 0.6), 0, sin(a + 0.6)) * 0.04, p, pc)
		b.tri(stem + Vector3(0, 0.01, 0), p, p + Vector3(cos(a + 0.6), 0, sin(a + 0.6)) * 0.04, pc.darkened(0.1))
	b.add_mesh(ico(0.035), Transform3D(Basis(), stem + Vector3(0, 0.02, 0)), c("flower_yellow") if variant % cols.size() != 1 else c("wood"))
	_mesh_cache[key] = b.commit()
	return _mesh_cache[key]


static func mushroom() -> ArrayMesh:
	if _mesh_cache.has("mushroom"):
		return _mesh_cache["mushroom"]
	var b := Builder.new()
	b.add_mesh(cone(0.05, 0.07, 0.2, 5), Transform3D(Basis(), Vector3(0, 0.1, 0)), c("flower_white"))
	b.add_mesh(cone(0.0, 0.16, 0.12, 6), Transform3D(Basis(), Vector3(0, 0.24, 0)), c("mushroom"))
	_mesh_cache["mushroom"] = b.commit()
	return _mesh_cache["mushroom"]

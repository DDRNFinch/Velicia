class_name PlaceholderBody
extends Node3D
## PLACEHOLDER ART. A procedural humanoid built from primitive meshes with
## procedural animation, so gameplay can be built and tested before final
## rigged models exist. Proportions follow docs/CHARACTER_DESIGN.md so each
## people's silhouette reads correctly (human faces for Amir and Burrok,
## stocky dwarf-like Gouran, wiry Gyria, larger Gyria bosses).
## Replace with rigged glTF models per docs/ASSET_REQUIREMENTS.md.

signal footstep

const DEFAULTS := {
	"people": &"human",
	"height": 1.78,
	"shoulder": 0.46,
	"limb": 0.065,
	"head_scale": 1.0,
	"arm_mult": 1.0,
	"leg_mult": 1.0,
	"depth": 1.0,
	"skin": Color(0.78, 0.6, 0.47),
	"cloth": Color(0.3, 0.33, 0.4),
	"armor": Color(0.45, 0.38, 0.3),
	"hair": Color(0.25, 0.17, 0.1),
	"accent": Color(0.85, 0.7, 0.3),
	"cloak": Color(0.2, 0.3, 0.45),
	"has_cloak": false,
	"tail": false,
	"arm_fur": false,
	"fur": Color(0.42, 0.36, 0.3),
	"robe": false,
	"beard": false,
	"heavy_brow": false,
	"nose_scale": 1.0,
	"pointed_ears": false,
	"tusks": false,
	"mantle": false,
	"markings": false,
	"pauldrons": false,
	"pouches": false,
	"angular": false,
	"crest": false,
	"ears": &"",          # "" human, &"wolf" (Amir), &"bear" (Burrok), &"fin" (Vapouriun)
	"fin_crest": false,   # Vapouriun head fin
	"claws": false,       # Amir clawed hands
	"paws": false,        # Burrok furry bear paws
	"belly": 0.0,         # Gouran pot belly (0 = none)
	"hood": false,
	"beard_len": 1.0,
	"eye_scale": 1.0,
	"skin_detail": "skin",
	"hair_style": &"short",
	"weapon": &"sword",
	"dual_wield": false,
	"shield": false,
}

## Characters further than this are not drawn (they are tiny on a phone screen).
const VIEW_RANGE := 70.0

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

var params: Dictionary = {}
var height: float = 1.78
var leg_len: float = 0.8
var torso_len: float = 0.5
var head_r: float = 0.11
var arm_len: float = 0.6

var hips: Node3D
var spine: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapon_pivot: Node3D
var offhand_pivot: Node3D
var hand_r_anchor: Node3D
var tail_segments: Array[Node3D] = []

var _meshes: Array[MeshInstance3D] = []
var _weapon_meshes: Array[MeshInstance3D] = []
var _walk_phase := 0.0
var _last_step_sign := 1.0
var _pose_target: Dictionary = {}
var _pose_active := false
var _pose_weight := 0.0
var _flash_mat: StandardMaterial3D
var _flash_time := 0.0
var _telegraph_mat: StandardMaterial3D
var _telegraph_on := false
var _time := 0.0
var _base_weapon_rot := Vector3(-0.9, 0, 0)
var _weapon_len := 0.9
var trail: WeaponTrail



# ------------------------------------------------------------- Mesh cache

## Cached flat-colour material (`detail` only affects metal's sheen now).
static func mat(color: Color, roughness: float = 0.85, emission: float = 0.0, alpha: float = 1.0, detail: String = "", detail_scale: float = 3.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%s|%.1f" % [color.to_html(), roughness, emission, alpha, detail, detail_scale]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = roughness
	if not detail.is_empty():
		var tex := VeliciaMaterials.tex(detail + "_albedo")
		if tex:
			m.albedo_texture = tex
			var nrm := VeliciaMaterials.tex(detail + "_normal")
			if nrm:
				m.normal_enabled = true
				m.normal_texture = nrm
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * detail_scale
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if detail == "metal":
			m.metallic = 0.65
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif emission <= 0.0:
		# Soft rim light makes figures pop against the ground from above.
		m.rim_enabled = true
		m.rim = 0.22
		m.rim_tint = 0.5
	_mat_cache[key] = m
	return m


## Lifts dark, muddy preset colours into the brighter, saturated palette of
## the low-poly style (they were tuned for the old realistic lighting).
static func _tone(c: Color, lift: float = 0.16) -> Color:
	var h := c.h
	var sat := clampf(c.s * 1.15 + 0.04, 0.0, 1.0)
	var v := clampf(c.v + lift + (0.12 if c.v < 0.3 else 0.0), 0.0, 1.0)
	return Color.from_hsv(h, sat, v)


static func box_mesh(size: Vector3) -> Mesh:
	var key := "box%.3v" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = LowPoly.flat(m)
	return _mesh_cache[key]


static func capsule_mesh(radius: float, h: float) -> Mesh:
	var key := "cap%.3f_%.3f" % [radius, h]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(h, radius * 2.0 + 0.01)
		m.radial_segments = 7
		m.rings = 2
		_mesh_cache[key] = LowPoly.flat(m)
	return _mesh_cache[key]


static func sphere_mesh(radius: float) -> Mesh:
	var key := "sph%.3f" % radius
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 9
		m.rings = 5
		_mesh_cache[key] = LowPoly.flat(m)
	return _mesh_cache[key]


static func cylinder_mesh(top: float, bottom: float, h: float, sides: int = 8) -> Mesh:
	var key := "cyl%.3f_%.3f_%.3f_%d" % [top, bottom, h, sides]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = sides
		m.rings = 1
		_mesh_cache[key] = LowPoly.flat(m)
	return _mesh_cache[key]


func _part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.visibility_range_end = VIEW_RANGE
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


# ------------------------------------------------------------------ Build

func build(new_params: Dictionary) -> void:
	params = DEFAULTS.duplicate()
	for k in new_params:
		params[k] = new_params[k]
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_meshes.clear()
	_weapon_meshes.clear()
	tail_segments.clear()

	height = params.height
	# Chunky, toy-like limbs and slightly broader shoulders for the chibi look.
	var s: float = params.shoulder * 1.1
	var limb: float = params.limb * 1.5
	var skin := mat(_tone(params.skin, 0.06), 0.55 if params.skin_detail == "scales" else 0.62)
	var cloth := mat(_tone(params.cloth), 0.9)
	var armor := mat(_tone(params.armor), 0.6)
	var plate := mat(_tone(Color(params.armor).lightened(0.25)), 0.35, 0.0, 1.0, "metal")
	var accent := mat(_tone(params.accent), 0.4, 0.0, 1.0, "metal")
	var hair := mat(_tone(params.hair, 0.08), 0.8)
	var dark := mat(Color(0.08, 0.06, 0.06), 0.5)

	# Chibi proportions (big heads, short legs) so faces and each people's
	# features read clearly from the high, angled camera.
	head_r = height * 0.112 * float(params.head_scale)
	leg_len = height * 0.36 * float(params.leg_mult)
	var neck := height * 0.025
	torso_len = height - leg_len - neck - head_r * 2.0
	arm_len = height * 0.3 * float(params.arm_mult)

	hips = _pivot(self, Vector3(0, leg_len, 0), "Hips")
	spine = _pivot(hips, Vector3.ZERO, "Spine")

	# Torso
	var depth: float = s * 0.55 * float(params.depth)
	var round_mesh := sphere_mesh(0.5)
	_part(hips, round_mesh, cloth, Vector3(0, 0, 0), Vector3.ZERO, Vector3(s * 0.9, height * 0.14, depth * 0.95))
	_part(spine, round_mesh, cloth, Vector3(0, torso_len * 0.24, 0), Vector3.ZERO, Vector3(s * 0.84, torso_len * 0.55, depth * 0.88))
	_part(spine, round_mesh, armor, Vector3(0, torso_len * 0.66, 0), Vector3.ZERO, Vector3(s * 1.04, torso_len * 0.72, depth * 1.02))
	_part(spine, round_mesh, armor, Vector3(0, torso_len * 0.84, -depth * 0.08), Vector3.ZERO, Vector3(s * 0.7, torso_len * 0.3, depth * 0.8))
	_part(spine, cylinder_mesh(0.5, 0.5, 1.0, 14), accent, Vector3(0, torso_len * 0.04, 0), Vector3.ZERO, Vector3(s * 0.94, height * 0.035, depth * 1.0))
	if float(params.belly) > 0.0:
		var b: float = params.belly
		_part(spine, round_mesh, cloth, Vector3(0, torso_len * 0.3, -depth * 0.22 * b), Vector3.ZERO, Vector3(s * 0.88, torso_len * 0.62, depth * (1.0 + 0.35 * b)))
	if params.pouches:
		for x in [-0.32, 0.0, 0.3]:
			_part(spine, box_mesh(Vector3(s * 0.16, height * 0.06, depth * 0.3)), mat(Color(0.4, 0.28, 0.16)), Vector3(s * x, torso_len * 0.0, -depth * 0.55))
	if params.pauldrons:
		for side in [-1.0, 1.0]:
			_part(spine, sphere_mesh(0.5), plate, Vector3(side * s * 0.52, torso_len * 0.98, 0), Vector3(0, 0, side * -0.3), Vector3(s * 0.42, torso_len * 0.22, depth * 1.05))
	if params.has_cloak:
		var cloak_len := torso_len * 0.9 + leg_len * 0.65
		_part(spine, box_mesh(Vector3(s * 0.82, cloak_len, 0.03)), mat(_tone(params.cloak), 0.9), Vector3(0, torso_len * 0.95 - cloak_len * 0.5, depth * 0.55), Vector3(-0.06, 0, 0))
	if params.mantle:
		# Vapouriun: translucent layered mist-mantle over the shoulders.
		var mist: Color = params.accent.lerp(Color(0.85, 0.95, 1.0), 0.5)
		var mantle_len := torso_len * 0.8 + leg_len * 0.75
		_part(spine, box_mesh(Vector3(s * 1.15, mantle_len, depth * 1.25)), mat(mist, 0.2, 0.15, 0.32), Vector3(0, torso_len * 1.0 - mantle_len * 0.5, depth * 0.08))
		_part(spine, cylinder_mesh(s * 0.42, s * 0.62, torso_len * 0.3, 10), mat(mist, 0.2, 0.2, 0.45), Vector3(0, torso_len * 0.92, 0))
	if params.robe:
		var robe_h := leg_len * 0.92
		_part(hips, cylinder_mesh(s * 0.48, s * 0.82, robe_h, 10), cloth, Vector3(0, -robe_h * 0.5 + height * 0.03, 0))
		_part(hips, cylinder_mesh(s * 0.83, s * 0.86, height * 0.04, 10), accent, Vector3(0, -robe_h + height * 0.04, 0))

	# Head and face: every people has a human-structured face.
	head = _pivot(spine, Vector3(0, torso_len + neck, 0), "Head")
	_part(head, capsule_mesh(limb * 1.3, neck * 2.5), skin, Vector3(0, -neck * 0.2, 0))
	var head_scale := Vector3(0.86, 1.12, 0.95) if params.angular else Vector3(1, 1.05, 1)
	_part(head, sphere_mesh(head_r), skin, Vector3(0, head_r, 0), Vector3.ZERO, head_scale)
	# Human jaw and chin
	var jaw_w := head_r * (1.25 if params.angular else 1.45)
	_part(head, sphere_mesh(0.5), skin, Vector3(0, head_r * 0.5, -head_r * 0.2), Vector3.ZERO, Vector3(jaw_w * 0.95, head_r * 0.8, head_r * 1.35))
	# Human nose (never a muzzle or snout)
	var ns: float = params.nose_scale
	_part(head, box_mesh(Vector3(head_r * 0.24 * ns, head_r * 0.42 * ns, head_r * 0.28 * ns)), skin, Vector3(0, head_r * 0.95, -head_r * 0.98), Vector3(-0.25, 0, 0))
	# Eyes and mouth
	for side in [-1.0, 1.0]:
		# Big, bright stylised eyes: a white disc with a dark pupil and a glint.
		var es := float(params.eye_scale)
		var eye_pos := Vector3(side * head_r * 0.38, head_r * 1.12, -head_r * 0.84)
		_part(head, sphere_mesh(head_r * 0.2 * es), mat(Color(0.97, 0.96, 0.92), 0.3), eye_pos, Vector3.ZERO, Vector3(0.85, 1.0, 0.45))
		_part(head, sphere_mesh(head_r * 0.13 * es), dark, eye_pos + Vector3(0, -head_r * 0.01, -head_r * 0.07), Vector3.ZERO, Vector3(0.85, 1.0, 0.5))
		_part(head, sphere_mesh(head_r * 0.04 * es), mat(Color.WHITE, 0.2, 1.5), eye_pos + Vector3(side * head_r * 0.04, head_r * 0.05, -head_r * 0.13))
	_part(head, box_mesh(Vector3(head_r * 0.5, head_r * 0.06, head_r * 0.05)), mat(Color(0.45, 0.2, 0.18)), Vector3(0, head_r * 0.58, -head_r * 0.98))
	if params.heavy_brow:
		_part(head, box_mesh(Vector3(head_r * 1.35, head_r * 0.22, head_r * 0.35)), skin, Vector3(0, head_r * 1.38, -head_r * 0.82))
	# Ears. Amir and Burrok keep human faces; only the ears are animal.
	var fur_mat := mat(_tone(params.fur, 0.1), 0.95)
	for side in [-1.0, 1.0]:
		if params.ears == &"wolf":
			_part(head, cylinder_mesh(0.0, head_r * 0.3, head_r * 0.85, 4), fur_mat, Vector3(side * head_r * 0.55, head_r * 2.15, head_r * 0.05), Vector3(0.1, PI * 0.25, side * -0.28), Vector3(1, 1, 0.45))
			_part(head, cylinder_mesh(0.0, head_r * 0.16, head_r * 0.55, 4), mat(_tone(Color(params.fur).lightened(0.3), 0.1), 0.95), Vector3(side * head_r * 0.55, head_r * 2.08, -head_r * 0.03), Vector3(0.1, PI * 0.25, side * -0.28), Vector3(1, 1, 0.3))
		elif params.ears == &"bear":
			_part(head, sphere_mesh(head_r * 0.34), fur_mat, Vector3(side * head_r * 0.78, head_r * 2.0, head_r * 0.05), Vector3(0, 0, side * -0.35), Vector3(1, 1, 0.55))
			_part(head, sphere_mesh(head_r * 0.2), mat(_tone(Color(params.fur).darkened(0.35), 0.1), 0.95), Vector3(side * head_r * 0.78, head_r * 2.0, -head_r * 0.08), Vector3(0, 0, side * -0.35), Vector3(1, 1, 0.4))
		elif params.ears == &"fin":
			_part(head, cylinder_mesh(0.0, head_r * 0.4, head_r * 1.1, 4), skin, Vector3(side * head_r * 1.05, head_r * 1.2, head_r * 0.35), Vector3(-0.9, 0, side * -1.1), Vector3(1, 1, 0.18))
		elif params.pointed_ears:
			_part(head, cylinder_mesh(0.0, head_r * 0.2, head_r * 0.75, 4), skin, Vector3(side * head_r * 1.15, head_r * 1.15, head_r * 0.1), Vector3(0, 0, side * -1.2))
		else:
			_part(head, sphere_mesh(head_r * 0.2), skin, Vector3(side * head_r * 0.98, head_r * 1.0, 0), Vector3.ZERO, Vector3(0.5, 1, 0.8))
	if params.tusks:
		for side in [-1.0, 1.0]:
			_part(head, cylinder_mesh(0.0, head_r * 0.07, head_r * 0.3, 4), mat(Color(0.92, 0.88, 0.75)), Vector3(side * head_r * 0.3, head_r * 0.62, -head_r * 0.9))
	if params.markings:
		var tide := mat(params.accent, 0.3, 1.2)
		for side in [-1.0, 1.0]:
			_part(head, box_mesh(Vector3(head_r * 0.06, head_r * 0.4, head_r * 0.04)), tide, Vector3(side * head_r * 0.62, head_r * 0.9, -head_r * 0.78), Vector3(0, side * 0.5, side * 0.3))
	if params.beard:
		_part(head, box_mesh(Vector3(head_r * 1.2, head_r * 1.0, head_r * 0.6)), hair, Vector3(0, head_r * 0.15, -head_r * 0.62))
		var bl: float = params.beard_len
		if bl > 1.0:
			_part(head, cylinder_mesh(head_r * 0.58, head_r * 0.12, head_r * (bl - 0.4), 8), hair, Vector3(0, -head_r * (bl - 0.4) * 0.5 - head_r * 0.2, -head_r * 0.75), Vector3(-0.15, 0, 0), Vector3(1, 1, 0.55))
	if params.hood:
		_part(head, sphere_mesh(head_r * 1.28), cloth, Vector3(0, head_r * 1.15, head_r * 0.22), Vector3.ZERO, Vector3(1.0, 1.05, 1.05))
		_part(head, cylinder_mesh(0.0, head_r * 0.6, head_r * 0.9, 6), cloth, Vector3(0, head_r * 1.2, head_r * 1.3), Vector3(1.9, 0, 0))
	else:
		_build_hair(params.hair_style, hair)
	if params.fin_crest:
		var fin := mat(_tone(Color(params.skin).lightened(0.15), 0.06), 0.4)
		for i in 3:
			_part(head, cylinder_mesh(0.0, head_r * 0.35, head_r * (0.9 - 0.15 * i), 4), fin, Vector3(0, head_r * (2.0 - 0.18 * i), head_r * (-0.15 + 0.45 * i)), Vector3(-0.35 - 0.25 * i, 0, 0), Vector3(0.15, 1, 1))
	if params.crest:
		for i in 3:
			_part(head, cylinder_mesh(0.0, head_r * 0.12, head_r * 0.6, 4), armor, Vector3(0, head_r * 2.0, head_r * (-0.4 + 0.4 * i)), Vector3(-0.3, 0, 0))

	# Arms
	var arm_mat := mat(_tone(params.fur, 0.1), 0.95) if params.arm_fur else skin
	var sleeve := cloth
	for side in [-1.0, 1.0]:
		var shoulder := _pivot(spine, Vector3(side * (s * 0.5 + limb * 0.7), torso_len * 0.88, 0), "ArmR" if side > 0 else "ArmL")
		var upper_r := limb * (1.2 if params.arm_fur else 1.0)
		_part(shoulder, capsule_mesh(upper_r, arm_len * 0.52), arm_mat if params.arm_fur else sleeve, Vector3(0, -arm_len * 0.25, 0))
		var elbow := _pivot(shoulder, Vector3(0, -arm_len * 0.5, 0), "Forearm")
		_part(elbow, capsule_mesh(upper_r * 0.92, arm_len * 0.5), arm_mat, Vector3(0, -arm_len * 0.22, 0))
		if params.arm_fur:
			# Fur tufts along the forearm (Amir).
			for i in 3:
				_part(elbow, cylinder_mesh(0.0, limb * 0.5, limb * 1.6, 4), arm_mat, Vector3(side * limb * 0.9, -arm_len * (0.08 + 0.13 * i), limb * 0.3), Vector3(0, 0, side * -1.1))
		if params.paws:
			# Burrok: large furry bear paws with blunt claws (human face, animal hands).
			_part(elbow, sphere_mesh(limb * 1.9), arm_mat, Vector3(0, -arm_len * 0.5, 0), Vector3.ZERO, Vector3(1.0, 0.85, 1.1))
			for c in 4:
				_part(elbow, cylinder_mesh(0.0, limb * 0.22, limb * 0.8, 4), mat(Color(0.18, 0.15, 0.12), 0.4), Vector3(limb * (-0.75 + 0.5 * c), -arm_len * 0.5 - limb * 1.6, -limb * 0.7), Vector3(PI + 0.4, 0, 0))
		else:
			_part(elbow, sphere_mesh(limb * 1.3), skin, Vector3(0, -arm_len * 0.47, 0))
			if params.claws:
				for c in 4:
					_part(elbow, cylinder_mesh(0.0, limb * 0.18, limb * 0.9, 4), mat(Color(0.86, 0.82, 0.72), 0.4), Vector3(limb * (-0.6 + 0.4 * c), -arm_len * 0.47 - limb * 1.3, -limb * 0.55), Vector3(PI + 0.35, 0, 0))
		var hand := _pivot(elbow, Vector3(0, -arm_len * 0.47, 0), "Hand")
		if side > 0:
			arm_r = shoulder
			forearm_r = elbow
			hand_r_anchor = hand
			weapon_pivot = _pivot(hand, Vector3.ZERO, "Weapon")
			weapon_pivot.rotation = _base_weapon_rot
		else:
			arm_l = shoulder
			forearm_l = elbow
			offhand_pivot = _pivot(hand, Vector3.ZERO, "Offhand")
			offhand_pivot.rotation = _base_weapon_rot

	# Legs
	for side in [-1.0, 1.0]:
		var leg := _pivot(hips, Vector3(side * s * 0.24, 0, 0), "LegR" if side > 0 else "LegL")
		_part(leg, capsule_mesh(limb * 1.3, leg_len * 0.98), cloth if not params.arm_fur else mat(_tone(params.cloth.darkened(0.2))), Vector3(0, -leg_len * 0.5, 0))
		_part(leg, sphere_mesh(0.5), mat(Color(0.3, 0.21, 0.14), 0.7, 0.0, 1.0, "leather", 3.0), Vector3(0, -leg_len + height * 0.025, -limb * 0.9), Vector3.ZERO, Vector3(limb * 2.5, height * 0.06, limb * 4.4))
		_part(leg, cylinder_mesh(limb * 1.45, limb * 1.3, leg_len * 0.32, 10), mat(Color(0.3, 0.21, 0.14), 0.7, 0.0, 1.0, "leather", 3.0), Vector3(0, -leg_len * 0.82, 0))
		if side > 0:
			leg_r = leg
		else:
			leg_l = leg

	if params.tail:
		_build_tail(s, mat(_tone(params.fur, 0.1), 0.95))
	_build_weapon(params.weapon, weapon_pivot)
	if params.dual_wield:
		_build_weapon(params.weapon, offhand_pivot)
	if params.shield:
		_build_shield()
	_merge_parts()
	trail = WeaponTrail.new()
	add_child(trail)

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 1, 1, 0.0)
	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat.albedo_color = Color(1, 0.2, 0.1, 0.0)


## Merges the primitive parts under each animated pivot into one mesh with a
## surface per material. Animation is unchanged (pivots still move), but a
## character drops from ~40 draw objects to ~12, which matters on phones.
func _merge_parts() -> void:
	var weapon_parents := {}
	for w in _weapon_meshes:
		if is_instance_valid(w):
			weapon_parents[w.get_parent()] = true
	_meshes = merge_by_parent(_meshes, VIEW_RANGE)
	var weapons: Array[MeshInstance3D] = []
	for mi in _meshes:
		if weapon_parents.has(mi.get_parent()):
			weapons.append(mi)
	_weapon_meshes = weapons


## Merges mesh instances that share a parent into one mesh with a surface per
## material. Returns the resulting instances (merged or untouched singles).
static func merge_by_parent(list: Array[MeshInstance3D], view_range: float) -> Array[MeshInstance3D]:
	var groups := {}
	for mi in list:
		if not is_instance_valid(mi):
			continue
		var parent := mi.get_parent()
		if not groups.has(parent):
			groups[parent] = []
		groups[parent].append(mi)
	var out: Array[MeshInstance3D] = []
	for parent in groups:
		var parts: Array = groups[parent]
		if parts.size() < 2:
			out.append(parts[0])
			continue
		var by_mat := {}
		for mi in parts:
			var src: Mesh = (mi as MeshInstance3D).mesh
			for surf in src.get_surface_count():
				var m: Material = mi.material_override if mi.material_override else src.surface_get_material(surf)
				if not by_mat.has(m):
					by_mat[m] = []
				by_mat[m].append([src, surf, (mi as MeshInstance3D).transform])
		var mesh := ArrayMesh.new()
		for m in by_mat:
			var st := SurfaceTool.new()
			for entry in by_mat[m]:
				st.append_from(entry[0], entry[1], entry[2])
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		for mi in parts:
			(parent as Node).remove_child(mi)
			mi.queue_free()
		var merged := MeshInstance3D.new()
		merged.mesh = mesh
		merged.visibility_range_end = view_range
		(parent as Node).add_child(merged)
		out.append(merged)
	return out


func _build_hair(style: StringName, hair: Material) -> void:
	match style:
		&"none":
			pass
		&"long":
			_part(head, sphere_mesh(head_r * 1.06), hair, Vector3(0, head_r * 1.15, head_r * 0.08), Vector3.ZERO, Vector3(1, 0.9, 1))
			_part(head, box_mesh(Vector3(head_r * 1.6, head_r * 1.8, head_r * 0.4)), hair, Vector3(0, head_r * 0.5, head_r * 0.72))
		&"tide":
			# Vapouriun: heavy swept strands that trail behind like a current.
			_part(head, sphere_mesh(head_r * 1.05), hair, Vector3(0, head_r * 1.2, head_r * 0.12), Vector3.ZERO, Vector3(0.95, 0.85, 1.1))
			for i in 3:
				_part(head, capsule_mesh(head_r * 0.22, head_r * 2.2), hair, Vector3(head_r * (-0.4 + 0.4 * i), head_r * 0.5, head_r * 1.0), Vector3(0.5, 0, 0))
		&"topknot":
			_part(head, sphere_mesh(head_r * 1.04), hair, Vector3(0, head_r * 1.2, head_r * 0.1), Vector3.ZERO, Vector3(1, 0.75, 1))
			_part(head, sphere_mesh(head_r * 0.35), hair, Vector3(0, head_r * 2.05, head_r * 0.2))
		&"mane":
			_part(head, sphere_mesh(head_r * 1.1), hair, Vector3(0, head_r * 1.15, head_r * 0.15), Vector3.ZERO, Vector3(1.05, 0.95, 1.1))
			_part(head, box_mesh(Vector3(head_r * 1.2, head_r * 1.4, head_r * 0.5)), hair, Vector3(0, head_r * 0.6, head_r * 0.85))
		_:
			_part(head, sphere_mesh(head_r * 1.04), hair, Vector3(0, head_r * 1.22, head_r * 0.1), Vector3.ZERO, Vector3(1, 0.7, 1))


func _build_tail(s: float, fur: Material) -> void:
	var seg_len := height * 0.14
	var parent: Node3D = _pivot(hips, Vector3(0, -height * 0.02, s * 0.3), "Tail")
	parent.rotation.x = 0.55
	for i in 5:
		var r := height * 0.03 * (1.0 - i * 0.12)
		_part(parent, capsule_mesh(r, seg_len * 1.15), fur, Vector3(0, 0, seg_len * 0.5), Vector3(PI * 0.5, 0, 0))
		tail_segments.append(parent)
		var next := _pivot(parent, Vector3(0, 0, seg_len), "TailSeg%d" % i)
		next.rotation.x = 0.12
		parent = next
	_part(parent, sphere_mesh(height * 0.022), mat(_tone(Color(params.fur).lightened(0.35), 0.1)), Vector3.ZERO)


func _build_weapon(kind: StringName, pivot: Node3D) -> void:
	if pivot == null:
		return
	var steel := mat(Color(0.82, 0.84, 0.88), 0.25, 0.0, 1.0, "metal", 4.0)
	var wood := mat(Color(0.8, 0.65, 0.5), 0.8, 0.0, 1.0, "bark", 3.0)
	var grip := mat(Color(0.35, 0.25, 0.18), 0.7, 0.0, 1.0, "leather", 6.0)
	var gold := mat(params.accent, 0.4)
	var k := height / 1.78
	var parts: Array[MeshInstance3D] = []
	_weapon_len = {&"sword": 0.97, &"spear": 1.95, &"axe": 0.85, &"great_axe": 1.4 * k, &"dagger": 0.36,
		&"hookblade": 0.8 * k, &"cleaver": 1.2 * k, &"staff": 1.1, &"bow": 0.4}.get(kind, 0.2)
	match kind:
		&"bow":
			var limb_mat := mat(Color(0.45, 0.3, 0.18), 0.7, 0.0, 1.0, "bark", 4.0)
			for seg in [-1.0, 0.0, 1.0]:
				parts.append(_part(pivot, box_mesh(Vector3(0.04, 0.42, 0.04)), limb_mat, Vector3(0, seg * 0.38, -0.12 - (0.0 if seg == 0.0 else -0.08)), Vector3(seg * -0.45, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.006, 1.1, 0.006)), mat(Color(0.9, 0.88, 0.8)), Vector3(0, 0, 0.0)))
		&"sword":
			parts.append(_part(pivot, cylinder_mesh(0.02, 0.02, 0.2), grip, Vector3(0, 0, 0.04), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.22, 0.03, 0.04)), gold, Vector3(0, 0, -0.07)))
			parts.append(_part(pivot, box_mesh(Vector3(0.055, 0.014, 0.9)), steel, Vector3(0, 0, -0.52)))
		&"spear":
			parts.append(_part(pivot, cylinder_mesh(0.018, 0.018, 2.2), wood, Vector3(0, 0, -0.55), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, cylinder_mesh(0.0, 0.045, 0.32, 4), steel, Vector3(0, 0, -1.8), Vector3(-PI * 0.5, 0, 0)))
		&"axe":
			parts.append(_part(pivot, cylinder_mesh(0.022, 0.022, 0.9), wood, Vector3(0, 0, -0.32), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.03, 0.26, 0.22)), steel, Vector3(0, 0.1, -0.7)))
		&"great_axe":
			parts.append(_part(pivot, cylinder_mesh(0.035 * k, 0.035 * k, 1.5 * k), wood, Vector3(0, 0, -0.5 * k), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.05, 0.55, 0.42) * k), steel, Vector3(0, 0.2 * k, -1.1 * k)))
			parts.append(_part(pivot, box_mesh(Vector3(0.05, 0.35, 0.2) * k), steel, Vector3(0, -0.15 * k, -1.1 * k)))
		&"dagger":
			parts.append(_part(pivot, cylinder_mesh(0.018, 0.018, 0.12), grip, Vector3(0, 0, 0.02), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.05, 0.012, 0.32)), mat(Color(0.7, 0.9, 0.95), 0.2, 0.3), Vector3(0, 0, -0.2)))
		&"hookblade":
			parts.append(_part(pivot, cylinder_mesh(0.02 * k, 0.02 * k, 0.24 * k), grip, Vector3(0, 0, 0.05 * k), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.07, 0.014, 0.72) * k), mat(Color(0.5, 0.48, 0.45), 0.5), Vector3(0, 0, -0.42 * k)))
			parts.append(_part(pivot, box_mesh(Vector3(0.16, 0.014, 0.06) * k), mat(Color(0.5, 0.48, 0.45), 0.5), Vector3(0.06 * k, 0, -0.76 * k), Vector3(0, 0.6, 0)))
		&"cleaver":
			parts.append(_part(pivot, cylinder_mesh(0.03 * k, 0.03 * k, 0.4 * k), grip, Vector3(0, 0, 0.08 * k), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, box_mesh(Vector3(0.24, 0.025, 1.1) * k), mat(Color(0.42, 0.38, 0.34), 0.5), Vector3(0.04 * k, 0, -0.65 * k)))
			parts.append(_part(pivot, box_mesh(Vector3(0.1, 0.03, 0.3) * k), mat(params.accent, 0.5), Vector3(0.13 * k, 0, -1.05 * k)))
		&"staff":
			parts.append(_part(pivot, cylinder_mesh(0.022, 0.026, 1.5), wood, Vector3(0, 0, -0.3), Vector3(PI * 0.5, 0, 0)))
			parts.append(_part(pivot, sphere_mesh(0.07), mat(params.accent, 0.2, 2.0), Vector3(0, 0, -1.08)))
		&"fists":
			parts.append(_part(pivot, sphere_mesh(params.limb * 1.6), mat(Color(0.5, 0.4, 0.3)), Vector3.ZERO))
		_:
			pass
	_weapon_meshes.append_array(parts)


func _build_shield() -> void:
	var holder := _pivot(offhand_pivot, Vector3(-0.06, 0.02, 0), "Shield")
	holder.rotation = Vector3(0.9, 0, 0)
	var k := height / 1.78
	var board := mat(Color(0.75, 0.62, 0.5), 0.8, 0.0, 1.0, "planks", 2.0)
	var rim := mat(Color(0.55, 0.52, 0.5), 0.35, 0.0, 1.0, "metal", 3.0)
	_part(holder, box_mesh(Vector3(0.06, 0.82, 0.6) * k), board, Vector3(-0.04, 0.05, -0.12) * k)
	_part(holder, box_mesh(Vector3(0.07, 0.86, 0.06) * k), rim, Vector3(-0.04, 0.05, -0.42) * k)
	_part(holder, box_mesh(Vector3(0.07, 0.86, 0.06) * k), rim, Vector3(-0.04, 0.05, 0.18) * k)
	_part(holder, sphere_mesh(0.07 * k), rim, Vector3(-0.09, 0.05, -0.12) * k)


func set_trail(on: bool, color: Color = Color(1.0, 0.95, 0.85)) -> void:
	if trail:
		trail.emitting = on
		trail.color = color


func get_weapon_base() -> Vector3:
	return weapon_pivot.global_transform * Vector3(0, 0, -0.12) if weapon_pivot else global_position


func set_weapon(kind: StringName) -> void:
	for m in _weapon_meshes:
		if is_instance_valid(m):
			_meshes.erase(m)
			m.get_parent().remove_child(m)
			m.queue_free()
	_weapon_meshes.clear()
	params.weapon = kind
	_build_weapon(kind, weapon_pivot)
	if params.dual_wield:
		_build_weapon(kind, offhand_pivot)
	_merge_parts()


# -------------------------------------------------------------- Animation

## Call every frame with the current horizontal speed.
func animate(delta: float, speed: float, run_speed: float, on_floor: bool) -> void:
	_time += delta
	var f := clampf(speed / maxf(run_speed, 0.1), 0.0, 1.5)
	var cadence := sqrt(1.78 / height)
	_walk_phase += delta * (3.0 + 7.0 * f) * cadence * (1.0 if f > 0.05 else 0.0)
	var amp := 0.6 * minf(f, 1.2)
	var sw := sin(_walk_phase)
	var base := {
		"leg_l": Vector3(sw * amp, 0, 0),
		"leg_r": Vector3(-sw * amp, 0, 0),
		"arm_l": Vector3(-sw * amp * 0.6, 0, -0.08),
		"arm_r": Vector3(sw * amp * 0.6, 0, 0.08),
		"forearm_l": Vector3(0.25 + f * 0.3, 0, 0),
		"forearm_r": Vector3(0.25 + f * 0.3, 0, 0),
		"spine": Vector3(f * 0.12, 0, 0),
		"weapon": _base_weapon_rot,
	}
	if not on_floor:
		base.leg_l = Vector3(0.6, 0, 0)
		base.leg_r = Vector3(-0.2, 0, 0)
		base.arm_l = Vector3(0.3, 0, -0.4)
	else:
		# Idle breathing
		base["spine"] = Vector3(f * 0.12 + sin(_time * 1.8) * 0.015, 0, 0)
	hips.position.y = leg_len + absf(sw) * 0.035 * f * height / 1.78
	if f > 0.15 and on_floor:
		var sign_now := signf(sw)
		if sign_now != _last_step_sign and sign_now != 0.0:
			_last_step_sign = sign_now
			footstep.emit()

	_pose_weight = move_toward(_pose_weight, 1.0 if _pose_active else 0.0, delta * 14.0)
	var joints := {
		"leg_l": leg_l, "leg_r": leg_r, "arm_l": arm_l, "arm_r": arm_r,
		"forearm_l": forearm_l, "forearm_r": forearm_r, "spine": spine, "weapon": weapon_pivot,
	}
	for key in joints:
		var node: Node3D = joints[key]
		var rot: Vector3 = base[key]
		if _pose_weight > 0.0 and _pose_target.has(key):
			rot = rot.lerp(_pose_target[key], _pose_weight)
		node.rotation = rot
	if _pose_weight > 0.0 and _pose_target.has("head"):
		head.rotation = Vector3.ZERO.lerp(_pose_target.head, _pose_weight)
	else:
		head.rotation = Vector3.ZERO

	for i in tail_segments.size():
		var seg := tail_segments[i]
		seg.rotation.y = sin(_walk_phase * 0.5 + _time * 1.5 + i * 0.7) * (0.12 + 0.12 * f)
		if i == 0:
			seg.rotation.x = lerpf(0.75, 0.25, minf(f, 1.0))

	if _flash_time > 0.0:
		_flash_time -= delta
		_flash_mat.albedo_color.a = clampf(_flash_time * 4.0, 0.0, 0.7)
		if _flash_time <= 0.0:
			_set_overlay(_meshes, null)
	if _telegraph_on:
		_telegraph_mat.albedo_color.a = 0.35 + 0.35 * sin(_time * 22.0)
	if trail and trail.is_active():
		trail.sample(get_weapon_base(), get_weapon_tip(), delta)


func set_pose(target: Dictionary) -> void:
	_pose_target = target
	_pose_active = true


func clear_pose() -> void:
	_pose_active = false


func has_pose() -> bool:
	return _pose_active


## Procedural attack animation. stage: 0 windup, 1 active, 2 recovery; t in 0..1.
func pose_attack(kind: StringName, stage: int, t: float) -> void:
	var e := ease(t, 0.4) if stage == 1 else ease(t, -1.6)
	var rest := {"arm_r": Vector3(0.4, 0, 0.1), "arm_l": Vector3(0.2, 0, -0.1), "spine": Vector3.ZERO, "weapon": _base_weapon_rot, "forearm_r": Vector3(0.3, 0, 0), "forearm_l": Vector3(0.3, 0, 0)}
	var a: Dictionary
	var b: Dictionary
	match kind:
		&"thrust", &"charge":
			a = {"arm_r": Vector3(-0.3, 0, 0.25), "forearm_r": Vector3(1.4, 0, 0), "spine": Vector3(0.0, -0.45, 0), "weapon": Vector3(-1.2, 0, 0), "arm_l": Vector3(0.9, 0, -0.3)}
			b = {"arm_r": Vector3(1.55, 0, 0.0), "forearm_r": Vector3(0.05, 0, 0), "spine": Vector3(0.25 if kind == &"charge" else 0.1, 0.25, 0), "weapon": Vector3(-1.5, 0, 0), "arm_l": Vector3(-0.4, 0, -0.3)}
		&"slam":
			a = {"arm_r": Vector3(3.0, 0, 0.15), "arm_l": Vector3(3.0, 0, -0.15), "forearm_r": Vector3(0.3, 0, 0), "forearm_l": Vector3(0.3, 0, 0), "spine": Vector3(-0.25, 0, 0), "weapon": Vector3(0.3, 0, 0)}
			b = {"arm_r": Vector3(0.8, 0, 0.1), "arm_l": Vector3(0.8, 0, -0.1), "forearm_r": Vector3(0.1, 0, 0), "forearm_l": Vector3(0.1, 0, 0), "spine": Vector3(0.45, 0, 0), "weapon": Vector3(-0.6, 0, 0)}
		&"sweep":
			a = {"arm_r": Vector3(1.45, 0, 1.3), "forearm_r": Vector3(0.2, 0, 0), "spine": Vector3(0, -0.9, 0), "weapon": Vector3(-1.5, 0, 0), "arm_l": Vector3(0.6, 0, -0.6)}
			b = {"arm_r": Vector3(1.45, 0, -0.7), "forearm_r": Vector3(0.1, 0, 0), "spine": Vector3(0, 0.9, 0), "weapon": Vector3(-1.5, 0, 0), "arm_l": Vector3(0.3, 0, -0.3)}
		&"spin":
			a = {"arm_r": Vector3(1.45, 0, 1.2), "spine": Vector3(0, -0.6, 0), "weapon": Vector3(-1.5, 0, 0), "arm_l": Vector3(1.2, 0, -1.2)}
			b = {"arm_r": Vector3(1.45, 0, 1.2), "spine": Vector3(0, -0.6 + TAU, 0), "weapon": Vector3(-1.5, 0, 0), "arm_l": Vector3(1.2, 0, -1.2)}
		&"roar":
			a = {"arm_r": Vector3(0.3, 0, 0.3), "arm_l": Vector3(0.3, 0, -0.3), "spine": Vector3(0.2, 0, 0)}
			b = {"arm_r": Vector3(0.6, 0, 1.3), "arm_l": Vector3(0.6, 0, -1.3), "spine": Vector3(-0.35, 0, 0), "head": Vector3(-0.45, 0, 0)}
		&"aim":
			a = {"arm_r": Vector3(1.2, 0, 0.1), "arm_l": Vector3(1.45, 0, -0.1), "forearm_r": Vector3(0.6, 0, 0), "spine": Vector3(0, -0.6, 0), "weapon": Vector3(-1.57, 0, 0)}
			b = {"arm_r": Vector3(1.45, 0, 0.1), "arm_l": Vector3(1.5, 0, -0.1), "forearm_r": Vector3(1.5, 0, 0), "spine": Vector3(0, -0.75, 0), "weapon": Vector3(-1.57, 0, 0)}
		&"cast":
			a = {"arm_r": Vector3(0.5, 0, 0.4), "arm_l": Vector3(0.5, 0, -0.4), "spine": Vector3(-0.1, 0, 0)}
			b = {"arm_r": Vector3(1.6, 0, 0.1), "arm_l": Vector3(1.6, 0, -0.1), "spine": Vector3(0.15, 0, 0)}
		_:
			# slash: diagonal cut from high right to low left
			a = {"arm_r": Vector3(2.7, 0, 0.55), "forearm_r": Vector3(0.6, 0, 0), "spine": Vector3(-0.05, -0.55, 0), "weapon": Vector3(0.9, 0, 0), "arm_l": Vector3(0.6, 0, -0.3)}
			b = {"arm_r": Vector3(0.9, 0, -0.55), "forearm_r": Vector3(0.1, 0, 0), "spine": Vector3(0.12, 0.55, 0), "weapon": Vector3(-0.8, 0, 0), "arm_l": Vector3(0.2, 0, -0.4)}
	var target := {}
	match stage:
		0:
			target = _blend_pose(rest, a, e)
		1:
			target = _blend_pose(a, b, e)
		_:
			target = _blend_pose(b, rest, e)
	set_pose(target)


func pose_block() -> void:
	set_pose({"arm_r": Vector3(1.3, 0, -0.45), "forearm_r": Vector3(0.9, 0, 0), "weapon": Vector3(-0.2, 0, -1.2), "arm_l": Vector3(1.2, 0, 0.35), "forearm_l": Vector3(1.0, 0, 0), "spine": Vector3(0.05, 0.15, 0)})


func pose_stagger(t: float) -> void:
	var k := sin(clampf(t, 0.0, 1.0) * PI)
	set_pose({"spine": Vector3(-0.45 * k, 0.1, 0), "arm_r": Vector3(-0.3, 0, 0.7 * k), "arm_l": Vector3(-0.3, 0, -0.7 * k), "head": Vector3(-0.3 * k, 0, 0)})


func pose_dodge() -> void:
	set_pose({"spine": Vector3(0.6, 0, 0), "arm_r": Vector3(-0.7, 0, 0.3), "arm_l": Vector3(-0.7, 0, -0.3), "leg_l": Vector3(0.9, 0, 0), "leg_r": Vector3(-0.5, 0, 0)})


func pose_capture() -> void:
	set_pose({"arm_r": Vector3(1.9, 0, 0.15), "forearm_r": Vector3(0.1, 0, 0), "arm_l": Vector3(0.3, 0, -0.2), "spine": Vector3(-0.1, 0, 0), "weapon": _base_weapon_rot})


func _blend_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = a[k]
	for k in b:
		var from: Vector3 = a.get(k, Vector3.ZERO) if k != "weapon" else a.get(k, _base_weapon_rot)
		out[k] = from.lerp(b[k], t)
	return out


func play_death() -> void:
	clear_pose()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "rotation:x", PI * 0.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:y", height * 0.08, 0.55)


func reset_death() -> void:
	rotation = Vector3.ZERO
	position = Vector3.ZERO


func flash(color: Color, duration: float = 0.12) -> void:
	if _flash_mat == null:
		return
	_flash_mat.albedo_color = Color(color, 0.7)
	_flash_time = duration
	_set_overlay(_meshes, _flash_mat)


func set_telegraph(on: bool, color: Color = Color(1, 0.2, 0.1)) -> void:
	if _telegraph_mat == null:
		return
	_telegraph_on = on
	_telegraph_mat.albedo_color = Color(color, 0.5 if on else 0.0)
	_set_overlay(_weapon_meshes, _telegraph_mat if on else null)


func _set_overlay(list: Array[MeshInstance3D], m: Material) -> void:
	for mi in list:
		if is_instance_valid(mi):
			mi.material_overlay = m
	if m == null and _telegraph_on:
		for mi in _weapon_meshes:
			if is_instance_valid(mi):
				mi.material_overlay = _telegraph_mat


func get_weapon_tip() -> Vector3:
	if weapon_pivot == null:
		return global_position + Vector3.UP
	return weapon_pivot.global_transform * Vector3(0, 0, -_weapon_len)


func get_hand_position() -> Vector3:
	return hand_r_anchor.global_position if hand_r_anchor else global_position + Vector3.UP


# ---------------------------------------------------------------- Presets

## Base look for each canon people. Variant shifts colours for variety.
static func preset(people: StringName, variant: int = 0) -> Dictionary:
	var v := float(variant % 4)
	match people:
		&"amir":
			return {
				"people": people, "height": 1.8, "shoulder": 0.42, "limb": 0.055,
				"skin": Color(0.72, 0.56, 0.44).darkened(v * 0.06), "fur": Color(0.48, 0.42, 0.36).darkened(v * 0.08),
				"cloth": Color(0.36, 0.3, 0.22), "armor": Color(0.34, 0.25, 0.17), "accent": Color(0.75, 0.62, 0.35),
				"hair": Color(0.32, 0.28, 0.24), "hair_style": &"mane", "tail": true, "arm_fur": true, "weapon": &"spear",
				"ears": &"wolf", "claws": true,
			}
		&"burrok":
			return {
				"people": people, "height": 2.75, "shoulder": 1.02, "limb": 0.135, "depth": 1.15, "head_scale": 0.92,
				"skin": Color(0.7, 0.52, 0.4).darkened(v * 0.05), "cloth": Color(0.3, 0.24, 0.18),
				"armor": Color(0.42, 0.4, 0.38), "accent": Color(0.65, 0.45, 0.25), "hair": Color(0.3, 0.2, 0.12),
				"hair_style": &"mane", "beard": variant % 2 == 0, "pauldrons": true, "weapon": &"great_axe",
				"ears": &"bear", "paws": true, "arm_fur": true, "fur": Color(0.5, 0.36, 0.22).darkened(v * 0.06),
			}
		&"vapouriun":
			return {
				"people": people, "height": 1.74, "shoulder": 0.42, "limb": 0.055,
				"skin": Color(0.3, 0.5, 0.66).darkened(v * 0.08), "skin_detail": "scales", "cloth": Color(0.2, 0.22, 0.26),
				"armor": Color(0.3, 0.24, 0.2), "accent": Color(0.55, 0.75, 0.85), "hair": Color(0.12, 0.2, 0.26),
				"hair_style": &"none", "ears": &"fin", "fin_crest": true, "weapon": &"dagger", "dual_wield": true,
			}
		&"gouran":
			return {
				"people": people, "height": 1.3, "shoulder": 0.56, "limb": 0.1, "head_scale": 1.45, "leg_mult": 0.82,
				"depth": 1.15, "skin": Color(0.66, 0.54, 0.46).darkened(v * 0.07), "cloth": Color(0.36, 0.26, 0.4),
				"armor": Color(0.42, 0.32, 0.25), "accent": Color(0.95, 0.55, 0.2), "hair": Color(0.55, 0.52, 0.48),
				"hair_style": &"topknot", "heavy_brow": true, "nose_scale": 1.7, "robe": true, "pouches": true,
				"beard": true, "beard_len": 2.2 + v * 0.2, "belly": 1.0, "hood": variant % 2 == 0, "eye_scale": 0.65,
				"weapon": &"staff",
			}
		&"gyria":
			return {
				"people": people, "height": 1.86, "shoulder": 0.36, "limb": 0.045, "arm_mult": 1.12, "leg_mult": 1.04,
				"depth": 0.85, "angular": true, "pointed_ears": true, "tusks": true,
				"skin": Color(0.36, 0.5, 0.28).darkened(v * 0.06), "cloth": Color(0.3, 0.26, 0.22),
				"armor": Color(0.36, 0.3, 0.25), "accent": Color(0.55, 0.22, 0.16), "hair": Color(0.1, 0.1, 0.1),
				"hair_style": &"topknot", "weapon": &"hookblade",
			}
		&"gyria_boss":
			return {
				"people": &"gyria", "height": 1.86 * 1.45, "shoulder": 0.7, "limb": 0.09, "arm_mult": 1.12,
				"depth": 1.0, "angular": true, "pointed_ears": true, "tusks": true, "pauldrons": true, "crest": true,
				"skin": Color(0.32, 0.45, 0.25), "cloth": Color(0.25, 0.18, 0.16), "armor": Color(0.3, 0.26, 0.24),
				"accent": Color(0.75, 0.25, 0.12), "hair": Color(0.08, 0.08, 0.08), "hair_style": &"mane",
				"weapon": &"cleaver",
			}
		_:
			return {
				"people": &"human", "height": 1.78, "shoulder": 0.46, "limb": 0.065,
				"skin": Color(0.78, 0.6, 0.47).darkened(v * 0.12), "cloth": Color(0.3, 0.33, 0.4),
				"armor": Color(0.36, 0.27, 0.19), "hair": Color(0.25, 0.17, 0.1), "weapon": &"sword",
			}

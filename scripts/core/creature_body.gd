class_name CreatureBody
extends Node3D
## PLACEHOLDER ART for creatures, generated from a CreatureDefinition's
## appearance fields. Supports "quadruped" and "hover" body shapes.
## Final creature models are pending the author's creature designs.

var definition: CreatureDefinition
var size: float = 1.0
var legs: Array[Node3D] = []
var head: Node3D
var torso: Node3D
var tail: Node3D
var shards: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _phase := 0.0
var _time := 0.0
var _attack_t := -1.0
var _flash_mat: StandardMaterial3D
var _flash_time := 0.0
var _telegraph_mat: StandardMaterial3D
var _telegraph_on := false
var _base_height := 0.0


func build(def: CreatureDefinition) -> void:
	definition = def
	size = def.size
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_meshes.clear()
	legs.clear()
	shards.clear()
	var body_mat := PlaceholderBody.mat(def.body_color, 0.85, 0.0, 1.0, "fur", 3.0)
	var accent := PlaceholderBody.mat(def.accent_color, 0.6, 0.0, 1.0, "leather", 3.0)
	var eye := PlaceholderBody.mat(def.eye_color, 0.2, 2.5)
	if def.body_shape == &"hover":
		_base_height = 1.1 * size
		torso = _pivot(self, Vector3(0, _base_height, 0))
		_part(torso, PlaceholderBody.sphere_mesh(0.38 * size), PlaceholderBody.mat(def.body_color, 0.3, 0.6), Vector3.ZERO)
		_part(torso, PlaceholderBody.sphere_mesh(0.22 * size), PlaceholderBody.mat(def.accent_color, 0.2, 1.5, 0.6), Vector3(0, 0, -0.2 * size))
		head = _pivot(torso, Vector3(0, 0.1 * size, -0.25 * size))
		for side in [-1.0, 1.0]:
			_part(head, PlaceholderBody.sphere_mesh(0.06 * size), eye, Vector3(side * 0.12 * size, 0.05 * size, -0.12 * size))
		for i in 4:
			var orbit := _pivot(torso, Vector3.ZERO)
			orbit.rotation.y = TAU * i / 4.0
			_part(orbit, PlaceholderBody.box_mesh(Vector3(0.1, 0.28, 0.1) * size), accent, Vector3(0.6 * size, 0, 0), Vector3(0, 0, 0.4))
			shards.append(orbit)
	else:
		_base_height = 0.62 * size
		torso = _pivot(self, Vector3(0, _base_height, 0))
		_part(torso, PlaceholderBody.sphere_mesh(0.42 * size), body_mat, Vector3.ZERO, Vector3.ZERO, Vector3(0.85, 0.75, 1.45))
		_part(torso, PlaceholderBody.box_mesh(Vector3(0.18, 0.12, 0.7) * size), accent, Vector3(0, 0.3 * size, 0.05 * size))
		head = _pivot(torso, Vector3(0, 0.22 * size, -0.62 * size))
		_part(head, PlaceholderBody.sphere_mesh(0.27 * size), body_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.9, 1.1))
		_part(head, PlaceholderBody.sphere_mesh(0.14 * size), accent, Vector3(0, -0.06 * size, -0.22 * size), Vector3.ZERO, Vector3(1, 0.8, 1.2))
		for side in [-1.0, 1.0]:
			_part(head, PlaceholderBody.sphere_mesh(0.055 * size), eye, Vector3(side * 0.12 * size, 0.07 * size, -0.22 * size))
			_part(head, PlaceholderBody.cylinder_mesh(0.0, 0.07 * size, 0.24 * size, 4), accent, Vector3(side * 0.14 * size, 0.24 * size, 0.02), Vector3(0, 0, side * -0.4))
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var leg := _pivot(torso, Vector3(corner.x * 0.24 * size, -0.1 * size, corner.y * 0.38 * size))
			_part(leg, PlaceholderBody.capsule_mesh(0.08 * size, 0.55 * size), body_mat, Vector3(0, -0.25 * size, 0))
			_part(leg, PlaceholderBody.sphere_mesh(0.09 * size), accent, Vector3(0, -0.5 * size, -0.02))
			legs.append(leg)
		tail = _pivot(torso, Vector3(0, 0.12 * size, 0.58 * size))
		tail.rotation.x = 0.6
		_part(tail, PlaceholderBody.capsule_mesh(0.06 * size, 0.6 * size), accent, Vector3(0, 0, 0.28 * size), Vector3(PI * 0.5, 0, 0))
	_meshes = PlaceholderBody.merge_by_parent(_meshes, 60.0)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat = _flash_mat.duplicate()


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.visibility_range_end = 60.0
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func animate(delta: float, speed: float, max_speed: float, dazed: bool) -> void:
	_time += delta
	var f := clampf(speed / maxf(max_speed, 0.1), 0.0, 1.5)
	_phase += delta * (2.0 + 9.0 * f)
	for i in legs.size():
		var offset := 0.0 if i == 0 or i == 3 else PI
		legs[i].rotation.x = sin(_phase + offset) * 0.6 * minf(f, 1.0)
	if tail:
		tail.rotation.y = sin(_time * 3.0 + _phase * 0.3) * 0.4
	for s in shards:
		s.rotation.y += delta * (1.5 + f * 3.0)
	var bob := sin(_time * 2.2) * (0.08 if definition and definition.body_shape == &"hover" else 0.02 * f)
	torso.position.y = _base_height + bob
	torso.rotation.z = sin(_time * 7.0) * 0.18 if dazed else 0.0
	if _attack_t >= 0.0:
		_attack_t += delta
		var k := sin(clampf(_attack_t / 0.35, 0.0, 1.0) * PI)
		head.position.z = (-0.62 * size if legs.size() > 0 else -0.25 * size) - k * 0.25 * size
		torso.rotation.x = k * 0.2
		if _attack_t > 0.35:
			_attack_t = -1.0
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash_mat.albedo_color.a = clampf(_flash_time * 4.0, 0.0, 0.7)
		if _flash_time <= 0.0:
			_overlay(null if not _telegraph_on else _telegraph_mat)
	if _telegraph_on:
		_telegraph_mat.albedo_color.a = 0.3 + 0.3 * sin(_time * 20.0)


func play_attack() -> void:
	_attack_t = 0.0


func flash(color: Color, duration: float = 0.12) -> void:
	_flash_mat.albedo_color = Color(color, 0.7)
	_flash_time = duration
	_overlay(_flash_mat)


func set_telegraph(on: bool, color: Color = Color(1, 0.2, 0.1)) -> void:
	_telegraph_on = on
	_telegraph_mat.albedo_color = Color(color, 0.4)
	_overlay(_telegraph_mat if on else null)


func _overlay(m: Material) -> void:
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_overlay = m


func get_center() -> Vector3:
	return torso.global_position if torso else global_position

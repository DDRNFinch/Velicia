class_name CombatUtil
extends RefCounted
## Shared hit detection and targeting helpers.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_CREATURE := 8
const LAYER_INTERACT := 16
const LAYER_NPC := 32

static var _sphere := SphereShape3D.new()


## Returns combatant nodes inside the attack's hit area that belong to a
## different team than the attacker.
static func query_targets(attacker: Node3D, atk: AttackDefinition, mask: int, team: StringName, reach_override: float = -1.0) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var space := attacker.get_world_3d().direct_space_state
	var reach := atk.reach if reach_override < 0.0 else reach_override
	var forward := -attacker.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var origin := attacker.global_position + Vector3.UP * 1.0
	_sphere.radius = reach + 0.6
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _sphere
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = mask
	params.exclude = [attacker.get_rid()]
	var results := space.intersect_shape(params, 24)
	for r in results:
		var body = r.get("collider")
		if not (body is Node3D) or body == attacker:
			continue
		if not body.has_method("receive_hit"):
			continue
		if body.get("team") == team:
			continue
		if not is_in_hit_area(attacker, body, atk, reach, forward):
			continue
		if not (body in out):
			out.append(body)
	return out


static func is_in_hit_area(attacker: Node3D, target: Node3D, atk: AttackDefinition, reach: float, forward: Vector3) -> bool:
	var to := target.global_position - attacker.global_position
	var vertical := absf(to.y)
	to.y = 0.0
	var radius := body_radius(target)
	var dist := to.length() - radius
	if dist > reach or vertical > 2.5 + radius:
		return false
	if to.length() < 0.6:
		return true
	match atk.hit_shape:
		AttackDefinition.HitShape.CIRCLE:
			return true
		AttackDefinition.HitShape.THRUST:
			var along := to.dot(forward)
			var side := absf(to.dot(forward.cross(Vector3.UP)))
			return along > 0.0 and side < 0.8 + radius
		_:
			var angle := rad_to_deg(forward.angle_to(to.normalized()))
			return angle <= atk.arc_degrees * 0.5 + 10.0


static func body_radius(n: Node) -> float:
	var r = n.get("body_radius")
	return float(r) if r != null else 0.4


## Finds the best target for soft-targeting: close, alive and in front of
## the given direction.
static func best_target(from: Node3D, direction: Vector3, candidates: Array, max_distance: float, max_angle_deg: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var dir := direction
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -from.global_transform.basis.z
	dir = dir.normalized()
	for c in candidates:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		if c.has_method("is_targetable") and not c.is_targetable():
			continue
		var to: Vector3 = c.global_position - from.global_position
		to.y = 0.0
		var d := to.length()
		if d > max_distance:
			continue
		var angle := rad_to_deg(dir.angle_to(to.normalized())) if d > 0.1 else 0.0
		if angle > max_angle_deg:
			continue
		var score := d + angle * 0.06
		if score < best_score:
			best_score = score
			best = c
	return best


static func flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


## Smoothly rotates a node's yaw to face a flat direction.
static func turn_toward(node: Node3D, direction: Vector3, speed: float, delta: float) -> void:
	if direction.length() < 0.01:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	node.rotation.y = lerp_angle(node.rotation.y, target_yaw, clampf(speed * delta, 0.0, 1.0))


static func face_instantly(node: Node3D, direction: Vector3) -> void:
	if direction.length() < 0.01:
		return
	node.rotation.y = atan2(-direction.x, -direction.z)

class_name Projectile
extends Node3D
## A flying arrow or bolt. Sweeps a ray each physics frame so it never
## tunnels through targets. Can be dodged, blocked or parried; a parried
## arrow is deflected back at its shooter.

signal deflected

var source: Node3D
var attack: AttackDefinition
var damage: float = 10.0
var team: StringName = &"gyria"
var velocity: Vector3 = Vector3.ZERO
var max_distance: float = 22.0
var mask: int = CombatUtil.LAYER_WORLD | CombatUtil.LAYER_PLAYER | CombatUtil.LAYER_CREATURE

var _travelled := 0.0
var _stuck := false
var _mesh: MeshInstance3D
var _exclude: Array[RID] = []


func launch(from: Vector3, to: Vector3, speed: float) -> void:
	global_position = from
	velocity = (to - from).normalized() * speed
	look_at(from + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)


func _ready() -> void:
	add_to_group("projectiles")
	_mesh = MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.015
	shaft.bottom_radius = 0.015
	shaft.height = 0.75
	shaft.radial_segments = 4
	_mesh.mesh = shaft
	_mesh.rotation.x = PI * 0.5
	_mesh.material_override = PlaceholderBody.mat(Color(0.55, 0.42, 0.28), 0.8)
	add_child(_mesh)
	var tip := MeshInstance3D.new()
	tip.mesh = PlaceholderBody.cylinder_mesh(0.0, 0.035, 0.12, 4)
	tip.rotation.x = -PI * 0.5
	tip.position.z = -0.42
	tip.material_override = PlaceholderBody.mat(Color(0.7, 0.7, 0.72), 0.3, 0.0, 1.0, "metal", 4.0)
	add_child(tip)
	var glow := MeshInstance3D.new()
	glow.mesh = PlaceholderBody.sphere_mesh(0.05)
	glow.position.z = 0.36
	glow.material_override = PlaceholderBody.mat(Settings.telegraph_color(), 0.2, 2.0)
	add_child(glow)
	if source and is_instance_valid(source):
		_exclude.append((source as CollisionObject3D).get_rid())


func _physics_process(delta: float) -> void:
	if _stuck:
		return
	var step := velocity * delta
	var from := global_position
	var to := from + step
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, _exclude)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		_travelled += step.length()
		if _travelled > max_distance:
			queue_free()
		return
	var body = hit.collider
	global_position = hit.position
	if body is Node and body.has_method("receive_hit") and body.get("team") != team:
		var h := HitData.new()
		h.source = source if is_instance_valid(source) else self
		h.damage = damage
		h.poise_damage = attack.poise_damage if attack else 12.0
		h.knockback = attack.knockback if attack else 1.5
		h.parryable = attack.parryable if attack else true
		h.direction = Vector3(velocity.x, 0, velocity.z).normalized()
		var result: int = body.receive_hit(h)
		if result == HitData.Result.PARRIED and is_instance_valid(source):
			_deflect(body)
			return
		if result == HitData.Result.EVADED:
			_exclude.append((body as CollisionObject3D).get_rid())
			return
		queue_free()
		return
	# Hit the world: stick in for a moment.
	_stuck = true
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(queue_free)


## Sends the arrow back at whoever shot it.
func _deflect(by: Node) -> void:
	var target := source
	_exclude = [(by as CollisionObject3D).get_rid()]
	team = by.get("team")
	mask = CombatUtil.LAYER_WORLD | CombatUtil.LAYER_ENEMY
	source = by as Node3D
	damage *= 1.5
	_travelled = 0.0
	var speed := velocity.length() * 1.3
	launch(global_position, target.global_position + Vector3.UP * 1.2, speed)
	deflected.emit()
	Fx.floating_text(global_position, "Deflected!", Color(1.0, 0.85, 0.3))

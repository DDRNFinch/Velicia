class_name HeartPickup
extends Area3D
## A recovery heart dropped by bushes and enemies. Restores one heart.

const HEAL := 20.0

var _t := 0.0
var _mesh: MeshInstance3D


static func spawn(parent: Node, at: Vector3) -> HeartPickup:
	var h := HeartPickup.new()
	parent.add_child(h)
	h.global_position = at
	return h


func _ready() -> void:
	add_to_group("heart_pickups")
	collision_layer = 0
	collision_mask = CombatUtil.LAYER_PLAYER
	monitoring = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	cs.shape = sphere
	add_child(cs)
	_mesh = MeshInstance3D.new()
	var b := LowPoly.Builder.new()
	var red := Color(0.95, 0.2, 0.25)
	b.add_mesh(LowPoly.ico(0.16), Transform3D(Basis(), Vector3(-0.11, 0.05, 0)), red)
	b.add_mesh(LowPoly.ico(0.16), Transform3D(Basis(), Vector3(0.11, 0.05, 0)), red)
	b.add_mesh(LowPoly.cone(0.0, 0.2, 0.28, 4), Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.12, 0)), red.darkened(0.1))
	_mesh.mesh = b.commit(LowPoly.vcol_mat(0.3, 0.6))
	add_child(_mesh)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y = _t * 2.5
	_mesh.position.y = 0.25 + sin(_t * 4.0) * 0.08
	if _t > 20.0:
		queue_free()


func _on_body(b: Node) -> void:
	if b is Player and _t > 0.2:
		var p := b as Player
		p.stats.heal(HEAL)
		AudioManager.play_sfx("pickup", global_position)
		Fx.floating_text(global_position + Vector3.UP * 0.6, "+1 heart", Color(1, 0.5, 0.55))
		queue_free()

class_name CuttableBush
extends StaticBody3D
## A bush you can slash, Zelda-style: it bursts into leaves, sometimes drops a
## heart, and grows back after a while. It blocks the way until it is cut.

const REGROW_TIME := 90.0

var team: StringName = &"neutral"
var body_radius := 0.5
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _cut := false
var _variant := 0


func _init(variant: int = 0) -> void:
	_variant = variant


func _ready() -> void:
	add_to_group("cuttables")
	collision_layer = CombatUtil.LAYER_WORLD | CombatUtil.LAYER_ENEMY
	collision_mask = 0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = LowPoly.bush(_variant)
	_mesh.visibility_range_end = 55.0
	add_child(_mesh)
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 1.0
	_shape.shape = cyl
	_shape.position.y = 0.5
	add_child(_shape)


func is_cut() -> bool:
	return _cut


func receive_hit(hit: HitData) -> int:
	if _cut:
		return -1
	_cut = true
	_mesh.visible = false
	_shape.set_deferred("disabled", true)
	var p := global_position + Vector3.UP * 0.5
	Fx.spark_burst(p, LowPoly.c("leaf_light"), 1.4)
	Fx.dust(global_position, 0.8)
	AudioManager.play_sfx("dodge", p)
	var r := randf()
	if r < 0.22 or (hit != null and hit.attacker is Player and (hit.attacker as Player).stats.health_fraction() < 0.5 and r < 0.45):
		HeartPickup.spawn(get_parent(), global_position + Vector3.UP * 0.4)
	get_tree().create_timer(REGROW_TIME).timeout.connect(_regrow)
	return -1


func _regrow() -> void:
	if not is_inside_tree():
		return
	_cut = false
	_mesh.visible = true
	_shape.set_deferred("disabled", false)

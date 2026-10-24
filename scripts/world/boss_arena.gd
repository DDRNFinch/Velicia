class_name BossArena
extends Area3D
## Wakes the boss when the player enters the arena.

@export var boss_path: NodePath
@export var radius: float = 16.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatUtil.LAYER_PLAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 20.0
	shape.shape = cyl
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(b: Node) -> void:
	if not (b is Player):
		return
	var boss := get_node_or_null(boss_path)
	if boss and boss.has_method("engage"):
		boss.engage()

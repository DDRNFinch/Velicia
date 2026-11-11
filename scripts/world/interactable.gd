class_name Interactable
extends Area3D
## Base class for anything the player can use: talk, open, read, rest.
## Detects the player and registers with them; the player picks the nearest.

signal used(by: Player)

@export var prompt: String = "Interact"
@export var radius: float = 2.2

var enabled: bool = true


func _ready() -> void:
	collision_layer = CombatUtil.LAYER_INTERACT
	collision_mask = CombatUtil.LAYER_PLAYER
	monitorable = false
	if get_child_count() == 0 or not _has_shape():
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
		shape.position.y = 1.0
		add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return true
	return false


func _on_body_entered(b: Node) -> void:
	if b is Player:
		(b as Player).register_interactable(self)


func _on_body_exited(b: Node) -> void:
	if b is Player:
		(b as Player).unregister_interactable(self)


func can_interact() -> bool:
	return enabled


func get_prompt() -> String:
	return prompt


func interact(by: Player) -> void:
	used.emit(by)

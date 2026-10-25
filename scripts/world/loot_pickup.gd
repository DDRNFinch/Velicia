class_name LootPickup
extends Area3D
## A glowing item in the world, collected by walking into it.
## Set collect_id to make the pickup persistent (collected once per save).

@export var item_id: String = ""
@export var count: int = 1
@export var collect_id: String = ""

var _mesh: MeshInstance3D
var _time := 0.0
var _collected := false
var _color := Color.WHITE


func _ready() -> void:
	if not collect_id.is_empty() and GameState.is_world_marked("collected", collect_id):
		queue_free()
		return
	collision_layer = 0
	collision_mask = CombatUtil.LAYER_PLAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	shape.position.y = 0.5
	add_child(shape)
	var def := Database.item(item_id)
	var col := def.icon_color if def else Color.WHITE
	_color = col
	_mesh = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = 0.16
	gem.height = 0.4
	gem.radial_segments = 6
	gem.rings = 3
	_mesh.mesh = gem
	_mesh.material_override = PlaceholderBody.mat(col, 0.2, 1.8)
	_mesh.position.y = 0.6
	_mesh.visibility_range_end = 60.0
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if _mesh:
		_mesh.position.y = 0.6 + sin(_time * 3.0) * 0.12
		_mesh.rotation.y += delta * 2.0


func _on_body_entered(b: Node) -> void:
	if _collected or not (b is Player):
		return
	_collected = true
	GameState.add_item(item_id, count)
	if not collect_id.is_empty():
		GameState.mark_world("collected", collect_id)
	AudioManager.play_sfx("pickup", global_position)
	Fx.ring_burst(global_position + Vector3.UP * 0.5, _color, 0.8, 0.3)
	queue_free()

class_name TreasureChest
extends Node3D
## A chest whose contents are granted once per save.

@export var chest_id: String = ""
## item_id -> count
@export var loot: Dictionary = {}
@export var hidden_cache: bool = false

var _lid: Node3D
var _interact: Interactable


func _ready() -> void:
	var wood := PlaceholderBody.mat(Color(0.45, 0.3, 0.16) if not hidden_cache else Color(0.35, 0.36, 0.4))
	var trim := PlaceholderBody.mat(Color(0.85, 0.7, 0.3), 0.4)
	var base := MeshInstance3D.new()
	base.mesh = PlaceholderBody.box_mesh(Vector3(0.9, 0.5, 0.6))
	base.material_override = wood
	base.position.y = 0.25
	add_child(base)
	var band := MeshInstance3D.new()
	band.mesh = PlaceholderBody.box_mesh(Vector3(0.94, 0.08, 0.64))
	band.material_override = trim
	band.position.y = 0.45
	add_child(band)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.5, 0.3)
	add_child(_lid)
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.mesh = PlaceholderBody.box_mesh(Vector3(0.9, 0.2, 0.6))
	lid_mesh.material_override = wood
	lid_mesh.position = Vector3(0, 0.1, -0.3)
	_lid.add_child(lid_mesh)
	var solid := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.7, 0.6)
	shape.shape = box
	shape.position.y = 0.35
	solid.add_child(shape)
	add_child(solid)
	_interact = Interactable.new()
	_interact.prompt = "Open chest"
	_interact.radius = 1.8
	add_child(_interact)
	_interact.used.connect(_open)
	if GameState.is_world_marked("opened", chest_id):
		_lid.rotation.x = -1.9
		_interact.enabled = false


func _open(_by: Player) -> void:
	if GameState.is_world_marked("opened", chest_id):
		return
	GameState.mark_world("opened", chest_id)
	_interact.enabled = false
	create_tween().tween_property(_lid, "rotation:x", -1.9, 0.4).set_trans(Tween.TRANS_BACK)
	AudioManager.play_sfx("pickup", global_position)
	Fx.ring_burst(global_position + Vector3.UP * 0.6, Color(1, 0.85, 0.4), 1.2)
	for item_id in loot:
		GameState.add_item(String(item_id), int(loot[item_id]))

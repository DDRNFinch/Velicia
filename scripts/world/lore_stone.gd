class_name LoreStone
extends Node3D
## An inscribed stone, banner or relic that adds a lore entry to the journal.

@export var lore_id: String = ""
@export var prompt: String = "Read inscription"
@export var style: String = "stone" # stone, banner, relic

var _interact: Interactable


func _ready() -> void:
	match style:
		"banner":
			var pole := MeshInstance3D.new()
			pole.mesh = PlaceholderBody.cylinder_mesh(0.05, 0.06, 3.0, 6)
			pole.material_override = VeliciaMaterials.surface("bark", Color.WHITE, 2.0, 0.95, false)
			pole.position.y = 1.5
			add_child(pole)
			var cloth := MeshInstance3D.new()
			cloth.mesh = PlaceholderBody.box_mesh(Vector3(0.8, 1.2, 0.03))
			cloth.material_override = VeliciaMaterials.surface("fabric", Color(0.6, 0.22, 0.17), 2.0, 0.95, false)
			cloth.position = Vector3(0.42, 2.3, 0)
			add_child(cloth)
		"relic":
			var r := MeshInstance3D.new()
			r.mesh = PlaceholderBody.box_mesh(Vector3(0.4, 0.4, 0.4))
			r.material_override = PlaceholderBody.mat(Color(0.6, 0.5, 0.9), 0.2, 1.5)
			r.position.y = 0.9
			r.rotation = Vector3(0.6, 0.6, 0)
			add_child(r)
		_:
			var s := MeshInstance3D.new()
			s.mesh = PlaceholderBody.box_mesh(Vector3(0.9, 1.7, 0.35))
			s.material_override = VeliciaMaterials.surface("rock", Color.WHITE, 1.2, 0.95, false)
			s.position.y = 0.85
			s.rotation.z = 0.05
			add_child(s)
			var rune := MeshInstance3D.new()
			rune.mesh = PlaceholderBody.box_mesh(Vector3(0.5, 0.9, 0.02))
			rune.material_override = PlaceholderBody.mat(Color(0.95, 0.75, 0.35), 0.3, 1.4)
			rune.position = Vector3(0, 0.95, -0.18)
			rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rune)
	_interact = Interactable.new()
	_interact.prompt = prompt
	_interact.radius = 2.0
	add_child(_interact)
	_interact.used.connect(_read)


func _read(_by: Player) -> void:
	GameState.unlock_lore(lore_id)
	EventBus.request_panel.emit("lore", {"id": lore_id})

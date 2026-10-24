class_name LocationTrigger
extends Area3D
## A named place. Entering it discovers it (journal, map, XP) and reports the
## visit for quests. It also flattens terrain and tells the region builder
## which structure to raise here.

@export var location_id: String = ""
@export var display_name: String = ""
@export var radius: float = 18.0
## Terrain flattening; set flatten_radius to 0 to keep natural ground.
@export var flatten_radius: float = 0.0
@export var flatten_height: float = 3.0
@export var flatten_falloff: float = 14.0
## Structure kit the region builder places here (see region_builder.gd).
@export var structure: String = ""
## Map icon: settlement, ruin, camp, fort, cave, lake, wild
@export var map_icon: String = "wild"
@export var is_draft_name: bool = true


func _ready() -> void:
	add_to_group("locations")
	collision_layer = 0
	collision_mask = CombatUtil.LAYER_PLAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 40.0
	shape.shape = cyl
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(b: Node) -> void:
	if not (b is Player):
		return
	GameState.discover_location(location_id, display_name)
	EventBus.location_entered.emit(StringName(location_id))

class_name SaveShrine
extends Node3D
## A Ring Stone of the Emoria Guild: rest to heal, restore creatures, set your
## respawn point and save. Ring/vault management is only possible here.

@export var shrine_id: String = ""
@export var display_name: String = "Ring Stone"

var _ring: MeshInstance3D
var _time := 0.0
var _interact: Interactable


func _ready() -> void:
	add_to_group("shrines")
	var stone := PlaceholderBody.mat(Color(0.5, 0.52, 0.55), 0.9)
	var glow := PlaceholderBody.mat(Color(0.4, 0.9, 1.0), 0.2, 2.2)
	var base := MeshInstance3D.new()
	base.mesh = PlaceholderBody.cylinder_mesh(1.1, 1.3, 0.4, 8)
	base.material_override = stone
	base.position.y = 0.2
	add_child(base)
	var pillar := MeshInstance3D.new()
	pillar.mesh = PlaceholderBody.cylinder_mesh(0.28, 0.4, 2.4, 6)
	pillar.material_override = stone
	pillar.position.y = 1.6
	add_child(pillar)
	var rune := MeshInstance3D.new()
	rune.mesh = PlaceholderBody.box_mesh(Vector3(0.1, 1.2, 0.62))
	rune.material_override = glow
	rune.position = Vector3(0, 1.6, 0)
	add_child(rune)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.68
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = glow
	_ring.position.y = 3.2
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var solid := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 3.0
	shape.shape = cyl
	shape.position.y = 1.5
	solid.add_child(shape)
	add_child(solid)
	_interact = Interactable.new()
	_interact.prompt = "Rest at " + display_name
	_interact.radius = 2.8
	add_child(_interact)
	_interact.used.connect(func(by): EventBus.request_panel.emit("shrine", {"shrine": self, "player": by}))


func _process(delta: float) -> void:
	_time += delta
	_ring.rotation = Vector3(sin(_time * 0.7) * 0.4, _time * 0.8, 0)
	_ring.position.y = 3.2 + sin(_time * 1.3) * 0.12


func spawn_position() -> Vector3:
	return global_position + global_transform.basis.z * 2.2 + Vector3.UP * 0.3


## Heal, restore creatures, set respawn and save. Returns true if saved.
func rest(by: Player) -> bool:
	by.stats.setup(GameState.get_max_health(), GameState.get_max_stamina(), Player.MAX_POISE)
	GameState.restore_all_creatures()
	if by.rings.companion:
		by.rings.companion.stats.set_health(by.rings.companion.stats.max_health)
	GameState.respawn_point = shrine_id
	Fx.ring_burst(global_position + Vector3.UP * 0.4, Color(0.4, 0.9, 1.0), 3.5, 0.9)
	AudioManager.play_sfx("magic", global_position)
	var ok := SaveManager.save_game()
	EventBus.notify.emit("Rested. Health and creatures restored. " + ("Game saved." if ok else "Save failed: " + SaveManager.last_error))
	return ok

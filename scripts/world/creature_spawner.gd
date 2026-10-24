class_name CreatureSpawner
extends Node3D
## Keeps a population of wild creatures around this point and respawns them
## some time after they are captured or retreat.

@export var creature: CreatureDefinition
@export var count: int = 2
@export var min_level: int = 1
@export var max_level: int = 3
@export var spread: float = 6.0
@export var respawn_time: float = 50.0

var _alive: Array[CreatureActor] = []
var _pending := 0
var _timer := 0.0


func _ready() -> void:
	add_to_group("creature_spawners")
	_spawn_all.call_deferred()


func _spawn_all() -> void:
	for i in count:
		_spawn_one()


func _spawn_one() -> void:
	if creature == null:
		return
	var actor := CreatureActor.new()
	actor.definition = creature
	actor.level = randi_range(min_level, max_level)
	actor.spawner = self
	get_parent().add_child(actor)
	var ang := randf() * TAU
	var r := randf_range(0.5, spread)
	var x := global_position.x + cos(ang) * r
	var z := global_position.z + sin(ang) * r
	actor.global_position = Vector3(x, VeliciaTerrain.height_at(x, z) + 0.5, z)
	actor.home = actor.global_position
	_alive.append(actor)


func on_creature_removed(actor: CreatureActor) -> void:
	_alive.erase(actor)
	_pending += 1
	if _timer <= 0.0:
		_timer = respawn_time


func _process(delta: float) -> void:
	if _pending <= 0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var p := CombatDirector.player
	if p and is_instance_valid(p) and p.global_position.distance_to(global_position) < 35.0:
		_timer = 5.0 # don't pop creatures in front of the player
		return
	_pending -= 1
	_spawn_one()
	_timer = respawn_time if _pending > 0 else 0.0


func alive_count() -> int:
	return _alive.size()

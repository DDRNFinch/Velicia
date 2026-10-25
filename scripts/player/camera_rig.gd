class_name CameraRig
extends Node3D
## Fixed angled follow camera (Tunic / Death's Door style): the view never
## rotates, so "up" on the stick is always "up" on screen. It follows the
## player smoothly with a little look-ahead, pulls back in combat and shakes
## on heavy hits. A long lens keeps the world looking like a diorama.

@export var pitch_degrees: float = 52.0
@export var distance: float = 15.5
@export var fov: float = 30.0
@export var follow_speed: float = 6.0
@export var look_ahead: float = 1.6

var target: Node3D
var yaw_node: Node3D
var pitch_node: Node3D
var camera: Camera3D
var _shake := 0.0
var _shake_time := 0.0
var _ahead := Vector3.ZERO
var _zoom := 0.0


func _ready() -> void:
	top_level = true
	add_to_group("camera_rig")
	yaw_node = Node3D.new()
	add_child(yaw_node)
	pitch_node = Node3D.new()
	yaw_node.add_child(pitch_node)
	pitch_node.rotation.x = deg_to_rad(-pitch_degrees)
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 1.0
	camera.far = 90.0
	camera.position = Vector3(0, 0, distance)
	pitch_node.add_child(camera)
	camera.current = true
	EventBus.camera_shake.connect(_on_shake)


func set_target(t: Node3D) -> void:
	target = t
	if t:
		global_position = t.global_position + Vector3.UP * 0.8


func get_yaw() -> float:
	return yaw_node.rotation.y


## Screen "up" projected on the ground (movement is relative to this).
func get_forward() -> Vector3:
	return -yaw_node.global_transform.basis.z


func snap_behind_target() -> void:
	pass


func add_look_input(_delta_px: Vector2) -> void:
	pass


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var vel: Variant = target.get("velocity")
	var v: Vector3 = vel if vel is Vector3 else Vector3.ZERO
	v.y = 0.0
	_ahead = _ahead.lerp(v.limit_length(1.0) * look_ahead if v.length() > 0.5 else Vector3.ZERO, clampf(2.0 * delta, 0.0, 1.0))
	var focus := target.global_position + Vector3.UP * 0.8 + _ahead
	var lock = target.get("lock_target")
	if lock != null and is_instance_valid(lock):
		focus = focus.lerp((lock as Node3D).global_position, 0.3)
	global_position = global_position.lerp(focus, clampf(follow_speed * delta, 0.0, 1.0))
	# Pull back a little in combat so groups of enemies stay readable.
	_zoom = lerpf(_zoom, 3.0 if CombatDirector.in_combat() else 0.0, clampf(1.5 * delta, 0.0, 1.0))
	camera.position.z = distance + _zoom
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := _shake * (_shake_time / 0.3)
		camera.h_offset = randf_range(-1.0, 1.0) * k * 0.3
		camera.v_offset = randf_range(-1.0, 1.0) * k * 0.3
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _on_shake(strength: float) -> void:
	_shake = maxf(strength, _shake if _shake_time > 0.0 else 0.0)
	_shake_time = 0.3

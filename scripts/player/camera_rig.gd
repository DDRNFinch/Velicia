class_name CameraRig
extends Node3D
## Third-person follow camera with collision, touch/mouse/gamepad look,
## lock-on framing and screen shake.

@export var distance: float = 4.6
@export var height_offset: float = 1.55
@export var follow_speed: float = 12.0
@export var min_pitch: float = -60.0
@export var max_pitch: float = 35.0
@export var mouse_sensitivity: float = 0.0035
@export var touch_sensitivity: float = 0.006
@export var stick_speed: float = 2.6

var target: Node3D
var yaw_node: Node3D
var pitch_node: Node3D
var spring: SpringArm3D
var camera: Camera3D
var _shake := 0.0
var _shake_time := 0.0
var _look_velocity := Vector2.ZERO


func _ready() -> void:
	top_level = true
	add_to_group("camera_rig")
	yaw_node = Node3D.new()
	add_child(yaw_node)
	pitch_node = Node3D.new()
	yaw_node.add_child(pitch_node)
	pitch_node.rotation.x = deg_to_rad(-14.0)
	spring = SpringArm3D.new()
	spring.spring_length = distance
	spring.collision_mask = CombatUtil.LAYER_WORLD
	spring.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	pitch_node.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = float(Settings.get_value("graphics", "view_distance"))
	camera.position = Vector3(0.0, 0.0, 0.0)
	spring.add_child(camera)
	camera.current = true
	EventBus.camera_shake.connect(_on_shake)
	Settings.changed.connect(_on_settings_changed)


func set_target(t: Node3D) -> void:
	target = t
	if t:
		global_position = t.global_position + Vector3.UP * height_offset
		spring.add_excluded_object(t.get_rid())
		yaw_node.rotation.y = t.rotation.y


func get_yaw() -> float:
	return yaw_node.rotation.y


func get_forward() -> Vector3:
	return -yaw_node.global_transform.basis.z


func snap_behind_target() -> void:
	if target:
		yaw_node.rotation.y = target.rotation.y


## Touch drag look input, in screen pixels.
func add_look_input(delta_px: Vector2) -> void:
	var sens := touch_sensitivity * float(Settings.get_value("controls", "look_sensitivity"))
	_apply_look(delta_px * sens)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * float(Settings.get_value("controls", "look_sensitivity"))
		_apply_look(event.relative * sens)


func _apply_look(d: Vector2) -> void:
	var invert := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
	yaw_node.rotation.y -= d.x
	pitch_node.rotation.x = clampf(pitch_node.rotation.x - d.y * invert, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var desired := target.global_position + Vector3.UP * height_offset
	global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))

	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.05:
		var sens := float(Settings.get_value("controls", "look_sensitivity"))
		_apply_look(stick * stick_speed * sens * delta)

	var lock = target.get("lock_target")
	if lock != null and is_instance_valid(lock):
		var to: Vector3 = (lock as Node3D).global_position - target.global_position
		to.y = 0.0
		if to.length() > 0.5:
			var want := atan2(-to.x, -to.z)
			yaw_node.rotation.y = lerp_angle(yaw_node.rotation.y, want, clampf(6.0 * delta, 0.0, 1.0))
			pitch_node.rotation.x = lerpf(pitch_node.rotation.x, deg_to_rad(-18.0), clampf(3.0 * delta, 0.0, 1.0))

	if _shake_time > 0.0:
		_shake_time -= delta
		var k := _shake * (_shake_time / 0.3)
		camera.h_offset = randf_range(-1.0, 1.0) * k * 0.25
		camera.v_offset = randf_range(-1.0, 1.0) * k * 0.25
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _on_shake(strength: float) -> void:
	_shake = maxf(strength, _shake if _shake_time > 0.0 else 0.0)
	_shake_time = 0.3


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics" and key == "view_distance":
		camera.far = float(Settings.get_value("graphics", "view_distance"))

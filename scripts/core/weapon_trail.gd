class_name WeaponTrail
extends MeshInstance3D
## Fading ribbon traced by a weapon during attacks, drawn with ImmediateMesh.

const MAX_POINTS := 14
const LIFETIME := 0.16

var color: Color = Color(1.0, 0.95, 0.85)
var emitting: bool = false
var _points: Array = [] # [base, tip, age]
var _imesh: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imesh = ImmediateMesh.new()
	mesh = _imesh
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	global_transform = Transform3D.IDENTITY


func is_active() -> bool:
	return emitting or not _points.is_empty()


## Records the weapon's current base and tip; call every frame.
func sample(base: Vector3, tip: Vector3, delta: float) -> void:
	for p in _points:
		p[2] += delta
	while not _points.is_empty() and _points[0][2] > LIFETIME:
		_points.pop_front()
	if emitting:
		_points.append([base, tip, 0.0])
		while _points.size() > MAX_POINTS:
			_points.pop_front()
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	if _points.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _points:
		var a := clampf(1.0 - float(p[2]) / LIFETIME, 0.0, 1.0)
		_imesh.surface_set_color(Color(color, a * 0.05))
		_imesh.surface_add_vertex(p[0])
		_imesh.surface_set_color(Color(color, a * 0.55))
		_imesh.surface_add_vertex(p[1])
	_imesh.surface_end()

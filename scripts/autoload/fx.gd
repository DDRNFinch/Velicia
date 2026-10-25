extends Node
## Pooled combat and magic feedback: hit sparks, floating damage numbers,
## ring bursts, hitstop and camera shake requests.

const SPARK_POOL := 16
const NUMBER_POOL := 16
const BURST_POOL := 6
const PARTICLE_POOL := 8

var _sparks: Array[MeshInstance3D] = []
var _numbers: Array[Label3D] = []
var _bursts: Array[MeshInstance3D] = []
var _next_spark := 0
var _next_number := 0
var _next_burst := 0
var _hitstop_active := false
var _slowmo_active := false
var _spark_bursts: Array[CPUParticles3D] = []
var _dust_bursts: Array[CPUParticles3D] = []
var _next_spark_burst := 0
var _next_dust := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.18
	spark_mesh.height = 0.36
	spark_mesh.radial_segments = 8
	spark_mesh.rings = 4
	for i in SPARK_POOL:
		var m := MeshInstance3D.new()
		m.mesh = spark_mesh
		m.material_override = _unshaded(Color.WHITE)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_sparks.append(m)
	for i in NUMBER_POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 64
		l.outline_size = 12
		l.pixel_size = 0.006
		l.visible = false
		add_child(l)
		_numbers.append(l)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	for i in BURST_POOL:
		var b := MeshInstance3D.new()
		b.mesh = torus
		b.material_override = _unshaded(Color.WHITE, true)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		_bursts.append(b)
	for i in PARTICLE_POOL:
		_spark_bursts.append(_make_sparks())
		_dust_bursts.append(_make_dust())


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 18
	p.lifetime = 0.35
	var m := BoxMesh.new()
	m.size = Vector3(0.025, 0.025, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.material = mat
	p.mesh = m
	p.particle_flag_align_y = true
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 3.5
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	ramp.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 12
	p.lifetime = 0.8
	var m := SphereMesh.new()
	m.radius = 0.18
	m.height = 0.36
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.48, 0.38, 0.45))
	ramp.set_color(1, Color(0.55, 0.48, 0.38, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## Burst of glowing sparks (weapon impacts, parries).
func spark_burst(pos: Vector3, color: Color = Color(1, 0.8, 0.4), amount_scale: float = 1.0) -> void:
	var p := _spark_bursts[_next_spark_burst]
	_next_spark_burst = (_next_spark_burst + 1) % PARTICLE_POOL
	p.global_position = pos
	p.amount = int(18 * amount_scale)
	p.color = color
	p.restart()
	p.emitting = true


## Puff of dust (dodges, landings, heavy impacts on the ground).
func dust(pos: Vector3, size: float = 1.0) -> void:
	var p := _dust_bursts[_next_dust]
	_next_dust = (_next_dust + 1) % PARTICLE_POOL
	p.global_position = pos + Vector3.UP * 0.1
	p.scale = Vector3.ONE * size
	p.restart()
	p.emitting = true


## Brief slow motion (perfect dodges). Skipped when "hitstop" is disabled.
func slowmo(duration: float, scale: float = 0.3) -> void:
	if not Settings.get_value("accessibility", "hitstop") or _slowmo_active:
		return
	_slowmo_active = true
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_slowmo_active = false


static func _unshaded(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func hit_spark(pos: Vector3, color: Color = Color(1, 0.9, 0.6), size: float = 1.0) -> void:
	var m := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % SPARK_POOL
	(m.material_override as StandardMaterial3D).albedo_color = color
	m.global_position = pos
	m.scale = Vector3.ONE * 0.3 * size
	m.visible = true
	var t := m.create_tween()
	t.tween_property(m, "scale", Vector3.ONE * 1.4 * size, 0.12)
	t.tween_property(m, "scale", Vector3.ONE * 0.01, 0.1)
	t.tween_callback(m.hide)


func damage_number(pos: Vector3, amount: float, color: Color = Color(1, 0.95, 0.85)) -> void:
	floating_text(pos, str(roundi(amount)), color)


func floating_text(pos: Vector3, text: String, color: Color = Color.WHITE) -> void:
	var l := _numbers[_next_number]
	_next_number = (_next_number + 1) % NUMBER_POOL
	l.text = text
	l.modulate = color
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	l.visible = true
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "global_position", l.global_position + Vector3(0, 1.2, 0), 0.8)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(l.hide)


## Expanding magical ring, used for captures and summons.
func ring_burst(pos: Vector3, color: Color, radius: float = 1.6, duration: float = 0.6) -> void:
	var b := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % BURST_POOL
	var mat := b.material_override as StandardMaterial3D
	mat.albedo_color = Color(color, 0.9)
	b.global_position = pos
	b.scale = Vector3.ONE * 0.2
	b.visible = true
	var t := b.create_tween()
	t.set_parallel(true)
	t.tween_property(b, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, duration)
	t.chain().tween_callback(b.hide)


func hitstop(duration: float) -> void:
	if not Settings.get_value("accessibility", "hitstop") or _hitstop_active or _slowmo_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.06
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 0.3 if _slowmo_active else 1.0
	_hitstop_active = false


func shake(strength: float) -> void:
	if Settings.get_value("accessibility", "screen_shake"):
		EventBus.camera_shake.emit(strength)

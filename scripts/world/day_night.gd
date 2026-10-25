class_name DayNight
extends Node
## Day/night cycle: moves the sun (and moon at night), and blends sky, fog,
## ambient and light colours through dawn, day, dusk and night.
## One in-game day lasts 24 real minutes by default. Time persists in saves
## (GameState.world.time_of_day) and can be switched off in Settings.

const KEYS := [
	# hour, sky top, horizon, sun colour, sun energy, ambient, fog colour, stars
	[0.0, Color(0.03, 0.06, 0.14), Color(0.12, 0.16, 0.26), Color(0.6, 0.7, 0.95), 0.38, 0.42, Color(0.1, 0.13, 0.2), 1.0],
	[5.0, Color(0.06, 0.1, 0.22), Color(0.28, 0.25, 0.34), Color(0.65, 0.65, 0.9), 0.36, 0.42, Color(0.2, 0.2, 0.26), 0.6],
	[6.5, Color(0.22, 0.32, 0.55), Color(0.95, 0.62, 0.42), Color(1.0, 0.7, 0.45), 0.7, 0.4, Color(0.75, 0.6, 0.5), 0.0],
	[9.0, Color(0.2, 0.4, 0.72), Color(0.72, 0.78, 0.86), Color(1.0, 0.95, 0.86), 1.05, 0.55, Color(0.68, 0.73, 0.8), 0.0],
	[16.0, Color(0.2, 0.4, 0.72), Color(0.74, 0.78, 0.84), Color(1.0, 0.93, 0.82), 1.0, 0.55, Color(0.7, 0.74, 0.8), 0.0],
	[18.8, Color(0.24, 0.26, 0.48), Color(0.98, 0.55, 0.32), Color(1.0, 0.6, 0.35), 0.65, 0.4, Color(0.78, 0.55, 0.42), 0.0],
	[20.5, Color(0.07, 0.1, 0.24), Color(0.32, 0.24, 0.34), Color(0.65, 0.65, 0.9), 0.38, 0.42, Color(0.22, 0.19, 0.26), 0.6],
	[24.0, Color(0.03, 0.06, 0.14), Color(0.12, 0.16, 0.26), Color(0.6, 0.7, 0.95), 0.38, 0.42, Color(0.1, 0.13, 0.2), 1.0],
]

@export var seconds_per_hour: float = 60.0

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var hour: float = 9.0


func setup(p_sun: DirectionalLight3D, p_env: Environment, p_sky: ShaderMaterial) -> void:
	sun = p_sun
	environment = p_env
	sky_material = p_sky
	hour = float(GameState.world.get("time_of_day", 9.0))
	_apply()


func _process(delta: float) -> void:
	if sun == null:
		return
	if Settings.get_value("graphics", "day_night"):
		hour = fmod(hour + delta / seconds_per_hour, 24.0)
		GameState.world["time_of_day"] = hour
	_apply()


func is_night() -> bool:
	return hour < 5.5 or hour > 20.0


func set_hour(h: float) -> void:
	hour = fmod(h, 24.0)
	GameState.world["time_of_day"] = hour
	_apply()


func _apply() -> void:
	var a: Array = KEYS[0]
	var b: Array = KEYS[1]
	for i in KEYS.size() - 1:
		if hour >= KEYS[i][0] and hour <= KEYS[i + 1][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var t := (hour - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
	var top: Color = (a[1] as Color).lerp(b[1], t)
	var horizon: Color = (a[2] as Color).lerp(b[2], t)
	var light: Color = (a[3] as Color).lerp(b[3], t)
	var energy := lerpf(a[4], b[4], t)
	var ambient := lerpf(a[5], b[5], t)
	var fog: Color = (a[6] as Color).lerp(b[6], t)
	var stars := lerpf(a[7], b[7], t)

	# The sun arcs east to west; after dusk the same light becomes the moon.
	var day_phase := (hour - 6.0) / 12.0
	var elevation: float
	if hour >= 6.0 and hour <= 18.0:
		elevation = sin(day_phase * PI) * 62.0 + 6.0
	else:
		var night_phase := fmod(hour + 6.0, 24.0) / 12.0
		elevation = sin(night_phase * PI) * 45.0 + 10.0
	var azimuth := -35.0 + day_phase * 120.0
	sun.rotation_degrees = Vector3(-elevation, azimuth, 0)
	sun.light_color = light
	sun.light_energy = energy
	if environment:
		environment.ambient_light_energy = ambient
		environment.fog_light_color = fog
	if sky_material:
		sky_material.set_shader_parameter("top_color", top)
		sky_material.set_shader_parameter("horizon_color", horizon)
		sky_material.set_shader_parameter("ground_color", horizon.darkened(0.6))
		sky_material.set_shader_parameter("star_strength", stars)
		sky_material.set_shader_parameter("cloud_color", Color(0.96, 0.95, 0.92).lerp(Color(0.25, 0.28, 0.38), stars).lerp(Color(1.0, 0.75, 0.6), 0.0))

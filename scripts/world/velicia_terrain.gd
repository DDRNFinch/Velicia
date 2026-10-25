class_name VeliciaTerrain
extends RefCounted
## Deterministic height function for a region. Location triggers flatten
## ground for settlements, ruins and arenas; lakes carve basins; the region is
## ringed by mountains so its edges read as natural boundaries.

static var size: float = 360.0
static var water_level: float = -1.4
static var _noise: FastNoiseLite
static var _detail: FastNoiseLite
## Each: { "center": Vector2, "radius": float, "height": float, "falloff": float }
static var flat_zones: Array = []
## Each: { "center": Vector2, "radius": float, "depth": float, "falloff": float }
static var lakes: Array = []


static func configure(seed_value: int, region_size: float, zones: Array, lake_list: Array) -> void:
	size = region_size
	flat_zones = zones
	lakes = lake_list
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0065
	_noise.fractal_octaves = 4
	_detail = FastNoiseLite.new()
	_detail.seed = seed_value + 17
	_detail.frequency = 0.04
	_detail.fractal_octaves = 2


static func height_at(x: float, z: float) -> float:
	if _noise == null:
		configure(1337, size, flat_zones, lakes)
	var half := size * 0.5
	# Gentle rolling ground (the camera looks down on it), ringed by steep
	# hills that read as the region's natural walls.
	var h := _noise.get_noise_2d(x, z) * 4.5 + _detail.get_noise_2d(x, z) * 0.6 + 1.0
	var edge := maxf(absf(x), absf(z))
	h += smoothstep(half - 36.0, half - 4.0, edge) * 26.0
	var p := Vector2(x, z)
	for l in lakes:
		var d := p.distance_to(l.center)
		var t := smoothstep(float(l.radius), float(l.radius) + float(l.falloff), d)
		h = lerpf(float(l.depth), h, t)
	for zone in flat_zones:
		var d := p.distance_to(zone.center)
		var t := smoothstep(float(zone.radius), float(zone.radius) + float(zone.falloff), d)
		h = lerpf(float(zone.height), h, t)
	return h


static func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


static func in_flat_zone(x: float, z: float, margin: float = 0.0) -> bool:
	var p := Vector2(x, z)
	for zone in flat_zones:
		if p.distance_to(zone.center) < float(zone.radius) + margin:
			return true
	return false


static func in_lake(x: float, z: float, margin: float = 0.0) -> bool:
	var p := Vector2(x, z)
	for l in lakes:
		if p.distance_to(l.center) < float(l.radius) + float(l.falloff) * 0.5 + margin:
			return true
	return false

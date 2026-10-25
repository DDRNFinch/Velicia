class_name VeliciaMaterials
extends RefCounted
## Material library for the low-poly look: flat palette colours, vertex
## colours for faceted meshes, no textures and no custom shaders.
## `surface()` keeps its old signature so structure kits stay readable:
## the name picks a palette colour, the tint shifts it.

const SURFACE_COLORS := {
	"fabric": "cloth_blue", "bark": "bark", "planks": "wood", "stone_wall": "stone", "rock": "rock",
	"leather": "wood_dark", "metal": "stone_dark", "fur": "bark", "skin": "plaster",
}

static var _cache: Dictionary = {}


## Kept for compatibility: the low-poly style uses no textures.
static func tex(_name: String) -> Texture2D:
	return null


static func terrain() -> StandardMaterial3D:
	return LowPoly.vcol_mat(1.0)


static func water() -> StandardMaterial3D:
	if not _cache.has("water"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(LowPoly.c("water"), 0.82)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["water"] = m
	return _cache["water"]


static func surface(name: String, tint: Color = Color.WHITE, _scale: float = 0.5, roughness: float = 0.9, _world: bool = true) -> StandardMaterial3D:
	var base := LowPoly.c(SURFACE_COLORS.get(name, "stone"))
	var col := base
	if name == "fabric":
		col = tint
	elif tint != Color.WHITE:
		col = Color(clampf(base.r * tint.r, 0, 1), clampf(base.g * tint.g, 0, 1), clampf(base.b * tint.b, 0, 1))
	return LowPoly.mat(col, roughness)

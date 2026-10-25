class_name CharacterModel
extends Node3D
## A realistic, skinned character built by tools/build_characters.py from the
## CC0 MakeHuman base mesh. Loads models/characters/<name>.glb, dresses it
## with tinted materials, shows the chosen hair/beard/cloak parts, and lets
## PlaceholderBody drive its 20-bone rig from the animation pivots.

const DIR := "res://models/characters/"

static var _mat_cache: Dictionary = {}
static var _info_cache: Dictionary = {}

var skeleton: Skeleton3D
var parts: Dictionary = {}
var info: Dictionary = {}
var model_height: float = 1.78
var head_center: Vector3 = Vector3(0, 1.65, 0)
var _bone_idx: Dictionary = {}


static func exists(model_name: StringName) -> bool:
	return ResourceLoader.exists(DIR + String(model_name) + ".glb")


static func create(model_name: StringName, params: Dictionary = {}) -> CharacterModel:
	var m := CharacterModel.new()
	m.name = "Model"
	m.setup(model_name, params)
	return m


static func load_info(model_name: StringName) -> Dictionary:
	var key := String(model_name)
	if not _info_cache.has(key):
		var path := DIR + key + ".json"
		var data: Variant = null
		if FileAccess.file_exists(path):
			data = JSON.parse_string(FileAccess.get_file_as_string(path))
		_info_cache[key] = data if data is Dictionary else {}
	return _info_cache[key]


func setup(model_name: StringName, params: Dictionary) -> void:
	var scene: PackedScene = load(DIR + String(model_name) + ".glb")
	var inst := scene.instantiate()
	add_child(inst)
	skeleton = _find_skeleton(inst)
	for mi in _find_meshes(inst):
		parts[String(mi.name)] = mi
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = PlaceholderBody.VIEW_RANGE
	if skeleton:
		for i in skeleton.get_bone_count():
			_bone_idx[skeleton.get_bone_name(i)] = i
	info = load_info(model_name)
	model_height = float(info.get("height", 1.78))
	var hc: Array = info.get("head_center", [0.0, model_height * 0.93, 0.0])
	head_center = Vector3(hc[0], hc[1], hc[2])
	apply_params(params)


func apply_params(params: Dictionary) -> void:
	var hair := _hair_part(StringName(params.get("hair_style", &"short")))
	for part_name in parts:
		var mi: MeshInstance3D = parts[part_name]
		var n := String(part_name)
		if n.begins_with("Hair_"):
			mi.visible = n == hair
		elif n == "Beard":
			mi.visible = bool(params.get("beard", true))
		elif n == "Cloak":
			mi.visible = bool(params.get("has_cloak", false))
		elif n == "Hood":
			mi.visible = bool(params.get("hood", true))
		_dress(mi, params)


## Picks the hair mesh for a style; models only carry the styles that suit
## their people, so unknown styles fall back to the closest one.
func _hair_part(style: StringName) -> String:
	if style == &"none":
		return ""
	var want := "Hair_" + String(style)
	if parts.has(want):
		return want
	var fallback := {&"mane": "Hair_long", &"tide": "Hair_long", &"topknot": "Hair_short"}
	if fallback.has(style) and parts.has(fallback[style]):
		return fallback[style]
	for n in parts:
		if String(n).begins_with("Hair_"):
			return n
	return ""


func _dress(mi: MeshInstance3D, params: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var kind := src.resource_name if src else "skin"
		mi.set_surface_override_material(s, material_for(kind, params))


static func material_for(kind: String, p: Dictionary) -> Material:
	var skin: Color = p.get("skin", Color(0.78, 0.6, 0.47))
	var hair: Color = p.get("hair", Color(0.25, 0.17, 0.1))
	var detail: String = p.get("skin_detail", "skin")
	match kind:
		"skin":
			var key := "skin|%s|%s|%s" % [skin.to_html(), hair.to_html(), detail]
			if not _mat_cache.has(key):
				var m := ShaderMaterial.new()
				m.shader = load("res://shaders/skin.gdshader")
				m.set_shader_parameter("skin_color", skin)
				m.set_shader_parameter("brow_color", hair.darkened(0.15) if detail == "skin" else skin.darkened(0.35))
				m.set_shader_parameter("lip_color", skin.lerp(Color(0.62, 0.3, 0.3), 0.45) if detail == "skin" else skin.darkened(0.2))
				m.set_shader_parameter("detail_albedo", VeliciaMaterials.tex(detail + "_albedo"))
				m.set_shader_parameter("detail_normal", VeliciaMaterials.tex(detail + "_normal"))
				m.set_shader_parameter("detail_scale", 9.0 if detail == "skin" else 70.0)
				m.set_shader_parameter("detail_strength", 0.6 if detail == "skin" else 0.45)
				m.set_shader_parameter("normal_strength", 0.45 if detail == "skin" else 0.6)
				m.set_shader_parameter("roughness_value", 0.58 if detail == "skin" else 0.42)
				_mat_cache[key] = m
			return _mat_cache[key]
		"top":
			return _std("leather", p.get("armor", Color(0.45, 0.38, 0.3)), 0.62, 14.0, false, false, false, 1.0)
		"tunic":
			return _std("leather", p.get("armor", Color(0.45, 0.38, 0.3)), 0.62, 14.0, true, true, true, 1.0)
		"robe":
			return _std("fabric", p.get("cloth", Color(0.36, 0.26, 0.4)), 0.92, 16.0)
		"hood":
			return _std("fabric", p.get("cloth", Color(0.36, 0.26, 0.4)), 0.92, 16.0, true, true, true)
		"pants":
			return _std("fabric", p.get("cloth", Color(0.3, 0.33, 0.4)), 0.9, 16.0)
		"boots":
			return _std("leather", Color(0.3, 0.21, 0.14), 0.7, 12.0)
		"belt":
			return _std("leather", Color(p.get("accent", Color(0.6, 0.45, 0.25))).darkened(0.45), 0.55, 10.0)
		"cloak":
			return _std("fabric", p.get("cloak", Color(0.2, 0.3, 0.45)), 0.92, 3.0, true)
		"fur":
			return _std("fur", p.get("fur", hair), 0.95, 6.0, false, true)
		"hair", "beard":
			return _std("fur", hair, 0.75, 10.0, true, true, true)
		"eyes":
			var key := "eyes"
			if not _mat_cache.has(key):
				var m := StandardMaterial3D.new()
				m.vertex_color_use_as_albedo = true
				m.roughness = 0.12
				m.metallic_specular = 0.8
				_mat_cache[key] = m
			return _mat_cache[key]
		"claw":
			return _std("", Color(0.86, 0.82, 0.72), 0.35)
		"fin":
			return _std("scales", skin.darkened(0.05), 0.35, 4.0, true, true)
	return _std("fabric", Color(0.5, 0.5, 0.5), 0.9, 8.0)


static func _std(detail: String, color: Color, roughness: float, scale: float = 8.0, double_sided: bool = false, vcol: bool = false, cutout: bool = false, gain: float = 1.25) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%.1f|%s|%s|%s|%.2f" % [detail, color.to_html(), roughness, scale, double_sided, vcol, cutout, gain]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if not detail.is_empty():
		# The detail textures average ~0.65; compensate so tints read as chosen.
		m.albedo_color = Color(minf(color.r * gain, 1.0), minf(color.g * gain, 1.0), minf(color.b * gain, 1.0), color.a)
		m.albedo_texture = VeliciaMaterials.tex(detail + "_albedo")
		var n := VeliciaMaterials.tex(detail + "_normal")
		if n:
			m.normal_enabled = true
			m.normal_texture = n
		m.uv1_scale = Vector3(scale, scale, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if vcol:
		m.vertex_color_use_as_albedo = true
	if cutout:
		# Soft hairlines and beard edges come from vertex alpha.
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	_mat_cache[key] = m
	return m


func bone(bone_name: String) -> int:
	return _bone_idx.get(bone_name, -1)


func bone_rest_position(bone_name: String) -> Vector3:
	var i := bone(bone_name)
	if i < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_rest(i).origin


## Sets a bone's local rotation (rest orientations are identity, so this is
## the same rotation a PlaceholderBody pivot uses).
func set_bone_rotation(i: int, q: Quaternion) -> void:
	if i >= 0:
		skeleton.set_bone_pose_rotation(i, q)


func set_overlay(m: Material) -> void:
	for p in parts.values():
		(p as MeshInstance3D).material_overlay = m


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


func _find_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out

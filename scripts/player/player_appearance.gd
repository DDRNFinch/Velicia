class_name PlayerAppearance
extends RefCounted
## Customisation options for the Emoria warrior and conversion to
## PlaceholderBody parameters. Stored in GameState.player.appearance as indexes.

const SKIN_TONES: Array[Color] = [
	Color(0.95, 0.8, 0.68), Color(0.86, 0.68, 0.54), Color(0.76, 0.58, 0.44),
	Color(0.6, 0.43, 0.31), Color(0.45, 0.31, 0.22), Color(0.32, 0.22, 0.16),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.08, 0.07, 0.06), Color(0.3, 0.19, 0.1), Color(0.55, 0.36, 0.18),
	Color(0.78, 0.62, 0.38), Color(0.62, 0.22, 0.12), Color(0.82, 0.8, 0.78),
]
const CLOAK_COLORS: Array[Color] = [
	Color(0.18, 0.28, 0.45), Color(0.45, 0.14, 0.14), Color(0.2, 0.36, 0.22),
	Color(0.38, 0.3, 0.5), Color(0.5, 0.42, 0.25), Color(0.15, 0.15, 0.17),
]
const BUILDS := [
	{"name": "Lean", "shoulder": 0.42, "limb": 0.058},
	{"name": "Balanced", "shoulder": 0.46, "limb": 0.065},
	{"name": "Broad", "shoulder": 0.52, "limb": 0.074},
]
const HAIR_STYLES: Array[StringName] = [&"short", &"long", &"topknot", &"none"]
const HAIR_STYLE_NAMES := ["Short", "Long", "Topknot", "Shaved"]


static func to_body_params(appearance: Dictionary, armor_color: Color = Color(0.45, 0.38, 0.3), weapon: StringName = &"sword") -> Dictionary:
	var p := PlaceholderBody.preset(&"human")
	var build: Dictionary = BUILDS[clampi(int(appearance.get("build", 1)), 0, BUILDS.size() - 1)]
	p.shoulder = build.shoulder
	p.limb = build.limb
	p.skin = SKIN_TONES[clampi(int(appearance.get("skin", 2)), 0, SKIN_TONES.size() - 1)]
	p.hair = HAIR_COLORS[clampi(int(appearance.get("hair", 1)), 0, HAIR_COLORS.size() - 1)]
	p.cloak = CLOAK_COLORS[clampi(int(appearance.get("cloak", 0)), 0, CLOAK_COLORS.size() - 1)]
	p.hair_style = HAIR_STYLES[clampi(int(appearance.get("hair_style", 0)), 0, HAIR_STYLES.size() - 1)]
	p.has_cloak = true
	p.cloth = Color(0.26, 0.24, 0.22)
	p.armor = armor_color
	p.accent = Color(0.85, 0.7, 0.32) # Emoria Guild gold
	p.weapon = weapon
	return p

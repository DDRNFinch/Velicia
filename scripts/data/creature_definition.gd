class_name CreatureDefinition
extends Resource
## Reusable definition for a capturable creature. New creatures are added by
## creating a new resource in res://data/creatures — no code changes needed.
## The official roster will be supplied by the game's author; anything marked
## is_placeholder is a temporary test creature.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum Temperament { AGGRESSIVE, DEFENSIVE, SUPPORT }

@export var id: StringName
@export var display_name: String = ""
@export var is_placeholder: bool = true
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
## Companion behaviour when summoned.
@export var temperament: Temperament = Temperament.AGGRESSIVE

@export_group("Stats")
@export var base_health: float = 60.0
@export var base_attack: float = 8.0
@export var base_defense: float = 2.0
@export var move_speed: float = 5.0
@export var health_per_level: float = 8.0
@export var attack_per_level: float = 1.5
@export var defense_per_level: float = 0.5
@export var max_level: int = 30

@export_group("Abilities")
@export var abilities: Array[CreatureAbility] = []

@export_group("Capture")
## Must be weakened to this health fraction (or lower) to be capturable.
@export var capture_health_threshold: float = 0.4
@export var base_capture_chance: float = 0.55
@export var min_ring_tier: int = 1
## Optional extra rule. Supported: "" (none), "dazed" (must be dazed).
@export var capture_condition: StringName = &""
@export var capture_hint: String = ""

@export_group("Appearance (placeholder)")
## quadruped or hover
@export var body_shape: StringName = &"quadruped"
@export var body_color: Color = Color(0.6, 0.5, 0.4)
@export var accent_color: Color = Color(0.9, 0.8, 0.5)
@export var eye_color: Color = Color(0.4, 1.0, 0.9)
@export var size: float = 1.0

@export_group("Wild behaviour")
@export var wander_radius: float = 8.0
@export var flee_when_weak: bool = false
@export var hostile_on_sight: bool = false


func max_health_at(level: int) -> float:
	return base_health + health_per_level * float(level - 1)


func attack_at(level: int) -> float:
	return base_attack + attack_per_level * float(level - 1)


func defense_at(level: int) -> float:
	return base_defense + defense_per_level * float(level - 1)


func rarity_name() -> String:
	return Rarity.keys()[rarity].capitalize()


func rarity_capture_mult() -> float:
	match rarity:
		Rarity.COMMON:
			return 1.0
		Rarity.UNCOMMON:
			return 0.85
		Rarity.RARE:
			return 0.65
		Rarity.EPIC:
			return 0.45
		_:
			return 0.25


func temperament_name() -> String:
	return Temperament.keys()[temperament].capitalize()

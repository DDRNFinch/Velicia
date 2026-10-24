class_name CreatureAbility
extends Resource
## An ability a creature can use. Unlocked by creature level and bond level.

enum Kind { MELEE, RANGED, AREA, HEAL_ALLY, GUARD }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.MELEE
## Damage/heal multiplier of the creature's attack stat.
@export var power: float = 1.0
@export var cooldown: float = 2.0
@export var ability_range: float = 2.0
@export var windup: float = 0.35
@export var poise_damage: float = 15.0
@export var required_level: int = 1
@export var required_bond: int = 0
@export var color: Color = Color(1, 1, 1)

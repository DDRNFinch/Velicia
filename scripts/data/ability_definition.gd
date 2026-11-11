class_name AbilityDefinition
extends Resource
## A player ability of the Emoria Guild, unlocked by character level.

enum Kind { PASSIVE, ACTIVE }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.PASSIVE
@export var unlock_level: int = 1
@export var stamina_cost: float = 0.0
@export var cooldown: float = 0.0
@export var power: float = 1.0
## For active abilities that perform an attack.
@export var attack: AttackDefinition

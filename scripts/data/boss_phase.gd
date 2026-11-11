class_name BossPhase
extends Resource
## A boss phase becomes active once the boss's health fraction drops to
## health_fraction or below. Each phase can change tactics completely.

@export var health_fraction: float = 1.0
@export var attacks: Array[AttackDefinition] = []
@export var speed_mult: float = 1.0
@export var recovery_mult: float = 1.0
@export var announcement: String = ""

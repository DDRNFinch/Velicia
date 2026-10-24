class_name EnemyDefinition
extends Resource
## Data for an enemy type. Bosses add phases with their own attack sets.

@export var id: StringName
@export var display_name: String = ""
## One of the canon peoples: human, amir, burrok, vapouriun, gouran, gyria.
@export var people: StringName = &"gyria"
@export var tags: PackedStringArray = PackedStringArray()
@export var is_boss: bool = false
@export var is_draft: bool = true

@export_group("Stats")
@export var max_health: float = 80.0
@export var max_poise: float = 40.0
@export var defense: float = 0.0
@export var walk_speed: float = 2.0
@export var run_speed: float = 4.2
@export var turn_speed: float = 7.0
@export var aggro_range: float = 14.0
@export var leash_range: float = 35.0
@export var preferred_distance: float = 3.2
## Chance to raise guard when the player winds up nearby.
@export var block_chance: float = 0.25
@export var xp_reward: int = 25

@export_group("Combat")
@export var attacks: Array[AttackDefinition] = []
## Bosses only; phases replace the attack list as health falls.
@export var phases: Array[BossPhase] = []
## item_id -> drop chance (0..1)
@export var loot: Dictionary = {}

@export_group("Appearance")
## Overall scale of the body relative to the people's base height.
@export var scale: float = 1.0
@export var build: StringName = &"wiry"
@export var skin_color: Color = Color(0.45, 0.5, 0.36)
@export var armor_color: Color = Color(0.32, 0.27, 0.22)
@export var accent_color: Color = Color(0.6, 0.2, 0.15)
@export var weapon_kind: StringName = &"hookblade"

class_name AttackDefinition
extends Resource
## One attack: timing (anticipation / impact / recovery), hit area and effects.
## Used by the player, enemies and bosses. Damage is absolute for enemies and a
## multiplier of weapon damage for the player.

enum HitShape { ARC, THRUST, CIRCLE }

@export var id: StringName
@export var display_name: String = ""
## Anticipation: the readable telegraph before the hit lands.
@export var windup: float = 0.5
## Frames where the hit is live.
@export var active: float = 0.15
## Vulnerable recovery after the swing.
@export var recovery: float = 0.6
@export var damage: float = 10.0
@export var poise_damage: float = 20.0
@export var stamina_cost: float = 0.0
@export var hit_shape: HitShape = HitShape.ARC
@export var reach: float = 2.3
@export var arc_degrees: float = 110.0
@export var knockback: float = 3.0
## Forward movement during the late windup and active window.
@export var lunge_speed: float = 0.0
## Attackers keep turning toward their target until this fraction of windup.
@export var tracking_until: float = 0.75
@export var parryable: bool = true
@export var unblockable: bool = false
@export var guard_break: bool = false
@export var is_heavy: bool = false
@export_group("Ranged")
## Greater than zero makes this a projectile attack (arrows, bolts).
@export var projectile_speed: float = 0.0
@export var projectile_range: float = 22.0
@export_group("AI selection")
@export var min_range: float = 0.0
@export var max_range: float = 2.6
@export var cooldown: float = 0.0
@export var weight: float = 1.0
@export_group("Presentation")
## Pose family for procedural animation: slash, thrust, slam, sweep, spin, charge, bite, roar.
@export var pose: StringName = &"slash"
## Shows a ground marker during windup (area attacks).
@export var ground_telegraph: bool = false


func total_time() -> float:
	return windup + active + recovery

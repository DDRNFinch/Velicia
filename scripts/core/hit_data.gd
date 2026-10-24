class_name HitData
extends RefCounted
## Everything a target needs to resolve one incoming hit.

enum Result { HIT, BLOCKED, PARRIED, EVADED, IGNORED }

var damage: float = 0.0
var poise_damage: float = 0.0
var knockback: float = 0.0
## Horizontal direction from attacker to target.
var direction: Vector3 = Vector3.FORWARD
var source: Node3D
var parryable: bool = true
var unblockable: bool = false
var guard_break: bool = false
var is_heavy: bool = false
var is_critical: bool = false


static func make(src: Node3D, target: Node3D, atk: AttackDefinition, dmg: float) -> HitData:
	var h := HitData.new()
	h.source = src
	h.damage = dmg
	h.poise_damage = atk.poise_damage
	h.knockback = atk.knockback
	h.parryable = atk.parryable
	h.unblockable = atk.unblockable
	h.guard_break = atk.guard_break
	h.is_heavy = atk.is_heavy
	var d := target.global_position - src.global_position
	d.y = 0.0
	h.direction = d.normalized() if d.length() > 0.01 else -src.global_transform.basis.z
	return h

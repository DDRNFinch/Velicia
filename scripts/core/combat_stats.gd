class_name CombatStats
extends Node
## Health, stamina and poise for any combatant.

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal died
signal poise_broken

var max_health: float = 100.0
var health: float = 100.0
var max_stamina: float = 100.0
var stamina: float = 100.0
var stamina_regen: float = 32.0
var stamina_regen_delay: float = 0.7
var max_poise: float = 30.0
var poise: float = 30.0
var poise_regen: float = 12.0
var poise_regen_delay: float = 1.6
## Multiplier for stamina regeneration (e.g. while blocking).
var regen_scale: float = 1.0

var _since_stamina_use := 99.0
var _since_poise_hit := 99.0


func setup(hp: float, sta: float, poise_max: float) -> void:
	max_health = hp
	health = hp
	max_stamina = sta
	stamina = sta
	max_poise = poise_max
	poise = poise_max
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)


func _process(delta: float) -> void:
	_since_stamina_use += delta
	_since_poise_hit += delta
	if _since_stamina_use > stamina_regen_delay and stamina < max_stamina:
		stamina = minf(max_stamina, stamina + stamina_regen * regen_scale * delta)
		stamina_changed.emit(stamina, max_stamina)
	if _since_poise_hit > poise_regen_delay and poise < max_poise:
		poise = minf(max_poise, poise + poise_regen * delta)


func is_dead() -> bool:
	return health <= 0.0


func health_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


## Applies damage and returns the amount actually taken.
func apply_damage(amount: float) -> float:
	if is_dead():
		return 0.0
	var taken := minf(amount, health)
	health -= taken
	health_changed.emit(health, max_health)
	if health <= 0.0:
		health = 0.0
		died.emit()
	return taken


## Returns true if poise broke from this hit.
func apply_poise_damage(amount: float) -> bool:
	_since_poise_hit = 0.0
	poise -= amount
	if poise <= 0.0:
		poise = max_poise
		poise_broken.emit()
		return true
	return false


func heal(amount: float) -> void:
	if is_dead():
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


func set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)
	health_changed.emit(health, max_health)


func has_stamina() -> bool:
	return stamina > 0.5


## Spends stamina. Allowed while any stamina remains (can dip to zero),
## so actions are never blocked by a sliver of missing stamina.
func use_stamina(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if stamina <= 0.5:
		return false
	stamina = maxf(0.0, stamina - cost)
	_since_stamina_use = 0.0
	stamina_changed.emit(stamina, max_stamina)
	return true


func drain_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_since_stamina_use = 0.0
	stamina_changed.emit(stamina, max_stamina)


func restore_stamina(amount: float) -> void:
	stamina = minf(max_stamina, stamina + amount)
	stamina_changed.emit(stamina, max_stamina)

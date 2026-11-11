class_name CreatureInstance
extends RefCounted
## A captured creature owned by the player: its level, training, bond and
## current condition. Serialised into the save file.

const BOND_THRESHOLDS := [0, 10, 25, 50, 100]
const EXHAUST_SECONDS := 45.0

var uid: int = 0
var def_id: String = ""
var nickname: String = ""
var level: int = 1
var xp: int = 0
var bond: int = 0
var health: float = -1.0
## GameState.play_time until which the creature cannot be summoned.
var exhausted_until: float = 0.0
## Ring slot index, or -1 when resting in the guild vault.
var ring_slot: int = -1
var times_summoned: int = 0


func definition() -> CreatureDefinition:
	return Database.creature(def_id)


func display_name() -> String:
	if not nickname.is_empty():
		return nickname
	var d := definition()
	return d.display_name if d else def_id


func max_health() -> float:
	var d := definition()
	return d.max_health_at(level) if d else 50.0


func attack() -> float:
	var d := definition()
	var base := d.attack_at(level) if d else 6.0
	return base * (1.0 + 0.05 * bond_level())


func defense() -> float:
	var d := definition()
	return d.defense_at(level) if d else 1.0


func xp_to_next() -> int:
	return int(40.0 * pow(level, 1.5))


## Returns true when the creature levelled up.
func add_xp(amount: int) -> bool:
	var d := definition()
	var cap := d.max_level if d else 30
	var leveled := false
	xp += amount
	while xp >= xp_to_next() and level < cap:
		xp -= xp_to_next()
		level += 1
		leveled = true
		health = max_health()
	return leveled


func add_bond(amount: int) -> bool:
	var before := bond_level()
	bond = mini(bond + amount, BOND_THRESHOLDS[-1])
	return bond_level() > before


func bond_level() -> int:
	var lvl := 0
	for i in BOND_THRESHOLDS.size():
		if bond >= BOND_THRESHOLDS[i]:
			lvl = i
	return lvl


func bond_progress() -> float:
	var lvl := bond_level()
	if lvl >= BOND_THRESHOLDS.size() - 1:
		return 1.0
	var a: int = BOND_THRESHOLDS[lvl]
	var b: int = BOND_THRESHOLDS[lvl + 1]
	return float(bond - a) / float(b - a)


func available_abilities() -> Array[CreatureAbility]:
	var out: Array[CreatureAbility] = []
	var d := definition()
	if d == null:
		return out
	for a in d.abilities:
		if a.required_level <= level and a.required_bond <= bond_level():
			out.append(a)
	return out


func is_exhausted() -> bool:
	return GameState.play_time < exhausted_until


func exhaust() -> void:
	health = 0.0
	exhausted_until = GameState.play_time + EXHAUST_SECONDS


func restore() -> void:
	health = max_health()
	exhausted_until = 0.0


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"def_id": def_id,
		"nickname": nickname,
		"level": level,
		"xp": xp,
		"bond": bond,
		"health": health,
		"exhausted_until": exhausted_until,
		"ring_slot": ring_slot,
		"times_summoned": times_summoned,
	}


static func from_dict(d: Dictionary) -> CreatureInstance:
	var c := CreatureInstance.new()
	c.uid = int(d.get("uid", 0))
	c.def_id = String(d.get("def_id", ""))
	c.nickname = String(d.get("nickname", ""))
	c.level = int(d.get("level", 1))
	c.xp = int(d.get("xp", 0))
	c.bond = int(d.get("bond", 0))
	c.health = float(d.get("health", -1.0))
	c.exhausted_until = float(d.get("exhausted_until", 0.0))
	c.ring_slot = int(d.get("ring_slot", -1))
	c.times_summoned = int(d.get("times_summoned", 0))
	if c.health < 0.0:
		c.health = c.max_health()
	return c

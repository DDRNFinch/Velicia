class_name Creatures
extends RefCounted
## Creature instances are plain Dictionaries (easy to save):
##   {uid, species, level, xp, hp, moves: [move ids], bond}
## This class holds the maths: stats, levelling, learning moves.

const MAX_MOVES := 4
const MAX_LEVEL := 50

static var _uid := 1


static func create(species: String, level: int) -> Dictionary:
	var c := {"uid": _next_uid(), "species": species, "level": level, "xp": xp_for_level(level), "hp": 0, "moves": [], "bond": 0}
	for entry in learnset(species):
		if int(entry[0]) <= level:
			_learn(c, String(entry[1]))
	c.hp = max_hp(c)
	return c


static func _next_uid() -> int:
	_uid += 1
	return int(Time.get_ticks_usec() % 1000000) * 100 + _uid


static func species_data(c: Dictionary) -> Dictionary:
	return Data.creature(String(c.get("species", "")))


static func learnset(species: String) -> Array:
	return Data.creature(species).get("learnset", [])


static func display_name(c: Dictionary) -> String:
	return String(species_data(c).get("name", c.get("species", "?")))


static func element(c: Dictionary) -> String:
	return String(species_data(c).get("element", "normal"))


static func base(c: Dictionary, stat: String) -> int:
	return int(species_data(c).get("base", {}).get(stat, 40))


static func max_hp(c: Dictionary) -> int:
	return int(base(c, "hp") * 2 * int(c.level) / 100.0) + int(c.level) + 10


static func stat(c: Dictionary, s: String) -> int:
	return int(base(c, s) * 2 * int(c.level) / 100.0) + 5


static func xp_for_level(level: int) -> int:
	return int(round(0.8 * pow(level, 3)))


static func xp_to_next(c: Dictionary) -> int:
	return xp_for_level(int(c.level) + 1) - int(c.xp)


static func is_fainted(c: Dictionary) -> bool:
	return int(c.hp) <= 0


static func heal(c: Dictionary, amount: int = -1) -> void:
	var m := max_hp(c)
	c.hp = m if amount < 0 else mini(m, int(c.hp) + amount)


## Adds experience; returns a list of events ("level:N", "learn:move_id").
static func gain_xp(c: Dictionary, amount: int) -> Array:
	var events: Array = []
	c.xp = int(c.xp) + amount
	while int(c.level) < MAX_LEVEL and int(c.xp) >= xp_for_level(int(c.level) + 1):
		var old_max := max_hp(c)
		c.level = int(c.level) + 1
		c.hp = int(c.hp) + (max_hp(c) - old_max)
		events.append("level:%d" % int(c.level))
		for entry in learnset(String(c.species)):
			if int(entry[0]) == int(c.level) and not c.moves.has(entry[1]):
				_learn(c, String(entry[1]))
				events.append("learn:" + String(entry[1]))
	return events


static func _learn(c: Dictionary, move_id: String) -> void:
	if c.moves.has(move_id):
		return
	if c.moves.size() >= MAX_MOVES:
		c.moves.remove_at(0)
	c.moves.append(move_id)


## XP a defeated creature gives.
static func xp_reward(defeated: Dictionary) -> int:
	return int(float(species_data(defeated).get("xp_yield", 50)) * int(defeated.level) / 5.0) + 4

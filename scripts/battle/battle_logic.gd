class_name BattleLogic
extends RefCounted
## Battle maths on "actors" (no UI, so it is easy to test). An actor is a
## Dictionary: {kind: creature|warrior|fighter, name, level, hp, max_hp, atk,
## def, spd, element, moves, stages, sprite, ref}. `ref` points at the saved
## creature Dictionary so HP carries over after battle.

const CRIT_CHANCE := 0.0625
const STAB := 1.25

## Gyria fighters: draft stats (they fight like human warriors).
const FIGHTERS := {
	"gyria": {"hp": 46, "atk": 54, "def": 42, "spd": 56, "moves": ["slash", "hook", "war_cry"], "hp_mult": 1.5},
	"gyria_archer": {"hp": 38, "atk": 52, "def": 36, "spd": 64, "moves": ["arrow_shot", "volley", "slash"], "hp_mult": 1.4},
	"gyria_boss": {"hp": 70, "atk": 66, "def": 56, "spd": 46, "moves": ["cleave", "skull_bash", "war_cry", "hook"], "hp_mult": 2.6},
}


static var _next_bid := 1


## A unique id per actor: animation state is keyed by it (actor
## Dictionaries change as HP changes, so they can't be keys themselves).
static func bid() -> int:
	_next_bid += 1
	return _next_bid


static func actor_from_creature(c: Dictionary, wild: bool = false) -> Dictionary:
	return {"bid": bid(),
		"kind": "creature", "name": Creatures.display_name(c).to_upper(), "level": int(c.level),
		"hp": int(c.hp), "max_hp": Creatures.max_hp(c), "atk": Creatures.stat(c, "atk"), "def": Creatures.stat(c, "def"),
		"spd": Creatures.stat(c, "spd"), "element": Creatures.element(c), "moves": c.get("moves", []).duplicate(),
		"stages": {}, "sprite": String(Creatures.species_data(c).get("sprite", c.species)), "ref": c, "wild": wild,
	}


static func actor_warrior() -> Dictionary:
	var p := Game.player
	return {"bid": bid(),
		"kind": "warrior", "name": String(p.name), "level": int(p.level), "hp": int(p.hp),
		"max_hp": Game.trainer_max_hp(), "atk": Game.trainer_stat("atk"), "def": Game.trainer_stat("def"),
		"spd": Game.trainer_stat("spd"), "element": "normal", "moves": ["strike"], "stages": {}, "sprite": "trainer",
		"guarding": false,
	}


static func actor_fighter(kind: String, fighter_name: String, level: int) -> Dictionary:
	var f: Dictionary = FIGHTERS.get(kind, FIGHTERS.gyria)
	var st := func(b: int) -> int: return int(b * 2 * level / 100.0) + 5
	var hp := int((int(f.hp) * 2 * level / 100.0 + level + 10) * float(f.hp_mult))
	return {"bid": bid(),
		"kind": "fighter", "name": fighter_name.to_upper(), "level": level, "hp": hp, "max_hp": hp,
		"atk": st.call(int(f.atk)), "def": st.call(int(f.def)), "spd": st.call(int(f.spd)), "element": "normal",
		"moves": (f.moves as Array).duplicate(), "stages": {}, "sprite": kind,
	}


static func stage_mult(stage: int) -> float:
	stage = clampi(stage, -6, 6)
	return (2.0 + stage) / 2.0 if stage >= 0 else 2.0 / (2.0 - stage)


static func stat(a: Dictionary, s: String) -> float:
	return float(a.get(s, 10)) * stage_mult(int(a.get("stages", {}).get(s, 0)))


## roll in [0.85, 1.0] (or -1 = random); crit 1/0 (or -1 = random).
static func damage(att: Dictionary, def: Dictionary, move: Dictionary, roll: float = -1.0, crit: int = -1) -> Dictionary:
	var power := float(move.get("power", 0))
	if power <= 0.0:
		return {"damage": 0, "mult": 1.0, "crit": false}
	var lvl := float(att.get("level", 5))
	var base := ((2.0 * lvl / 5.0 + 2.0) * power * stat(att, "atk") / maxf(stat(def, "def"), 1.0)) / 50.0 + 2.0
	var mel := String(move.get("element", "normal"))
	var mult := Data.element_mult(mel, String(def.get("element", "normal")))
	var stab := STAB if mel == String(att.get("element", "")) and mel != "normal" else 1.0
	var is_crit := (randf() < CRIT_CHANCE) if crit < 0 else crit == 1
	var r := randf_range(0.85, 1.0) if roll < 0.0 else roll
	var dmg := int(floor(base * mult * stab * r * (1.5 if is_crit else 1.0)))
	if bool(def.get("guarding", false)):
		dmg = int(dmg * 0.5)
	return {"damage": maxi(1, dmg) if mult > 0.0 else 0, "mult": mult, "crit": is_crit}


static func hits(move: Dictionary) -> bool:
	return randf() <= float(move.get("accuracy", 1.0))


static func capture_chance(wild: Dictionary, ring_bonus: float = 1.0) -> float:
	var rate := float(Creatures.species_data(wild).get("catch_rate", 0.45))
	var hp_frac := float(wild.hp) / float(maxi(1, Creatures.max_hp(wild)))
	return clampf(rate * (1.0 - 0.72 * hp_frac) * ring_bonus * 1.25, 0.05, 0.95)


static func run_chance(own_spd: float, wild_spd: float) -> float:
	return clampf(0.55 + (own_spd - wild_spd) / maxf(wild_spd, 1.0) * 0.4, 0.3, 0.98)


static func goes_first(a: Dictionary, move_a: Dictionary, b: Dictionary, move_b: Dictionary) -> bool:
	var pa := int(move_a.get("priority", 0))
	var pb := int(move_b.get("priority", 0))
	if pa != pb:
		return pa > pb
	var sa := stat(a, "spd")
	var sb := stat(b, "spd")
	if is_equal_approx(sa, sb):
		return randf() < 0.5
	return sa > sb


static func ai_move(a: Dictionary) -> String:
	var mv: Array = a.get("moves", [])
	if mv.is_empty():
		return "tackle"
	var attacks: Array = []
	for m in mv:
		if String(Data.move(String(m)).get("kind", "attack")) == "attack":
			attacks.append(m)
	if attacks.size() > 0 and randf() < 0.82:
		return String(attacks[randi() % attacks.size()])
	return String(mv[randi() % mv.size()])


## Enemies pick between your creature and your warrior (fighters prefer the warrior).
static func ai_target(enemy: Dictionary, creature_up: bool) -> String:
	if not creature_up:
		return "warrior"
	var p := 0.55 if String(enemy.kind) == "fighter" else 0.3
	return "warrior" if randf() < p else "creature"

extends Node
## Loads every data-driven definition (items, creatures, enemies, abilities,
## quests, dialogue, lore) so gameplay code can look them up by id.
## Add content by dropping new .tres/.json files into res://data/<kind>/.

const DIRS := {
	"items": "res://data/items",
	"creatures": "res://data/creatures",
	"enemies": "res://data/enemies",
	"abilities": "res://data/abilities",
	"quests": "res://data/quests",
	"attacks": "res://data/attacks",
}
const DIALOGUE_DIR := "res://data/dialogue"
const LORE_FILE := "res://data/lore/lore.json"

var items: Dictionary = {}
var creatures: Dictionary = {}
var enemies: Dictionary = {}
var abilities: Dictionary = {}
var quests: Dictionary = {}
var attacks: Dictionary = {}
var lore: Dictionary = {}
var _dialogue_cache: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	items = _load_resources(DIRS.items)
	creatures = _load_resources(DIRS.creatures)
	enemies = _load_resources(DIRS.enemies)
	abilities = _load_resources(DIRS.abilities)
	quests = _load_resources(DIRS.quests)
	attacks = _load_resources(DIRS.attacks)
	lore = _load_json(LORE_FILE)
	_dialogue_cache.clear()


func item(id) -> ItemDefinition:
	return items.get(String(id))


func creature(id) -> CreatureDefinition:
	return creatures.get(String(id))


func enemy(id) -> EnemyDefinition:
	return enemies.get(String(id))


func ability(id) -> AbilityDefinition:
	return abilities.get(String(id))


func quest(id) -> QuestDefinition:
	return quests.get(String(id))


func attack(id) -> AttackDefinition:
	return attacks.get(String(id))


func lore_entry(id) -> Dictionary:
	return lore.get(String(id), {})


func dialogue(id: String) -> Dictionary:
	if not _dialogue_cache.has(id):
		_dialogue_cache[id] = _load_json(DIALOGUE_DIR.path_join(id + ".json"))
	return _dialogue_cache[id]


func dialogue_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DIALOGUE_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out


func _load_resources(path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Database: missing folder " + path)
		return out
	for file_name in dir.get_files():
		# Exported builds list converted resources as *.remap.
		var clean := file_name.trim_suffix(".remap")
		if not (clean.ends_with(".tres") or clean.ends_with(".res")):
			continue
		var res: Resource = load(path.path_join(clean))
		if res == null or not ("id" in res):
			push_warning("Database: could not load " + clean)
			continue
		var key := String(res.get("id"))
		if key.is_empty():
			push_warning("Database: resource without id " + clean)
			continue
		out[key] = res
	return out


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Database: missing file " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Database: invalid JSON in " + path)
		return {}
	return parsed

extends Node
## Loads all JSON game data (creatures, moves, elements, items, quests,
## dialogue, tiles). Content lives in res://data so it can be edited without code.

var creatures: Dictionary = {}
var moves: Dictionary = {}
var elements: Dictionary = {}
var items: Dictionary = {}
var quests: Dictionary = {}
var dialogue: Dictionary = {}
var tiles: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	creatures = _strip(_load("res://data/creatures.json"))
	moves = _load("res://data/moves.json")
	elements = _load("res://data/elements.json")
	items = _load("res://data/items.json")
	quests = _load("res://data/quests.json")
	tiles = _load("res://art/tiles.json")
	dialogue.clear()
	var dir := DirAccess.open("res://data/dialogue")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				dialogue[f.get_basename()] = _load("res://data/dialogue/" + f)


func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Bad JSON in " + path)
	return {}


func _strip(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if not String(k).begins_with("_"):
			out[k] = d[k]
	return out


func creature(id: String) -> Dictionary:
	return creatures.get(id, {})


func move(id: String) -> Dictionary:
	return moves.get(id, {"name": id, "element": "normal", "power": 40, "accuracy": 1.0, "kind": "attack"})


func item(id: String) -> Dictionary:
	return items.get(id, {"name": id, "desc": "", "kind": "key", "price": 0})


func element_mult(attack: String, defend: String) -> float:
	var chart: Dictionary = elements.get("chart", {})
	var row: Dictionary = chart.get(attack, {})
	return float(row.get(defend, 1.0))


func element_name(e: String) -> String:
	return String(elements.get("names", {}).get(e, e.capitalize()))


func element_color(e: String) -> Color:
	return Color(String(elements.get("colors", {}).get(e, "#c8c0b0")))


func tile_index(tile_name: String) -> int:
	return int(tiles.get("tiles", {}).get(tile_name, 0))

extends Node
## Whole game state: the warrior (who fights in battles too), ring creatures
## (party = worn rings, vault = stored), bag, marks (money), flags, quests,
## where you are, and which trainers/items are done. Versioned JSON saves.

const SAVE_PATH := "user://velicia_gbc.json"
const BACKUP_PATH := "user://velicia_gbc.bak.json"
const SAVE_VERSION := 2
const MAX_PARTY := 3

var player := {}
var coins := 0
var inventory: Dictionary = {}
var party: Array = []
var vault: Array = []
var flags: Dictionary = {}
var quests: Dictionary = {}
var map_id := "home"
var tile := Vector2i(3, 4)
var facing := "down"
var respawn := {"map": "home", "x": 3, "y": 4}
var done: Dictionary = {}        # defeated trainers, taken items
var play_time := 0.0
var session_active := false


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	if session_active:
		play_time += delta


func reset() -> void:
	player = {"name": "WARDEN", "level": 3, "xp": Creatures.xp_for_level(3), "hp": 0, "weapon": 4}
	player.hp = trainer_max_hp()
	coins = 300
	inventory = {"binding_ring": 0, "tonic": 1}
	party = []
	vault = []
	flags = {}
	quests = {}
	map_id = "home"
	tile = Vector2i(3, 4)
	facing = "down"
	respawn = {"map": "home", "x": 3, "y": 4}
	done = {}
	play_time = 0.0


func new_game(player_name: String = "WARDEN") -> void:
	reset()
	player.name = player_name.to_upper().substr(0, 8)
	start_quest("emoria_watch")
	session_active = true


# ------------------------------------------------------------ the warrior

func trainer_max_hp() -> int:
	return 22 + int(player.level) * 5


func trainer_stat(s: String) -> int:
	var lvl := int(player.level)
	match s:
		"atk":
			return 7 + lvl * 2 + int(player.get("weapon", 4))
		"def":
			return 6 + lvl * 2
		"spd":
			return 8 + lvl * 2
	return 10


## Trainer XP; returns level-up count.
func trainer_gain_xp(amount: int) -> int:
	var ups := 0
	player.xp = int(player.xp) + amount
	while int(player.level) < 50 and int(player.xp) >= Creatures.xp_for_level(int(player.level) + 1):
		var old := trainer_max_hp()
		player.level = int(player.level) + 1
		player.hp = int(player.hp) + (trainer_max_hp() - old)
		ups += 1
	return ups


func heal_all() -> void:
	player.hp = trainer_max_hp()
	for c in party:
		Creatures.heal(c)
	Events.party_changed.emit()


func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)
	Events.coins_changed.emit()


# ------------------------------------------------------------ items

func give_item(id: String, count: int = 1) -> void:
	var it := Data.item(id)
	if it.get("kind", "") == "heart_vessel":
		player["vessels"] = int(player.get("vessels", 0)) + 1
		player.level = int(player.level) + 1
		player.hp = trainer_max_hp()
		return
	inventory[id] = int(inventory.get(id, 0)) + count
	Events.inventory_changed.emit()


func has_item(id: String, count: int = 1) -> bool:
	return int(inventory.get(id, 0)) >= count


func take_item(id: String, count: int = 1) -> bool:
	if not has_item(id, count):
		return false
	inventory[id] = int(inventory[id]) - count
	if int(inventory[id]) <= 0:
		inventory.erase(id)
	Events.inventory_changed.emit()
	return true


# ------------------------------------------------------------ creatures

func add_creature(c: Dictionary) -> String:
	if party.size() < MAX_PARTY:
		party.append(c)
		Events.party_changed.emit()
		return "party"
	vault.append(c)
	Events.party_changed.emit()
	return "vault"


func has_creature() -> bool:
	return not party.is_empty()


func first_able_index() -> int:
	for i in party.size():
		if not Creatures.is_fainted(party[i]):
			return i
	return -1


func heal_party() -> void:
	for c in party:
		Creatures.heal(c)
	Events.party_changed.emit()


# ------------------------------------------------------------ flags & quests

func set_flag(f: String, value: Variant = true) -> void:
	flags[f] = value
	Events.flag_set.emit(f)


func has_flag(f: String) -> bool:
	return bool(flags.get(f, false))


func quest_stages(id: String) -> Array:
	return Data.quests.get(id, {}).get("stages", [])


func start_quest(id: String) -> void:
	if quests.has(id):
		return
	quests[id] = {"stage": 0, "done": false}
	Events.quest_changed.emit(id)


func set_quest_stage(id: String, stage_id: String) -> void:
	if not quests.has(id):
		start_quest(id)
	var stages := quest_stages(id)
	for i in stages.size():
		if stages[i].id == stage_id:
			quests[id].stage = i
			Events.quest_changed.emit(id)
			return


func complete_quest(id: String) -> void:
	if not quests.has(id):
		quests[id] = {"stage": 0, "done": false}
	quests[id].done = true
	Events.quest_changed.emit(id)


func quest_stage_id(id: String) -> String:
	if not quests.has(id) or quests[id].done:
		return ""
	var stages := quest_stages(id)
	var i := int(quests[id].stage)
	return String(stages[i].id) if i < stages.size() else ""


func quest_active(id: String) -> bool:
	return quests.has(id) and not quests[id].done


func quest_done(id: String) -> bool:
	return quests.has(id) and quests[id].done


func current_objective() -> String:
	for id in ["emoria_watch", "first_bond", "kesh", "ilith_stone"]:
		if quest_active(id):
			var stages := quest_stages(id)
			var i := int(quests[id].stage)
			if i < stages.size():
				return String(stages[i].text)
	return ""


# ------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "player": player, "coins": coins, "inventory": inventory, "party": party,
		"vault": vault, "flags": flags, "quests": quests, "map": map_id, "tile": [tile.x, tile.y], "facing": facing,
		"respawn": respawn, "done": done, "play_time": play_time}


func from_dict(d: Dictionary) -> void:
	reset()
	player.merge(d.get("player", {}), true)
	for k in ["level", "xp", "hp", "weapon"]:
		player[k] = int(player.get(k, 0))
	coins = int(d.get("coins", 0))
	inventory = d.get("inventory", {})
	for k in inventory.keys():
		inventory[k] = int(inventory[k])
	party = d.get("party", [])
	vault = d.get("vault", [])
	for c in party + vault:
		for k in ["level", "xp", "hp", "bond", "uid"]:
			c[k] = int(c.get(k, 0))
	flags = d.get("flags", {})
	quests = d.get("quests", {})
	for q in quests.values():
		q.stage = int(q.get("stage", 0))
		q.done = bool(q.get("done", false))
	map_id = String(d.get("map", "home"))
	var t: Array = d.get("tile", [3, 4])
	tile = Vector2i(int(t[0]), int(t[1]))
	facing = String(d.get("facing", "down"))
	respawn = d.get("respawn", respawn)
	done = d.get("done", {})
	play_time = float(d.get("play_time", 0.0))


func save_game() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BACKUP_PATH))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	Events.game_saved.emit()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)


func load_game() -> bool:
	for path in [SAVE_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and int(parsed.get("version", 0)) >= SAVE_VERSION:
				from_dict(parsed)
				session_active = true
				return true
	return false


func delete_save() -> void:
	for path in [SAVE_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

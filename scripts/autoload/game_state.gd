extends Node
## The player's persistent progress: character, inventory, equipment,
## creatures and rings, quests, flags, reputation and world state.
## Everything here round-trips through to_dict()/from_dict() for saving.

const MAX_RING_SLOTS := 3
const GAME_SCENE := "res://scenes/game/game.tscn"
const MENU_SCENE := "res://scenes/main/main_menu.tscn"

const ATTRIBUTE_NAMES := {
	"vitality": "Vitality (+10 health)",
	"endurance": "Endurance (+8 stamina)",
	"strength": "Strength (+2 damage)",
}

const STARTING_ITEMS := {
	"guild_longsword": 1,
	"guild_leathers": 1,
	"healing_draught": 3,
	"apprentice_ring": 1,
	"training_ration": 2,
}

var player: Dictionary = {}
var inventory: Dictionary = {}
var equipment: Dictionary = {}
var creatures: Array[CreatureInstance] = []
## Each slot: { "ring": item_id }. Creatures reference slots by index.
var ring_slots: Array = []
var active_ring: int = 0
var next_creature_uid: int = 1
var quests: Dictionary = {}
var tracked_quest: String = ""
var flags: Dictionary = {}
var reputation: Dictionary = {}
var discovered: Array = []
var lore: Array = []
var world: Dictionary = {}
var respawn_point: String = "outpost_shrine"
var region: String = "hollow_march"
var play_time: float = 0.0
## Set while loading a save so the game scene restores the stored position.
var has_saved_position: bool = false
var saved_position: Vector3 = Vector3.ZERO
var saved_yaw: float = 0.0
var session_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	reset()


func _process(delta: float) -> void:
	if session_active:
		play_time += delta


func reset() -> void:
	player = {
		"level": 1,
		"xp": 0,
		"stat_points": 0,
		"attributes": {"vitality": 0, "endurance": 0, "strength": 0},
		"health": -1.0,
		"appearance": default_appearance(),
		"equipped_skill": "whirling_cut",
	}
	inventory = {}
	equipment = {"weapon": "", "armor": "", "trinket": ""}
	creatures = []
	ring_slots = []
	active_ring = 0
	next_creature_uid = 1
	quests = {}
	tracked_quest = ""
	flags = {}
	reputation = {"emoria_guild": 0, "gyria_clans": 0, "hollow_settlers": 0}
	discovered = []
	lore = []
	world = {"opened": [], "defeated": [], "collected": []}
	respawn_point = "outpost_shrine"
	region = "hollow_march"
	play_time = 0.0
	has_saved_position = false


static func default_appearance() -> Dictionary:
	return {"skin": 2, "hair": 1, "cloak": 0, "build": 1, "hair_style": 0}


# ---------------------------------------------------------------- Game flow

func start_new_game(appearance: Dictionary) -> void:
	reset()
	player.appearance = appearance.duplicate()
	for id in STARTING_ITEMS:
		inventory[id] = STARTING_ITEMS[id]
	equipment.weapon = "guild_longsword"
	equipment.armor = "guild_leathers"
	_remove_raw("guild_longsword", 1)
	_remove_raw("guild_leathers", 1)
	equip_ring("apprentice_ring")
	player.health = get_max_health()
	QuestManager.start_quest(&"the_emoria_watch", false)
	session_active = true
	get_tree().change_scene_to_file(GAME_SCENE)


func continue_game(slot: int = 0) -> bool:
	if not SaveManager.load_game(slot):
		return false
	session_active = true
	get_tree().change_scene_to_file(GAME_SCENE)
	return true


func quit_to_menu() -> void:
	session_active = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


# --------------------------------------------------------------- Character

func get_level() -> int:
	return int(player.level)


func xp_to_next() -> int:
	return int(100.0 * pow(get_level(), 1.4))


func add_xp(amount: int) -> void:
	player.xp = int(player.xp) + amount
	var leveled := false
	while int(player.xp) >= xp_to_next():
		player.xp = int(player.xp) - xp_to_next()
		player.level = get_level() + 1
		player.stat_points = int(player.stat_points) + 2
		leveled = true
		EventBus.level_up.emit(get_level())
		EventBus.notify.emit("Level up! You are now level %d. (+2 attribute points)" % get_level())
		for a in Database.abilities.values():
			if a.unlock_level == get_level():
				EventBus.notify.emit("New ability: " + a.display_name)
	if leveled:
		player.health = get_max_health()
		AudioManager.play_ui("level_up")
	EventBus.player_stats_changed.emit()


func attribute(attr_name: String) -> int:
	return int(player.attributes.get(attr_name, 0))


func spend_stat_point(attr_name: String) -> bool:
	if int(player.stat_points) <= 0 or not player.attributes.has(attr_name):
		return false
	player.stat_points = int(player.stat_points) - 1
	player.attributes[attr_name] = attribute(attr_name) + 1
	EventBus.player_stats_changed.emit()
	return true


func get_max_health() -> float:
	var trinket := Database.item(equipment.get("trinket", ""))
	var bonus := trinket.bonus_health if trinket else 0.0
	return 100.0 + attribute("vitality") * 10.0 + (get_level() - 1) * 6.0 + bonus


func get_max_stamina() -> float:
	var trinket := Database.item(equipment.get("trinket", ""))
	var bonus := trinket.bonus_stamina if trinket else 0.0
	return 100.0 + attribute("endurance") * 8.0 + bonus


func get_weapon() -> ItemDefinition:
	return Database.item(equipment.get("weapon", ""))


func get_weapon_damage() -> float:
	var w := get_weapon()
	var base := w.damage if w else 6.0
	return base + attribute("strength") * 2.0 + (get_level() - 1) * 1.0


func get_defense() -> float:
	var a := Database.item(equipment.get("armor", ""))
	return a.defense if a else 0.0


func has_ability(ability_id: String) -> bool:
	var a := Database.ability(ability_id)
	return a != null and get_level() >= a.unlock_level


func unlocked_abilities() -> Array:
	var out := []
	for a in Database.abilities.values():
		if get_level() >= a.unlock_level:
			out.append(a)
	return out


# --------------------------------------------------------------- Inventory

func add_item(id: String, count: int = 1, announce: bool = true) -> void:
	var def := Database.item(id)
	if def == null:
		push_warning("GameState: unknown item " + id)
		return
	inventory[id] = int(inventory.get(id, 0)) + count
	if announce:
		EventBus.notify.emit("Received: %s%s" % [def.display_name, " x%d" % count if count > 1 else ""])
	EventBus.item_collected.emit(StringName(id), count)
	EventBus.inventory_changed.emit()


func remove_item(id: String, count: int = 1) -> bool:
	if count_item(id) < count:
		return false
	_remove_raw(id, count)
	EventBus.inventory_changed.emit()
	return true


func _remove_raw(id: String, count: int) -> void:
	var n := int(inventory.get(id, 0)) - count
	if n <= 0:
		inventory.erase(id)
	else:
		inventory[id] = n


func count_item(id: String) -> int:
	return int(inventory.get(id, 0))


func equip_item(id: String) -> bool:
	var def := Database.item(id)
	if def == null:
		return false
	if def.type == ItemDefinition.ItemType.RING:
		return equip_ring(id)
	if not def.is_equippable() or count_item(id) <= 0:
		return false
	var slot := def.equip_slot()
	var previous: String = equipment.get(slot, "")
	_remove_raw(id, 1)
	if not previous.is_empty():
		inventory[previous] = count_item(previous) + 1
	equipment[slot] = id
	EventBus.inventory_changed.emit()
	EventBus.player_stats_changed.emit()
	return true


func unequip(slot: String) -> void:
	var current: String = equipment.get(slot, "")
	if current.is_empty():
		return
	equipment[slot] = ""
	inventory[current] = count_item(current) + 1
	EventBus.inventory_changed.emit()
	EventBus.player_stats_changed.emit()


func use_consumable(id: String, target_player: Node = null) -> bool:
	var def := Database.item(id)
	if def == null or def.type != ItemDefinition.ItemType.CONSUMABLE or count_item(id) <= 0:
		return false
	remove_item(id, 1)
	if target_player and target_player.has_method("apply_consumable"):
		target_player.apply_consumable(def)
	else:
		player.health = minf(float(player.health) + def.heal_amount, get_max_health())
	return true


# ------------------------------------------------------- Rings & creatures

func equip_ring(id: String) -> bool:
	var def := Database.item(id)
	if def == null or def.type != ItemDefinition.ItemType.RING:
		return false
	if ring_slots.size() >= MAX_RING_SLOTS or count_item(id) <= 0:
		return false
	_remove_raw(id, 1)
	ring_slots.append({"ring": id})
	EventBus.creatures_changed.emit()
	EventBus.inventory_changed.emit()
	return true


func ring_definition(slot: int) -> ItemDefinition:
	if slot < 0 or slot >= ring_slots.size():
		return null
	return Database.item(ring_slots[slot].ring)


func creature_in_slot(slot: int) -> CreatureInstance:
	for c in creatures:
		if c.ring_slot == slot:
			return c
	return null


func first_empty_ring(min_tier: int = 1) -> int:
	for i in ring_slots.size():
		var r := ring_definition(i)
		if creature_in_slot(i) == null and r and r.ring_tier >= min_tier:
			return i
	return -1


func find_creature(uid: int) -> CreatureInstance:
	for c in creatures:
		if c.uid == uid:
			return c
	return null


func add_captured_creature(def_id: String, level: int, slot: int, health_fraction: float = 1.0) -> CreatureInstance:
	var c := CreatureInstance.new()
	c.uid = next_creature_uid
	next_creature_uid += 1
	c.def_id = def_id
	c.level = level
	c.ring_slot = slot
	c.health = c.max_health() * clampf(health_fraction, 0.1, 1.0)
	creatures.append(c)
	EventBus.creatures_changed.emit()
	return c


## Moves a creature between a ring slot and the vault (-1). Rings hold one.
func move_creature(uid: int, slot: int) -> bool:
	var c := find_creature(uid)
	if c == null:
		return false
	if slot >= 0:
		if slot >= ring_slots.size() or creature_in_slot(slot) != null:
			return false
	c.ring_slot = slot
	EventBus.creatures_changed.emit()
	return true


func restore_all_creatures() -> void:
	for c in creatures:
		c.restore()
	EventBus.creatures_changed.emit()


# -------------------------------------------------- Flags, world & factions

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	EventBus.flag_changed.emit(StringName(flag))


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func add_reputation(faction: String, amount: int) -> void:
	reputation[faction] = int(reputation.get(faction, 0)) + amount
	EventBus.notify.emit("Reputation with %s %s%d" % [faction_name(faction), "+" if amount >= 0 else "", amount])


static func faction_name(faction: String) -> String:
	match faction:
		"emoria_guild":
			return "the Emoria Guild"
		"gyria_clans":
			return "the Gyria clans"
		"hollow_settlers":
			return "the Hollow settlers"
	return faction.capitalize()


func discover_location(id: String, display_name: String) -> bool:
	if id in discovered:
		return false
	discovered.append(id)
	set_flag("visited_" + id)
	EventBus.notify.emit("Discovered: " + display_name)
	EventBus.location_discovered.emit(StringName(id))
	add_xp(15)
	return true


func unlock_lore(id: String) -> bool:
	if id in lore:
		return false
	lore.append(id)
	var entry := Database.lore_entry(id)
	EventBus.notify.emit("Journal: " + String(entry.get("title", id)))
	EventBus.lore_unlocked.emit(StringName(id))
	return true


func mark_world(list_name: String, id: String) -> void:
	if not world.has(list_name):
		world[list_name] = []
	if not (id in world[list_name]):
		world[list_name].append(id)


func is_world_marked(list_name: String, id: String) -> bool:
	return id in world.get(list_name, [])


# ------------------------------------------------------------ Serialisation

func to_dict() -> Dictionary:
	var creature_dicts := []
	for c in creatures:
		creature_dicts.append(c.to_dict())
	return {
		"player": player.duplicate(true),
		"inventory": inventory.duplicate(),
		"equipment": equipment.duplicate(),
		"creatures": creature_dicts,
		"ring_slots": ring_slots.duplicate(true),
		"active_ring": active_ring,
		"next_creature_uid": next_creature_uid,
		"quests": quests.duplicate(true),
		"tracked_quest": tracked_quest,
		"flags": flags.duplicate(true),
		"reputation": reputation.duplicate(),
		"discovered": discovered.duplicate(),
		"lore": lore.duplicate(),
		"world": world.duplicate(true),
		"respawn_point": respawn_point,
		"region": region,
		"play_time": play_time,
		"position": [saved_position.x, saved_position.y, saved_position.z],
		"yaw": saved_yaw,
	}


func from_dict(d: Dictionary) -> void:
	reset()
	var p: Dictionary = d.get("player", {})
	for key in p:
		player[key] = p[key]
	# JSON turns ints into floats; normalise the important ones.
	player.level = int(player.level)
	player.xp = int(player.xp)
	player.stat_points = int(player.stat_points)
	for key in player.attributes:
		player.attributes[key] = int(player.attributes[key])
	var appearance: Dictionary = player.get("appearance", {})
	for key in appearance:
		appearance[key] = int(appearance[key])
	inventory = {}
	var inv: Dictionary = d.get("inventory", {})
	for key in inv:
		if Database.item(key) != null:
			inventory[key] = int(inv[key])
	var eq: Dictionary = d.get("equipment", {})
	for key in equipment:
		equipment[key] = String(eq.get(key, ""))
	creatures = []
	for cd in d.get("creatures", []):
		var c := CreatureInstance.from_dict(cd)
		if c.definition() != null:
			creatures.append(c)
	ring_slots = []
	for r in d.get("ring_slots", []):
		ring_slots.append({"ring": String(r.get("ring", "apprentice_ring"))})
	active_ring = int(d.get("active_ring", 0))
	next_creature_uid = int(d.get("next_creature_uid", creatures.size() + 1))
	quests = {}
	var q: Dictionary = d.get("quests", {})
	for key in q:
		var entry: Dictionary = q[key]
		var progress := []
		for v in entry.get("progress", []):
			progress.append(int(v))
		quests[key] = {"stage": int(entry.get("stage", 0)), "progress": progress, "status": String(entry.get("status", "active"))}
	tracked_quest = String(d.get("tracked_quest", ""))
	flags = d.get("flags", {})
	var rep: Dictionary = d.get("reputation", {})
	for key in rep:
		reputation[key] = int(rep[key])
	discovered = d.get("discovered", [])
	lore = d.get("lore", [])
	var w: Dictionary = d.get("world", {})
	for key in w:
		world[key] = w[key]
	respawn_point = String(d.get("respawn_point", "outpost_shrine"))
	region = String(d.get("region", "hollow_march"))
	play_time = float(d.get("play_time", 0.0))
	var pos: Array = d.get("position", [])
	if pos.size() == 3:
		saved_position = Vector3(pos[0], pos[1], pos[2])
		saved_yaw = float(d.get("yaw", 0.0))
		has_saved_position = true
	EventBus.inventory_changed.emit()
	EventBus.creatures_changed.emit()
	EventBus.player_stats_changed.emit()

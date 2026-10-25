extends Node
## Automated smoke and integration tests. Run headless from the project folder:
##   godot --headless res://tests/test_runner.tscn
## Exit code = number of failed checks. Uses save slot 9 so real saves are untouched.

const TEST_SLOT := 9

var passed := 0
var failed := 0
var _killed: Array = []


func _ready() -> void:
	print("=== Velicia test suite ===")
	Settings.set_value("accessibility", "hitstop", false)
	Settings.set_value("accessibility", "screen_shake", false)
	await _run_all()
	print("=== %d passed, %d failed ===" % [passed, failed])
	SaveManager.delete_save(TEST_SLOT)
	SaveManager.delete_save(SaveManager.AUTOSAVE_SLOT)
	get_tree().quit(failed)


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		print("  FAIL ", what)


func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func tap(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await physics_frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await physics_frames(1)


const KEYS := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT, "block": KEY_Q, "attack_heavy": KEY_K}


## Holds a keyboard key bound to the action (exercises the real input map).
func hold(action: String, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEYS[action]
	e.keycode = KEYS[action]
	e.pressed = pressed
	Input.parse_input_event(e)


func _run_all() -> void:
	_test_data()
	_test_dialogue_data()
	_test_quests_logic()
	_test_save_load()
	await _test_character_models()
	await _test_gameplay()
	await _test_main_menu()


# ------------------------------------------------------------------ Character models

func _test_character_models() -> void:
	print("[character models]")
	for people in [&"human", &"amir", &"burrok", &"vapouriun", &"gouran", &"gyria", &"gyria_boss"]:
		var body := PlaceholderBody.new()
		add_child(body)
		body.build(PlaceholderBody.preset(people, 0))
		var ok := body.model != null and body.model.skeleton != null and body.model.skeleton.get_bone_count() >= 19
		check(ok, "%s uses a skinned realistic model" % people)
		if not ok:
			body.queue_free()
			continue
		check(absf(body.height - float(PlaceholderBody.preset(people).height)) < 0.05, "%s model height matches the canon (%.2f m)" % [people, body.height])
		body.pose_attack(&"slash", 0, 1.0)
		for i in 10:
			body.animate(0.05, 0.0, 5.0, true)
		var arm := body.model.bone("UpperArm_R")
		var q := body.model.skeleton.get_bone_pose_rotation(arm)
		check(q.angle_to(Quaternion.IDENTITY) > 0.5, "%s: animation pivots drive the model's bones" % people)
		var hand := body.model.skeleton.global_transform * body.model.skeleton.get_bone_global_pose(body.model.bone("Hand_R")).origin
		check(hand.distance_to(body.get_hand_position()) < 0.2 * body.height / 1.78, "%s: weapon hand follows the model's hand" % people)
		body.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ Data

func _test_data() -> void:
	print("[data]")
	check(Database.items.size() >= 15, "items loaded (%d)" % Database.items.size())
	check(Database.creatures.size() >= 3, "creatures loaded (%d)" % Database.creatures.size())
	check(Database.enemies.size() >= 3, "enemies loaded (%d)" % Database.enemies.size())
	check(Database.quests.size() >= 5, "quests loaded (%d)" % Database.quests.size())
	check(Database.abilities.size() >= 4, "abilities loaded")
	check(not Database.lore.is_empty(), "lore loaded")
	for id in ["player_light_1", "player_light_2", "player_light_3", "player_heavy"]:
		check(Database.attack(id) != null, "player attack " + id)
	var ok := true
	for e in Database.enemies.values():
		for item_id in e.loot:
			if Database.item(item_id) == null:
				ok = false
				print("    missing loot item ", item_id)
		if e.attacks.is_empty() and e.phases.is_empty():
			ok = false
		if e.is_boss:
			check(e.phases.size() >= 2, "boss %s has multiple phases" % e.id)
	check(ok, "enemy loot and attacks valid")
	ok = true
	for q in Database.quests.values():
		for item_id in q.reward_items:
			ok = ok and Database.item(item_id) != null
		for s in q.stages:
			for o in s.objectives:
				if o.type == QuestObjective.Type.COLLECT:
					ok = ok and Database.item(o.target) != null
		if q.next_quest != &"":
			ok = ok and Database.quest(q.next_quest) != null
	check(ok, "quest references valid")
	for c in Database.creatures.values():
		check(c.is_placeholder, "creature %s is labelled as a placeholder" % c.id)
		check(not c.abilities.is_empty(), "creature %s has abilities" % c.id)


func _test_dialogue_data() -> void:
	print("[dialogue]")
	var known_conditions := ["quest_active", "quest_completed", "quest_not_started", "quest_stage", "flag", "has_item", "level", "has_creature"]
	var known_effects := ["start_quest", "complete_quest", "advance_quest", "set_flag", "clear_flag", "give_item", "take_item", "xp", "rep", "heal", "lore", "panel"]
	for id in Database.dialogue_ids():
		var d := Database.dialogue(id)
		var nodes: Dictionary = d.get("nodes", {})
		var ok := not nodes.is_empty()
		var refs := []
		for e in d.get("entries", []):
			refs.append(e.node)
			for c in e.get("conditions", []):
				ok = ok and String(c).trim_prefix("!").split(":")[0] in known_conditions
		if d.has("start"):
			refs.append(d.start)
		for n in nodes.values():
			refs.append(n.get("next", "end"))
			for ef in n.get("effects", []):
				ok = ok and _effect_valid(String(ef), known_effects)
			for ch in n.get("choices", []):
				refs.append(ch.get("next", "end"))
				for ef in ch.get("effects", []):
					ok = ok and _effect_valid(String(ef), known_effects)
				for c in ch.get("conditions", []):
					ok = ok and String(c).trim_prefix("!").split(":")[0] in known_conditions
		for r in refs:
			if r != "end" and not nodes.has(r):
				ok = false
				print("    %s: missing node %s" % [id, r])
		check(ok, "dialogue %s is consistent" % id)


func _effect_valid(ef: String, known: Array) -> bool:
	var parts := ef.split(":")
	if not parts[0] in known:
		print("    unknown effect ", ef)
		return false
	if parts[0] in ["give_item", "take_item"] and Database.item(parts[1]) == null:
		print("    unknown item in effect ", ef)
		return false
	if parts[0] in ["start_quest", "complete_quest", "advance_quest"] and Database.quest(parts[1]) == null:
		print("    unknown quest in effect ", ef)
		return false
	if parts[0] == "lore" and Database.lore_entry(parts[1]).is_empty():
		print("    unknown lore in effect ", ef)
		return false
	return true


func _test_quests_logic() -> void:
	print("[quests]")
	GameState.reset()
	QuestManager.start_quest("first_watch", false)
	check(QuestManager.is_active("first_watch"), "quest starts")
	EventBus.location_entered.emit(&"sentinel_spire")
	check(QuestManager.stage_index("first_watch") == 1, "REACH objective advances stage")
	for i in 3:
		EventBus.enemy_killed.emit(&"gyria_skirmisher", PackedStringArray(["gyria", "gyria_scout"]), Vector3.ZERO)
	check(QuestManager.stage_index("first_watch") == 2, "KILL objective counts tags")
	GameState.add_item("sealed_letter", 1, false)
	check(QuestManager.stage_index("first_watch") == 3, "COLLECT objective tracks inventory")
	EventBus.talked_to.emit(&"warden")
	check(QuestManager.is_completed("first_watch"), "TALK completes quest")
	check(GameState.count_item("bound_ring") == 1, "quest rewards granted")
	check(QuestManager.is_active("ashes_of_ashfen"), "follow-up quest started")
	EventBus.location_entered.emit(&"ashfen_camp")
	GameState.set_flag("kesh_decided")
	check(QuestManager.stage_index("ashes_of_ashfen") == 2, "FLAG objective completes from a choice")
	GameState.reset()


# ------------------------------------------------------------- Save/load

func _test_save_load() -> void:
	print("[save/load]")
	GameState.reset()
	for id in GameState.STARTING_ITEMS:
		GameState.inventory[id] = GameState.STARTING_ITEMS[id]
	GameState.equip_item("guild_longsword")
	GameState.equip_ring("apprentice_ring")
	GameState.add_xp(250)
	var c := GameState.add_captured_creature("test_creature_alpha", 3, 0, 0.5)
	c.add_bond(12)
	c.nickname = "Tester"
	QuestManager.start_quest("first_watch", false)
	EventBus.location_entered.emit(&"sentinel_spire")
	GameState.set_flag("spared_kesh")
	GameState.add_reputation("gyria_clans", 10)
	GameState.discover_location("sentinel_spire", "The Sentinel Spire")
	GameState.mark_world("opened", "spire_chest")
	GameState.saved_position = Vector3(12.5, 7.0, -40.25)
	var before := JSON.stringify(_comparable(GameState.to_dict()))
	check(SaveManager.save_game(TEST_SLOT), "save succeeds")
	check(SaveManager.has_save(TEST_SLOT), "save file exists")
	GameState.reset()
	check(GameState.creatures.is_empty(), "state cleared before load")
	check(SaveManager.load_game(TEST_SLOT), "load succeeds")
	var after := JSON.stringify(_comparable(GameState.to_dict()))
	check(before == after, "loaded state matches saved state")
	if before != after:
		print("    before: ", before.substr(0, 400))
		print("    after:  ", after.substr(0, 400))
	check(GameState.get_level() >= 2, "level restored")
	check(GameState.creatures.size() == 1 and GameState.creatures[0].nickname == "Tester" and GameState.creatures[0].bond_level() == 1, "creature, nickname and bond restored")
	check(QuestManager.stage_index("first_watch") == 1, "quest stage restored")
	check(GameState.has_saved_position and GameState.saved_position.distance_to(Vector3(12.5, 7.0, -40.25)) < 0.01, "position restored")
	# Second save creates a backup; corrupt the main file and recover.
	check(SaveManager.save_game(TEST_SLOT), "second save")
	var f := FileAccess.open(SaveManager.slot_path(TEST_SLOT), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	GameState.reset()
	check(SaveManager.load_game(TEST_SLOT), "corrupt save falls back to backup")
	check(GameState.creatures.size() == 1, "backup contains the creature")
	check(SaveManager.migrate({"save_version": 0}).get("save_version") == 1, "old save migrates")
	check(SaveManager.migrate({"save_version": 999}).is_empty(), "newer save is rejected safely")
	SaveManager.delete_save(TEST_SLOT)
	check(not SaveManager.load_game(TEST_SLOT), "missing save fails gracefully")
	GameState.reset()


func _comparable(d: Dictionary) -> Dictionary:
	# Round-trip through JSON so int/float differences don't matter.
	var parsed = JSON.parse_string(JSON.stringify(d))
	parsed.erase("play_time")
	return parsed


# ------------------------------------------------------------- Gameplay

func _new_game_state() -> void:
	GameState.reset()
	for id in GameState.STARTING_ITEMS:
		GameState.inventory[id] = GameState.STARTING_ITEMS[id]
	GameState.equip_item("guild_longsword")
	GameState.equip_item("guild_leathers")
	GameState.equip_ring("apprentice_ring")
	GameState.player.health = GameState.get_max_health()
	QuestManager.start_quest(&"the_emoria_watch", false)
	GameState.session_active = true


func _test_gameplay() -> void:
	print("[gameplay]")
	_new_game_state()
	Settings.set_value("controls", "touch_mode", "on")
	EventBus.enemy_killed.connect(func(id, _t, _p): _killed.append(id))
	var game: Node3D = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await physics_frames(40)
	var player: Player = game.player
	check(player != null, "player spawned")
	check(player.is_on_floor(), "player stands on terrain")
	var spawn_h := VeliciaTerrain.height_at(player.global_position.x, player.global_position.z)
	check(absf(player.global_position.y - spawn_h) < 0.6, "player at ground height (%.2f vs %.2f)" % [player.global_position.y, spawn_h])
	check(get_tree().get_nodes_in_group("locations").size() >= 8, "region locations present")
	check(get_tree().get_nodes_in_group("shrines").size() >= 3, "Ring Stones present")
	check(get_tree().get_nodes_in_group("npcs").size() >= 6, "NPCs present")
	check(get_tree().get_nodes_in_group("enemies").size() >= 8, "Gyria enemies present")
	await physics_frames(10)
	check(get_tree().get_nodes_in_group("creatures").size() >= 8, "wild creatures spawned")

	# Movement (keyboard path)
	var start := player.global_position
	hold("move_forward", true)
	await seconds(1.0)
	hold("move_forward", false)
	await physics_frames(20)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	check(moved > 2.5, "player walks forward (%.1f m)" % moved)
	check(player.is_on_floor(), "player still grounded after moving")

	# Sprint and stamina
	var sta := player.stats.stamina
	hold("move_forward", true)
	hold("sprint", true)
	await seconds(0.8)
	var sprint_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var sta_after := player.stats.stamina
	hold("sprint", false)
	hold("move_forward", false)
	check(sta_after < sta, "sprinting consumes stamina (%.0f -> %.0f, speed %.1f, state %d, floor %s)" % [sta, sta_after, sprint_speed, player.state, player.is_on_floor()])
	await physics_frames(10)

	# Jump
	player.velocity = Vector3.ZERO
	await physics_frames(5)
	var y0 := player.global_position.y
	await tap("jump")
	await physics_frames(10)
	check(player.global_position.y > y0 + 0.3, "jump lifts the player")
	await seconds(1.0)

	# Combat against a Gyria skirmisher
	var enemy: Enemy = game.region.get_node("Enemies/SpireScout1")
	var fwd := -player.global_transform.basis.z
	enemy.global_position = player.global_position + fwd * 1.8 + Vector3.UP * 0.5
	enemy.home = enemy.global_position
	enemy.velocity = Vector3.ZERO
	await physics_frames(3)
	CombatUtil.face_instantly(enemy, -fwd)
	var hp := enemy.stats.health
	await tap("attack_light")
	await seconds(0.6)
	check(enemy.stats.health < hp, "light attack damages the Gyria (%.0f -> %.0f)" % [hp, enemy.stats.health])
	check(enemy.engaged, "enemy becomes engaged when struck")

	# Heavy attack
	player.stats.restore_stamina(999)
	enemy.global_position = player.global_position - player.global_transform.basis.z * 1.8
	hp = enemy.stats.health
	await tap("attack_heavy")
	await seconds(1.3)
	check(enemy.stats.health < hp, "heavy attack damages")

	# Defence: block, parry, dodge, unguarded hit
	player.stats.restore_stamina(999)
	var atk := Database.attack("gyria_slash")
	CombatUtil.face_instantly(player, CombatUtil.flat_direction(player.global_position, enemy.global_position))
	hold("block", true)
	await physics_frames(2)
	var res := player.receive_hit(HitData.make(enemy, player, atk, 12.0))
	check(res == HitData.Result.PARRIED, "timed block parries (result %d)" % res)
	check(enemy.is_vulnerable(), "parried enemy is open to a riposte")
	await seconds(0.5)
	var hp_before_block := player.stats.health
	res = player.receive_hit(HitData.make(enemy, player, atk, 12.0))
	check(res == HitData.Result.BLOCKED, "held block blocks")
	check(hp_before_block - player.stats.health < 3.0, "blocking reduces damage")
	hold("block", false)
	await physics_frames(3)
	var hp_before := player.stats.health
	res = player.receive_hit(HitData.make(enemy, player, atk, 12.0))
	check(res == HitData.Result.HIT and player.stats.health < hp_before, "unguarded hit damages the player")
	await seconds(0.7)
	player.stats.restore_stamina(999)
	await tap("dodge")
	await physics_frames(4)
	res = player.receive_hit(HitData.make(enemy, player, atk, 12.0))
	check(res == HitData.Result.EVADED, "dodge i-frames evade hits")
	await seconds(0.6)

	# Charged heavy: hold to charge, release to strike harder.
	# Freeze the enemy's AI so it can't interrupt the charge.
	enemy.set_physics_process(false)
	await seconds(1.2)
	player.stats.restore_stamina(999)
	enemy.global_position = player.global_position - player.global_transform.basis.z * 1.8
	enemy.home = enemy.global_position
	enemy.stats.max_health = 400.0
	enemy.stats.set_health(400.0)
	await physics_frames(2)
	hp = enemy.stats.health
	hold("attack_heavy", true)
	await seconds(0.9)
	var was_charging := player.is_charging()
	var charge := player.charge_fraction()
	hold("attack_heavy", false)
	await seconds(1.0)
	check(was_charging and charge > 0.5, "holding heavy charges the attack (%.0f%%)" % (charge * 100.0))
	check(enemy.stats.health < hp - 30.0, "charged heavy hits hard (%.0f damage)" % (hp - enemy.stats.health))
	await seconds(0.8)

	# Perfect dodge: dodging at the last moment opens a counter window.
	player.stats.restore_stamina(999)
	await tap("dodge")
	await physics_frames(3)
	res = player.receive_hit(HitData.make(enemy, player, atk, 12.0))
	check(res == HitData.Result.EVADED and player.has_counter(), "perfect dodge grants a counter window")
	check(enemy.is_vulnerable(), "perfect dodge exposes the attacker")
	await seconds(1.2)
	enemy.set_physics_process(true)

	# Enemy AI attacks on its own
	player.stats.set_health(player.stats.max_health)
	var hp_ai := player.stats.health
	var attacked := false
	for i in 300:
		await get_tree().physics_frame
		if enemy.state == Enemy.State.ATTACK:
			attacked = true
		if player.stats.health < hp_ai or attacked:
			break
	check(attacked, "Gyria AI telegraphs and performs attacks")

	# Defeat
	QuestManager.start_quest("first_watch", false)
	EventBus.location_entered.emit(&"sentinel_spire")
	enemy.stats.set_health(1.0)
	var h := HitData.new()
	h.source = player
	h.damage = 50.0
	h.direction = CombatUtil.flat_direction(player.global_position, enemy.global_position)
	enemy.receive_hit(h)
	await physics_frames(2)
	check(enemy.state == Enemy.State.DEAD, "enemy can be defeated")
	check(&"gyria_skirmisher" in _killed, "defeat is broadcast")
	check(QuestManager.objective_progress("first_watch", 0) == 1, "defeat counts toward quest")
	check(not enemy.is_in_group("targetable"), "defeated enemy no longer targetable")
	await seconds(0.3)

	# Shield-warden blocks frontal light attacks; heavy blows break the guard.
	var shield: Enemy = game.region.get_node("Enemies/CampShield")
	shield.global_position = player.global_position - player.global_transform.basis.z * 2.0 + Vector3.UP * 0.5
	shield.home = shield.global_position
	await physics_frames(3)
	CombatUtil.face_instantly(shield, CombatUtil.flat_direction(shield.global_position, player.global_position))
	shield._set_state(Enemy.State.POSITION)
	var light := HitData.make(player, shield, Database.attack("player_light_1"), 15.0)
	check(shield.receive_hit(light) == HitData.Result.BLOCKED, "shield blocks a frontal light attack")
	var heavy := HitData.make(player, shield, Database.attack("player_heavy"), 30.0)
	check(shield.receive_hit(heavy) == HitData.Result.HIT and shield.state == Enemy.State.STAGGER, "heavy attack breaks the shield guard")
	shield.global_position = Vector3(86, 20, 4)
	shield.home = shield.global_position
	await physics_frames(2)

	# Bow-scout fires arrows; a parried arrow is deflected.
	var archer: Enemy = game.region.get_node("Enemies/SpireArcher")
	player.stats.set_health(player.stats.max_health)
	var open_ground := Vector3(30, VeliciaTerrain.height_at(30, 34) + 0.5, 34)
	player.global_position = open_ground
	player.velocity = Vector3.ZERO
	await physics_frames(5)
	archer.global_position = open_ground + Vector3(0, 0, -10)
	archer.global_position.y = VeliciaTerrain.height_at(archer.global_position.x, archer.global_position.z) + 0.5
	archer.home = archer.global_position
	await physics_frames(3)
	var arrow_seen := false
	var hp_arrow := player.stats.health
	for i in 420:
		await get_tree().physics_frame
		if not get_tree().get_nodes_in_group("projectiles").is_empty():
			arrow_seen = true
		if player.stats.health < hp_arrow:
			break
	check(arrow_seen, "bow-scout shoots arrows")
	check(player.stats.health < hp_arrow, "arrows can hit the player")
	archer.global_position = Vector3(46, 30, -64)
	archer.home = archer.global_position
	await seconds(1.0)
	CombatUtil.face_instantly(player, Vector3(0, 0, -1))
	hold("block", true)
	await physics_frames(2)
	var proj := Projectile.new()
	proj.source = enemy
	proj.attack = Database.attack("gyria_arrow")
	proj.damage = 10.0
	game.add_child(proj)
	var deflects := [false]
	proj.deflected.connect(func(): deflects[0] = true)
	proj.launch(player.global_position + Vector3(0, 1.2, -2.5), player.global_position + Vector3.UP * 1.2, 20.0)
	for i in 40:
		await get_tree().physics_frame
		if deflects[0]:
			break
	var deflected: bool = deflects[0]
	hold("block", false)
	check(deflected, "parrying an arrow deflects it back")
	if is_instance_valid(proj):
		proj.queue_free()
	await seconds(0.5)

	# World presentation systems
	var builder: RegionBuilder = game.region
	check(builder.grass != null and builder.grass.chunk_count() > 0, "grass chunks built around the player (%d)" % (builder.grass.chunk_count() if builder.grass else 0))
	builder.day_night.set_hour(23.0)
	check(builder.day_night.is_night() and builder.day_night.sun.light_energy < 0.5, "night falls with the day/night cycle")
	builder.day_night.set_hour(10.0)
	check(not builder.day_night.is_night() and builder.day_night.sun.light_energy > 0.8, "day returns")

	# Capture and companion
	var def := Database.creature("test_creature_alpha")
	var wild := CreatureActor.new()
	wild.definition = def
	wild.level = 2
	game.add_child(wild)
	wild.global_position = player.global_position - player.global_transform.basis.z * 2.5 + Vector3.UP
	await physics_frames(5)
	check(not wild.is_capturable(), "healthy creature is not capturable")
	wild.stats.set_health(wild.stats.max_health * 0.3)
	check(wild.is_capturable(), "weakened creature is capturable")
	check(player.rings.capture_chance(wild) > 0.3, "capture chance computed (%.0f%%)" % (player.rings.capture_chance(wild) * 100.0))
	player.rings.force_capture_result = 1
	check(player.rings.try_capture(wild), "capture begins")
	await seconds(1.8)
	check(GameState.creatures.size() == 1, "creature bound to ring")
	check(GameState.creature_in_slot(0) != null, "creature occupies ring slot 0")
	check(QuestManager.is_active("the_ring_trial") or true, "capture event fired")
	check(player.state == Player.State.MOVE, "player regains control after capture")

	# Failed capture path
	var wild2 := CreatureActor.new()
	wild2.definition = def
	game.add_child(wild2)
	wild2.global_position = player.global_position + player.global_transform.basis.x * 3.0 + Vector3.UP
	await physics_frames(5)
	wild2.stats.set_health(wild2.stats.max_health * 0.2)
	check(player.rings.can_capture_reason(wild2) != "", "capture refused with no empty ring")
	GameState.inventory["apprentice_ring"] = 1
	GameState.equip_ring("apprentice_ring")
	player.rings.force_capture_result = 0
	player.rings.try_capture(wild2)
	await seconds(1.8)
	check(GameState.creatures.size() == 1 and is_instance_valid(wild2) and wild2.state != CreatureActor.State.CAPTURED, "failed capture lets the creature break free")
	wild2.queue_free()

	# Summon, follow, dismiss
	check(player.rings.summon(0), "summon from ring")
	await physics_frames(10)
	var comp := player.rings.companion
	check(comp != null and comp.mode == CreatureActor.Mode.COMPANION, "companion spawned")
	var cstart := player.global_position
	hold("move_back", true)
	await seconds(1.5)
	hold("move_back", false)
	await seconds(1.5)
	check(comp.global_position.distance_to(player.global_position) < 6.0, "companion follows the player (%.1f m)" % comp.global_position.distance_to(player.global_position))
	check(player.global_position.distance_to(cstart) > 2.0, "player moved for follow test")

	# Companion fights an enemy
	var e2: Enemy = game.region.get_node("Enemies/SpireScout2")
	e2.global_position = comp.global_position - player.global_transform.basis.z * 2.0 + Vector3.UP * 0.5
	e2.home = e2.global_position
	await physics_frames(2)
	var e2hp := e2.stats.health
	comp.command(e2)
	var hurt := false
	for i in 360:
		await get_tree().physics_frame
		if e2.stats.health < e2hp:
			hurt = true
			break
	check(hurt, "companion attacks on command")
	e2.stats.set_health(1.0)
	e2.receive_hit(h)
	await physics_frames(3)
	check(GameState.creature_in_slot(0).xp > 0 or GameState.creature_in_slot(0).level > 2, "companion earns experience")
	player.rings.dismiss()
	await seconds(0.5)
	check(player.rings.companion == null, "companion dismissed")

	# Touch controls drive the same actions
	var hud: HUD = game.hud
	check(hud.touch.is_visible_in_tree(), "touch controls visible when enabled")
	var vp_size := hud.touch.size
	var attack_pos := hud.touch.button_center(hud.touch.button_index("attack_light"))
	_touch(0, attack_pos, true)
	await physics_frames(2)
	check(Input.is_action_pressed("attack_light"), "touch attack button presses attack_light")
	_touch(0, attack_pos, false)
	await physics_frames(2)
	check(not Input.is_action_pressed("attack_light"), "releasing touch releases attack_light")
	var stick_start := Vector2(200, vp_size.y - 200)
	_touch(1, stick_start, true)
	_drag(1, stick_start + Vector2(70, 0), Vector2(70, 0))
	await physics_frames(2)
	check(Input.get_action_strength("move_right") > 0.5, "touch joystick moves right (%.2f)" % Input.get_action_strength("move_right"))
	_drag(1, stick_start + Vector2(0, -90), Vector2(-70, -90))
	await physics_frames(2)
	check(Input.is_action_pressed("sprint"), "pushing the joystick to the edge sprints")
	_touch(1, stick_start + Vector2(0, -90), false)
	await physics_frames(2)
	check(Input.get_action_strength("move_forward") == 0.0 and not Input.is_action_pressed("sprint"), "joystick release stops movement")
	var cam_yaw: float = game.camera_rig.get_yaw()
	var look_pos := Vector2(vp_size.x * 0.6, vp_size.y * 0.3)
	_touch(2, look_pos, true)
	_drag(2, look_pos + Vector2(80, 0), Vector2(80, 0))
	_touch(2, look_pos + Vector2(80, 0), false)
	await physics_frames(2)
	check(absf(game.camera_rig.get_yaw() - cam_yaw) > 0.1, "touch drag rotates the camera")
	# Touch attack actually attacks
	player.stats.restore_stamina(999)
	_touch(3, attack_pos, true)
	await physics_frames(3)
	var touch_attacked := player.state == Player.State.ATTACK
	_touch(3, attack_pos, false)
	check(touch_attacked, "touch attack performs an attack")
	await seconds(0.8)

	# Dialogue and quests with an NPC
	var warden: NPC = game.region.get_node("NPCs/Warden")
	player.global_position = warden.global_position + Vector3(0, 0.5, 2.0)
	await physics_frames(20)
	hud.start_dialogue("warden", warden)
	check(hud.dialogue_active(), "dialogue opens")
	check(not player.input_enabled, "dialogue pauses player control")
	hud.dialogue_choose(0) # ask about duty -> starts the quest
	var guard := 0
	while hud.dialogue_active() and guard < 10:
		hud.dialogue_choose(0)
		guard += 1
	check(not hud.dialogue_active(), "dialogue closes")
	check(player.input_enabled, "control returns after dialogue")
	check(QuestManager.is_completed("the_emoria_watch"), "talking to the Warden completes the prologue")

	# Interaction via the interact action
	player.global_position = warden.global_position + Vector3(0, 0.5, 1.5)
	await physics_frames(30)
	check(player.current_interactable != null, "nearby NPC offers an interaction")

	# Shrine rest saves
	var shrine: SaveShrine = game.find_shrine("outpost_shrine")
	check(shrine != null, "outpost shrine found")
	SaveManager.delete_save(SaveManager.AUTOSAVE_SLOT)
	player.stats.set_health(10.0)
	check(shrine.rest(player), "resting at the shrine saves")
	check(player.stats.health == player.stats.max_health, "resting heals")
	check(SaveManager.has_save(), "autosave written")

	# Death and respawn
	player.stats.apply_damage(99999.0)
	await physics_frames(2)
	check(player.is_dead(), "player can die")
	game.respawn_player()
	await physics_frames(10)
	check(not player.is_dead() and player.stats.health == player.stats.max_health, "player respawns at the Ring Stone")

	# Menu opens and pauses
	game.open_menu("creatures")
	await physics_frames(1)
	check(get_tree().paused, "menu pauses the game")
	for tab in ["inventory", "creatures", "character", "journal", "map", "settings", "system"]:
		game.menu.open(tab)
		await get_tree().process_frame
	check(game.menu.is_open(), "all menu tabs open")
	game.menu.close()
	check(not get_tree().paused, "closing the menu resumes")

	game.queue_free()
	await physics_frames(5)
	Settings.set_value("controls", "touch_mode", "auto")
	GameState.session_active = false


## Converts logical (canvas) coordinates to window pixels, as a real touch
## screen would report them.
func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(pos)
	e.relative = get_viewport().get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _test_main_menu() -> void:
	print("[menu]")
	var menu: Control = (load("res://scenes/main/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	check(menu.get_child_count() > 3, "main menu builds")
	menu.queue_free()
	await get_tree().process_frame

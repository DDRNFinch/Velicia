extends SceneTree
## Writes the starter content resources into res://data/.
##   godot --headless -s res://tools/generate_data.gd           (only missing files)
##   godot --headless -s res://tools/generate_data.gd -- --force (overwrite all)
## After the first run, edit the .tres files in the Godot inspector instead;
## this script exists so the starter set can be regenerated or reviewed.

var force := false
var written := 0
var skipped := 0


func _init() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	_attacks()
	_items()
	_abilities()
	_enemies()
	_creatures()
	_quests()
	print("generate_data: wrote %d, kept %d existing" % [written, skipped])
	quit()


func _save(res: Resource, path: String) -> void:
	if FileAccess.file_exists(path) and not force:
		skipped += 1
		res.take_over_path(path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("Could not save %s: %s" % [path, error_string(err)])
	else:
		written += 1
	# So later resources reference this file instead of embedding a copy.
	res.take_over_path(path)


func _atk(id: String, d: Dictionary) -> AttackDefinition:
	var a := AttackDefinition.new()
	a.id = StringName(id)
	for k in d:
		a.set(k, d[k])
	_save(a, "res://data/attacks/%s.tres" % id)
	return a


# ------------------------------------------------------------------ Attacks

var A := {}


func _attacks() -> void:
	var ARC := AttackDefinition.HitShape.ARC
	var THRUST := AttackDefinition.HitShape.THRUST
	var CIRCLE := AttackDefinition.HitShape.CIRCLE
	# Player (damage = multiplier of weapon damage)
	A.pl1 = _atk("player_light_1", {"display_name": "Guild Cut", "windup": 0.14, "active": 0.12, "recovery": 0.3, "damage": 1.0, "poise_damage": 12.0, "stamina_cost": 12.0, "reach": 2.3, "arc_degrees": 110.0, "lunge_speed": 3.0, "pose": &"slash", "knockback": 2.0})
	A.pl2 = _atk("player_light_2", {"display_name": "Return Sweep", "windup": 0.12, "active": 0.12, "recovery": 0.32, "damage": 1.05, "poise_damage": 12.0, "stamina_cost": 12.0, "reach": 2.3, "arc_degrees": 150.0, "lunge_speed": 2.5, "pose": &"sweep", "knockback": 2.0})
	A.pl3 = _atk("player_light_3", {"display_name": "Driving Thrust", "windup": 0.2, "active": 0.14, "recovery": 0.44, "damage": 1.5, "poise_damage": 28.0, "stamina_cost": 16.0, "reach": 2.7, "hit_shape": THRUST, "lunge_speed": 6.0, "pose": &"thrust", "knockback": 4.0})
	A.ph = _atk("player_heavy", {"display_name": "Sundering Blow", "windup": 0.48, "active": 0.16, "recovery": 0.55, "damage": 2.3, "poise_damage": 45.0, "stamina_cost": 28.0, "reach": 2.6, "arc_degrees": 90.0, "lunge_speed": 3.0, "pose": &"slam", "is_heavy": true, "guard_break": true, "knockback": 6.0})
	A.pw = _atk("player_whirling_cut", {"display_name": "Whirling Cut", "windup": 0.2, "active": 0.36, "recovery": 0.42, "damage": 1.4, "poise_damage": 25.0, "stamina_cost": 32.0, "reach": 2.9, "hit_shape": CIRCLE, "pose": &"spin", "is_heavy": true, "knockback": 5.0})
	# Gyria soldiers
	A.gs = _atk("gyria_slash", {"display_name": "Hookblade Slash", "windup": 0.55, "active": 0.14, "recovery": 0.7, "damage": 12.0, "poise_damage": 18.0, "reach": 2.2, "max_range": 2.5, "lunge_speed": 2.5, "pose": &"slash", "weight": 3.0, "cooldown": 0.4})
	A.gl = _atk("gyria_lunge", {"display_name": "Lunging Cut", "windup": 0.8, "active": 0.16, "recovery": 0.9, "damage": 16.0, "poise_damage": 26.0, "reach": 2.4, "hit_shape": THRUST, "min_range": 1.6, "max_range": 4.4, "lunge_speed": 7.5, "pose": &"thrust", "weight": 1.5, "cooldown": 3.0, "knockback": 4.0})
	A.gt = _atk("gyria_spear_thrust", {"display_name": "Spear Thrust", "windup": 0.65, "active": 0.15, "recovery": 0.75, "damage": 13.0, "poise_damage": 20.0, "reach": 3.2, "hit_shape": THRUST, "max_range": 3.4, "lunge_speed": 3.0, "pose": &"thrust", "weight": 3.0, "cooldown": 0.5})
	A.gw = _atk("gyria_spear_sweep", {"display_name": "Spear Sweep", "windup": 0.75, "active": 0.18, "recovery": 0.8, "damage": 11.0, "poise_damage": 22.0, "reach": 3.0, "arc_degrees": 170.0, "max_range": 3.0, "pose": &"sweep", "weight": 1.2, "cooldown": 3.5, "knockback": 4.0})
	# Gyria Warchief (boss)
	A.wc = _atk("warchief_cleave", {"display_name": "Cleaver Arc", "windup": 0.7, "active": 0.18, "recovery": 0.8, "damage": 24.0, "poise_damage": 40.0, "reach": 3.3, "arc_degrees": 120.0, "max_range": 3.4, "lunge_speed": 2.5, "pose": &"slash", "weight": 3.0, "cooldown": 0.6, "is_heavy": true, "knockback": 5.0})
	A.ws = _atk("warchief_slam", {"display_name": "Earthbreaker", "windup": 1.1, "active": 0.2, "recovery": 1.1, "damage": 32.0, "poise_damage": 60.0, "reach": 4.2, "hit_shape": CIRCLE, "max_range": 3.6, "pose": &"slam", "weight": 1.6, "cooldown": 6.0, "unblockable": true, "parryable": false, "ground_telegraph": true, "is_heavy": true, "knockback": 8.0})
	A.ww = _atk("warchief_sweep", {"display_name": "Wide Reaping", "windup": 0.85, "active": 0.2, "recovery": 0.9, "damage": 20.0, "poise_damage": 35.0, "reach": 3.8, "arc_degrees": 210.0, "max_range": 3.6, "pose": &"sweep", "weight": 1.5, "cooldown": 4.0, "knockback": 5.0})
	A.wch = _atk("warchief_charge", {"display_name": "Bull Rush", "windup": 0.9, "active": 0.45, "recovery": 1.0, "damage": 26.0, "poise_damage": 50.0, "reach": 2.6, "hit_shape": THRUST, "min_range": 5.0, "max_range": 14.0, "lunge_speed": 13.0, "tracking_until": 0.9, "pose": &"charge", "weight": 2.0, "cooldown": 7.0, "is_heavy": true, "knockback": 9.0})
	A.wf = _atk("warchief_frenzy", {"display_name": "Frenzied Hack", "windup": 0.42, "active": 0.14, "recovery": 0.55, "damage": 17.0, "poise_damage": 25.0, "reach": 3.1, "arc_degrees": 110.0, "max_range": 3.2, "lunge_speed": 4.0, "pose": &"slash", "weight": 2.0, "cooldown": 1.5})


# -------------------------------------------------------------------- Items

func _item(id: String, d: Dictionary) -> void:
	var it := ItemDefinition.new()
	it.id = StringName(id)
	for k in d:
		it.set(k, d[k])
	_save(it, "res://data/items/%s.tres" % id)


func _items() -> void:
	var W := ItemDefinition.ItemType.WEAPON
	var AR := ItemDefinition.ItemType.ARMOR
	var TR := ItemDefinition.ItemType.TRINKET
	var C := ItemDefinition.ItemType.CONSUMABLE
	var M := ItemDefinition.ItemType.MATERIAL
	var R := ItemDefinition.ItemType.RING
	var Q := ItemDefinition.ItemType.QUEST
	_item("guild_longsword", {"display_name": "Guild Longsword", "type": W, "weapon_kind": &"sword", "damage": 14.0, "attack_speed": 1.0, "reach": 2.3, "max_stack": 1, "value": 40, "icon_color": Color(0.8, 0.82, 0.86), "description": "The balanced blade every Emoria warrior learns with. Reliable reach and recovery."})
	_item("emoria_spear", {"display_name": "Windstep Spear", "type": W, "weapon_kind": &"spear", "damage": 12.0, "attack_speed": 1.12, "stamina_cost_mult": 0.9, "reach": 3.0, "max_stack": 1, "value": 70, "icon_color": Color(0.75, 0.62, 0.4), "description": "A long, light spear in the Amir style. Fast, far-reaching strikes for a mobile fighter."})
	_item("quartermaster_axe", {"display_name": "Quartermaster's Axe", "type": W, "weapon_kind": &"axe", "damage": 20.0, "attack_speed": 0.82, "stamina_cost_mult": 1.3, "reach": 2.4, "max_stack": 1, "value": 80, "icon_color": Color(0.6, 0.6, 0.62), "description": "A Burrok-forged axe, cut down to a human grip. Slow, heavy and punishing."})
	_item("gyria_hookblade", {"display_name": "Gyria Hookblade", "type": W, "weapon_kind": &"hookblade", "damage": 13.0, "attack_speed": 1.15, "stamina_cost_mult": 0.95, "reach": 2.2, "max_stack": 1, "value": 45, "icon_color": Color(0.55, 0.5, 0.45), "description": "A practical Gyria field blade, hooked to drag shields aside. Worn but well kept."})
	_item("guild_leathers", {"display_name": "Guild Leathers", "type": AR, "defense": 6.0, "armor_color": Color(0.32, 0.36, 0.44), "max_stack": 1, "value": 30, "icon_color": Color(0.4, 0.45, 0.55), "description": "Layered leather in Emoria blue, cut for movement."})
	_item("gyria_scale_vest", {"display_name": "Gyria Scale Vest", "type": AR, "defense": 10.0, "armor_color": Color(0.36, 0.32, 0.27), "max_stack": 1, "value": 55, "icon_color": Color(0.5, 0.42, 0.32), "description": "Overlapping iron scales on hide. Gyria armour is plain, repaired many times, and made for long campaigns."})
	_item("warden_mail", {"display_name": "Warden's Mail", "type": AR, "defense": 15.0, "armor_color": Color(0.55, 0.55, 0.58), "max_stack": 1, "value": 120, "icon_color": Color(0.75, 0.75, 0.8), "description": "Mail and plate granted to warriors the Warden trusts."})
	_item("sentinel_charm", {"display_name": "Sentinel Charm", "type": TR, "bonus_health": 25.0, "max_stack": 1, "value": 60, "icon_color": Color(0.45, 0.9, 1.0), "description": "A chip of the Spire's crystal on a cord. It is warm to the touch."})
	_item("tide_pearl", {"display_name": "Tide Pearl", "type": TR, "bonus_stamina": 20.0, "max_stack": 1, "value": 60, "icon_color": Color(0.6, 0.95, 0.9), "description": "A Vapouriun keepsake that seems to breathe with the tide."})
	_item("healing_draught", {"display_name": "Healing Draught", "type": C, "heal_amount": 45.0, "value": 10, "icon_color": Color(0.85, 0.25, 0.3), "description": "Restores 45 health."})
	_item("greater_draught", {"display_name": "Greater Draught", "type": C, "heal_amount": 90.0, "stamina_restore": 30.0, "value": 25, "icon_color": Color(1.0, 0.4, 0.5), "description": "Restores 90 health and 30 stamina."})
	_item("stamina_tonic", {"display_name": "Stamina Tonic", "type": C, "stamina_restore": 70.0, "value": 8, "icon_color": Color(0.4, 0.85, 0.4), "description": "Restores 70 stamina."})
	_item("training_ration", {"display_name": "Training Ration", "type": M, "value": 6, "icon_color": Color(0.9, 0.75, 0.4), "description": "Spent at the ring-sage to train a creature (+40 experience, +3 bond)."})
	_item("gyria_token", {"display_name": "Gyria Clan Token", "type": M, "value": 5, "icon_color": Color(0.7, 0.3, 0.2), "description": "A carved token carried by Gyria soldiers to show their clan and hearth."})
	_item("ring_shard", {"display_name": "Ring Shard", "type": M, "value": 15, "icon_color": Color(0.5, 0.9, 1.0), "description": "A fragment of ring-stone. Used to forge rings (forging not yet implemented)."})
	_item("supply_bundle", {"display_name": "Outpost Supply Bundle", "type": Q, "value": 0, "icon_color": Color(0.95, 0.8, 0.45), "description": "Supplies lost on the road to the outpost."})
	_item("sealed_letter", {"display_name": "Sealed Gyria Letter", "type": Q, "max_stack": 1, "value": 0, "icon_color": Color(0.9, 0.85, 0.7), "description": "A letter in Gyria script, sealed with a clan mark."})
	_item("stolen_ringstone", {"display_name": "Stolen Ring-stone", "type": Q, "max_stack": 1, "value": 0, "icon_color": Color(0.4, 0.95, 1.0), "description": "One of the outpost's ring-stones, carried off by the Warchief."})
	_item("apprentice_ring", {"display_name": "Apprentice Ring", "type": R, "ring_tier": 1, "capture_power": 1.0, "max_stack": 3, "value": 50, "icon_color": Color(0.85, 0.7, 0.35), "description": "A simple Emoria ring. It can bind one creature of tier 1."})
	_item("bound_ring", {"display_name": "Bound Ring", "type": R, "ring_tier": 2, "capture_power": 1.3, "max_stack": 3, "value": 150, "icon_color": Color(0.5, 0.9, 1.0), "description": "A ring set with Spire crystal. Binds stronger creatures (tier 2) and captures more reliably."})


# ---------------------------------------------------------------- Abilities

func _abilities() -> void:
	var specs := [
		["whirling_cut", "Whirling Cut", AbilityDefinition.Kind.ACTIVE, 1, 0.0, 8.0, 1.0, "A spinning cut that strikes all around you. Good against groups. Uses the SKILL button.", A.pw],
		["emoria_riposte", "Emoria Riposte", AbilityDefinition.Kind.PASSIVE, 2, 0.0, 0.0, 2.2, "Strikes against parried or dazed foes deal ×2.2 damage instead of ×1.5.", null],
		["ring_surge", "Ring Surge", AbilityDefinition.Kind.ACTIVE, 3, 25.0, 20.0, 1.5, "Pour your strength into your ring: your summoned creature heals 30% and deals +50% damage for 8 seconds.", null],
		["second_wind", "Second Wind", AbilityDefinition.Kind.PASSIVE, 4, 0.0, 0.0, 1.3, "Stamina recovers 30% faster.", null],
	]
	for s in specs:
		var ab := AbilityDefinition.new()
		ab.id = StringName(s[0])
		ab.display_name = s[1]
		ab.kind = s[2]
		ab.unlock_level = s[3]
		ab.stamina_cost = s[4]
		ab.cooldown = s[5]
		ab.power = s[6]
		ab.description = s[7]
		ab.attack = s[8]
		_save(ab, "res://data/abilities/%s.tres" % s[0])


# ------------------------------------------------------------------ Enemies

func _enemies() -> void:
	var sk := EnemyDefinition.new()
	sk.id = &"gyria_skirmisher"
	sk.display_name = "Gyria Skirmisher"
	sk.people = &"gyria"
	sk.tags = PackedStringArray(["gyria", "gyria_scout"])
	sk.max_health = 70.0
	sk.max_poise = 30.0
	sk.walk_speed = 2.1
	sk.run_speed = 4.4
	sk.block_chance = 0.3
	sk.xp_reward = 30
	sk.attacks = [A.gs, A.gl] as Array[AttackDefinition]
	sk.loot = {"gyria_token": 0.6, "healing_draught": 0.25, "training_ration": 0.2}
	sk.weapon_kind = &"hookblade"
	_save(sk, "res://data/enemies/gyria_skirmisher.tres")

	var sp := EnemyDefinition.new()
	sp.id = &"gyria_spearman"
	sp.display_name = "Gyria Spear-warden"
	sp.people = &"gyria"
	sp.tags = PackedStringArray(["gyria", "gyria_scout"])
	sp.max_health = 80.0
	sp.max_poise = 34.0
	sp.walk_speed = 2.0
	sp.run_speed = 4.0
	sp.preferred_distance = 3.7
	sp.block_chance = 0.15
	sp.xp_reward = 34
	sp.attacks = [A.gt, A.gw] as Array[AttackDefinition]
	sp.loot = {"gyria_token": 0.6, "stamina_tonic": 0.3, "training_ration": 0.2}
	sp.skin_color = Color(0.44, 0.5, 0.4)
	sp.armor_color = Color(0.3, 0.27, 0.22)
	sp.weapon_kind = &"spear"
	_save(sp, "res://data/enemies/gyria_spearman.tres")

	var boss := EnemyDefinition.new()
	boss.id = &"gyria_warchief"
	boss.display_name = "Warchief Vorga (draft name)"
	boss.people = &"gyria"
	boss.tags = PackedStringArray(["gyria", "gyria_boss"])
	boss.is_boss = true
	boss.max_health = 520.0
	boss.max_poise = 120.0
	boss.defense = 8.0
	boss.walk_speed = 2.2
	boss.run_speed = 4.6
	boss.turn_speed = 5.0
	boss.aggro_range = 18.0
	boss.leash_range = 42.0
	boss.preferred_distance = 3.4
	boss.block_chance = 0.0
	boss.xp_reward = 260
	boss.weapon_kind = &"cleaver"
	boss.skin_color = Color(0.42, 0.47, 0.35)
	boss.armor_color = Color(0.3, 0.25, 0.22)
	boss.accent_color = Color(0.75, 0.28, 0.12)
	boss.loot = {"stolen_ringstone": 1.0, "greater_draught": 1.0, "ring_shard": 1.0}
	var p1 := BossPhase.new()
	p1.health_fraction = 1.0
	p1.attacks = [A.wc, A.ws, A.ww] as Array[AttackDefinition]
	var p2 := BossPhase.new()
	p2.health_fraction = 0.55
	p2.attacks = [A.wc, A.ws, A.ww, A.wch, A.wf] as Array[AttackDefinition]
	p2.speed_mult = 1.2
	p2.recovery_mult = 0.75
	p2.announcement = "The Warchief roars: \"For the hearths of the north!\" Her attacks quicken."
	boss.phases = [p1, p2] as Array[BossPhase]
	boss.attacks = p1.attacks
	_save(boss, "res://data/enemies/gyria_warchief.tres")


# ---------------------------------------------------------------- Creatures

func _ability(id: String, d: Dictionary) -> CreatureAbility:
	var a := CreatureAbility.new()
	a.id = StringName(id)
	for k in d:
		a.set(k, d[k])
	return a


func _creatures() -> void:
	var MELEE := CreatureAbility.Kind.MELEE
	var RANGED := CreatureAbility.Kind.RANGED
	var AREA := CreatureAbility.Kind.AREA
	var HEAL := CreatureAbility.Kind.HEAL_ALLY
	var GUARD := CreatureAbility.Kind.GUARD

	var a := CreatureDefinition.new()
	a.id = &"test_creature_alpha"
	a.display_name = "Test Creature α"
	a.description = "TEMPORARY TEST CREATURE. A quick, bold four-legged placeholder used to test capturing, summoning and melee companion behaviour. Not part of the official roster."
	a.rarity = CreatureDefinition.Rarity.COMMON
	a.temperament = CreatureDefinition.Temperament.AGGRESSIVE
	a.base_health = 60.0
	a.base_attack = 9.0
	a.base_defense = 2.0
	a.move_speed = 5.6
	a.capture_health_threshold = 0.45
	a.base_capture_chance = 0.62
	a.capture_hint = "Weaken it below 45% health."
	a.body_color = Color(0.72, 0.52, 0.3)
	a.accent_color = Color(0.95, 0.75, 0.3)
	a.eye_color = Color(0.4, 1.0, 0.9)
	a.size = 0.9
	a.abilities = [
		_ability("test_bite", {"display_name": "Test Bite", "description": "Quick bite.", "kind": MELEE, "power": 1.0, "cooldown": 1.6, "ability_range": 1.6, "windup": 0.35, "color": Color(1, 0.85, 0.5)}),
		_ability("test_pounce", {"display_name": "Test Pounce", "description": "Leaping strike that staggers.", "kind": MELEE, "power": 1.8, "cooldown": 6.0, "ability_range": 2.2, "windup": 0.5, "poise_damage": 35.0, "required_bond": 1, "color": Color(1, 0.6, 0.3)}),
		_ability("test_roar_burst", {"display_name": "Test Roar Burst", "description": "Shockwave around the creature.", "kind": AREA, "power": 1.2, "cooldown": 10.0, "ability_range": 3.5, "windup": 0.6, "required_level": 4, "color": Color(1, 0.9, 0.4)}),
	] as Array[CreatureAbility]
	_save(a, "res://data/creatures/test_creature_alpha.tres")

	var b := CreatureDefinition.new()
	b.id = &"test_creature_beta"
	b.display_name = "Test Creature β"
	b.description = "TEMPORARY TEST CREATURE. A hovering placeholder that tests ranged attacks, healing support and the 'must be dazed' capture rule. Not part of the official roster."
	b.rarity = CreatureDefinition.Rarity.UNCOMMON
	b.temperament = CreatureDefinition.Temperament.SUPPORT
	b.base_health = 45.0
	b.base_attack = 7.0
	b.base_defense = 1.0
	b.move_speed = 4.8
	b.capture_health_threshold = 0.4
	b.base_capture_chance = 0.55
	b.capture_condition = &"dazed"
	b.capture_hint = "Weaken it until it is dazed, then capture before it recovers."
	b.body_shape = &"hover"
	b.body_color = Color(0.3, 0.55, 0.85)
	b.accent_color = Color(0.45, 0.9, 1.0)
	b.eye_color = Color(1.0, 1.0, 0.8)
	b.size = 0.9
	b.flee_when_weak = true
	b.abilities = [
		_ability("test_spark", {"display_name": "Test Spark", "description": "Ranged bolt.", "kind": RANGED, "power": 0.9, "cooldown": 1.8, "ability_range": 9.0, "windup": 0.45, "color": Color(0.5, 0.9, 1.0)}),
		_ability("test_mend", {"display_name": "Test Mend", "description": "Heals its warrior.", "kind": HEAL, "power": 1.4, "cooldown": 12.0, "ability_range": 10.0, "windup": 0.6, "color": Color(0.5, 1.0, 0.6)}),
		_ability("test_ward", {"display_name": "Test Ward", "description": "Shields itself, reducing damage taken.", "kind": GUARD, "power": 1.0, "cooldown": 14.0, "ability_range": 20.0, "windup": 0.3, "required_bond": 2, "color": Color(0.7, 0.8, 1.0)}),
	] as Array[CreatureAbility]
	_save(b, "res://data/creatures/test_creature_beta.tres")

	var g := CreatureDefinition.new()
	g.id = &"test_creature_gamma"
	g.display_name = "Test Creature γ"
	g.description = "TEMPORARY TEST CREATURE. A large, territorial placeholder that tests hostile-on-sight wild behaviour and the tier-2 ring requirement. Not part of the official roster."
	g.rarity = CreatureDefinition.Rarity.RARE
	g.temperament = CreatureDefinition.Temperament.DEFENSIVE
	g.base_health = 120.0
	g.base_attack = 13.0
	g.base_defense = 5.0
	g.move_speed = 4.4
	g.capture_health_threshold = 0.3
	g.base_capture_chance = 0.6
	g.min_ring_tier = 2
	g.capture_hint = "Requires a tier-2 ring. Weaken it below 30%."
	g.body_color = Color(0.35, 0.38, 0.3)
	g.accent_color = Color(0.75, 0.95, 0.4)
	g.eye_color = Color(1.0, 0.5, 0.3)
	g.size = 1.5
	g.hostile_on_sight = true
	g.wander_radius = 5.0
	g.abilities = [
		_ability("test_stomp", {"display_name": "Test Stomp", "description": "Ground slam around it.", "kind": AREA, "power": 1.3, "cooldown": 5.0, "ability_range": 3.2, "windup": 0.8, "poise_damage": 30.0, "color": Color(0.8, 1.0, 0.4)}),
		_ability("test_gore", {"display_name": "Test Gore", "description": "Heavy charge.", "kind": MELEE, "power": 1.6, "cooldown": 3.0, "ability_range": 2.4, "windup": 0.6, "poise_damage": 30.0, "color": Color(1.0, 0.7, 0.3)}),
	] as Array[CreatureAbility]
	_save(g, "res://data/creatures/test_creature_gamma.tres")


# ------------------------------------------------------------------- Quests

func _obj(type: int, target: String, desc: String, count: int = 1, marker: String = "") -> QuestObjective:
	var o := QuestObjective.new()
	o.type = type
	o.target = StringName(target)
	o.description = desc
	o.count = count
	o.marker_location = StringName(marker)
	return o


func _stage(id: String, text: String, objs: Array) -> QuestStage:
	var s := QuestStage.new()
	s.id = StringName(id)
	s.journal_text = text
	s.objectives.assign(objs)
	return s


func _quest(id: String, title: String, summary: String, is_main: bool, stages: Array, rewards: Dictionary) -> void:
	var q := QuestDefinition.new()
	q.id = StringName(id)
	q.title = title
	q.summary = summary
	q.is_main = is_main
	q.is_draft = true
	q.stages.assign(stages)
	q.reward_xp = rewards.get("xp", 0)
	q.reward_items = rewards.get("items", {})
	q.reward_flags = PackedStringArray(rewards.get("flags", []))
	q.reward_reputation = rewards.get("rep", {})
	q.next_quest = StringName(rewards.get("next", ""))
	_save(q, "res://data/quests/%s.tres" % id)


func _quests() -> void:
	var T := QuestObjective.Type
	_quest("the_emoria_watch", "The Emoria Watch", "Report for duty at the Emoria Watch Outpost.", true, [
		_stage("report", "You have arrived at the Emoria Watch Outpost on the edge of the Hollow March. Report to the Warden.", [
			_obj(T.TALK, "warden", "Speak with Warden Aldren", 1, "emoria_outpost")]),
	], {"xp": 20})

	_quest("first_watch", "Smoke over the Spire", "Gyria scouts have been seen at the Sentinel Spire, the ancient tower north of the outpost.", true, [
		_stage("investigate", "The Warden sent you north to the Sentinel Spire, where smoke was seen at dawn.", [
			_obj(T.REACH, "sentinel_spire", "Travel to the Sentinel Spire", 1, "sentinel_spire")]),
		_stage("drive_off", "Gyria scouts are searching the ruins around the Spire. Drive them off.", [
			_obj(T.KILL, "gyria_scout", "Defeat Gyria scouts at the Spire", 3, "sentinel_spire")]),
		_stage("search", "The scouts were looking for something. Search the ruins near the tower.", [
			_obj(T.COLLECT, "sealed_letter", "Find what the scouts were carrying", 1, "sentinel_spire")]),
		_stage("report", "You found a sealed Gyria letter. Bring it to the Warden.", [
			_obj(T.TALK, "warden", "Bring the letter to Warden Aldren", 1, "emoria_outpost")]),
	], {"xp": 120, "items": {"bound_ring": 1, "healing_draught": 2}, "rep": {"emoria_guild": 10}, "next": "ashes_of_ashfen"})

	_quest("ashes_of_ashfen", "The Ashfen Camp", "The letter points to a Gyria war-camp at Ashfen and a Warchief gathering ring-stones.", true, [
		_stage("scout", "The letter speaks of a camp at Ashfen, east of the outpost. Find it.", [
			_obj(T.REACH, "ashfen_camp", "Find the Gyria camp at Ashfen", 1, "ashfen_camp")]),
		_stage("scout_fate", "A wounded Gyria scout was left behind at the camp. Decide what to do with her.", [
			_obj(T.FLAG, "kesh_decided", "Speak with the wounded scout and decide her fate", 1, "ashfen_camp")]),
		_stage("fort", "The Warchief holds the stolen ring-stones at the Broken Fort, north of the Spire.", [
			_obj(T.REACH, "broken_fort", "Go to the Broken Fort", 1, "broken_fort")]),
		_stage("warchief", "The Warchief waits within the fort.", [
			_obj(T.KILL, "gyria_boss", "Defeat the Warchief", 1, "broken_fort")]),
		_stage("return", "The ring-stone is recovered. Return to the Warden.", [
			_obj(T.TALK, "warden", "Return to Warden Aldren", 1, "emoria_outpost")]),
	], {"xp": 300, "items": {"warden_mail": 1}, "rep": {"emoria_guild": 15}, "flags": ["prologue_complete"]})

	_quest("the_ring_trial", "The Ring Trial", "Master Oddrin will teach you the rings once you have bound a creature.", false, [
		_stage("capture", "Weaken a wild creature and bind it to your Apprentice Ring. Mossglade, west of the outpost, is full of them.", [
			_obj(T.CAPTURE, "any", "Capture a wild creature", 1, "mossglade")]),
		_stage("summon", "Call your new companion from the ring.", [
			_obj(T.SUMMON, "any", "Summon your creature")]),
		_stage("report", "Return to Master Oddrin with your companion.", [
			_obj(T.TALK, "ring_sage", "Speak with Master Oddrin", 1, "emoria_outpost")]),
	], {"xp": 80, "items": {"training_ration": 3, "apprentice_ring": 1}})

	_quest("lost_supplies", "Lost on the Road", "Quartermaster Brannoch's supply bundles were scattered when a cart overturned.", false, [
		_stage("gather", "Recover the three supply bundles lost along the roads around the outpost.", [
			_obj(T.COLLECT, "supply_bundle", "Recover supply bundles", 3)]),
		_stage("return", "Bring the bundles back to the Quartermaster.", [
			_obj(T.TALK, "quartermaster", "Return to Quartermaster Brannoch", 1, "emoria_outpost")]),
	], {"xp": 70, "items": {"quartermaster_axe": 1, "greater_draught": 1}, "rep": {"hollow_settlers": 10}})

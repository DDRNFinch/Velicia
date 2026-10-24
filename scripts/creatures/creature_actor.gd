class_name CreatureActor
extends CharacterBody3D
## A creature in the world. In WILD mode it wanders, defends itself, becomes
## dazed when weakened and can be captured. In COMPANION mode it follows the
## player, fights by temperament, obeys commands and gains experience and bond.
## All numbers come from its CreatureDefinition, so new creatures need no code.

enum Mode { WILD, COMPANION }
enum State { IDLE, WANDER, HOSTILE, DAZED, FLEE, CAPTURED, FOLLOW, ENGAGE, ABILITY, RECOVER, STAGGER, KO, APPEAR }

const GRAVITY := 18.0
const DAZE_TIME := 5.0
const TELEPORT_DISTANCE := 32.0

@export var definition: CreatureDefinition
@export var level: int = 1

var mode: Mode = Mode.WILD
var instance: CreatureInstance
var owner_player: Player
var team: StringName = &"wild"
var body_radius: float = 0.5
var stats: CombatStats
var visual: CreatureBody
var state: State = State.IDLE
var target: Node3D
var home: Vector3
var spawner: Node

var _state_time := 0.0
var _time := 0.0
var _wander_target := Vector3.ZERO
var _cooldowns: Dictionary = {}
var _ability: CreatureAbility
var _ability_done := false
var _daze_used := false
var _hold := false
var _commanded_target: Node3D
var _empower_until := -1.0
var _empower_mult := 1.0
var _guard_until := -1.0
var _knock := Vector3.ZERO
var _stagger_time := 0.0
var _label: Label3D
var _capture_marker: MeshInstance3D
var _marker_mat: StandardMaterial3D


func setup_companion(inst: CreatureInstance, p: Player) -> void:
	mode = Mode.COMPANION
	instance = inst
	owner_player = p
	team = &"player"
	level = inst.level


func _ready() -> void:
	if definition == null:
		push_error("CreatureActor without definition")
		queue_free()
		return
	add_to_group("creatures")
	collision_layer = CombatUtil.LAYER_CREATURE
	collision_mask = CombatUtil.LAYER_WORLD | CombatUtil.LAYER_ENEMY | CombatUtil.LAYER_CREATURE
	if mode == Mode.WILD:
		collision_mask |= CombatUtil.LAYER_PLAYER
		add_to_group("targetable")
	else:
		add_to_group("player_team")
	var sz := definition.size
	body_radius = 0.45 * sz
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42 * sz
	capsule.height = maxf(1.0 * sz, capsule.radius * 2.0 + 0.05)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)

	stats = CombatStats.new()
	add_child(stats)
	stats.setup(definition.max_health_at(level), 100.0, 20.0 + 12.0 * sz)
	if instance:
		stats.set_health(instance.health if instance.health > 0.0 else stats.max_health)
	stats.died.connect(_on_defeated)

	visual = CreatureBody.new()
	add_child(visual)
	visual.build(definition)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.font_size = 32
	_label.outline_size = 10
	_label.position.y = 1.5 * sz + 0.3
	_label.no_depth_test = false
	add_child(_label)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.8 * sz
	ring.outer_radius = 0.95 * sz
	ring.rings = 20
	ring.ring_segments = 4
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = Color(definition.accent_color, 0.8)
	_capture_marker = MeshInstance3D.new()
	_capture_marker.mesh = ring
	_capture_marker.material_override = _marker_mat
	_capture_marker.position.y = 0.05
	_capture_marker.scale = Vector3(1, 0.2, 1)
	_capture_marker.visible = false
	add_child(_capture_marker)

	home = global_position
	if mode == Mode.COMPANION:
		_set_state(State.APPEAR)
		scale = Vector3.ONE * 0.1
		create_tween().tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_set_state(State.WANDER)
	_update_label()


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0


# ------------------------------------------------------------ Main loop

func _physics_process(delta: float) -> void:
	if definition == null:
		return
	_time += delta
	_state_time += delta
	for k in _cooldowns.keys():
		_cooldowns[k] = maxf(0.0, float(_cooldowns[k]) - delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	match state:
		State.IDLE, State.WANDER:
			_state_wander(delta)
		State.HOSTILE, State.ENGAGE:
			_state_fight(delta)
		State.FOLLOW:
			_state_follow(delta)
		State.ABILITY:
			_state_ability(delta)
		State.RECOVER:
			_slow(delta)
			if _state_time > 0.45:
				_set_state(State.ENGAGE if mode == Mode.COMPANION else State.HOSTILE)
		State.STAGGER:
			_stagger_time -= delta
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
			if _stagger_time <= 0.0:
				_set_state(State.ENGAGE if mode == Mode.COMPANION else State.HOSTILE)
		State.DAZED:
			_slow(delta)
			if _state_time > DAZE_TIME:
				_set_state(State.FLEE if definition.flee_when_weak else State.HOSTILE)
		State.FLEE:
			_state_flee(delta)
		State.APPEAR:
			_slow(delta)
			if _state_time > 0.4:
				_set_state(State.FOLLOW)
		State.CAPTURED, State.KO:
			velocity.x = 0.0
			velocity.z = 0.0
	move_and_slide()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	visual.animate(delta, hspeed, definition.move_speed, state == State.DAZED)
	if Engine.get_physics_frames() % 10 == 0:
		_update_label()
	if global_position.y < -40.0:
		if mode == Mode.COMPANION and owner_player:
			global_position = owner_player.global_position + Vector3.UP
		else:
			global_position = home + Vector3.UP
		velocity = Vector3.ZERO


func _slow(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _move_toward_point(point: Vector3, speed: float, delta: float, stop_distance: float = 0.3) -> float:
	var to := point - global_position
	to.y = 0.0
	var d := to.length()
	var want := Vector3.ZERO
	if d > stop_distance:
		want = to.normalized() * speed
		if is_on_wall():
			want = want.rotated(Vector3.UP, 0.9)
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want, 22.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if hv.length() > 0.2:
		CombatUtil.turn_toward(self, hv.normalized(), 9.0, delta)
	return d


# ----------------------------------------------------------- Wild states

func _state_wander(delta: float) -> void:
	if _wander_target == Vector3.ZERO or _state_time > 5.0 or global_position.distance_to(_wander_target) < 0.6:
		var ang := randf() * TAU
		var r := randf_range(1.0, definition.wander_radius)
		_wander_target = home + Vector3(cos(ang) * r, 0, sin(ang) * r)
		_state_time = randf_range(0.0, 2.0)
	if _state_time < 1.5:
		_slow(delta)
	else:
		_move_toward_point(_wander_target, definition.move_speed * 0.35, delta)
	if definition.hostile_on_sight and CombatDirector.player and is_instance_valid(CombatDirector.player):
		if global_position.distance_to(CombatDirector.player.global_position) < 7.0 and not CombatDirector.player.is_dead():
			target = CombatDirector.player
			_set_state(State.HOSTILE)


func _state_flee(delta: float) -> void:
	if target == null or not is_instance_valid(target) or _state_time > 4.0:
		_set_state(State.WANDER)
		return
	var away := CombatUtil.flat_direction(target.global_position, global_position)
	_move_toward_point(global_position + away * 4.0, definition.move_speed * 1.1, delta)


# ------------------------------------------------------ Companion states

func _state_follow(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		return
	var b := owner_player.global_transform.basis
	var spot := owner_player.global_position + b.x * 1.6 + b.z * 1.4
	var d := global_position.distance_to(owner_player.global_position)
	if d > TELEPORT_DISTANCE:
		global_position = spot + Vector3.UP * 0.5
		velocity = Vector3.ZERO
		return
	var speed := definition.move_speed * (1.15 if d > 6.0 else 0.6)
	if _move_toward_point(spot, speed, delta, 0.8) < 1.0:
		CombatUtil.turn_toward(self, -b.z, 4.0, delta)
	if _state_time > 0.25:
		_state_time = 0.0
		var t := _pick_companion_target()
		if t:
			target = t
			_set_state(State.ENGAGE)
	# Support creatures tend their warrior.
	if definition.temperament == CreatureDefinition.Temperament.SUPPORT and owner_player.stats.health_fraction() < 0.5:
		var heal := _find_ability(CreatureAbility.Kind.HEAL_ALLY)
		if heal:
			target = owner_player
			_begin_ability(heal)


func _pick_companion_target() -> Node3D:
	if _hold:
		return null
	if _commanded_target and is_instance_valid(_commanded_target) and _is_hostile(_commanded_target):
		return _commanded_target
	_commanded_target = null
	if definition.temperament == CreatureDefinition.Temperament.SUPPORT:
		return null
	var best: Node3D = null
	var best_d := 11.0 if definition.temperament == CreatureDefinition.Temperament.AGGRESSIVE else 6.0
	for n in get_tree().get_nodes_in_group("targetable"):
		if not _is_hostile(n):
			continue
		var engaged: bool = definition.temperament == CreatureDefinition.Temperament.AGGRESSIVE or n.get("target") == owner_player or n.get("target") == self
		if not engaged:
			continue
		var d: float = owner_player.global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _is_hostile(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or n == self:
		return false
	if n.has_method("is_targetable") and not n.is_targetable():
		return false
	var t = n.get("team")
	if t == null or t == team:
		return false
	if n is CreatureActor and (n as CreatureActor).mode == Mode.WILD:
		# Leave peaceful wild creatures alone unless they are fighting us.
		return n.get("state") in [State.HOSTILE, State.ABILITY, State.RECOVER] or n == _commanded_target
	return true


## Player command: attack the given target, or toggle holding back.
func command(player_target: Node3D) -> void:
	var name_text := instance.display_name() if instance else definition.display_name
	if player_target and is_instance_valid(player_target) and player_target.get("team") != team:
		_hold = false
		_commanded_target = player_target
		target = player_target
		_set_state(State.ENGAGE)
		EventBus.notify.emit("%s: attacking!" % name_text)
	else:
		_hold = not _hold
		if _hold:
			target = null
			_set_state(State.FOLLOW)
		EventBus.notify.emit("%s: %s" % [name_text, "holding back" if _hold else "fighting freely"])


## Defensive companions join in on whatever the player strikes.
func on_owner_hit(t: Node3D) -> void:
	if _hold or state in [State.ABILITY, State.KO, State.APPEAR]:
		return
	if definition.temperament != CreatureDefinition.Temperament.SUPPORT and _is_hostile_or_wild(t):
		target = t
		if state == State.FOLLOW:
			_set_state(State.ENGAGE)


func _is_hostile_or_wild(t: Node) -> bool:
	return t and is_instance_valid(t) and t.get("team") != team


func is_holding() -> bool:
	return _hold


# --------------------------------------------------------------- Fighting

func _state_fight(delta: float) -> void:
	var valid: bool = target != null and is_instance_valid(target) and (not target.has_method("is_targetable") or target.is_targetable())
	if mode == Mode.COMPANION:
		if not valid or _hold or (owner_player and owner_player.global_position.distance_to(target.global_position) > 22.0):
			target = null
			_set_state(State.FOLLOW)
			return
	else:
		if not valid or global_position.distance_to(home) > 30.0 or (target.has_method("is_dead") and target.is_dead()):
			target = null
			stats.heal(stats.max_health * 0.3)
			_set_state(State.WANDER)
			return
	var ability := _choose_ability()
	var rng := ability.ability_range if ability else 2.0
	var d := global_position.distance_to(target.global_position) - CombatUtil.body_radius(target)
	if d > rng * 0.9:
		_move_toward_point(target.global_position, definition.move_speed, delta, rng * 0.6)
	else:
		_slow(delta)
		CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, target.global_position), 10.0, delta)
		if ability and _state_time > 0.25:
			_begin_ability(ability)


func _abilities() -> Array[CreatureAbility]:
	if instance:
		return instance.available_abilities()
	var out: Array[CreatureAbility] = []
	for a in definition.abilities:
		if a.required_level <= level and a.required_bond == 0:
			out.append(a)
	return out


func _choose_ability() -> CreatureAbility:
	var best: CreatureAbility = null
	for a in _abilities():
		if a.kind == CreatureAbility.Kind.HEAL_ALLY:
			continue
		if float(_cooldowns.get(a.id, 0.0)) > 0.0:
			continue
		if best == null or a.power > best.power:
			best = a
	return best


func _find_ability(kind: CreatureAbility.Kind) -> CreatureAbility:
	for a in _abilities():
		if a.kind == kind and float(_cooldowns.get(a.id, 0.0)) <= 0.0:
			return a
	return null


func _begin_ability(a: CreatureAbility) -> void:
	_ability = a
	_ability_done = false
	_set_state(State.ABILITY)
	visual.set_telegraph(true, Settings.telegraph_color() if mode == Mode.WILD else a.color)


func _state_ability(delta: float) -> void:
	_slow(delta)
	var a := _ability
	if a == null:
		_set_state(State.RECOVER)
		return
	if target and is_instance_valid(target) and _state_time < a.windup * 0.8:
		CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, target.global_position), 8.0, delta)
	if not _ability_done and _state_time >= a.windup:
		_ability_done = true
		visual.set_telegraph(false)
		visual.play_attack()
		_execute_ability(a)
		_cooldowns[a.id] = a.cooldown
	if _state_time >= a.windup + 0.25:
		_set_state(State.RECOVER)


func attack_power() -> float:
	var base := instance.attack() if instance else definition.attack_at(level)
	return base * (_empower_mult if _time < _empower_until else 1.0)


func _execute_ability(a: CreatureAbility) -> void:
	var dmg := attack_power() * a.power
	AudioManager.play_sfx("creature_attack", global_position)
	match a.kind:
		CreatureAbility.Kind.HEAL_ALLY:
			var who: Node = owner_player if owner_player else self
			var amount := dmg * 1.5
			if who == owner_player:
				owner_player.stats.heal(amount)
			else:
				stats.heal(amount)
			Fx.ring_burst((who as Node3D).global_position + Vector3.UP, a.color, 1.6)
			Fx.floating_text((who as Node3D).global_position + Vector3.UP * 2.0, "+%d" % roundi(amount), Color(0.4, 1.0, 0.5))
		CreatureAbility.Kind.GUARD:
			_guard_until = _time + 4.0
			Fx.ring_burst(global_position + Vector3.UP * 0.6, a.color, 1.5)
		CreatureAbility.Kind.AREA:
			Fx.ring_burst(global_position + Vector3.UP * 0.2, a.color, a.ability_range, 0.5)
			for n in _hostiles_in_radius(a.ability_range):
				_deal_hit(n, dmg, a)
		CreatureAbility.Kind.RANGED:
			if target and is_instance_valid(target):
				_fire_projectile(target, dmg, a)
		_:
			if target and is_instance_valid(target):
				var d := global_position.distance_to(target.global_position) - CombatUtil.body_radius(target)
				if d <= a.ability_range + 0.4:
					_deal_hit(target, dmg, a)


func _hostiles_in_radius(r: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var groups := ["targetable"] if mode == Mode.COMPANION else ["player_team"]
	for g in groups:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and n != self and n.get("team") != team and n.has_method("receive_hit"):
				if (n as Node3D).global_position.distance_to(global_position) <= r + CombatUtil.body_radius(n):
					if mode == Mode.WILD or _is_hostile(n) or n == target:
						out.append(n)
	return out


func _deal_hit(n: Node3D, dmg: float, a: CreatureAbility) -> void:
	var hit := HitData.new()
	hit.source = self
	hit.damage = dmg
	hit.poise_damage = a.poise_damage
	hit.knockback = 2.5
	hit.direction = CombatUtil.flat_direction(global_position, n.global_position)
	var result: int = n.receive_hit(hit)
	if result == HitData.Result.HIT:
		Fx.hit_spark(n.global_position + Vector3.UP, a.color, 1.0)
		if mode == Mode.COMPANION:
			Fx.damage_number(n.global_position + Vector3.UP * 1.6, dmg, a.color.lightened(0.3))


func _fire_projectile(t: Node3D, dmg: float, a: CreatureAbility) -> void:
	var orb := MeshInstance3D.new()
	orb.mesh = PlaceholderBody.sphere_mesh(0.16)
	orb.material_override = PlaceholderBody.mat(a.color, 0.2, 2.5)
	get_parent().add_child(orb)
	var from := visual.get_center() - global_transform.basis.z * 0.4
	orb.global_position = from
	var to := t.global_position + Vector3.UP
	var duration := clampf(from.distance_to(to) / 14.0, 0.08, 0.8)
	var tw := orb.create_tween()
	tw.tween_property(orb, "global_position", to, duration)
	tw.tween_callback(func():
		if is_instance_valid(t) and is_instance_valid(self) and t.global_position.distance_to(to - Vector3.UP) < 1.8:
			_deal_hit(t, dmg, a)
		orb.queue_free())


# -------------------------------------------------------------- Defence

func receive_hit(hit: HitData) -> int:
	if state in [State.KO, State.CAPTURED, State.APPEAR]:
		return HitData.Result.IGNORED
	if mode == Mode.WILD and hit.source and is_instance_valid(hit.source):
		target = hit.source
		if state in [State.IDLE, State.WANDER, State.FLEE]:
			_set_state(State.HOSTILE)
	var dmg := hit.damage * 30.0 / (30.0 + (instance.defense() if instance else definition.defense_at(level)))
	if _time < _guard_until:
		dmg *= 0.4
	stats.apply_damage(dmg)
	visual.flash(Color(1, 1, 1))
	if instance:
		instance.health = stats.health
	if stats.is_dead():
		return HitData.Result.HIT
	if mode == Mode.WILD and not _daze_used and stats.health_fraction() <= definition.capture_health_threshold:
		_daze_used = true
		visual.set_telegraph(false)
		_ability = null
		_set_state(State.DAZED)
		Fx.floating_text(global_position + Vector3.UP * 1.8, "Dazed — capture it!", definition.accent_color.lightened(0.3))
		return HitData.Result.HIT
	if state != State.DAZED and (stats.apply_poise_damage(hit.poise_damage) or hit.is_heavy):
		visual.set_telegraph(false)
		_ability = null
		_knock = hit.direction * hit.knockback
		_stagger_time = 0.45
		_set_state(State.STAGGER)
	return HitData.Result.HIT


func is_targetable() -> bool:
	return mode == Mode.WILD and not (state in [State.KO, State.CAPTURED])


func is_vulnerable() -> bool:
	return state == State.DAZED


func is_dead() -> bool:
	return state == State.KO


func is_capturable() -> bool:
	if mode != Mode.WILD or state in [State.KO, State.CAPTURED]:
		return false
	if stats.health_fraction() > definition.capture_health_threshold:
		return false
	if definition.capture_condition == &"dazed" and state != State.DAZED:
		return false
	return true


func _on_defeated() -> void:
	visual.set_telegraph(false)
	if mode == Mode.COMPANION:
		_set_state(State.KO)
		if owner_player and owner_player.rings:
			owner_player.rings.on_companion_defeated(self)
		vanish(false)
		return
	# Wild creatures are never killed: they faint and retreat into the wilds.
	_set_state(State.KO)
	remove_from_group("targetable")
	EventBus.enemy_killed.emit(definition.id, PackedStringArray(["creature"]), global_position)
	GameState.add_xp(6 + 3 * level)
	Fx.floating_text(global_position + Vector3.UP * 1.5, "Retreated", Color(0.8, 0.8, 0.8))
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.5)
	tw.tween_callback(_despawn)


# -------------------------------------------------------------- Capture

func begin_capture() -> void:
	visual.set_telegraph(false)
	_ability = null
	_set_state(State.CAPTURED)


func capture_visual(progress: float) -> void:
	visual.rotation.y += 0.3
	var s := 1.0 - 0.35 * progress + 0.06 * sin(_time * 25.0)
	visual.scale = Vector3.ONE * s


func complete_capture() -> void:
	remove_from_group("targetable")
	remove_from_group("creatures")
	_set_state(State.KO)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ONE * 0.02, 0.35)
	tw.tween_property(self, "global_position", global_position + Vector3.UP * 1.2, 0.35)
	tw.chain().tween_callback(_despawn)


func break_free(attacker: Node3D) -> void:
	visual.scale = Vector3.ONE
	stats.heal(stats.max_health * 0.12)
	target = attacker
	Fx.ring_burst(global_position + Vector3.UP * 0.5, Color(1, 0.5, 0.3), 1.8)
	_knock = CombatUtil.flat_direction(attacker.global_position, global_position) * 2.0 if attacker else Vector3.ZERO
	_stagger_time = 0.3
	_set_state(State.STAGGER)


func _despawn() -> void:
	if spawner and is_instance_valid(spawner) and spawner.has_method("on_creature_removed"):
		spawner.on_creature_removed(self)
	queue_free()


# ------------------------------------------------------------ Companion

func store_state() -> void:
	if instance:
		instance.health = stats.health


func vanish(instant: bool) -> void:
	remove_from_group("player_team")
	collision_layer = 0
	if instant:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.3)
	tw.tween_callback(queue_free)


func empower(duration: float, mult: float) -> void:
	_empower_until = _time + duration
	_empower_mult = mult
	stats.heal(stats.max_health * 0.3)
	visual.flash(Color(0.5, 0.9, 1.0), 0.4)


func apply_level(inst: CreatureInstance) -> void:
	level = inst.level
	stats.max_health = inst.max_health()
	stats.set_health(inst.health)


func _update_label() -> void:
	if _label == null:
		return
	var text := ""
	if mode == Mode.COMPANION:
		text = "%s  Lv %d" % [instance.display_name() if instance else definition.display_name, level]
		if _hold:
			text += "  (holding)"
		_label.modulate = Color(0.6, 1.0, 0.8)
	else:
		text = "%s  Lv %d" % [definition.display_name, level]
		_label.modulate = Color(1, 1, 1, 0.85)
		if is_capturable():
			text += "\n✦ Capturable"
			_label.modulate = definition.accent_color.lightened(0.35)
	_label.text = text
	var show_marker := is_capturable()
	_capture_marker.visible = show_marker
	if show_marker:
		_capture_marker.rotation.y = _time
		_marker_mat.albedo_color.a = 0.5 + 0.4 * sin(_time * 6.0)

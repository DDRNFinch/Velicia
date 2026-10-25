class_name Player
extends CharacterBody3D
## The Emoria warrior: third-person movement, melee combat (light combo,
## heavy, block/parry, dodge with i-frames), soft targeting and lock-on,
## interaction, skills and the creature ring controller.

signal interactable_changed(target: Node)
signal target_changed(target: Node3D)

enum State { MOVE, ATTACK, DODGE, STAGGER, CAPTURE, DEAD, CHARGE }

const GRAVITY := 18.0
const PARRY_WINDOW := 0.2
const PARRY_WINDOW_ASSIST := 0.32
const DODGE_TIME := 0.42
const DODGE_SPEED := 9.5
const DODGE_IFRAME_START := 0.03
const DODGE_IFRAME_END := 0.3
const DODGE_COST := 22.0
const SPRINT_COST := 14.0
const BUFFER_TIME := 0.32
const COMBO_RESET := 0.75
const LIGHT_COMBO: Array[StringName] = [&"player_light_1", &"player_light_2", &"player_light_3"]
const HEAVY_ATTACK := &"player_heavy"
const MAX_POISE := 40.0
const CHARGED_ATTACK := &"player_heavy_charged"
const CHARGE_MIN := 0.22
const CHARGE_FULL := 1.1
const PERFECT_DODGE_WINDOW := 0.16
const COUNTER_WINDOW := 1.6

@export var walk_speed: float = 2.4
@export var run_speed: float = 5.2
@export var sprint_speed: float = 7.8
@export var acceleration: float = 26.0
@export var deceleration: float = 34.0
@export var air_control: float = 6.0
@export var jump_velocity: float = 6.4
@export var turn_speed: float = 12.0

var team: StringName = &"player"
var body_radius: float = 0.4
var stats: CombatStats
var body: PlaceholderBody
var rings: RingController
var camera_rig: CameraRig
var state: State = State.MOVE
var input_enabled: bool = true
var lock_target: Node3D
var soft_target: Node3D
var current_interactable: Node

var _interactables: Array[Node] = []
var _attack: AttackDefinition
var _attack_elapsed := 0.0
var _attack_stage := -1
var _attack_hits: Array[Node3D] = []
var _attack_is_skill := false
var _combo_index := 0
var _since_attack_end := 99.0
var _buffered := ""
var _buffer_time := 0.0
var _blocking := false
var _block_started := -10.0
var _block_toggled := false
var _dodge_elapsed := 0.0
var _dodge_dir := Vector3.ZERO
var _stagger_time := 0.0
var _stagger_total := 0.1
var _coyote := 0.0
var _jump_buffer := 0.0
var _time := 0.0
var _skill_cooldown := 0.0
var _knockback := Vector3.ZERO
var _sprinting := false
var _last_safe_position := Vector3.ZERO
var _targets_refresh := 0.0
var _interact_refresh := 0.0
var _charge_time := 0.0
var _charge_full_fx := false
var _charge_mult := 1.0
var _counter_until := -10.0
var _perfect_used := false
var _air_speed := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("player_team")
	collision_layer = CombatUtil.LAYER_PLAYER
	collision_mask = CombatUtil.LAYER_WORLD | CombatUtil.LAYER_ENEMY | CombatUtil.LAYER_CREATURE | CombatUtil.LAYER_NPC
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	if get_node_or_null("CollisionShape3D") == null:
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.38
		capsule.height = 1.78
		shape.shape = capsule
		shape.position.y = 0.89
		add_child(shape)

	stats = CombatStats.new()
	stats.name = "Stats"
	add_child(stats)
	stats.setup(GameState.get_max_health(), GameState.get_max_stamina(), MAX_POISE)
	var saved_health := float(GameState.player.get("health", -1.0))
	if saved_health > 0.0:
		stats.set_health(saved_health)
	stats.died.connect(_on_died)
	stats.health_changed.connect(func(h, _m): GameState.player.health = h)

	body = PlaceholderBody.new()
	body.name = "Body"
	add_child(body)
	refresh_appearance()
	body.footstep.connect(_on_footstep)

	rings = RingController.new()
	rings.name = "Rings"
	rings.player = self
	add_child(rings)

	EventBus.player_stats_changed.connect(refresh_stats)
	EventBus.inventory_changed.connect(refresh_appearance)
	SaveManager.before_save.connect(_store_runtime_state)
	CombatDirector.register_player(self)
	_last_safe_position = global_position


func refresh_appearance() -> void:
	var armor := Database.item(GameState.equipment.get("armor", ""))
	var weapon := GameState.get_weapon()
	var armor_color := armor.armor_color if armor else Color(0.3, 0.28, 0.25)
	var kind: StringName = weapon.weapon_kind if weapon else &"fists"
	var params := PlayerAppearance.to_body_params(GameState.player.appearance, armor_color, kind)
	if body.params.is_empty() or _appearance_differs(params):
		body.build(params)


func _appearance_differs(p: Dictionary) -> bool:
	for k in ["skin", "hair", "cloak", "armor", "weapon", "shoulder", "hair_style"]:
		if body.params.get(k) != p.get(k):
			return true
	return false


func refresh_stats() -> void:
	stats.max_health = GameState.get_max_health()
	stats.max_stamina = GameState.get_max_stamina()
	stats.set_health(minf(stats.health, stats.max_health))
	stats.restore_stamina(0.0)


func _store_runtime_state() -> void:
	GameState.saved_position = global_position
	GameState.saved_yaw = rotation.y
	GameState.player.health = stats.health


# ------------------------------------------------------------------ Input

func _pressed(action: String) -> bool:
	return input_enabled and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return input_enabled and Input.is_action_pressed(action)


func get_move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _world_dir(input: Vector2) -> Vector3:
	var yaw := camera_rig.get_yaw() if camera_rig else rotation.y
	return Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)


func _poll_actions() -> void:
	if _pressed("attack_light"):
		_buffer("light")
	if _pressed("attack_heavy"):
		_buffer("heavy")
	if _pressed("dodge"):
		_buffer("dodge")
	if _pressed("skill"):
		_buffer("skill")


func _buffer(action: String) -> void:
	_buffered = action
	_buffer_time = BUFFER_TIME


func _take_buffer() -> String:
	var a := _buffered
	_buffered = ""
	return a


# --------------------------------------------------------------- Physics

func _physics_process(delta: float) -> void:
	_time += delta
	_since_attack_end += delta
	_skill_cooldown = maxf(0.0, _skill_cooldown - delta)
	_buffer_time -= delta
	if _buffer_time <= 0.0:
		_buffered = ""
	_poll_actions()
	_update_targets(delta)
	_update_interactable(delta)

	var on_floor := is_on_floor()
	_coyote = 0.12 if on_floor else _coyote - delta
	if not on_floor:
		velocity.y -= GRAVITY * delta

	match state:
		State.MOVE:
			_state_move(delta)
		State.ATTACK:
			_state_attack(delta)
		State.DODGE:
			_state_dodge(delta)
		State.STAGGER:
			_state_stagger(delta)
		State.CHARGE:
			_state_charge(delta)
		State.CAPTURE, State.DEAD:
			_decelerate(delta)

	if _knockback.length() > 0.05 and state != State.STAGGER:
		velocity.x += _knockback.x
		velocity.z += _knockback.z
		_knockback = _knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	var was_on_floor := is_on_floor()
	if not was_on_floor:
		_air_speed = minf(_air_speed, velocity.y)
	move_and_slide()
	if is_on_floor() and not was_on_floor:
		if _air_speed < -6.0:
			Fx.dust(global_position, clampf(-_air_speed / 8.0, 0.8, 1.6))
		_air_speed = 0.0

	var hspeed := Vector2(velocity.x, velocity.z).length()
	body.animate(delta, hspeed, run_speed, is_on_floor())
	stats.regen_scale = 0.0 if _sprinting else (0.35 if _blocking else (1.3 if GameState.has_ability("second_wind") else 1.0))

	if is_on_floor() and state == State.MOVE and Engine.get_physics_frames() % 30 == 0:
		_last_safe_position = global_position
	if global_position.y < -40.0:
		global_position = _last_safe_position + Vector3.UP
		velocity = Vector3.ZERO
		stats.apply_damage(10.0)


func _decelerate(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, deceleration * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _state_move(delta: float) -> void:
	var input := get_move_input()
	var dir := _world_dir(input)
	var mag := minf(dir.length(), 1.0)
	_update_block()
	_sprinting = _held("sprint") and mag > 0.3 and not _blocking and stats.has_stamina() and is_on_floor()
	if _sprinting:
		stats.drain_stamina(SPRINT_COST * delta)
	var max_speed := sprint_speed if _sprinting else lerpf(walk_speed, run_speed, clampf((mag - 0.25) / 0.55, 0.0, 1.0))
	if _blocking:
		max_speed = walk_speed * 0.75
	var target_vel := dir.normalized() * max_speed if mag > 0.1 else Vector3.ZERO
	var accel := acceleration if target_vel.length() > 0.1 else deceleration
	if not is_on_floor():
		accel = air_control
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_vel, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z

	if lock_target and is_instance_valid(lock_target):
		CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, lock_target.global_position), turn_speed, delta)
	elif hv.length() > 0.3:
		CombatUtil.turn_toward(self, hv.normalized(), turn_speed, delta)

	_jump_buffer = 0.15 if _pressed("jump") else _jump_buffer - delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and not _blocking:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0

	if _pressed("interact"):
		interact()
	if _pressed("quick_heal"):
		quick_heal()
	if _pressed("lock_on"):
		toggle_lock()

	match _take_buffer():
		"light":
			_start_light()
		"heavy":
			_begin_charge()
		"dodge":
			_start_dodge(dir)
		"skill":
			use_skill()


# ------------------------------------------------------- Charged heavy

func _begin_charge() -> void:
	if not stats.has_stamina():
		Fx.floating_text(global_position + Vector3.UP * 2.0, "Out of stamina", Color(1, 0.8, 0.3))
		return
	state = State.CHARGE
	_charge_time = 0.0
	_charge_full_fx = false
	_blocking = false
	var t := _acquire_attack_target()
	if t:
		CombatUtil.face_instantly(self, CombatUtil.flat_direction(global_position, t.global_position))


func is_charging() -> bool:
	return state == State.CHARGE


func charge_fraction() -> float:
	return clampf((_charge_time - CHARGE_MIN) / (CHARGE_FULL - CHARGE_MIN), 0.0, 1.0)


func _state_charge(delta: float) -> void:
	_decelerate(delta)
	_charge_time += delta
	stats.drain_stamina(6.0 * delta)
	var t := current_target()
	if t and global_position.distance_to(t.global_position) < 6.0:
		CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, t.global_position), 8.0, delta)
	body.pose_attack(&"slam", 0, clampf(_charge_time / CHARGE_FULL, 0.0, 1.0) * 0.95)
	if _charge_time >= CHARGE_FULL and not _charge_full_fx:
		_charge_full_fx = true
		body.flash(Color(1.0, 0.85, 0.35), 0.25)
		Fx.ring_burst(global_position + Vector3.UP * 0.2, Color(1.0, 0.8, 0.3), 1.6, 0.35)
		AudioManager.play_sfx("magic", global_position, -6.0)
	if _buffered == "dodge":
		_take_buffer()
		state = State.MOVE
		body.clear_pose()
		_start_dodge(_world_dir(get_move_input()))
		return
	var released := not _held("attack_heavy")
	if released or _charge_time >= CHARGE_FULL + 0.6:
		state = State.MOVE
		if _charge_time < CHARGE_MIN:
			_start_attack(Database.attack(HEAVY_ATTACK))
		else:
			var f := charge_fraction()
			if _start_attack(Database.attack(CHARGED_ATTACK)):
				_charge_mult = lerpf(1.1, 1.9, f)


func _update_block() -> void:
	var want := false
	if Settings.get_value("controls", "toggle_block"):
		if _pressed("block"):
			_block_toggled = not _block_toggled
		want = _block_toggled
	else:
		want = _held("block")
	if want and not stats.has_stamina():
		want = false
	if want and not _blocking:
		_block_started = _time
		body.pose_block()
	elif not want and _blocking:
		body.clear_pose()
	_blocking = want


func is_blocking() -> bool:
	return _blocking


func is_invulnerable() -> bool:
	return state == State.DODGE and _dodge_elapsed >= DODGE_IFRAME_START and _dodge_elapsed <= DODGE_IFRAME_END


# ---------------------------------------------------------------- Attacks

func _start_light() -> void:
	if _since_attack_end > COMBO_RESET:
		_combo_index = 0
	var atk := Database.attack(LIGHT_COMBO[_combo_index % LIGHT_COMBO.size()])
	_combo_index = (_combo_index + 1) % LIGHT_COMBO.size()
	_start_attack(atk)


func _start_attack(atk: AttackDefinition, is_skill: bool = false) -> bool:
	if atk == null:
		return false
	var w := GameState.get_weapon()
	var cost := atk.stamina_cost * (w.stamina_cost_mult if w else 1.0)
	if not stats.use_stamina(cost):
		Fx.floating_text(global_position + Vector3.UP * 2.0, "Out of stamina", Color(1, 0.8, 0.3))
		return false
	_attack = atk
	_attack_elapsed = 0.0
	_attack_stage = -1
	_attack_hits.clear()
	_attack_is_skill = is_skill
	_charge_mult = 1.0
	_blocking = false
	_block_toggled = false
	state = State.ATTACK
	var t := _acquire_attack_target()
	if t:
		CombatUtil.face_instantly(self, CombatUtil.flat_direction(global_position, t.global_position))
	else:
		var dir := _world_dir(get_move_input())
		if dir.length() > 0.2:
			CombatUtil.face_instantly(self, dir.normalized())
	return true


func _state_attack(delta: float) -> void:
	var a := _attack
	if a == null:
		_end_attack()
		return
	var w := GameState.get_weapon()
	_attack_elapsed += delta * (w.attack_speed if w else 1.0)
	var stage := 0
	var t := 0.0
	if _attack_elapsed < a.windup:
		t = _attack_elapsed / maxf(a.windup, 0.001)
	elif _attack_elapsed < a.windup + a.active:
		stage = 1
		t = (_attack_elapsed - a.windup) / maxf(a.active, 0.001)
	else:
		stage = 2
		t = (_attack_elapsed - a.windup - a.active) / maxf(a.recovery, 0.001)
	if stage != _attack_stage:
		_attack_stage = stage
		if stage == 1:
			AudioManager.play_sfx("swing_heavy" if a.is_heavy else "swing", global_position + Vector3.UP)
			body.set_trail(true, Color(1.0, 0.85, 0.5) if _charge_mult > 1.0 else Color(0.9, 0.95, 1.0))
			if a.is_heavy:
				Fx.dust(global_position - global_transform.basis.z * 1.2, 0.8 * _charge_mult)
		elif stage == 2:
			body.set_trail(false)
	body.pose_attack(a.pose, stage, t)

	var lunge := a.lunge_speed if (stage == 0 and t > 0.6) or stage == 1 else 0.0
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(-global_transform.basis.z * lunge, 40.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if stage == 0 and t < a.tracking_until:
		var target := current_target()
		if target and global_position.distance_to(target.global_position) < 5.0:
			CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, target.global_position), 10.0, delta)
	if stage == 1:
		_resolve_hits()
	if stage == 2:
		if _buffered == "dodge":
			_take_buffer()
			_end_attack()
			_start_dodge(_world_dir(get_move_input()))
			return
		if t > 0.3 and not _attack_is_skill and _buffered in ["light", "heavy", "skill"]:
			var next := _take_buffer()
			_end_attack()
			match next:
				"light":
					_start_light()
				"heavy":
					_start_attack(Database.attack(HEAVY_ATTACK))
				"skill":
					use_skill()
			return
	if _attack_elapsed >= a.total_time():
		_end_attack()


func _end_attack() -> void:
	body.set_trail(false)
	_attack = null
	_attack_stage = -1
	_since_attack_end = 0.0
	if state == State.ATTACK:
		state = State.MOVE
	body.clear_pose()


func _resolve_hits() -> void:
	var a := _attack
	var w := GameState.get_weapon()
	var reach := a.reach * ((w.reach / 2.3) if w and not _attack_is_skill else 1.0)
	var targets := CombatUtil.query_targets(self, a, CombatUtil.LAYER_ENEMY | CombatUtil.LAYER_CREATURE, team, reach)
	for target in targets:
		if target in _attack_hits:
			continue
		_attack_hits.append(target)
		var dmg := GameState.get_weapon_damage() * a.damage * _charge_mult
		var crit := false
		if target.has_method("is_vulnerable") and target.is_vulnerable():
			dmg *= 2.2 if GameState.has_ability("emoria_riposte") else 1.5
			crit = true
		elif _time < _counter_until:
			dmg *= 1.8
			crit = true
			_counter_until = -10.0
		var hit := HitData.make(self, target, a, dmg)
		hit.is_critical = crit
		if _charge_mult > 1.0:
			hit.poise_damage *= _charge_mult
			hit.knockback *= _charge_mult
		var result: int = target.receive_hit(hit)
		_on_hit_result(target, result, hit)
		if rings and rings.companion and is_instance_valid(rings.companion):
			rings.companion.on_owner_hit(target)


func _on_hit_result(target: Node3D, result: int, hit: HitData) -> void:
	var pos := target.global_position + Vector3.UP * 1.1
	match result:
		HitData.Result.HIT:
			Fx.hit_spark(pos, Color(1.0, 0.55, 0.2) if hit.is_critical else Color(1, 0.9, 0.7), 1.4 if hit.is_heavy else 1.0)
			Fx.spark_burst(pos, Color(1.0, 0.7, 0.35) if hit.is_critical else Color(1.0, 0.9, 0.7), 1.6 if hit.is_heavy or hit.is_critical else 1.0)
			if hit.is_critical:
				Fx.floating_text(pos + Vector3.UP * 0.8, "Critical!", Color(1.0, 0.6, 0.2))
			Fx.damage_number(pos + Vector3.UP * 0.4, hit.damage, Color(1, 0.6, 0.2) if hit.is_critical else Color(1, 0.95, 0.85))
			Fx.hitstop(0.11 if hit.is_critical else (0.085 if hit.is_heavy else 0.045))
			Fx.shake(0.35 if hit.is_heavy or hit.is_critical else 0.15)
			AudioManager.play_sfx("hit", pos)
		HitData.Result.BLOCKED:
			Fx.hit_spark(pos, Color(0.7, 0.85, 1.0), 0.8)
			Fx.spark_burst(pos, Color(0.75, 0.85, 1.0), 0.7)
			Fx.floating_text(pos + Vector3.UP * 0.4, "Blocked", Color(0.7, 0.85, 1.0))
			AudioManager.play_sfx("block", pos)
			if not hit.is_heavy and not _attack_is_skill:
				# Light attacks bounce off a raised guard: use heavies to break it.
				_end_attack()
				_start_stagger(0.3, -hit.direction * 2.0)
		HitData.Result.EVADED:
			Fx.floating_text(pos, "Evaded", Color(0.8, 0.8, 0.8))


func _acquire_attack_target() -> Node3D:
	if lock_target and is_instance_valid(lock_target):
		return lock_target
	if not Settings.get_value("controls", "auto_target"):
		return null
	var dir := _world_dir(get_move_input())
	if dir.length() < 0.2:
		dir = -global_transform.basis.z
	var assist: bool = Settings.get_value("accessibility", "combat_assist")
	return CombatUtil.best_target(self, dir, get_tree().get_nodes_in_group("targetable"), 6.0 if assist else 4.5, 120.0 if assist else 95.0)


func use_skill() -> void:
	if state != State.MOVE:
		return
	var id := String(GameState.player.get("equipped_skill", ""))
	var ab := Database.ability(id)
	if ab == null or ab.kind != AbilityDefinition.Kind.ACTIVE:
		EventBus.notify.emit("No active skill equipped.")
		return
	if not GameState.has_ability(id):
		EventBus.notify.emit("%s unlocks at level %d." % [ab.display_name, ab.unlock_level])
		return
	if _skill_cooldown > 0.0:
		Fx.floating_text(global_position + Vector3.UP * 2.2, "%.0fs" % ceilf(_skill_cooldown), Color(0.8, 0.8, 1.0))
		return
	if ab.attack:
		if _start_attack(ab.attack, true):
			_skill_cooldown = ab.cooldown
	elif id == "ring_surge":
		if rings.companion == null:
			EventBus.notify.emit("Summon a creature to use Ring Surge.")
			return
		if stats.use_stamina(ab.stamina_cost):
			rings.companion.empower(8.0, ab.power)
			Fx.ring_burst(global_position + Vector3.UP, Color(0.5, 0.9, 1.0), 3.0)
			AudioManager.play_sfx("magic", global_position)
			_skill_cooldown = ab.cooldown


func skill_cooldown() -> float:
	return _skill_cooldown


# ---------------------------------------------------------- Dodge/stagger

func _start_dodge(dir: Vector3) -> void:
	if not stats.use_stamina(DODGE_COST):
		Fx.floating_text(global_position + Vector3.UP * 2.0, "Out of stamina", Color(1, 0.8, 0.3))
		return
	state = State.DODGE
	_dodge_elapsed = 0.0
	_perfect_used = false
	_blocking = false
	Fx.dust(global_position, 0.9)
	if dir.length() < 0.2:
		_dodge_dir = global_transform.basis.z # backstep
	else:
		_dodge_dir = dir.normalized()
		if lock_target == null:
			CombatUtil.face_instantly(self, _dodge_dir)
	body.pose_dodge()
	AudioManager.play_sfx("dodge", global_position)


func _state_dodge(delta: float) -> void:
	_dodge_elapsed += delta
	var k := 1.0 - _dodge_elapsed / DODGE_TIME
	var spd := DODGE_SPEED * (0.3 + 0.7 * k)
	velocity.x = _dodge_dir.x * spd
	velocity.z = _dodge_dir.z * spd
	if _dodge_elapsed >= DODGE_TIME:
		state = State.MOVE
		body.clear_pose()


func _start_stagger(duration: float, knock: Vector3) -> void:
	_attack = null
	_blocking = false
	state = State.STAGGER
	_stagger_time = duration
	_stagger_total = duration
	_knockback = knock


func _state_stagger(delta: float) -> void:
	_stagger_time -= delta
	body.pose_stagger(1.0 - _stagger_time / _stagger_total)
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, 18.0 * delta)
	if _stagger_time <= 0.0:
		state = State.MOVE
		_knockback = Vector3.ZERO
		body.clear_pose()


# -------------------------------------------------------------- Defence

## Resolves an incoming hit; returns a HitData.Result.
func receive_hit(hit: HitData) -> int:
	if state == State.DEAD:
		return HitData.Result.IGNORED
	if is_invulnerable():
		if _dodge_elapsed <= PERFECT_DODGE_WINDOW + DODGE_IFRAME_START and not _perfect_used:
			_on_perfect_dodge(hit)
		else:
			Fx.floating_text(global_position + Vector3.UP * 2.0, "Dodged", Color(0.75, 0.9, 1.0))
		return HitData.Result.EVADED
	var facing := (-global_transform.basis.z).dot(-hit.direction) > 0.2
	if _blocking and facing and not hit.unblockable:
		var window := PARRY_WINDOW_ASSIST if Settings.get_value("accessibility", "combat_assist") else PARRY_WINDOW
		if hit.parryable and _time - _block_started <= window:
			_on_parry(hit)
			return HitData.Result.PARRIED
		var cost := hit.damage * 1.1
		if hit.guard_break or stats.stamina < cost:
			stats.drain_stamina(stats.stamina)
			Fx.floating_text(global_position + Vector3.UP * 2.0, "Guard broken!", Color(1, 0.5, 0.3))
			AudioManager.play_sfx("block", global_position)
			_take_damage(hit.damage * 0.5, hit)
			_start_stagger(0.9, hit.direction * hit.knockback)
			return HitData.Result.HIT
		stats.drain_stamina(cost)
		_take_damage(hit.damage * 0.12, hit, false)
		Fx.hit_spark(global_position + Vector3.UP * 1.3 - hit.direction * 0.5, Color(0.7, 0.85, 1.0), 0.9)
		AudioManager.play_sfx("block", global_position)
		_knockback = hit.direction * hit.knockback * 0.4
		return HitData.Result.BLOCKED
	_take_damage(hit.damage, hit)
	if stats.is_dead():
		return HitData.Result.HIT
	var hyper := state == State.ATTACK and _attack and _attack.is_heavy and _attack_stage == 1
	if (stats.apply_poise_damage(hit.poise_damage) or hit.is_heavy) and not hyper:
		_end_attack()
		_start_stagger(0.55 if hit.is_heavy else 0.4, hit.direction * hit.knockback)
	elif not hyper:
		_knockback = hit.direction * hit.knockback * 0.3
	return HitData.Result.HIT


func _take_damage(amount: float, _hit: HitData, flash: bool = true) -> void:
	var dmg := amount * 50.0 / (50.0 + GameState.get_defense())
	stats.apply_damage(dmg)
	if flash:
		body.flash(Color(1, 0.2, 0.2))
		Fx.spark_burst(global_position + Vector3.UP * 1.2, Color(1.0, 0.35, 0.25), 0.7)
		Fx.damage_number(global_position + Vector3.UP * 2.0, dmg, Color(1, 0.35, 0.3))
		Fx.shake(0.25)
		AudioManager.play_sfx("hit", global_position + Vector3.UP)


## Dodging at the last moment slows time and opens a counter window.
func _on_perfect_dodge(hit: HitData) -> void:
	_perfect_used = true
	_counter_until = _time + COUNTER_WINDOW
	stats.restore_stamina(25.0)
	Fx.floating_text(global_position + Vector3.UP * 2.2, "Perfect dodge!", Color(0.6, 0.95, 1.0))
	Fx.ring_burst(global_position + Vector3.UP * 0.5, Color(0.6, 0.95, 1.0), 2.4, 0.5)
	Fx.slowmo(0.45, 0.3)
	AudioManager.play_sfx("magic", global_position)
	if hit.source and is_instance_valid(hit.source) and hit.source.has_method("expose"):
		hit.source.expose(COUNTER_WINDOW)


func has_counter() -> bool:
	return _time < _counter_until


func _on_parry(hit: HitData) -> void:
	var pos := global_position + Vector3.UP * 1.3 - hit.direction * 0.6
	Fx.hit_spark(pos, Color(1.0, 0.85, 0.3), 1.8)
	Fx.spark_burst(pos, Color(1.0, 0.85, 0.4), 2.0)
	Fx.floating_text(pos + Vector3.UP * 0.6, "Parry!", Color(1.0, 0.85, 0.3))
	Fx.hitstop(0.13)
	Fx.shake(0.3)
	AudioManager.play_sfx("parry", pos)
	stats.restore_stamina(15.0)
	if hit.source and is_instance_valid(hit.source) and hit.source.has_method("on_parried"):
		hit.source.on_parried(self)


func _on_died() -> void:
	state = State.DEAD
	_attack = null
	_blocking = false
	body.play_death()
	set_lock(null)
	rings.dismiss(true)
	EventBus.player_died.emit()


func respawn_at(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	state = State.MOVE
	body.reset_death()
	body.clear_pose()
	stats.setup(GameState.get_max_health(), GameState.get_max_stamina(), MAX_POISE)
	_last_safe_position = pos
	if camera_rig:
		camera_rig.snap_behind_target()
	EventBus.player_respawned.emit()


func is_dead() -> bool:
	return state == State.DEAD


func is_targetable() -> bool:
	return state != State.DEAD


func apply_consumable(def: ItemDefinition) -> void:
	if def.heal_amount > 0.0:
		stats.heal(def.heal_amount)
		Fx.floating_text(global_position + Vector3.UP * 2.0, "+%d" % roundi(def.heal_amount), Color(0.4, 1.0, 0.5))
	if def.stamina_restore > 0.0:
		stats.restore_stamina(def.stamina_restore)
	AudioManager.play_sfx("pickup", global_position)


func quick_heal() -> void:
	if state != State.MOVE:
		return
	if stats.health >= stats.max_health:
		EventBus.notify.emit("Already at full health.")
		return
	var best := ""
	for id in GameState.inventory:
		var def := Database.item(id)
		if def and def.type == ItemDefinition.ItemType.CONSUMABLE and def.heal_amount > 0.0:
			best = id
			break
	if best.is_empty():
		EventBus.notify.emit("No healing items.")
		return
	GameState.use_consumable(best, self)


# --------------------------------------------------------------- Targets

func current_target() -> Node3D:
	if lock_target and is_instance_valid(lock_target):
		return lock_target
	if soft_target and is_instance_valid(soft_target):
		return soft_target
	return null


func _update_targets(delta: float) -> void:
	if soft_target != null and not is_instance_valid(soft_target):
		soft_target = null
	if lock_target:
		var invalid := not is_instance_valid(lock_target)
		if invalid or (lock_target.has_method("is_targetable") and not lock_target.is_targetable()) or global_position.distance_to(lock_target.global_position) > 25.0:
			set_lock(null)
	_targets_refresh -= delta
	if _targets_refresh > 0.0:
		return
	_targets_refresh = 0.15
	var new_soft: Node3D = lock_target
	if new_soft == null:
		var dir := _world_dir(get_move_input())
		if dir.length() < 0.2:
			dir = camera_rig.get_forward() if camera_rig else -global_transform.basis.z
		new_soft = CombatUtil.best_target(self, dir, get_tree().get_nodes_in_group("targetable"), 9.0, 70.0)
	if new_soft != soft_target:
		soft_target = new_soft
		target_changed.emit(soft_target)


func toggle_lock() -> void:
	if lock_target:
		set_lock(null)
		return
	var fwd := camera_rig.get_forward() if camera_rig else -global_transform.basis.z
	set_lock(CombatUtil.best_target(self, fwd, get_tree().get_nodes_in_group("targetable"), 20.0, 75.0))


func set_lock(t: Node3D) -> void:
	lock_target = t
	_targets_refresh = 0.0
	if t:
		soft_target = t
	target_changed.emit(soft_target if t == null else t)


# ------------------------------------------------------------ Interaction

func register_interactable(n: Node) -> void:
	if not (n in _interactables):
		_interactables.append(n)
	_interact_refresh = 0.0


func unregister_interactable(n: Node) -> void:
	_interactables.erase(n)
	_interact_refresh = 0.0


func _update_interactable(delta: float) -> void:
	_interact_refresh -= delta
	if _interact_refresh > 0.0:
		return
	_interact_refresh = 0.2
	var best: Node = null
	var best_d := INF
	for n in _interactables.duplicate():
		if not is_instance_valid(n):
			_interactables.erase(n)
			continue
		if n.has_method("can_interact") and not n.can_interact():
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != current_interactable:
		current_interactable = best
		interactable_changed.emit(best)


func interact() -> void:
	if state != State.MOVE or current_interactable == null or not is_instance_valid(current_interactable):
		return
	current_interactable.interact(self)
	_interact_refresh = 0.0


func _on_footstep() -> void:
	AudioManager.play_sfx("footstep", global_position, -12.0, 0.15)

class_name Enemy
extends CharacterBody3D
## Data-driven melee enemy. Patrols, notices the player, circles while
## waiting for an attack token, telegraphs attacks, blocks, staggers when
## poise breaks and can be parried. Bosses switch tactics by phase.

enum State { IDLE, PATROL, ALERT, CHASE, POSITION, ATTACK, RECOVER, STAGGER, ROAR, RETURN, DEAD }

const GRAVITY := 18.0
const SLEEP_DISTANCE := 75.0

@export var definition: EnemyDefinition
## Set for enemies whose defeat should persist (bosses, story enemies).
@export var unique_id: String = ""
@export var patrol_radius: float = 6.0
## Bosses wait for an arena trigger before fighting.
@export var wait_for_engage: bool = false
@export var variant: int = 0

var team: StringName = &"gyria"
var body_radius: float = 0.4
var stats: CombatStats
var body: PlaceholderBody
var state: State = State.IDLE
var target: Node3D
var home: Vector3
var phase_index: int = -1
var engaged: bool = false

var _state_time := 0.0
var _time := 0.0
var _patrol_point := Vector3.ZERO
var _attack: AttackDefinition
var _attack_elapsed := 0.0
var _attack_stage := -1
var _attack_hits: Array[Node3D] = []
var _cooldowns: Dictionary = {}
var _guard_until := -1.0
var _knock := Vector3.ZERO
var _stagger_time := 0.0
var _vulnerable_until := -1.0
var _strafe_dir := 1.0
var _has_token := false
var _sleeping := false
var _alert_label: Label3D
var _telegraph_disc: MeshInstance3D
var _telegraph_mat: StandardMaterial3D
var _speed_mult := 1.0
var _recovery_mult := 1.0
var _home_set := false
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _aim_line: MeshInstance3D
var _aim_mat: StandardMaterial3D


func _ready() -> void:
	if definition == null:
		push_error("Enemy without definition: " + str(get_path()))
		queue_free()
		return
	if not unique_id.is_empty() and GameState.is_world_marked("defeated", unique_id):
		queue_free()
		return
	add_to_group("enemies")
	add_to_group("targetable")
	collision_layer = CombatUtil.LAYER_ENEMY
	collision_mask = CombatUtil.LAYER_WORLD | CombatUtil.LAYER_PLAYER | CombatUtil.LAYER_ENEMY | CombatUtil.LAYER_CREATURE
	floor_snap_length = 0.4

	var params := PlaceholderBody.preset(&"gyria_boss" if definition.is_boss else definition.people, variant)
	if definition.is_boss:
		params.shoulder = float(params.shoulder) * definition.scale
	params.height = float(params.height) * definition.scale
	params.skin = definition.skin_color
	params.armor = definition.armor_color
	params.accent = definition.accent_color
	params.weapon = definition.weapon_kind
	params.shield = definition.shield
	body = PlaceholderBody.new()
	add_child(body)
	body.build(params)
	var h: float = params.height
	body_radius = maxf(0.35, float(params.shoulder) * 0.6)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_radius
	capsule.height = h
	shape.shape = capsule
	shape.position.y = h * 0.5
	add_child(shape)

	stats = CombatStats.new()
	add_child(stats)
	stats.setup(definition.max_health, 100.0, definition.max_poise)
	stats.died.connect(_on_died)

	_alert_label = Label3D.new()
	_alert_label.text = "!"
	_alert_label.font_size = 96
	_alert_label.outline_size = 16
	_alert_label.modulate = Color(1, 0.8, 0.2)
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.position.y = h + 0.5
	_alert_label.visible = false
	add_child(_alert_label)

	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 24
	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat.albedo_color = Color(1, 0.2, 0.1, 0.3)
	_telegraph_disc = MeshInstance3D.new()
	_telegraph_disc.mesh = disc
	_telegraph_disc.material_override = _telegraph_mat
	_telegraph_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_disc.top_level = true
	_telegraph_disc.visible = false
	add_child(_telegraph_disc)

	_build_health_bar(h)
	_build_aim_line()
	home = global_position
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	if definition.is_boss:
		_enter_phase(0, false)
	_set_state(State.IDLE if wait_for_engage else State.PATROL)
	EventBus.player_respawned.connect(_on_player_respawned)


func _build_health_bar(h: float) -> void:
	if definition.is_boss:
		return
	_bar_root = Node3D.new()
	_bar_root.position.y = h + 0.35
	_bar_root.visible = false
	add_child(_bar_root)
	var bg := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.09)
	bg.mesh = quad
	bg.material_override = _bar_material(Color(0.05, 0.05, 0.06, 0.75), 0)
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.86, 0.06)
	_bar_fill.mesh = fq
	_bar_fill.material_override = _bar_material(Color(0.85, 0.22, 0.18, 0.95), 1)
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(_bar_fill)


static func _bar_material(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = priority
	m.albedo_color = c
	return m


func _update_health_bar() -> void:
	if _bar_root == null:
		return
	var frac := stats.health_fraction()
	_bar_root.visible = frac < 0.999 and state != State.DEAD
	_bar_fill.scale.x = maxf(frac, 0.001)


func _build_aim_line() -> void:
	_aim_line = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, 1.0)
	_aim_line.mesh = box
	_aim_mat = StandardMaterial3D.new()
	_aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_mat.albedo_color = Color(Settings.telegraph_color(), 0.5)
	_aim_line.material_override = _aim_mat
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_line.top_level = true
	_aim_line.visible = false
	add_child(_aim_line)


func _update_aim_line(t: float) -> void:
	if target == null or not is_instance_valid(target):
		_aim_line.visible = false
		return
	var from := body.get_hand_position()
	var to := target.global_position + Vector3.UP * 1.1
	_aim_line.visible = true
	_aim_line.global_position = (from + to) * 0.5
	_aim_line.look_at(to, Vector3.UP)
	_aim_line.scale = Vector3(1.0 + t * 1.5, 1.0 + t * 1.5, from.distance_to(to))
	_aim_mat.albedo_color = Color(Settings.telegraph_color(), 0.15 + 0.55 * t)


func _set_state(s: State) -> void:
	if state == State.ATTACK and s != State.ATTACK:
		body.set_telegraph(false)
		body.set_trail(false)
		_telegraph_disc.visible = false
		if _aim_line:
			_aim_line.visible = false
	state = s
	_state_time = 0.0


func current_attacks() -> Array[AttackDefinition]:
	if definition.is_boss and phase_index >= 0 and phase_index < definition.phases.size():
		return definition.phases[phase_index].attacks
	return definition.attacks


# ------------------------------------------------------------ Main loop

func _physics_process(delta: float) -> void:
	if definition == null:
		return
	if not _home_set:
		# Home is taken after the first physics frame so ground snapping applies.
		_home_set = true
		home = global_position
	_time += delta
	_state_time += delta
	for k in _cooldowns.keys():
		_cooldowns[k] = maxf(0.0, float(_cooldowns[k]) - delta)

	var player := CombatDirector.player
	if state != State.DEAD and player and is_instance_valid(player):
		var far := global_position.distance_to(player.global_position) > SLEEP_DISTANCE
		if far != _sleeping:
			_sleeping = far
			body.visible = not far
		if far and state in [State.IDLE, State.PATROL]:
			return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	match state:
		State.IDLE:
			_slow(delta)
			_look_for_target()
		State.PATROL:
			_state_patrol(delta)
		State.ALERT:
			_slow(delta)
			_face_target(delta, 6.0)
			if _state_time > (0.4 if definition.is_boss else 0.6):
				_alert_label.visible = false
				_set_state(State.CHASE)
		State.CHASE, State.POSITION:
			_state_engage(delta)
		State.ATTACK:
			_state_attack(delta)
		State.RECOVER:
			_slow(delta)
			if _state_time > 0.35 * _recovery_mult:
				_set_state(State.POSITION)
		State.STAGGER:
			_stagger_time -= delta
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
			body.pose_stagger(clampf(_state_time / 0.6, 0.0, 1.0))
			if _stagger_time <= 0.0:
				body.clear_pose()
				_set_state(State.POSITION)
		State.ROAR:
			_slow(delta)
			body.pose_attack(&"roar", 1, clampf(_state_time / 0.5, 0.0, 1.0))
			if _state_time > 1.3:
				body.clear_pose()
				_set_state(State.POSITION)
		State.RETURN:
			_state_return(delta)
		State.DEAD:
			_slow(delta)
	move_and_slide()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	body.animate(delta, hspeed, definition.run_speed, is_on_floor())
	if global_position.y < -40.0:
		global_position = home + Vector3.UP * 2.0
		velocity = Vector3.ZERO


func _slow(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 24.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _steer(want: Vector3, delta: float, accel: float = 18.0) -> void:
	if is_on_wall() and want.length() > 0.1:
		want = want.rotated(Vector3.UP, 1.0 * _strafe_dir)
	# Light separation from other enemies so groups don't stack.
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == self:
			continue
		var off: Vector3 = global_position - (n as Node3D).global_position
		off.y = 0.0
		var d := off.length()
		if d > 0.01 and d < 1.6:
			want += off.normalized() * (1.6 - d) * 2.5
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _face_target(delta: float, speed: float) -> void:
	if target and is_instance_valid(target):
		CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, target.global_position), speed, delta)


# ---------------------------------------------------------------- States

func _state_patrol(delta: float) -> void:
	if _patrol_point == Vector3.ZERO or _state_time > 7.0 or global_position.distance_to(_patrol_point) < 0.8:
		var ang := randf() * TAU
		_patrol_point = home + Vector3(cos(ang), 0, sin(ang)) * randf_range(1.5, patrol_radius)
		_state_time = randf_range(0.0, 2.5)
	if _state_time < 2.5:
		_slow(delta)
	else:
		var dir := CombatUtil.flat_direction(global_position, _patrol_point)
		_steer(dir * definition.walk_speed, delta)
		if dir.length() > 0.1:
			CombatUtil.turn_toward(self, dir, 5.0, delta)
	_look_for_target()


func _look_for_target() -> void:
	if wait_for_engage and not engaged:
		return
	var t := _nearest_hostile(definition.aggro_range)
	if t:
		_notice(t)


func _notice(t: Node3D) -> void:
	target = t
	engaged = true
	_alert_label.visible = true
	AudioManager.play_sfx("alert", global_position)
	_set_state(State.ALERT)
	if definition.is_boss:
		EventBus.boss_engaged.emit(self)
	# Alert nearby allies.
	for n in get_tree().get_nodes_in_group("enemies"):
		if n != self and n is Enemy and (n as Enemy).state in [State.IDLE, State.PATROL]:
			if (n as Enemy).global_position.distance_to(global_position) < 12.0 and not (n as Enemy).wait_for_engage:
				(n as Enemy).call_deferred("_notice", t)


func engage() -> void:
	if state in [State.DEAD] or engaged:
		return
	var t := _nearest_hostile(60.0)
	if t:
		_notice(t)


func _nearest_hostile(max_d: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_d
	for n in get_tree().get_nodes_in_group("player_team"):
		var node := n as Node3D
		if node == null or (node.has_method("is_dead") and node.is_dead()):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _state_engage(delta: float) -> void:
	if target == null or not is_instance_valid(target) or (target.has_method("is_dead") and target.is_dead()):
		var t := _nearest_hostile(definition.aggro_range * 1.5)
		if t:
			target = t
		else:
			_give_up()
			return
	if global_position.distance_to(home) > definition.leash_range:
		_give_up()
		return
	CombatDirector.mark_engaged(self)
	# Occasionally retarget to whichever ally of the player is closer.
	if Engine.get_physics_frames() % 45 == 0:
		var closer := _nearest_hostile(definition.aggro_range)
		if closer and closer != target and global_position.distance_to(closer.global_position) < global_position.distance_to(target.global_position) - 2.0:
			target = closer
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length() - CombatUtil.body_radius(target)
	var dir := to.normalized()
	_face_target(delta, definition.turn_speed)
	_maybe_guard()

	var atk := _choose_attack(d)
	if atk:
		# Ranged shots don't need a melee slot, so archers keep firing.
		if (atk.projectile_speed > 0.0 and CombatDirector.request_shot()) or (atk.projectile_speed <= 0.0 and CombatDirector.request_token(self)):
			_has_token = true
			_start_attack(atk)
			return
	var desired := definition.preferred_distance
	var want := Vector3.ZERO
	if d > desired + 1.5:
		_set_state_keep(State.CHASE)
		want = dir * definition.run_speed * _speed_mult
	elif d < desired - 0.8:
		want = -dir * definition.walk_speed
	else:
		_set_state_keep(State.POSITION)
		if randf() < 0.004:
			_strafe_dir *= -1.0
		want = dir.cross(Vector3.UP) * _strafe_dir * definition.walk_speed * 0.7
		# Close in when an attack slot is free.
		if d > 1.2:
			want += dir * definition.walk_speed * 0.5
	_steer(want, delta)


func _set_state_keep(s: State) -> void:
	if state != s:
		state = s


func _maybe_guard() -> void:
	if definition.block_chance <= 0.0 or _time < _guard_until + 1.5:
		return
	var p := target as Player
	if p and p.state == Player.State.ATTACK and global_position.distance_to(p.global_position) < 3.5:
		if randf() < definition.block_chance * 0.08:
			_guard_until = _time + 0.9
			body.pose_block()


func is_guarding() -> bool:
	return _time < _guard_until


func _choose_attack(distance: float) -> AttackDefinition:
	if is_guarding():
		return null
	var options: Array[AttackDefinition] = []
	var total := 0.0
	var los_checked := false
	var los := true
	for a in current_attacks():
		if float(_cooldowns.get(a.id, 0.0)) > 0.0:
			continue
		if distance < a.min_range or distance > a.max_range:
			continue
		if a.projectile_speed > 0.0:
			if not los_checked:
				los_checked = true
				los = _has_line_of_sight()
			if not los:
				continue
		options.append(a)
		total += a.weight
	if options.is_empty():
		return null
	var roll := randf() * total
	for a in options:
		roll -= a.weight
		if roll <= 0.0:
			return a
	return options[-1]


## True when nothing solid blocks a shot at the current target.
func _has_line_of_sight() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var from := global_position + Vector3.UP * body.height * 0.8
	var to := target.global_position + Vector3.UP * 1.1
	var q := PhysicsRayQueryParameters3D.create(from, to, CombatUtil.LAYER_WORLD | CombatUtil.LAYER_NPC, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _start_attack(atk: AttackDefinition) -> void:
	_attack = atk
	_attack_elapsed = 0.0
	_attack_stage = -1
	_attack_hits.clear()
	_cooldowns[atk.id] = atk.cooldown
	body.clear_pose()
	_guard_until = -1.0
	_set_state(State.ATTACK)
	body.set_telegraph(true, Settings.telegraph_color())
	if atk.ground_telegraph:
		_telegraph_mat.albedo_color = Color(Settings.telegraph_color(), 0.28)
		_telegraph_disc.visible = true


func _state_attack(delta: float) -> void:
	var a := _attack
	if a == null:
		_set_state(State.POSITION)
		return
	_attack_elapsed += delta * _speed_mult
	var stage := 0
	var t := 0.0
	var recovery := a.recovery * _recovery_mult
	if _attack_elapsed < a.windup:
		t = _attack_elapsed / a.windup
	elif _attack_elapsed < a.windup + a.active:
		stage = 1
		t = (_attack_elapsed - a.windup) / maxf(a.active, 0.001)
	else:
		stage = 2
		t = (_attack_elapsed - a.windup - a.active) / maxf(recovery, 0.001)
	if stage != _attack_stage:
		_attack_stage = stage
		if stage == 1:
			body.set_telegraph(false)
			if a.projectile_speed > 0.0:
				_fire_projectile(a)
			else:
				body.set_trail(true, Color(1.0, 0.75, 0.6))
				AudioManager.play_sfx("swing_heavy" if a.is_heavy else "swing", global_position + Vector3.UP)
				if a.ground_telegraph:
					Fx.dust(global_position - global_transform.basis.z * a.reach * 0.3, 2.2)
					Fx.shake(0.4)
		if stage == 2:
			_telegraph_disc.visible = false
			body.set_trail(false)
			if _has_token:
				CombatDirector.release_token(self)
				_has_token = false
	body.pose_attack(a.pose, stage, t)
	if stage == 0 and t < a.tracking_until:
		_face_target(delta, definition.turn_speed * 0.8)
	if a.projectile_speed > 0.0:
		if stage == 0:
			_update_aim_line(t)
		else:
			_aim_line.visible = false
	var lunge := a.lunge_speed if (stage == 0 and t > 0.7) or stage == 1 else 0.0
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(-global_transform.basis.z * lunge, 40.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if _telegraph_disc.visible:
		var center := global_position - global_transform.basis.z * (a.reach * 0.5 if a.hit_shape != AttackDefinition.HitShape.CIRCLE else 0.0)
		_telegraph_disc.global_position = center + Vector3.UP * 0.08
		var r := a.reach if a.hit_shape == AttackDefinition.HitShape.CIRCLE else a.reach * 0.6
		_telegraph_disc.scale = Vector3(r, 1, r) * (0.4 + 0.6 * t)
	if stage == 1 and a.projectile_speed <= 0.0:
		_resolve_hits(a)
	if _attack_elapsed >= a.windup + a.active + recovery:
		body.clear_pose()
		_attack = null
		_set_state(State.RECOVER)


func _resolve_hits(a: AttackDefinition) -> void:
	var targets := CombatUtil.query_targets(self, a, CombatUtil.LAYER_PLAYER | CombatUtil.LAYER_CREATURE, team)
	for t in targets:
		if t in _attack_hits:
			continue
		if not t.is_in_group("player_team"):
			continue
		_attack_hits.append(t)
		var hit := HitData.make(self, t, a, a.damage)
		var result: int = t.receive_hit(hit)
		if result == HitData.Result.HIT and t is CreatureActor:
			Fx.hit_spark(t.global_position + Vector3.UP, Color(1, 0.4, 0.3))


func _fire_projectile(a: AttackDefinition) -> void:
	if target == null or not is_instance_valid(target):
		return
	var arrow := Projectile.new()
	arrow.source = self
	arrow.attack = a
	arrow.damage = a.damage
	arrow.team = team
	arrow.max_distance = a.projectile_range
	get_parent().add_child(arrow)
	var from := body.get_hand_position() - global_transform.basis.z * 0.4
	var aim := target.global_position + Vector3.UP * 1.15
	# Lead the target slightly so strafing alone isn't a perfect defence.
	var tv = target.get("velocity")
	if tv is Vector3:
		aim += Vector3(tv.x, 0, tv.z) * (from.distance_to(aim) / a.projectile_speed) * 0.6
	arrow.launch(from, aim, a.projectile_speed)
	AudioManager.play_sfx("swing", global_position + Vector3.UP, -4.0)


func _give_up() -> void:
	target = null
	engaged = false
	if _has_token:
		CombatDirector.release_token(self)
		_has_token = false
	_set_state(State.RETURN)
	if definition.is_boss:
		EventBus.boss_engaged.emit(null)


func _state_return(delta: float) -> void:
	var to := home - global_position
	to.y = 0.0
	if to.length() < 1.0:
		stats.heal(stats.max_health)
		_set_state(State.IDLE if wait_for_engage else State.PATROL)
		return
	_steer(to.normalized() * definition.run_speed, delta)
	CombatUtil.turn_toward(self, to.normalized(), 6.0, delta)
	stats.heal(stats.max_health * 0.2 * delta)
	_update_health_bar()


# -------------------------------------------------------------- Defence

func receive_hit(hit: HitData) -> int:
	if state == State.DEAD:
		return HitData.Result.IGNORED
	if target == null and hit.source:
		_notice(hit.source)
	var facing := (-global_transform.basis.z).dot(-hit.direction) > 0.3
	var shield_up := definition.shield and state != State.STAGGER and not (state == State.ATTACK and _attack_stage >= 1) and not is_vulnerable()
	if shield_up and facing:
		if hit.guard_break or hit.is_heavy:
			# Heavy blows smash the shield guard aside.
			stats.apply_damage(hit.damage * 0.35)
			_update_health_bar()
			Fx.spark_burst(global_position + Vector3.UP * 1.3, Color(0.8, 0.85, 1.0), 1.5)
			Fx.floating_text(global_position + Vector3.UP * 2.3, "Guard broken!", Color(1, 0.6, 0.3))
			_stagger(1.1, hit.direction * hit.knockback)
			_vulnerable_until = _time + 1.2
			return HitData.Result.HIT
		Fx.spark_burst(global_position + Vector3.UP * 1.3, Color(0.8, 0.85, 1.0), 0.6)
		_knock = hit.direction * 1.2
		return HitData.Result.BLOCKED
	if is_guarding() and facing and not hit.guard_break and not hit.is_heavy:
		stats.apply_damage(hit.damage * 0.15)
		_knock = hit.direction * 1.5
		return HitData.Result.BLOCKED
	var dmg := hit.damage * 40.0 / (40.0 + definition.defense)
	stats.apply_damage(dmg)
	_update_health_bar()
	body.flash(Color(1, 1, 1))
	if stats.is_dead():
		return HitData.Result.HIT
	if definition.is_boss:
		_check_phase()
	_guard_until = -1.0
	var poise_break := stats.apply_poise_damage(hit.poise_damage)
	var interruptible := state != State.ATTACK or _attack_stage == 0
	if (poise_break or (hit.guard_break and is_guarding())) and state != State.ROAR:
		_stagger(0.8 if definition.is_boss else 0.6, hit.direction * hit.knockback)
	elif interruptible and not definition.is_boss and state != State.STAGGER:
		_knock = hit.direction * hit.knockback * 0.5
		velocity.x += _knock.x
		velocity.z += _knock.z
	return HitData.Result.HIT


func _stagger(duration: float, knock: Vector3) -> void:
	_attack = null
	if _has_token:
		CombatDirector.release_token(self)
		_has_token = false
	_knock = knock
	_stagger_time = duration
	_set_state(State.STAGGER)


func on_parried(_by: Node3D) -> void:
	if state == State.DEAD:
		return
	_stagger(1.4 if not definition.is_boss else 1.1, -global_transform.basis.z * -2.0)
	_vulnerable_until = _time + 1.6
	Fx.floating_text(global_position + Vector3.UP * (body.height + 0.3), "Staggered!", Color(1, 0.85, 0.3))


## Opens the enemy to critical hits without staggering it (perfect dodge).
func expose(duration: float) -> void:
	_vulnerable_until = _time + duration
	body.flash(Color(0.6, 0.95, 1.0), 0.3)


## True while open to a riposte (critical hits).
func is_vulnerable() -> bool:
	return _time < _vulnerable_until


func is_targetable() -> bool:
	return state != State.DEAD and not _sleeping


func is_dead() -> bool:
	return state == State.DEAD


func _check_phase() -> void:
	var frac := stats.health_fraction()
	var idx := phase_index
	for i in definition.phases.size():
		if frac <= definition.phases[i].health_fraction:
			idx = i
	if idx > phase_index:
		_enter_phase(idx, true)


func _enter_phase(idx: int, announce: bool) -> void:
	phase_index = idx
	var ph := definition.phases[idx] if idx < definition.phases.size() else null
	_speed_mult = ph.speed_mult if ph else 1.0
	_recovery_mult = ph.recovery_mult if ph else 1.0
	if announce and ph:
		if not ph.announcement.is_empty():
			EventBus.notify.emit(ph.announcement)
		_attack = null
		_set_state(State.ROAR)
		AudioManager.play_sfx("roar", global_position)
		Fx.shake(0.6)
		Fx.ring_burst(global_position + Vector3.UP * 0.3, definition.accent_color, 6.0, 0.8)
		# Shove nearby foes back without damage.
		for n in get_tree().get_nodes_in_group("player_team"):
			if n is Player and (n as Player).global_position.distance_to(global_position) < 5.0:
				(n as Player)._start_stagger(0.5, CombatUtil.flat_direction(global_position, (n as Player).global_position) * 6.0)


func _on_died() -> void:
	if _has_token:
		CombatDirector.release_token(self)
		_has_token = false
	_set_state(State.DEAD)
	_alert_label.visible = false
	_update_health_bar()
	remove_from_group("targetable")
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = CombatUtil.LAYER_WORLD
	body.play_death()
	GameState.add_xp(definition.xp_reward)
	if not unique_id.is_empty():
		GameState.mark_world("defeated", unique_id)
	_drop_loot()
	EventBus.enemy_killed.emit(definition.id, definition.tags, global_position)
	if definition.is_boss:
		EventBus.boss_defeated.emit(definition.id)
		EventBus.boss_engaged.emit(null)
		EventBus.notify.emit("%s has been defeated!" % definition.display_name)
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.6)
	tw.tween_callback(queue_free)


func _drop_loot() -> void:
	for item_id in definition.loot:
		if randf() <= float(definition.loot[item_id]):
			var pickup := LootPickup.new()
			pickup.item_id = String(item_id)
			get_parent().add_child(pickup)
			pickup.global_position = global_position + Vector3(randf_range(-0.8, 0.8), 0.4, randf_range(-0.8, 0.8))


func _on_player_respawned() -> void:
	if state == State.DEAD:
		return
	target = null
	engaged = false
	_attack = null
	body.clear_pose()
	global_position = home
	velocity = Vector3.ZERO
	stats.heal(stats.max_health)
	if definition.is_boss:
		_enter_phase(0, false)
	_set_state(State.IDLE if wait_for_engage else State.PATROL)

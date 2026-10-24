class_name RingController
extends Node3D
## The Emoria magical rings: capture weakened creatures into empty rings,
## summon and dismiss them, cycle the active ring and command the companion.
## Creatures resting in rings slowly recover; exhausted ones need time or a
## Ring Stone shrine before they can be summoned again.

signal changed
signal capture_started(target: CreatureActor)
signal capture_finished(success: bool)

const CAPTURE_TIME := 1.5
const SUMMON_COOLDOWN := 1.0
const RING_REGEN := 0.03 # fraction of max health per second while resting

var player: Player
var companion: CreatureActor
## Tests can force capture results: -1 random, 0 fail, 1 success.
var force_capture_result: int = -1

var _capture_target: CreatureActor
var _capture_elapsed := 0.0
var _capture_slot := -1
var _summon_cooldown := 0.0
var _ring_mesh: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	top_level = true
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.1
	torus.rings = 16
	torus.ring_segments = 6
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.85, 0.7, 0.35)
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.mesh = torus
	_ring_mesh.material_override = _ring_mat
	_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring_mesh)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.06
	beam_mesh.bottom_radius = 0.06
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 6
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = Color(0.6, 0.95, 1.0, 0.7)
	_beam = MeshInstance3D.new()
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	_time += delta
	_summon_cooldown = maxf(0.0, _summon_cooldown - delta)
	for c in GameState.creatures:
		if c.ring_slot >= 0 and (companion == null or companion.instance != c) and not c.is_exhausted():
			c.health = minf(c.max_health(), c.health + c.max_health() * RING_REGEN * delta)
	_update_ring_visual()
	if player == null:
		return
	if _capture_target != null:
		_update_capture(delta)
		return
	if player.input_enabled and player.state == Player.State.MOVE:
		if Input.is_action_just_pressed("summon"):
			toggle_summon()
		if Input.is_action_just_pressed("ring_next"):
			cycle(1)
		if Input.is_action_just_pressed("ring_prev"):
			cycle(-1)
		if Input.is_action_just_pressed("capture"):
			var c := capture_candidate()
			if c:
				try_capture(c)
			else:
				EventBus.notify.emit("No weakened creature nearby to capture.")
		if Input.is_action_just_pressed("companion_command"):
			command()


func _update_ring_visual() -> void:
	if player == null or player.body == null:
		return
	_ring_mesh.global_position = player.body.get_hand_position() + Vector3.UP * 0.05
	_ring_mesh.rotation = Vector3(PI * 0.5, _time * 2.0, 0)
	var inst := GameState.creature_in_slot(GameState.active_ring)
	var col := Color(0.85, 0.7, 0.35)
	if inst and inst.definition():
		col = inst.definition().accent_color
		if inst.is_exhausted():
			col = col.darkened(0.6)
	_ring_mat.albedo_color = col
	var pulse := 1.0 + 0.15 * sin(_time * 4.0)
	if companion:
		pulse += 0.3
	_ring_mesh.scale = Vector3.ONE * pulse
	_ring_mesh.visible = not GameState.ring_slots.is_empty()


# ---------------------------------------------------------------- Capture

func _player_target() -> Node3D:
	if player.lock_target and is_instance_valid(player.lock_target):
		return player.lock_target
	if player.soft_target and is_instance_valid(player.soft_target):
		return player.soft_target
	return null


func capture_candidate() -> CreatureActor:
	var t := _player_target()
	if t is CreatureActor and (t as CreatureActor).is_capturable():
		return t as CreatureActor
	var best: CreatureActor = null
	var best_d := 8.0
	for n in get_tree().get_nodes_in_group("creatures"):
		var c := n as CreatureActor
		if c and c.is_capturable():
			var d := player.global_position.distance_to(c.global_position)
			if d < best_d:
				best_d = d
				best = c
	return best


func capture_chance(c: CreatureActor) -> float:
	if c == null or c.definition == null:
		return 0.0
	var def := c.definition
	var slot := GameState.first_empty_ring(def.min_ring_tier)
	var ring := GameState.ring_definition(slot)
	var power := ring.capture_power if ring else 1.0
	var weakness := 1.0 - c.stats.health_fraction() / maxf(def.capture_health_threshold, 0.01)
	var chance := def.base_capture_chance * def.rarity_capture_mult() * power * (1.0 + clampf(weakness, 0.0, 1.0) * 0.6)
	if c.state == CreatureActor.State.DAZED:
		chance *= 1.25
	return clampf(chance, 0.05, 0.95)


func can_capture_reason(c: CreatureActor) -> String:
	if c == null:
		return "No creature"
	if GameState.ring_slots.is_empty():
		return "You have no ring"
	if GameState.first_empty_ring(c.definition.min_ring_tier) < 0:
		return "No empty ring of tier %d" % c.definition.min_ring_tier
	if not c.is_capturable():
		return "Weaken it below %d%%" % roundi(c.definition.capture_health_threshold * 100.0)
	return ""


func try_capture(c: CreatureActor) -> bool:
	var reason := can_capture_reason(c)
	if not reason.is_empty():
		EventBus.notify.emit(reason + ".")
		return false
	_capture_slot = GameState.first_empty_ring(c.definition.min_ring_tier)
	_capture_target = c
	_capture_elapsed = 0.0
	player.state = Player.State.CAPTURE
	player.body.pose_capture()
	c.begin_capture()
	_beam.visible = true
	AudioManager.play_sfx("magic", player.global_position)
	capture_started.emit(c)
	return true


func is_capturing() -> bool:
	return _capture_target != null


func capture_progress() -> float:
	return _capture_elapsed / CAPTURE_TIME


func _update_capture(delta: float) -> void:
	var c := _capture_target
	if not is_instance_valid(c) or player.state != Player.State.CAPTURE:
		_cancel_capture()
		return
	_capture_elapsed += delta
	var from := player.body.get_hand_position()
	var to := c.visual.get_center()
	var mid := (from + to) * 0.5
	var length := from.distance_to(to)
	_beam.global_position = mid
	if length > 0.05:
		_beam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT)
		_beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_beam.scale = Vector3(1.0 + 0.4 * sin(_time * 30.0), length, 1.0 + 0.4 * sin(_time * 30.0))
	_beam_mat.albedo_color = Color(c.definition.accent_color.lightened(0.4), 0.55 + 0.3 * sin(_time * 18.0))
	c.capture_visual(_capture_elapsed / CAPTURE_TIME)
	if Engine.get_physics_frames() % 12 == 0:
		Fx.ring_burst(to, c.definition.accent_color, 1.2, 0.4)
	if _capture_elapsed < CAPTURE_TIME:
		return
	var roll := randf()
	var success := roll < capture_chance(c)
	if force_capture_result >= 0:
		success = force_capture_result == 1
	_beam.visible = false
	player.state = Player.State.MOVE
	player.body.clear_pose()
	_capture_target = null
	if success:
		var inst := GameState.add_captured_creature(String(c.definition.id), c.level, _capture_slot, c.stats.health_fraction() + 0.3)
		Fx.ring_burst(c.visual.get_center(), c.definition.accent_color, 3.0, 0.8)
		Fx.ring_burst(player.body.get_hand_position(), c.definition.accent_color, 1.0, 0.6)
		Fx.hitstop(0.1)
		AudioManager.play_sfx("ring_capture", player.global_position)
		EventBus.notify.emit("%s was bound to your %s!" % [inst.display_name(), GameState.ring_definition(_capture_slot).display_name])
		GameState.active_ring = _capture_slot
		c.complete_capture()
		EventBus.creature_captured.emit(c.definition.id)
		GameState.add_xp(20 + 5 * c.level)
	else:
		AudioManager.play_sfx("ring_fail", c.global_position)
		Fx.floating_text(c.visual.get_center() + Vector3.UP * 0.6, "Broke free!", Color(1, 0.6, 0.3))
		EventBus.notify.emit("%s broke free of the ring!" % c.definition.display_name)
		c.break_free(player)
	capture_finished.emit(success)
	changed.emit()


func _cancel_capture() -> void:
	_beam.visible = false
	if is_instance_valid(_capture_target):
		_capture_target.break_free(player)
	_capture_target = null
	if player.state == Player.State.CAPTURE:
		player.state = Player.State.MOVE
		player.body.clear_pose()
	capture_finished.emit(false)


# ----------------------------------------------------------- Summoning

func toggle_summon() -> void:
	if companion and is_instance_valid(companion):
		dismiss()
	else:
		summon(GameState.active_ring)


func summon(slot: int) -> bool:
	if _summon_cooldown > 0.0:
		return false
	var inst := GameState.creature_in_slot(slot)
	if inst == null:
		EventBus.notify.emit("This ring is empty. Weaken a creature and capture it.")
		return false
	if inst.is_exhausted():
		EventBus.notify.emit("%s is exhausted (%ds)." % [inst.display_name(), ceili(inst.exhausted_until - GameState.play_time)])
		return false
	if companion and is_instance_valid(companion):
		dismiss()
	var actor := CreatureActor.new()
	actor.definition = inst.definition()
	actor.level = inst.level
	actor.setup_companion(inst, player)
	player.get_parent().add_child(actor)
	var side := player.global_transform.basis.x * 1.4 + player.global_transform.basis.z * 1.0
	actor.global_position = player.global_position + side + Vector3.UP * 0.3
	actor.rotation.y = player.rotation.y
	companion = actor
	inst.times_summoned += 1
	if inst.add_bond(1):
		EventBus.notify.emit("Your bond with %s grew stronger!" % inst.display_name())
	Fx.ring_burst(actor.global_position + Vector3.UP * 0.5, inst.definition().accent_color, 2.4, 0.7)
	AudioManager.play_sfx("ring_summon", actor.global_position)
	_summon_cooldown = SUMMON_COOLDOWN
	EventBus.creature_summoned.emit(StringName(inst.def_id))
	changed.emit()
	return true


func dismiss(instant: bool = false) -> void:
	if companion == null or not is_instance_valid(companion):
		companion = null
		return
	companion.store_state()
	Fx.ring_burst(companion.global_position + Vector3.UP * 0.5, companion.definition.accent_color, 1.8, 0.5)
	companion.vanish(instant)
	companion = null
	_summon_cooldown = SUMMON_COOLDOWN * (0.0 if instant else 1.0)
	changed.emit()


func on_companion_defeated(actor: CreatureActor) -> void:
	if actor.instance:
		actor.instance.exhaust()
		EventBus.notify.emit("%s is exhausted and returns to its ring." % actor.instance.display_name())
	if companion == actor:
		companion = null
	changed.emit()


func cycle(direction: int) -> void:
	var n := GameState.ring_slots.size()
	if n == 0:
		return
	GameState.active_ring = posmod(GameState.active_ring + direction, n)
	AudioManager.play_ui()
	changed.emit()


func select_ring(slot: int) -> void:
	if slot >= 0 and slot < GameState.ring_slots.size():
		GameState.active_ring = slot
		changed.emit()


func command() -> void:
	if companion == null or not is_instance_valid(companion):
		EventBus.notify.emit("No creature summoned.")
		return
	companion.command(_player_target())


func _on_enemy_killed(_id: StringName, _tags: PackedStringArray, pos: Vector3) -> void:
	if companion == null or not is_instance_valid(companion) or companion.instance == null:
		return
	if companion.global_position.distance_to(pos) > 30.0:
		return
	var inst := companion.instance
	if inst.add_xp(18):
		EventBus.notify.emit("%s reached level %d!" % [inst.display_name(), inst.level])
		companion.apply_level(inst)
	if inst.add_bond(1):
		EventBus.notify.emit("Your bond with %s deepened (bond %d)." % [inst.display_name(), inst.bond_level()])
	EventBus.creatures_changed.emit()

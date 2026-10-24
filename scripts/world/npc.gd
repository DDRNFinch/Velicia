class_name NPC
extends CharacterBody3D
## A named character with a simple daily routine (walks between waypoints,
## pauses, faces the player when spoken to) and data-driven dialogue.

@export var npc_id: String = ""
@export var display_name: String = ""
## Canon people: human, amir, burrok, vapouriun, gouran, gyria
@export var people: StringName = &"human"
@export var variant: int = 0
@export var dialogue_id: String = ""
@export var weapon: StringName = &""
@export var cloth_color: Color = Color(0, 0, 0, 0)
## Local offsets (relative to the NPC's start) visited in order.
@export var routine_points: PackedVector3Array = PackedVector3Array()
@export var routine_pause: float = 6.0
@export var walk_speed: float = 1.3
## Hide/show the NPC based on a flag ("" = always present).
@export var requires_flag: String = ""
@export var hidden_by_flag: String = ""

const GRAVITY := 18.0

var team: StringName = &"neutral"
var body: PlaceholderBody
var talking: bool = false
var _home: Vector3
var _route_index := 0
var _pause := 0.0
var _label: Label3D
var _marker: Label3D
var _interact: Interactable
var _home_set := false


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = CombatUtil.LAYER_NPC
	collision_mask = CombatUtil.LAYER_WORLD
	var params := PlaceholderBody.preset(people, variant)
	if weapon != &"":
		params.weapon = weapon
	if cloth_color.a > 0.0:
		params.cloth = cloth_color
	body = PlaceholderBody.new()
	add_child(body)
	body.build(params)
	var h: float = params.height
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(0.3, float(params.shoulder) * 0.55)
	capsule.height = h
	shape.shape = capsule
	shape.position.y = h * 0.5
	add_child(shape)

	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 36
	_label.outline_size = 10
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = h + 0.35
	_label.modulate = Color(1, 0.95, 0.8)
	add_child(_label)
	_marker = Label3D.new()
	_marker.text = "!"
	_marker.font_size = 110
	_marker.outline_size = 18
	_marker.modulate = Color(1.0, 0.82, 0.25)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.position.y = h + 0.85
	_marker.visible = false
	add_child(_marker)

	_interact = Interactable.new()
	_interact.prompt = "Talk to " + display_name
	_interact.radius = 2.4 if h < 2.2 else 3.2
	add_child(_interact)
	_interact.used.connect(_on_used)
	EventBus.quest_updated.connect(_on_quest_updated)
	EventBus.flag_changed.connect(_on_flag_changed)
	_refresh_presence()
	_refresh_marker.call_deferred()


func _on_quest_updated(_q: StringName) -> void:
	_refresh_marker()


func _on_flag_changed(_f: StringName) -> void:
	_refresh_presence()


func _refresh_presence() -> void:
	var present := true
	if not requires_flag.is_empty() and not GameState.has_flag(requires_flag):
		present = false
	if not hidden_by_flag.is_empty() and GameState.has_flag(hidden_by_flag):
		present = false
	visible = present
	_interact.enabled = present
	collision_layer = CombatUtil.LAYER_NPC if present else 0
	set_physics_process(present)


func _refresh_marker() -> void:
	var show := false
	for q in QuestManager.active_quests():
		var stage := QuestManager.current_stage(q.id)
		if stage == null:
			continue
		for i in stage.objectives.size():
			var obj := stage.objectives[i]
			if obj.type == QuestObjective.Type.TALK and String(obj.target) == npc_id and QuestManager.objective_progress(q.id, i) < obj.count:
				show = true
	_marker.visible = show and visible


func _physics_process(delta: float) -> void:
	if not _home_set:
		_home_set = true
		_home = global_position
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var speed := 0.0
	if talking:
		velocity.x = 0.0
		velocity.z = 0.0
		var p := CombatDirector.player
		if p:
			CombatUtil.turn_toward(self, CombatUtil.flat_direction(global_position, p.global_position), 6.0, delta)
	elif routine_points.size() > 0:
		if _pause > 0.0:
			_pause -= delta
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			var goal := _home + routine_points[_route_index]
			var to := goal - global_position
			to.y = 0.0
			if to.length() < 0.4:
				_route_index = (_route_index + 1) % routine_points.size()
				_pause = routine_pause * randf_range(0.7, 1.3)
			else:
				var v := to.normalized() * walk_speed
				velocity.x = v.x
				velocity.z = v.z
				speed = walk_speed
				CombatUtil.turn_toward(self, to.normalized(), 5.0, delta)
	move_and_slide()
	body.animate(delta, speed, 4.0, is_on_floor())


func _on_used(_by: Player) -> void:
	if dialogue_id.is_empty():
		EventBus.notify.emit(display_name + " nods at you.")
		return
	talking = true
	EventBus.request_dialogue.emit(dialogue_id, self)


func end_talk() -> void:
	talking = false
	_refresh_marker()


func is_targetable() -> bool:
	return false

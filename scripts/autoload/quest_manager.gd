extends Node
## Tracks quest progress stored in GameState.quests and reacts to gameplay
## events from EventBus to advance objectives.

const Type := QuestObjective.Type


func _ready() -> void:
	EventBus.talked_to.connect(func(id): _on_event(Type.TALK, id, 1))
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.item_collected.connect(func(_id, _n): _refresh_collect())
	EventBus.inventory_changed.connect(_refresh_collect)
	EventBus.creature_captured.connect(func(id): _on_event(Type.CAPTURE, id, 1))
	EventBus.creature_summoned.connect(func(id): _on_event(Type.SUMMON, id, 1))
	EventBus.location_entered.connect(func(id): _on_event(Type.REACH, id, 1))
	EventBus.flag_changed.connect(func(_f): _refresh_flags())


# ----------------------------------------------------------------- Queries

func status(id) -> String:
	var q: Dictionary = GameState.quests.get(String(id), {})
	return String(q.get("status", ""))


func is_active(id) -> bool:
	return status(id) == "active"


func is_completed(id) -> bool:
	return status(id) == "completed"


func stage_index(id) -> int:
	return int(GameState.quests.get(String(id), {}).get("stage", -1))


func active_quests() -> Array[QuestDefinition]:
	var out: Array[QuestDefinition] = []
	for id in GameState.quests:
		if is_active(id):
			var def := Database.quest(id)
			if def:
				out.append(def)
	out.sort_custom(func(a, b): return a.is_main and not b.is_main)
	return out


func completed_quests() -> Array[QuestDefinition]:
	var out: Array[QuestDefinition] = []
	for id in GameState.quests:
		if is_completed(id):
			var def := Database.quest(id)
			if def:
				out.append(def)
	return out


func current_stage(id) -> QuestStage:
	var def := Database.quest(id)
	var idx := stage_index(id)
	if def == null or idx < 0 or idx >= def.stages.size():
		return null
	return def.stages[idx]


func objective_progress(id, index: int) -> int:
	var q: Dictionary = GameState.quests.get(String(id), {})
	var progress: Array = q.get("progress", [])
	return int(progress[index]) if index < progress.size() else 0


## Lines like "Defeat Gyria scouts (1/3)" for the tracker.
func objective_lines(id) -> PackedStringArray:
	var out := PackedStringArray()
	var stage := current_stage(id)
	if stage == null:
		return out
	for i in stage.objectives.size():
		var obj := stage.objectives[i]
		var n := objective_progress(id, i)
		var done := n >= obj.count
		var line := ("✓ " if done else "• ") + obj.description
		if obj.count > 1:
			line += " (%d/%d)" % [mini(n, obj.count), obj.count]
		out.append(line)
	return out


## Location id of the first unfinished objective, for map markers.
func marker_location(id) -> String:
	var stage := current_stage(id)
	if stage == null:
		return ""
	for i in stage.objectives.size():
		var obj := stage.objectives[i]
		if objective_progress(id, i) < obj.count and obj.marker_location != &"":
			return String(obj.marker_location)
	return ""


# ---------------------------------------------------------------- Changes

func start_quest(id, announce: bool = true) -> bool:
	var key := String(id)
	var def := Database.quest(key)
	if def == null:
		push_warning("QuestManager: unknown quest " + key)
		return false
	if GameState.quests.has(key):
		return false
	GameState.quests[key] = {"stage": 0, "progress": [], "status": "active"}
	_begin_stage(key)
	if GameState.tracked_quest.is_empty() or def.is_main:
		GameState.tracked_quest = key
	if announce:
		EventBus.notify.emit(("Main quest: " if def.is_main else "Quest: ") + def.title)
	EventBus.quest_started.emit(StringName(key))
	EventBus.quest_updated.emit(StringName(key))
	return true


func _begin_stage(key: String) -> void:
	var stage := current_stage(key)
	if stage == null:
		return
	var progress := []
	progress.resize(stage.objectives.size())
	progress.fill(0)
	GameState.quests[key].progress = progress
	# Objectives that may already be satisfied when the stage begins.
	for i in stage.objectives.size():
		var obj := stage.objectives[i]
		match obj.type:
			Type.COLLECT:
				progress[i] = mini(GameState.count_item(String(obj.target)), obj.count)
			Type.FLAG:
				progress[i] = obj.count if GameState.has_flag(String(obj.target)) else 0
	_check_stage(key)


func _on_enemy_killed(enemy_id: StringName, tags: PackedStringArray, _pos: Vector3) -> void:
	_on_event(Type.KILL, enemy_id, 1)
	for tag in tags:
		_on_event(Type.KILL, StringName(tag), 1)


func _on_event(type: int, target, amount: int) -> void:
	for key in GameState.quests.keys():
		if not is_active(key):
			continue
		var stage := current_stage(key)
		if stage == null:
			continue
		var changed := false
		for i in stage.objectives.size():
			var obj := stage.objectives[i]
			if obj.type != type:
				continue
			if not (String(obj.target) == String(target) or String(obj.target) == "any"):
				continue
			var n := objective_progress(key, i)
			if n >= obj.count:
				continue
			GameState.quests[key].progress[i] = mini(n + amount, obj.count)
			changed = true
		if changed:
			EventBus.quest_updated.emit(StringName(key))
			_check_stage(key)


func _refresh_collect() -> void:
	_refresh_type(Type.COLLECT)


func _refresh_flags() -> void:
	_refresh_type(Type.FLAG)


func _refresh_type(type: int) -> void:
	for key in GameState.quests.keys():
		if not is_active(key):
			continue
		var stage := current_stage(key)
		if stage == null:
			continue
		var changed := false
		for i in stage.objectives.size():
			var obj := stage.objectives[i]
			if obj.type != type:
				continue
			var value := 0
			if type == Type.COLLECT:
				value = mini(GameState.count_item(String(obj.target)), obj.count)
			else:
				value = obj.count if GameState.has_flag(String(obj.target)) else 0
			if value != objective_progress(key, i):
				GameState.quests[key].progress[i] = value
				changed = true
		if changed:
			EventBus.quest_updated.emit(StringName(key))
			_check_stage(key)


func _check_stage(key: String) -> void:
	var stage := current_stage(key)
	if stage == null:
		return
	for i in stage.objectives.size():
		if objective_progress(key, i) < stage.objectives[i].count:
			return
	advance_stage(key)


func advance_stage(id) -> void:
	var key := String(id)
	var def := Database.quest(key)
	if def == null or not is_active(key):
		return
	var next := stage_index(key) + 1
	if next >= def.stages.size():
		complete_quest(key)
		return
	GameState.quests[key].stage = next
	EventBus.notify.emit("Quest updated: " + def.title)
	_begin_stage(key)
	EventBus.quest_updated.emit(StringName(key))


func complete_quest(id) -> void:
	var key := String(id)
	var def := Database.quest(key)
	if def == null or is_completed(key):
		return
	if not GameState.quests.has(key):
		GameState.quests[key] = {"stage": 0, "progress": [], "status": "active"}
	GameState.quests[key].status = "completed"
	GameState.quests[key].stage = def.stages.size()
	EventBus.notify.emit("Quest complete: " + def.title)
	if def.reward_xp > 0:
		GameState.add_xp(def.reward_xp)
	for item_id in def.reward_items:
		GameState.add_item(String(item_id), int(def.reward_items[item_id]))
	for flag in def.reward_flags:
		GameState.set_flag(flag)
	for faction in def.reward_reputation:
		GameState.add_reputation(String(faction), int(def.reward_reputation[faction]))
	if GameState.tracked_quest == key:
		GameState.tracked_quest = ""
		var remaining := active_quests()
		if not remaining.is_empty():
			GameState.tracked_quest = String(remaining[0].id)
	EventBus.quest_completed.emit(StringName(key))
	EventBus.quest_updated.emit(StringName(key))
	if def.next_quest != &"":
		start_quest(def.next_quest)

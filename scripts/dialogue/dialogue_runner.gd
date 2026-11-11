class_name DialogueRunner
extends RefCounted
## Runs a data-driven conversation from res://data/dialogue/<id>.json.
##
## Format:
##   { "id": "...", "speaker": "Name",
##     "entries": [ {"conditions": [...], "node": "node_id"}, ... ],  # first match wins
##     "nodes": { "node_id": { "text": "...", "speaker": "(optional)",
##                 "effects": [...], "next": "node_id" | "end",
##                 "choices": [ {"text": "...", "next": "...", "conditions": [...], "effects": [...]} ] } } }
##
## Conditions: quest_active:id  quest_completed:id  quest_not_started:id
##             quest_stage:id:n  flag:name  !flag:name  has_item:id[:n]  level:n
## Effects:    start_quest:id  complete_quest:id  advance_quest:id  set_flag:name
##             clear_flag:name  give_item:id[:n]  take_item:id[:n]  xp:n
##             rep:faction:n  heal  lore:id  panel:name

var dialogue_id: String = ""
var data: Dictionary = {}
var current_id: String = ""
var speaker_node: Node
var pending_panels: PackedStringArray = PackedStringArray()
var finished: bool = false


func start(id: String, speaker: Node = null) -> bool:
	dialogue_id = id
	data = Database.dialogue(id)
	speaker_node = speaker
	finished = false
	pending_panels.clear()
	if data.is_empty() or not data.has("nodes"):
		push_warning("Dialogue missing: " + id)
		return false
	var start_node := String(data.get("start", ""))
	for e in data.get("entries", []):
		if conditions_met(e.get("conditions", [])):
			start_node = String(e.get("node", start_node))
			break
	if start_node.is_empty() or not data.nodes.has(start_node):
		push_warning("Dialogue %s has no valid entry node" % id)
		return false
	_enter(start_node)
	return true


func current() -> Dictionary:
	return data.nodes.get(current_id, {})


func speaker_name() -> String:
	return String(current().get("speaker", data.get("speaker", "")))


func text() -> String:
	return String(current().get("text", ""))


func choices() -> Array:
	var out := []
	for c in current().get("choices", []):
		if conditions_met(c.get("conditions", [])):
			out.append(c)
	return out


func choose(index: int) -> void:
	var list := choices()
	if index < 0 or index >= list.size():
		return
	var c: Dictionary = list[index]
	apply_effects(c.get("effects", []))
	_goto(String(c.get("next", "end")))


func advance() -> void:
	_goto(String(current().get("next", "end")))


func _goto(id: String) -> void:
	if id.is_empty() or id == "end" or not data.nodes.has(id):
		finished = true
		current_id = ""
		return
	_enter(id)


func _enter(id: String) -> void:
	current_id = id
	apply_effects(current().get("effects", []))


func conditions_met(conds: Array) -> bool:
	for c in conds:
		if not check(String(c)):
			return false
	return true


static func check(cond: String) -> bool:
	var negate := cond.begins_with("!")
	if negate:
		cond = cond.substr(1)
	var parts := cond.split(":")
	var result := false
	match parts[0]:
		"quest_active":
			result = QuestManager.is_active(parts[1])
		"quest_completed":
			result = QuestManager.is_completed(parts[1])
		"quest_not_started":
			result = QuestManager.status(parts[1]).is_empty()
		"quest_stage":
			result = QuestManager.is_active(parts[1]) and QuestManager.stage_index(parts[1]) == int(parts[2])
		"flag":
			result = GameState.has_flag(parts[1])
		"has_item":
			result = GameState.count_item(parts[1]) >= (int(parts[2]) if parts.size() > 2 else 1)
		"level":
			result = GameState.get_level() >= int(parts[1])
		"has_creature":
			result = not GameState.creatures.is_empty()
		_:
			push_warning("Unknown dialogue condition: " + cond)
	return result != negate


func apply_effects(effects: Array) -> void:
	for e in effects:
		apply(String(e))


func apply(effect: String) -> void:
	var parts := effect.split(":")
	match parts[0]:
		"start_quest":
			QuestManager.start_quest(parts[1])
		"complete_quest":
			QuestManager.complete_quest(parts[1])
		"advance_quest":
			QuestManager.advance_stage(parts[1])
		"set_flag":
			GameState.set_flag(parts[1])
		"clear_flag":
			GameState.flags.erase(parts[1])
			EventBus.flag_changed.emit(StringName(parts[1]))
		"give_item":
			GameState.add_item(parts[1], int(parts[2]) if parts.size() > 2 else 1)
		"take_item":
			GameState.remove_item(parts[1], int(parts[2]) if parts.size() > 2 else 1)
		"xp":
			GameState.add_xp(int(parts[1]))
		"rep":
			GameState.add_reputation(parts[1], int(parts[2]))
		"heal":
			var p := CombatDirector.player as Player
			if p:
				p.stats.heal(p.stats.max_health)
		"lore":
			GameState.unlock_lore(parts[1])
		"panel":
			pending_panels.append(parts[1])
		_:
			push_warning("Unknown dialogue effect: " + effect)

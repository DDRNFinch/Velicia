class_name DialogueRunner
extends RefCounted
## Runs data/dialogue/<id>.json: picks the entry node from conditions, steps
## through nodes and choices, and applies effects to the game state.
## Conditions: flag:x  !flag:x  quest:id=stage  quest_active:id  quest_done:id
##             !quest_started:id  has_creature  item:id
## Effects:    flag:x  quest_start:id  quest_stage:id:stage  quest_done:id
##             give:item:n  coins:n  heal_party  heal_player  starter  shop

signal request(kind: String)        # UI work: "starter", "shop"

var data: Dictionary = {}
var dialogue_id := ""


func start(id: String) -> String:
	dialogue_id = id
	data = Data.dialogue.get(id, {})
	for e in data.get("entry", []):
		if check_all(e.get("if", [])):
			return String(e.node)
	return ""


func node(id: String) -> Dictionary:
	return data.get("nodes", {}).get(id, {})


func lines(n: Dictionary) -> Array:
	if n.has("if_flag") and not Game.has_flag(String(n.if_flag)):
		return n.get("else_text", [])
	var t: Variant = n.get("text", [])
	return t if t is Array else [String(t)]


func choices(n: Dictionary) -> Array:
	var out: Array = []
	for c in n.get("choices", []):
		if check_all(c.get("if", [])):
			out.append(c)
	return out


static func check_all(conds: Array) -> bool:
	for c in conds:
		if not check(String(c)):
			return false
	return true


static func check(c: String) -> bool:
	var neg := c.begins_with("!")
	if neg:
		c = c.substr(1)
	var ok := false
	var parts := c.split(":", true, 1)
	var key := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match key:
		"flag":
			ok = Game.has_flag(arg)
		"quest":
			var qs := arg.split("=")
			ok = Game.quest_stage_id(qs[0]) == (qs[1] if qs.size() > 1 else "")
		"quest_active":
			ok = Game.quest_active(arg)
		"quest_done":
			ok = Game.quest_done(arg)
		"quest_started":
			ok = Game.quests.has(arg)
		"has_creature":
			ok = Game.has_creature()
		"item":
			ok = Game.has_item(arg)
	return ok != neg


func apply(n: Dictionary) -> void:
	for e in n.get("do", []):
		apply_effect(String(e))


func apply_effect(e: String) -> void:
	var p := e.split(":")
	match p[0]:
		"flag":
			Game.set_flag(p[1])
		"quest_start":
			Game.start_quest(p[1])
		"quest_stage":
			Game.set_quest_stage(p[1], p[2])
		"quest_done":
			Game.complete_quest(p[1])
		"give":
			var n := int(p[2]) if p.size() > 2 else 1
			Game.give_item(p[1], n)
			Events.toast.emit("Received %s x%d" % [String(Data.item(p[1]).get("name", p[1])), n])
			Audio.play("pickup")
		"coins":
			Game.add_coins(int(p[1]))
			Events.toast.emit("Received %d marks" % int(p[1]))
		"heal_party":
			Game.heal_party()
			Audio.play("ring_summon")
		"heal_player":
			Game.heal_player()
		"starter", "shop":
			request.emit(p[0])

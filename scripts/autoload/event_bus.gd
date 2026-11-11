extends Node
## Global gameplay signal hub. Systems emit events here so quests, UI,
## progression and audio can react without hard references to each other.

signal notify(text: String)
signal enemy_killed(enemy_id: StringName, tags: PackedStringArray, position: Vector3)
signal item_collected(item_id: StringName, count: int)
signal creature_captured(def_id: StringName)
signal creature_summoned(def_id: StringName)
signal location_discovered(location_id: StringName)
signal location_entered(location_id: StringName)
signal talked_to(npc_id: StringName)
signal flag_changed(flag: StringName)
signal quest_started(quest_id: StringName)
signal quest_updated(quest_id: StringName)
signal quest_completed(quest_id: StringName)
signal player_died
signal player_respawned
signal boss_engaged(boss: Node)
signal boss_defeated(boss_id: StringName)
signal level_up(new_level: int)
signal inventory_changed
signal creatures_changed
signal player_stats_changed
signal lore_unlocked(lore_id: StringName)
signal camera_shake(strength: float)
signal request_dialogue(dialogue_id: String, speaker: Node)
signal request_panel(panel_id: String, context: Dictionary)

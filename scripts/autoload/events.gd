extends Node
## Global gameplay signals, so UI, quests and audio react without coupling.

signal coins_changed
signal inventory_changed
signal party_changed
signal quest_changed(quest_id: String)
signal flag_set(flag: String)
signal toast(text: String)
signal area_entered(area_name: String)
signal creature_bound(creature: Dictionary)
signal battle_started
signal battle_ended(result: String)
signal enemy_defeated(enemy_type: String)
signal player_died
signal dialogue_started
signal dialogue_finished
signal game_saved

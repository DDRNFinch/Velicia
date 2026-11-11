extends Node
## Coordinates enemies so fights stay readable: only a few enemies may attack
## at once (attack tokens), the rest circle and wait. Also tracks combat state
## for music and save restrictions.

const MAX_ATTACKERS := 2
const MAX_SHOOTERS := 1
const SHOT_SPACING := 1.4
const TOKEN_TIMEOUT := 4.0
const COMBAT_COOLDOWN := 5.0

var player: Node3D
var _tokens: Dictionary = {} # enemy instance id -> time granted
var _engaged: Dictionary = {} # enemy instance id -> last time engaged
var _time := 0.0
var _last_shot := -10.0
var _was_in_combat := false


func _process(delta: float) -> void:
	_time += delta
	for key in _tokens.keys():
		if _time - float(_tokens[key]) > TOKEN_TIMEOUT or not is_instance_id_valid(key):
			_tokens.erase(key)
	for key in _engaged.keys():
		if _time - float(_engaged[key]) > COMBAT_COOLDOWN or not is_instance_id_valid(key):
			_engaged.erase(key)
	var now := in_combat()
	if now != _was_in_combat:
		_was_in_combat = now
		if GameState.session_active:
			AudioManager.play_music("combat" if now else "exploration")


func register_player(p: Node3D) -> void:
	player = p
	_tokens.clear()
	_engaged.clear()


func request_token(enemy: Node) -> bool:
	var key := enemy.get_instance_id()
	if _tokens.has(key):
		_tokens[key] = _time
		return true
	var limit := MAX_ATTACKERS
	if enemy.get("definition") and enemy.definition.is_boss:
		limit += 1
	if _tokens.size() >= limit:
		return false
	_tokens[key] = _time
	return true


## Ranged attackers take turns: one shot at a time, spaced out, so archers
## pressure the player without stacking unavoidable damage.
func request_shot() -> bool:
	if _time - _last_shot < SHOT_SPACING / MAX_SHOOTERS:
		return false
	_last_shot = _time
	return true


func release_token(enemy: Node) -> void:
	_tokens.erase(enemy.get_instance_id())


func mark_engaged(enemy: Node) -> void:
	_engaged[enemy.get_instance_id()] = _time


func in_combat() -> bool:
	return not _engaged.is_empty()


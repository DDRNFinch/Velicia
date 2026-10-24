extends Node
## Audio playback with separate buses and pooled players.
## Missing sound files are skipped silently so the game runs without audio.

const BUSES := {
	"music": "Music",
	"sfx": "SFX",
	"ambient": "Ambient",
	"ui": "UI",
}

## Sound id -> file. Replace files freely; ids are what gameplay code uses.
const SOUNDS := {
	"swing": "res://audio/sfx/swing.wav",
	"swing_heavy": "res://audio/sfx/swing_heavy.wav",
	"hit": "res://audio/sfx/hit.wav",
	"block": "res://audio/sfx/block.wav",
	"parry": "res://audio/sfx/parry.wav",
	"footstep": "res://audio/sfx/footstep.wav",
	"dodge": "res://audio/sfx/dodge.wav",
	"ring_capture": "res://audio/sfx/ring_capture.wav",
	"ring_summon": "res://audio/sfx/ring_summon.wav",
	"ring_fail": "res://audio/sfx/ring_fail.wav",
	"alert": "res://audio/sfx/alert.wav",
	"roar": "res://audio/sfx/roar.wav",
	"pickup": "res://audio/sfx/pickup.wav",
	"ui_click": "res://audio/sfx/ui_click.wav",
	"level_up": "res://audio/sfx/level_up.wav",
	"creature_attack": "res://audio/sfx/creature_attack.wav",
	"magic": "res://audio/sfx/magic.wav",
}
const MUSIC := {
	"exploration": "res://audio/music/exploration.wav",
	"combat": "res://audio/music/combat.wav",
}
const AMBIENCE := {
	"wind": "res://audio/sfx/ambience_wind.wav",
}

const POOL_3D := 14
const POOL_UI := 4

var _cache: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_ui: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _next_3d := 0
var _next_ui := 0
var _music_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 40.0
		p.unit_size = 6.0
		add_child(p)
		_players_3d.append(p)
	for i in POOL_UI:
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		_players_ui.append(u)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Ambient"
	add_child(_ambient)


func _ensure_buses() -> void:
	for key in BUSES:
		var bus_name: String = BUSES[key]
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func set_bus_volume(key: String, linear: float) -> void:
	var bus_name: String = "Master" if key == "master" else BUSES.get(key, "")
	if bus_name.is_empty():
		return
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


## Plays a positional sound. Pass Vector3.INF for a non-positional UI sound.
func play_sfx(id: String, position: Vector3 = Vector3.INF, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	var stream := _get_stream(SOUNDS.get(id, ""))
	if stream == null:
		return
	if position == Vector3.INF:
		var u := _players_ui[_next_ui]
		_next_ui = (_next_ui + 1) % POOL_UI
		u.stream = stream
		u.volume_db = volume_db
		u.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
		u.play()
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = stream
	p.global_position = position
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


func play_ui(id: String = "ui_click") -> void:
	play_sfx(id, Vector3.INF, -4.0, 0.03)


func play_music(id: String) -> void:
	if id == _music_id and _music.playing:
		return
	_music_id = id
	var stream := _get_stream(MUSIC.get(id, ""))
	if stream == null:
		_music.stop()
		return
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music_id = ""
	_music.stop()


func play_ambient(id: String) -> void:
	var stream := _get_stream(AMBIENCE.get(id, ""))
	if stream == null:
		_ambient.stop()
		return
	_ambient.stream = stream
	_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


func _get_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]

extends Node
## Sound effects and music (synthesised placeholders in res://audio).

const SFX := ["hit", "pickup", "level_up", "ring_capture", "ring_fail", "ring_summon", "dodge", "alert",
		"block", "parry", "creature_attack", "magic", "footstep", "roar"]

var music_volume := 0.6
var sfx_volume := 0.8
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _streams: Dictionary = {}
var _current_music := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	for s in SFX:
		var path := "res://audio/sfx/%s.wav" % s
		if ResourceLoader.exists(path):
			_streams[s] = load(path)


func play(sfx_name: String, pitch: float = 1.0) -> void:
	if not _streams.has(sfx_name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[sfx_name]
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(maxf(sfx_volume, 0.001))
			p.play()
			return


const MUSIC_ALIASES := {"home": "town", "guild": "town"}


func music(track: String) -> void:
	track = MUSIC_ALIASES.get(track, track)
	if track == _current_music:
		return
	_current_music = track
	var path := "res://audio/music/%s.wav" % track
	if not ResourceLoader.exists(path):
		_music.stop()
		return
	var stream: AudioStreamWAV = load(path)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(music_volume * 0.6, 0.001))
	_music.play()


func set_volumes(m: float, s: float) -> void:
	music_volume = m
	sfx_volume = s
	if _music:
		_music.volume_db = linear_to_db(maxf(music_volume * 0.6, 0.001))

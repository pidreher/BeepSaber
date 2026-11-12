extends Node3D
class_name SaberEffectsAudio

const ARC_STREAM := preload("res://game/data/sfx/arc_loop.wav")
const CONTACT_STREAM := preload("res://game/data/sfx/clash_loop.wav")
const CLASH_STREAM := preload("res://game/data/sfx/saber_clash.wav")
const SILENCE := 0.0001
const ARC_VOLUME_DB := -29.0
const CONTACT_VOLUME_DB := -34.0

var _arc_players: Array[AudioStreamPlayer3D] = []
var _arc_targets: Array[float] = [0.0, 0.0]
var _arc_gains: Array[float] = [0.0, 0.0]
var _arc_phases: Array[float] = [0.0, 0.0]
var _contact: AudioStreamPlayer3D
var _strike: AudioStreamPlayer3D
var _touching := false
var _contact_gain := 0.0
var _strike_cooldown := 0.0

func _ready() -> void:
	# Gather all arc requests before mixing once per render frame.
	process_priority = 10
	for i in 2:
		_arc_players.append(_player(_loop(ARC_STREAM)))
	_contact = _player(_loop(CONTACT_STREAM))
	_strike = _player(CLASH_STREAM)
	_strike.max_polyphony = 3

func _player(stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = -80.0
	player.max_distance = 6.0
	add_child(player)
	return player

func _loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream

func request_arc(hand: int, strength: float, point: Vector3, phase: float) -> void:
	if strength <= _arc_targets[hand]: return
	_arc_targets[hand] = clampf(strength, 0.0, 1.0)
	_arc_players[hand].global_position = point
	_arc_phases[hand] = phase

func set_clash(touching: bool, point: Vector3, strength := 1.0) -> void:
	if touching:
		_contact.global_position = point
		if not _touching and _strike_cooldown <= 0.0:
			_strike.global_position = point
			_strike.pitch_scale = randf_range(0.94, 1.06)
			_strike.volume_db = lerpf(-27.0, -17.0, clampf(strength, 0.0, 1.0))
			_strike.play()
			_strike_cooldown = 0.1
	_touching = touching

func _process(delta: float) -> void:
	_strike_cooldown = maxf(0.0, _strike_cooldown - delta)
	for hand in 2:
		var target := _arc_targets[hand]
		_arc_targets[hand] = 0.0
		var breath := 0.86 + 0.12 * sin(TAU * BeepSaberController.ARC_PULSE_RATE * _arc_phases[hand])
		target *= breath * db_to_linear(ARC_VOLUME_DB)
		_arc_gains[hand] = _smooth_gain(_arc_players[hand], _arc_gains[hand], target, delta)
	_contact_gain = _smooth_gain(_contact, _contact_gain, db_to_linear(CONTACT_VOLUME_DB) if _touching else 0.0, delta)

func _smooth_gain(player: AudioStreamPlayer3D, gain: float, target: float, delta: float) -> float:
	var seconds := 0.025 if target > gain else 0.055
	gain = lerpf(gain, target, 1.0 - exp(-delta / seconds))
	if gain < SILENCE and target <= 0.0:
		player.stop()
		return 0.0
	player.volume_db = linear_to_db(maxf(gain, SILENCE))
	if not player.playing: player.play()
	return gain

func stop_all() -> void:
	_touching = false
	_contact_gain = 0.0
	_strike_cooldown = 0.0
	_contact.stop()
	_strike.stop()
	for hand in 2:
		_arc_targets[hand] = 0.0
		_arc_gains[hand] = 0.0
		_arc_players[hand].stop()

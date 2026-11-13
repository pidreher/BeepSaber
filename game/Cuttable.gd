extends PooledNode3D
class_name Cuttable

var speed: float
var beat: float
var lane_rotation := 0.
var _fly_time_left := 0.0
var _fly_extra := 0.0
var _jump_rise := 0.6
var _jump_origin := Vector3.ZERO
var _lane_basis := Basis.IDENTITY
var _jump_scale := Vector3.ONE
var _final_roll := 0.0
var _entry_roll := 0.0
var _entry_yaw := 0.0
var _turn_on_jump := false
var _preview_beat := 0.0

# Interpolate the rise for fractional rows used by custom maps and chains.
func configure_jump(row: float, final_roll: float = 0.0, turn: bool = false) -> void:
	var layer := clampf(row, 0.0, 2.0)
	_jump_rise = lerpf(0.6, 0.55, layer) if layer <= 1.0 else lerpf(0.55, 0.45, layer - 1.0)
	_final_roll = final_roll
	_turn_on_jump = turn
	_entry_roll = randf_range(-PI / 6.0, PI / 6.0) if turn else 0.0
	_entry_yaw = randf_range(-0.12, 0.12) if turn else 0.0

# used to release the cube once both of it's cut pieces have died off
# Note: serves no purpose for bombs
var _piece_death_count := 0

# overridden by bombs and cubes
@warning_ignore("unused_parameter")
func set_collision_disabled(value: bool) -> void:
	return

# overriden by bombs and cubes
@warning_ignore("unused_parameter")
func cut(saber: LightSaber, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController, blade_speed: float = -1.0) -> void:
	return

# overridden by cubes and chain links: true if this cut would be a bad cut
@warning_ignore("unused_parameter")
func is_bad_cut(saber_type: int, cut_speed: Vector3, blade_speed: float = -1.0) -> bool:
	return false

# Called before feedback or cutting. Physics queries can still return a consumed
# collider in the same tick; skip it and continue the ray to the next candidate.
@warning_ignore("unused_parameter")
func accepts_cut_from(area: Area3D, saber_type: int, cut_speed: Vector3, blade_speed: float) -> bool:
	return not is_queued_for_deletion() and process_mode != Node.PROCESS_MODE_DISABLED and is_visible_in_tree()

# this too
func on_miss() -> void:
	return

func _on_cut_piece_died() -> void:
	_piece_death_count += 1
	if _piece_death_count >= 2:
		release()
		
func add_lane_rotation(angle: float) -> void:
	var c := cos(angle)
	var s := sin(angle)
	
	var x := transform.origin.x
	var z := transform.origin.z
	transform.origin.x = c * x - s * z
	transform.origin.z = s * x + c * z
	
	rotation.y = -angle
	
	lane_rotation = angle

# Call at the end of spawn(), once position, scale and lane rotation are set.
func start_fly_in(fly_beat: float, current_beat: float) -> void:
	_lane_basis = Basis(Vector3.UP, -lane_rotation)
	_jump_scale = scale
	_jump_origin = position + _lane_basis.z * ((fly_beat - current_beat) * Map.beat_distance)
	_preview_beat = current_beat
	_apply_jump(current_beat)

# Position is evaluated from the song clock, including the fast approach before
# the jump. The lane axes are independent of the note's animated cut direction.
func _apply_jump(current_beat: float) -> void:
	var beats_left := beat - current_beat
	var half_jump := maxf(Map.half_jump_beats, 0.001)
	var phase := minf(beats_left / half_jump, 1.0)
	_fly_time_left = Map.fly_in_time_left(beat, current_beat)
	_fly_extra = Map.fly_in_extra_distance(_fly_time_left, speed)
	position = _jump_origin - _lane_basis.z * (beats_left * Map.beat_distance + _fly_extra) \
		- _lane_basis.y * (_jump_rise * phase * phase)
	var yaw := 0.0
	var roll := _final_roll
	if _turn_on_jump:
		var settle := clampf((1.0 - phase) / 0.4, 0.0, 1.0)
		var remaining := pow(1.0 - settle, 3.0)
		roll += _entry_roll * remaining
		var lane_x := _jump_origin.dot(_lane_basis.x)
		var distance := maxf(beats_left * Map.beat_distance + _fly_extra, 0.0)
		var face_yaw := clampf(atan2(-lane_x, distance + Constants.HIT_DISTANCE_FROM_HEAD), -0.16, 0.16)
		yaw = _entry_yaw * remaining + face_yaw * clampf(phase, 0.0, 1.0)
	transform.basis = (_lane_basis * Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll)).scaled_local(_jump_scale)

func _physics_process(delta: float) -> void:
	if Scoreboard.paused or not is_visible_in_tree() or not Map.current_info:
		return
	var game := GlobalReferences.main_game_scene
	if is_instance_valid(game) and is_instance_valid(game.song_player) and game.song_player.playing:
		# Same audio clock as spawning; interpolate between audio mixes for smooth motion.
		var seconds := game.song_player.get_playback_position() \
			+ AudioServer.get_time_since_last_mix() * game.song_player.pitch_scale
		_preview_beat = seconds * Map.current_info.beats_per_minute / 60.0
	else:
		_preview_beat += delta * Map.current_info.beats_per_minute / 60.0
	_apply_jump(_preview_beat)
	var rz := global_position.dot(_lane_basis.z)
	if rz > -3.0:
		set_collision_disabled(false)
	if rz > Constants.MISS_Z:
		on_miss()

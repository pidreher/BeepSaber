# The lightsaber logic is mostly contained in the BeepSaber_Game.gd
# here I only track the extended/sheethed state and provide helper functions to
# trigger the necessary animations
extends Area3D
class_name LightSaber

# the type of note this saber can cut (0 -> left, 1 -> right)
@export var type := 0 # (int, 0, 1)
@export var song_player_ref: AudioStreamPlayer

# store the saber material in a variable so the main game can set the color on initialize
@onready var _anim := $AnimationPlayer as AnimationPlayer
@onready var _ray_cast := $RayCast3D as RayCast3D
@onready var _swing_cast := $SwingableRayCast as SwingableRayCast
@onready var saber_visual := $saber_holder.get_child(0) as DefaultSaber
@onready var controller := get_parent() as BeepSaberController
@onready var collision_shape := $CollisionShape3D as CollisionShape3D
@onready var collision_cylinder := collision_shape.shape as CylinderShape3D

@export var offset_pos := Vector3.ZERO
@export var offset_rot := Vector3.ZERO
var extra_offset_pos := Vector3.ZERO
var extra_offset_rot := Vector3.ZERO
var second_extra_offset_rot := Vector3.ZERO

var saber_end := Vector3.ZERO
var saber_end_past := Vector3.ZERO
var last_dt := 0.0

var history := Array()
const history_size := 300
const preswing_time := 200
const followthrough_time := 200
var history_tail := history_size - 1

# entry: [time,position,pointing,preswing_angle,accuracy]
var score_queue := Array() 

func _update_size_and_angle():
	if type == 0:
		@warning_ignore("unsafe_cast")				
		extra_offset_rot = Settings.left_saber_offset_rot
		extra_offset_pos = Settings.left_saber_offset_pos
	else:
		@warning_ignore("unsafe_cast")				
		extra_offset_rot = Settings.right_saber_offset_rot
		extra_offset_pos = Settings.right_saber_offset_pos

	if Settings.claws:
		collision_shape.position.y = .2142
		collision_cylinder.height = 0.3744
		#extra_offset_rot.x -= 90
		#extra_offset_pos.z += .055
		#extra_offset_pos.y += -.005
	else:
		# The blade is 1.0 m long.
		collision_cylinder.height = 1.048
		collision_shape.position.y = .551

func _show() -> void:
	_update_size_and_angle()
	if not is_extended() or (Settings.claws and _swing_cast.target_position.y > 1.) or (not Settings.claws and _swing_cast.target_position.y < 1.):
		_anim.play(&"ShowShort" if Settings.claws else &"Show")
		saber_visual._show()

func is_extended() -> bool:
	return saber_visual.is_extended

func _hide() -> void:
	# This check makes sure that we are not already in the hidden state
	# (where we translated the light saber to the hilt) to avoid playing it back
	# again from the fully extended light saber position
	if (is_extended() and _anim.current_animation != "QuickHide"):
		_anim.play(&"HideShort" if Settings.claws else &"Hide")
		saber_visual._hide()

const REFLECTION_SHADER := preload("res://game/environment/Reflection.gdshader")

func set_color(color: Color) -> void:
	saber_visual.set_color(color)
	_update_reflection(color)

# The blade is mirrored on reflective floors (see game/environment). The mirrored copy is
# a child of the blade that shares its mesh, so it follows the extend animation.
func _update_reflection(color: Color) -> void:
	var blade := saber_visual.get_node_or_null(^"LightSaber_Mesh") as MeshInstance3D
	if blade == null: return
	var copy := blade.get_node_or_null(^"Reflection") as MeshInstance3D
	if copy == null:
		copy = MeshInstance3D.new()
		copy.name = &"Reflection"
		copy.mesh = blade.mesh
		copy.layers = blade.layers
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.extra_cull_margin = 4.0
		var material := ShaderMaterial.new()
		material.shader = REFLECTION_SHADER
		material.render_priority = -10
		copy.material_override = material
		blade.add_child(copy)
	(copy.material_override as ShaderMaterial).set_shader_parameter(&"color", color * 0.8)
	copy.visible = Settings.reflections

func on_settings_changed(key: StringName) -> void:
	match key:
		&"color_left":
			if type == 0:
				set_color(Settings.color_left)
		&"color_right":
			if type == 1:
				set_color(Settings.color_right)
		&"reflections":
			_update_reflection(Settings.color_left if type == 0 else Settings.color_right)
		&"thickness":
			saber_visual.set_thickness(Settings.thickness)
		&"saber_tail":
			saber_visual.set_trail(Settings.saber_tail)
		&"saber_visual":
			set_saber(Settings.get_saber_visuals())
		&"claws":
			set_saber(Settings.get_saber_visuals())
		&"left_saber_offset_pos":
			_update_size_and_angle()
		&"right_saber_offset_pos":
			_update_size_and_angle()
		&"left_saber_offset_rot":
			_update_size_and_angle()
		&"right_saber_offset_rot":
			_update_size_and_angle()

func _ready() -> void:
	set_saber(Settings.SABER_VISUALS[Settings.saber_visual][1])
	_anim.play(&"QuickHide")
	saber_visual.quickhide()
	saber_visual.set_thickness(Settings.thickness)
	saber_visual.set_trail(Settings.saber_tail)
	
	@warning_ignore("return_value_discarded")
	Settings.changed.connect(on_settings_changed)
	
	if type == 0:
		_swing_cast._set_collision_mask_value(CollisionLayerConstants.LeftNote_bit, true)
	else:
		_swing_cast._set_collision_mask_value(CollisionLayerConstants.RightNote_bit, true)
	_swing_cast._set_collision_mask_value(CollisionLayerConstants.Bombs_bit, true)
	
	_update_size_and_angle()
	
func get_pointing() -> Vector3:
	return (saber_end-global_transform.origin).normalized()
	
func _update_history(time: int) -> void:
	history_tail = (history_tail + 1) % history_size
	if history_tail >= history.size():
		history.append([time, get_pointing()])
	else:
		history[history_tail] = [time, get_pointing()]
	
func add_score(position: Vector3, lane_rotation: float, accuracy: float, arc_head: bool, arc_tail: bool) -> void:
	var time = Time.get_ticks_msec()
	var pointing := get_pointing()
	var preswing := get_preswing_angle(time, pointing) if not arc_head else Constants.TARGET_PRESWING_ANGLE
	if arc_tail:
		Scoreboard.add_swing_score(position, lane_rotation, accuracy, preswing, Constants.TARGET_FOLLOWTHROUGH_ANGLE)
	else:
		score_queue.append([Time.get_ticks_msec(), position, lane_rotation, get_pointing(), preswing, accuracy])
	
func add_chain_head_score(position: Vector3, lane_rotation: float, accuracy: float) -> void:
	var time = Time.get_ticks_msec()
	var pointing := get_pointing()
	var preswing := get_preswing_angle(time, pointing)
	Scoreboard.add_swing_score(position, lane_rotation, accuracy, preswing, 0.)
	
func get_preswing_angle(time: int, pointing: Vector3) -> float:
	if history[history_tail].size() == 0:
		return 0.
	var start_time := time - preswing_time
	var i := (history_tail - 1 + history_size) % history_size
	var smallest_dot_product := 1.
	while i != history_tail and history[i].size() > 0 and history[i][0] >= start_time:
		var dot := pointing.dot(history[i][1])
		if dot < smallest_dot_product:
			smallest_dot_product = dot
		i = (i - 1 + history_size) % history_size
	return 180. / PI * acos(smallest_dot_product)
	
func get_followthrough_angle(time: int, pointing: Vector3) -> float:
	if history[history_tail].size() == 0:
		return 0.
	var smallest_dot_product := pointing.dot(history[history_tail][1])
	var i := (history_tail - 1 + history_size) % history_size
	while i != history_tail and history[i].size() > 0 and history[i][0] > time:
		var dot := pointing.dot(history[i][1])
		if dot < smallest_dot_product:
			smallest_dot_product = dot
		i = (i - 1 + history_size) % history_size
	return 180. / PI * acos(smallest_dot_product)
	
func _update_score(score_entry) -> void:
	var position := score_entry[1] as Vector3
	var lane_rotation := score_entry[2] as float
	var pointing := score_entry[3] as Vector3
	var preswing := score_entry[4] as float
	var other_component := score_entry[5] as float
	var followthrough := get_followthrough_angle(score_entry[0], pointing)
	Scoreboard.add_swing_score(position, lane_rotation, other_component, preswing, followthrough)
	
func _update_scores() -> void:
	var start_time = Time.get_ticks_msec() - followthrough_time
	for i in range(score_queue.size()-1,-1,-1):
		if score_queue[i][0] <= start_time:
			_update_score(score_queue[i])
			score_queue.remove_at(i)
			
func _physics_process(delta: float) -> void:
	position = offset_pos + extra_offset_pos
	rotation_degrees = offset_rot + extra_offset_rot + second_extra_offset_rot
	saber_end_past = saber_end
	saber_end = saber_visual.tip.global_transform.origin
	var time := Time.get_ticks_msec()
	if Settings.swing_scoring:
		_update_history(time)
		_update_scores()
	
	last_dt = delta
	if is_extended():
		#check floor collision for burn mark
		_ray_cast.force_raycast_update()
		var raycoli := _ray_cast.get_collider()
		if raycoli is Floor:
			var floor_body := raycoli as Floor
			var colipoint := _ray_cast.get_collision_point()
			floor_body.burn_mark(colipoint,type)
	RenderingServer.global_shader_parameter_set(&"left_saber" if type == 0 else &"right_saber", saber_end)

func set_saber(saber_path: String) -> void:
	var newsaber := (load(saber_path) as PackedScene).instantiate()
	if newsaber is DefaultSaber:
		for i in $saber_holder.get_children():
			i.queue_free()
		saber_visual = newsaber
		$saber_holder.add_child(saber_visual)
		set_color(Settings.color_right if type else Settings.color_left)
		saber_visual.set_thickness(Settings.thickness)
		saber_visual.set_trail(Settings.saber_tail)

func set_swingcast_enabled(value: bool) -> void:
	_swing_cast.set_raycasts_enabled(value)

func _handle_area_collided(area: Area3D) -> void:
	if Scoreboard.paused: return
	var cut_object := area.get_parent()
	if not cut_object is Cuttable: return
	var note := cut_object as Cuttable
	
	var time_offset: float = (
		(note.beat/Map.current_info.beats_per_minute * 60.0)-
		song_player_ref.get_playback_position()
	)
	var controller_speed: Vector3 = (saber_end - saber_end_past) / last_dt
	# faster swings feel (and sound) stronger: ~1.5 m/s tip speed is a soft tap,
	# ~9 m/s a full swing
	# The cut sound is silent below 1.5 m/s tip speed and full from 4 m/s.
	var hit_strength := smoothstep(1.5, 4.0, controller_speed.length())
	# A note cut with the wrong saber gets its own sound instead of the cut sound.
	var wrong_saber: bool = ("which_saber" in note and note.get(&"which_saber") != type
		and not Map.one_saber and Settings.handedness == 0 and not note is Bomb)
	saber_visual.hit(time_offset, hit_strength, wrong_saber)
	# Every cut gets the same full-strength 0.13 s pulse.
	controller.simple_rumble(1.0, 0.13)
	
	var o := controller.global_transform.origin
	var cutplane := Plane(o, saber_end, saber_end_past + Vector3(0, 0, Map.beat_distance * Map.current_info.beats_per_minute * last_dt / 30)) # Account for relative position to track speed
	note.cut(self, controller_speed, cutplane, controller)

func _on_AnimationPlayer_animation_started(_anim_name: StringName) -> void:
	_swing_cast.adjust_segments = true

func _on_AnimationPlayer_animation_finished(_anim_name: StringName) -> void:
	_swing_cast.adjust_segments = false

extends Cuttable
class_name Bomb

@onready var collision_shape := $Area3D/CollisionShape3D as CollisionShape3D

func set_collision_disabled(value: bool) -> void:
	collision_shape.disabled = value

@warning_ignore("unused_parameter")
func cut(saber: LightSaber, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController, blade_speed: float = -1.0) -> void:
	Scoreboard.bad_cut(transform.origin, lane_rotation, "bomb")
	queue_free()

func on_miss() -> void:
	queue_free()

static var _chroma_materials := {}

static func _chroma_material(color: Color) -> StandardMaterial3D:
	if not _chroma_materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.5
		_chroma_materials[color] = m
	return _chroma_materials[color]

func spawn(info: BombInfo, current_beat: float) -> void:
	speed = Map.beat_distance * Map.current_info.beats_per_minute / 60.0
	beat = info.beat
	
	var distance: float = info.beat - current_beat
	
	transform.origin.x = Settings.LANE_DISTANCE_X * float(info.line_index) + Settings.LANE_ZERO_X
	transform.origin.y = Constants.layer_y(float(info.line_layer))
	transform.origin.z = -distance * Map.beat_distance
	
	add_lane_rotation(info.rotation)
	configure_jump(float(info.line_layer))
	start_fly_in(info.beat, current_beat)
	
	if info.custom_color.a > 0: # Chroma
		($BombAnimation/Mesh/Icosphere as MeshInstance3D).material_override = _chroma_material(info.custom_color)
	
	# Bombs can spawn before entering the tree; keep their visible root aligned.
	($BombAnimation as Node3D).transform = Transform3D.IDENTITY

extends Cuttable
class_name ChainLink

var which_saber: int
var _mesh: Mesh
var _mat: ShaderMaterial

@onready var mi := $Mesh as MeshInstance3D

var piece_left : CutPiece = null
var piece_right : CutPiece = null

func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mesh = mi.mesh
	
	# init our cut pieces with unique copies of our own material for reference,
	# and disable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, false)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, false)
	piece_left.set_chain_head(false)
	piece_right.set_chain_head(false)

static func construct_chain(chain_info: ChainInfo, current_beat: float, note_info_refs: Array[ColorNoteInfo], cube_refs: Array[BeepCube]) -> void:
	# instead of spawning a new note head for a chain, the map format
	# turns an already-existing note into the head, which is why we have to
	# do all this garbage with keeping references to other notes that were
	# spawned this frame.
	var i := 0
	while i < note_info_refs.size():
		var info_ref := note_info_refs[i]
		if (
			info_ref.beat == chain_info.head_beat
			and info_ref.line_index == chain_info.head_line_index
			and info_ref.line_layer == chain_info.head_line_layer
		):
			cube_refs[i].make_chain_head()
		i += 1
	
	# the curve of the chain is gotten from a 3-point bezier curve.  the first
	# point is the head position, the last point is the tail position, and the
	# mid point is based on the head and tail points.
	#
	# to get the mid point, draw a straight line from the head note, in the
	# direction the head note is pointing, with length equal to half the length
	# of a straight line from the head to the tail.  the end point of the line
	# you just drew is the mid point of the curve.
	var head_pos := Vector2(
		Settings.LANE_DISTANCE_X * float(chain_info.head_line_index) + Settings.LANE_ZERO_X,
		Constants.layer_y(float(chain_info.head_line_layer))
	)
	var tail_pos := Vector2(
		Settings.LANE_DISTANCE_X * float(chain_info.tail_line_index) + Settings.LANE_ZERO_X,
		Constants.layer_y(float(chain_info.tail_line_layer))
	)
	var mid_pos := head_pos + Utils.rotation_unit_vector(chain_info.head_cut_angle) * head_pos.distance_to(tail_pos) * 0.5
	i = 1
	while i < chain_info.slice_count:
		var chain_link := GlobalReferences.link_pool.acquire() as ChainLink
		chain_link.spawn(chain_info, current_beat, head_pos, tail_pos, mid_pos, i)
		i += 1

func spawn(chain_info: ChainInfo, current_beat: float, head_pos: Vector2, tail_pos: Vector2, mid_pos: Vector2, link_index: int) -> void:
	# Pooled nodes resume processing before any spawn state is changed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var color := Map.color_left if chain_info.color == 0 else Map.color_right
	speed = Map.beat_distance * Map.current_info.beats_per_minute * 0.016666666666666667
	which_saber = chain_info.color
	
	var lerp_factor := float(link_index) / float(chain_info.slice_count - 1) * chain_info.squish_factor
	beat = lerpf(chain_info.head_beat, chain_info.tail_beat, lerp_factor)
	
	var q0 := head_pos.lerp(mid_pos, lerp_factor)
	var q1 := mid_pos.lerp(tail_pos, lerp_factor)
	var bezier_pos := q0.lerp(q1, lerp_factor)
	
	# TODO: USE THIS
	#scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	
	transform.origin.x = bezier_pos.x
	transform.origin.y = bezier_pos.y
	transform.origin.z = -(beat - current_beat) * Map.beat_distance
	
	add_lane_rotation(chain_info.rotation)
	# Preserve the bezier tangent: links rise without the notes' entry tumble.
	var row := lerpf(float(chain_info.head_line_layer), float(chain_info.tail_line_layer), lerp_factor)
	configure_jump(row, q0.angle_to_point(q1) - TAU * 0.25)
	start_fly_in(beat, current_beat)
	
	# little bit of forgiveness.  if the chain link is more than a meter away
	# from the chain head, its hitbox is extended to halfway between the link
	# and the head.
	var z_distance_from_head := (beat - chain_info.head_beat) * Map.beat_distance
	if z_distance_from_head > 1.0:
		var collision := $Area3D/CollisionShape3D as CollisionShape3D
		var new_size := z_distance_from_head * 0.5
		(collision.shape as BoxShape3D).size.z = new_size
		collision.transform.origin.z = new_size * 0.5 - 0.25
	
	piece_left.set_color(color, false) # TODO: can it be true?
	piece_right.set_color(color, false)
	_mat.set_shader_parameter(&"color", color)
	
	mi.transform = Transform3D.IDENTITY
	
	mi.visible = true

# call this when clearing the track
func clear_from_track() -> void:
	hide_cube()
	piece_left.hide_piece()
	piece_right.hide_piece()
	if ! is_released():
		release()

func hide_cube() -> void:
	mi.visible = false
	set_collision_disabled(true)
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED # disable to help with performance

func cut(saber: LightSaber, _cut_speed: Vector3, cut_plane: Plane, _controller: BeepSaberController, _blade_speed: float = -1.0) -> void:
	#_cut_speed = _cut_speed.rotated(Vector3(0,1,0),-rotation.x)
	if saber.type == which_saber or Map.one_saber or Settings.handedness != 0:
		Scoreboard.chain_link_cut(transform.origin, lane_rotation)
	else:
		Scoreboard.bad_cut(transform.origin, lane_rotation, "chain wrong saber")
	
	hide_cube()
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release()# release now instead of waiting for cut pieces to die off

# Chain links only need the right saber (no direction or speed check).
func is_bad_cut(saber_type: int, _cut_speed: Vector3, _blade_speed: float = -1.0) -> bool:
	return not (saber_type == which_saber or Map.one_saber or Settings.handedness != 0)

func on_miss() -> void:
	Scoreboard.bad_cut(transform.origin, lane_rotation, "chain miss")
	hide_cube()
	release()

func set_collision_disabled(value: bool) -> void:
	($Area3D/CollisionShape3D as CollisionShape3D).disabled = value

func _start_cut_pieces(cutplane: Plane) -> void:
	piece_left.global_transform = global_transform
	piece_right.global_transform = global_transform
	
	_piece_death_count = 0
	piece_left.start_cut_plane(-cutplane.normal, -cutplane.d)
	piece_right.start_cut_plane(cutplane.normal, cutplane.d)
	var split_vector := cutplane.normal * 2.0
	piece_left.apply_central_impulse(-split_vector)
	piece_right.apply_central_impulse(split_vector)

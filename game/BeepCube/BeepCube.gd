# BeepCube is the standard cube that will get cut by the sabers
extends Cuttable
class_name BeepCube

# emitted when the cube gets cutted, correct_saber is true if the right saber was used
signal cutted(correct_saber: bool)

@onready var mi := $BeepCubeMesh as MeshInstance3D
@onready var collision_big := $BeepCube_Big/CollisionBig as CollisionShape3D
@onready var collision_small := $BeepCube_Small/CollisionSmall as CollisionShape3D
@onready var slice_particles := $SliceParticles as BeepCubeSliceParticles

var which_saber: int
var is_dot: bool

# we store the mesh here as part of the BeepCube for easier access because we will
# reuse it when we create the cut cube pieces
var _mesh: Mesh
var _mat: ShaderMaterial
var _cut_color := Color.WHITE
# Mirrored copy drawn on reflective floors (see game/environment).
var _reflection := ShaderMaterial.new()
const REFLECTION_SHADER := preload("res://game/environment/Reflection.gdshader")
const REFLECTION_STRENGTH := 0.5
const SYMBOL_GLOW_SHADER := preload("res://game/BeepCube/NoteSymbolGlow.gdshader")
static var _symbol_glow_mesh: QuadMesh
static var _symbol_glow_materials: Dictionary = {}
var _symbol_glow: MeshInstance3D
const BEAT_ACCURACY_ZERO_AT := 0.125

var piece_left : CutPiece = null
var piece_right : CutPiece = null
var arc_head = false
var arc_tail = false
var chain_head = false

func _ready() -> void:
	_mat = mi.material_override as ShaderMaterial
	_mesh = mi.mesh
	_reflection.shader = REFLECTION_SHADER
	_reflection.render_priority = -10
	if _symbol_glow_mesh == null:
		_symbol_glow_mesh = QuadMesh.new()
		_symbol_glow_mesh.size = Vector2.ONE
	_symbol_glow = MeshInstance3D.new()
	_symbol_glow.mesh = _symbol_glow_mesh
	_symbol_glow.layers = mi.layers
	_symbol_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(_symbol_glow)
	
	# init our cut pieces with unique copies of our own material for reference,
	# and enable "bouncy" physics behavior
	piece_left = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	piece_right = CutPiece.new(self, _mesh, _mat.duplicate(true) as ShaderMaterial, true)
	
	# slice_particles are within cube's tree, but want then to move in global space
	slice_particles.top_level = true
	
func spawn(note_info: ColorNoteInfo, current_beat: float) -> void:
	# Pooled nodes resume processing before any spawn state is changed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var color := Map.color_left if note_info.color == 0 else Map.color_right
	if note_info.custom_color.a > 0: # Chroma
		color = note_info.custom_color
	_cut_color = color
	speed = Map.beat_distance * Map.current_info.beats_per_minute * 0.016666666666666667
	beat = note_info.beat
	which_saber = note_info.color
	is_dot = note_info.cut_angle >= Constants.DIRECTION8_COMPARE
	
	if is_dot:
		(collision_big.shape as BoxShape3D).size.y = 0.8
	else:
		(collision_big.shape as BoxShape3D).size.y = 0.5
		
	scale = Vector3(Settings.block_size/100.,Settings.block_size/100.,Settings.block_size/100.)
	transform.origin.x = Settings.LANE_DISTANCE_X * float(note_info.line_index) + Settings.LANE_ZERO_X
	transform.origin.y = Constants.layer_y(float(note_info.line_layer))
	transform.origin.z = -(note_info.beat - current_beat) * Map.beat_distance
	
	add_lane_rotation(note_info.rotation)
	configure_jump(float(note_info.line_layer), 0.0 if is_dot else note_info.cut_angle, true)
	start_fly_in(note_info.beat, current_beat)
	
	piece_left.set_color(color, is_dot)
	piece_right.set_color(color, is_dot)
	_mat.set_shader_parameter(&"color", color)
	_mat.next_pass = _reflection if Settings.reflections else null
	_reflection.set_shader_parameter(&"color", color * REFLECTION_STRENGTH)
	_mat.set_shader_parameter(&"is_dot", is_dot)
	_mat.set_shader_parameter(&"arrows_enabled", Settings.arrows_enabled)
	# since cube instances get recycled, we gotta reset cubes that were chain
	# heads in a past life
	_mat.set_shader_parameter(&"is_chain_head", false)
	piece_left.set_chain_head(false)
	piece_right.set_chain_head(false)
	chain_head = false
	
	# separate cube collision layers to allow a diferent collider on right/wrong cuts.
	# opposing collision layers (ie. right note & left saber) will be placed on the
	# smalling collision shape, while similar collision layers (ie right note &
	# right saber) are placed on the larger collision shape.
	var is_left_note := note_info.color == 0
	var big_coll_area := $BeepCube_Big as Area3D
	big_coll_area.collision_layer = 0x0
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, is_left_note)
	big_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, not is_left_note)
	var small_coll_area := $BeepCube_Small as Area3D
	small_coll_area.collision_layer = 0x0
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.LeftNote_bit, not is_left_note)
	small_coll_area.set_collision_layer_value(CollisionLayerConstants.RightNote_bit, is_left_note)
	
	# The root now carries the full jump, so visuals and hitboxes stay aligned.
	mi.transform = Transform3D.IDENTITY
	_update_symbol_glow(color)
	
	slice_particles.reset()
	mi.visible = true

# Reuse one additive material per color/shape, including custom map colors.
func _update_symbol_glow(color: Color) -> void:
	var key := Vector4(color.r, color.g, color.b, 1.0 if is_dot else 0.0)
	if not _symbol_glow_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SYMBOL_GLOW_SHADER
		material.set_shader_parameter(&"color", color.lerp(Color.WHITE, 0.3))
		material.set_shader_parameter(&"is_dot", is_dot)
		_symbol_glow_materials[key] = material
	_symbol_glow.material_override = _symbol_glow_materials[key]
	_symbol_glow.position = Vector3(0.0, 0.0 if is_dot else 0.108, 0.253)
	_symbol_glow.scale = Vector3(0.5, 0.5, 1.0) if is_dot else Vector3(0.56, 0.28, 1.0)
	_symbol_glow.visible = is_dot or Settings.arrows_enabled

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
	process_mode = Node.PROCESS_MODE_DISABLED

func make_chain_head() -> void:
	_mat.set_shader_parameter(&"is_chain_head", true)
	piece_left.set_chain_head(true)
	piece_right.set_chain_head(true)
	chain_head = true

func on_miss() -> void:
	Scoreboard.bad_cut(global_transform.origin+Vector3(0,0,-3.5), lane_rotation, "miss")
	hide_cube()
	release()

func set_collision_disabled(value: bool) -> void:
	collision_big.disabled = value
	collision_small.disabled = value
	
func set_arc_head() -> void:
	arc_head = true

func set_arc_tail() -> void:
	arc_tail = true

# A cut only counts as good with the right saber, a blade speed above 2 m/s and, for
# arrows, a swing within 60 degrees of the arrow direction. Anything else is a bad cut.
const MIN_CUT_SPEED := 2.0
const MIN_CUT_DIRECTION_DOT := 0.5 # cos(60 deg)

func _is_right_saber(saber_type: int) -> bool:
	return saber_type == which_saber or Map.one_saber or Settings.handedness != 0

func is_bad_cut(saber_type: int, cut_speed: Vector3) -> bool:
	if not _is_right_saber(saber_type) or cut_speed.length() <= MIN_CUT_SPEED: return true
	if is_dot or not Settings.arrows_enabled: return false
	var cut_direction := -cut_speed.slide(_lane_basis.z).normalized()
	return global_transform.basis.orthonormalized().y.dot(cut_direction) < MIN_CUT_DIRECTION_DOT

func cut(saber: LightSaber, cut_speed: Vector3, cut_plane: Plane, controller: BeepSaberController) -> void:
	var world_cut_speed := cut_speed
	# compute the angle between the cube orientation and the cut direction
	var cut_direction := -cut_speed.slide(_lane_basis.z).normalized()
	var base_cut_angle_accuracy := global_transform.basis.orthonormalized().y.dot(cut_direction)
	var cut_distance := cut_plane.distance_to(global_transform.origin)
	var distance_scale := 100./Settings.block_size
	
	if not _is_right_saber(saber.type):
		Scoreboard.bad_cut(transform.origin, lane_rotation, "wrong saber")
		cutted.emit(false)
	elif is_bad_cut(saber.type, cut_speed):
		Scoreboard.bad_cut(transform.origin, lane_rotation, "bad cut")
		cutted.emit(false)
	else:
		var cut_angle_accuracy := clampf((base_cut_angle_accuracy-0.7)/0.3, 0.0, 1.0)
		if is_dot or not Settings.arrows_enabled: #ignore angle if is a dot
			cut_angle_accuracy = 1.0
		var cut_distance_accuracy := clampf((0.1 - absf(cut_distance*distance_scale))/0.1, 0.0, 1.0)
		var travel_distance_factor := controller.movement_aabb.get_longest_axis_size()
		travel_distance_factor = clampf((travel_distance_factor-0.5)/0.5, 0.0, 1.0)
		# allows a bit of save margin where the beat is considered 100% correct
		# Timing in seconds (track-local z=0 is on the beat): full within 62.5 ms, none past 125 ms.
		# This is the old 0.5 m / 1 m window at 8 m/s, so it no longer depends on the note speed.
		var seconds_off := absf(position.dot(_lane_basis.z)) / maxf(speed, 0.1)
		var beat_accuracy := clampf((1.0 - seconds_off / BEAT_ACCURACY_ZERO_AT) / 0.5, 0.0, 1.0)
		Scoreboard.note_cut(saber, transform.origin, lane_rotation, beat_accuracy, cut_angle_accuracy, cut_distance_accuracy, travel_distance_factor, arc_head, arc_tail, chain_head)
		cutted.emit(true)
	
	# reset the movement tracking volume for the next cut
	controller.reset_movement_aabb()
	var game := GlobalReferences.main_game_scene
	if game != null:
		game.cut_splashes.splash(cut_plane.project(global_position), world_cut_speed, _cut_color)
	
	hide_cube()
	if Settings.cube_cuts_falloff:
		_start_cut_pieces(cut_plane)
		# release() will be called by Cuttable class when it sees both pieces die
	else:
		release() # release now instead of waiting for cut pieces to die off

# cut the cube by creating two rigid bodies and using a CSGBox to create
# the cut plane
func _start_cut_pieces(cutplane: Plane) -> void:
	piece_left.scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	piece_right.scale = Vector3(Settings.block_size,Settings.block_size,Settings.block_size)/100.
	piece_left.global_transform = global_transform
	piece_right.global_transform = global_transform
	
	# calculate angle and position of the cut
	#var cut_angle_abs := Vector2(cutplane.normal.x, cutplane.normal.y).angle()
	
	_piece_death_count = 0

	var p := cutplane # ARP: fix rot global_transform * 
	piece_left.start_cut_plane(-p.normal, -p.d) # ARP: scale p.d for block size?
	piece_right.start_cut_plane(p.normal, p.d)
	
	# some impulse so the cube half moves
	var split_vector := p.normal * 2.0
	piece_left.apply_central_impulse(-split_vector) #piece_left.transform * -split_vector)
	piece_right.apply_central_impulse(split_vector)#piece_right.transform * split_vector)
	
	#slice_particles.global_transform.origin = global_transform.origin
	#slice_particles.rotation.z = cut_angle_abs+TAU*0.25
	#slice_particles.fire()

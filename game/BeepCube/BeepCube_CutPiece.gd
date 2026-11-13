extends RigidBody3D
class_name CutPiece

# structure of nodes that represent a cut piece of a cube (ie. one half)
static var cube_phys_mat := load("res://game/BeepCube/BeepCube_Cut.phymat") as PhysicsMaterial
var mesh := MeshInstance3D.new()
var coll := CollisionShape3D.new()
var lifetime: float = 0.0
var parent_cube : Node3D = null
var _material: ShaderMaterial
var _face := MeshInstance3D.new()
var _face_material := ShaderMaterial.new()
const CUT_FACE_SHADER := preload("res://game/BeepCube/CutFace.gdshader")
const MAX_LIFETIME := 0.6

func _init(parent: Node3D, mesh_in: Mesh, mat_in: ShaderMaterial, bouncy: bool) -> void:
	parent_cube = parent
	
	# cut pieces will reside inside of their parent_cube's node tree, but we want
	# them to move independently, thus setting their transform to be 'top_level'
	parent_cube.add_child(self)
	top_level = true
	
	add_to_group(&"cutted_cube")
	mat_in.set_shader_parameter(&"cutted", true)
	collision_layer = 0
	collision_mask = CollisionLayerConstants.Floor_mask
	gravity_scale = 1
	if bouncy:
		# set a physics material for some more bouncy behaviour
		physics_material_override = cube_phys_mat
	
	mesh.mesh = mesh_in
	mesh.layers = 3 # visible to both spectator and player
	mesh.material_override = mat_in
	_material = mat_in
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * mesh_in.get_aabb().size.length()
	_face.mesh = quad
	_face.custom_aabb = mesh_in.get_aabb().grow(0.01)
	_face.layers = mesh.layers
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face_material.shader = CUT_FACE_SHADER
	_face_material.set_shader_parameter(&"half_size", mesh_in.get_aabb().size * 0.5)
	_face.material_override = _face_material
	
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 0.25, 0.125)
	coll.shape = shape
	
	add_child(coll)
	add_child(mesh)
	add_child(_face)
	
	hide_piece()

func start_cut_plane(normal: Vector3, dist: float) -> void:
	# Pooled nodes resume processing before any spawn state is changed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# The rigid body's transform already includes the note's scale and orientation.
	mesh.scale = Vector3.ONE
	lifetime = 0.0
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3(randf_range(-1.8, 1.8), randf_range(-1.8, 1.8), randf_range(-2.4, 2.4))

	# Convert the world cut plane into the same local space as both visible halves.
	var local_plane: Plane = global_transform.affine_inverse() * Plane(normal, dist)
	local_plane = local_plane.normalized()
	_material.set_shader_parameter(&"cut_plane_normal", local_plane.normal)
	_material.set_shader_parameter(&"cut_plane_dist", local_plane.d)
	_material.set_shader_parameter(&"cut_vanish", 0.0)
	var tangent := local_plane.normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = local_plane.normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	_face_material.set_shader_parameter(&"plane_normal", local_plane.normal)
	_face_material.set_shader_parameter(&"plane_tangent", tangent)
	_face_material.set_shader_parameter(&"plane_dist", local_plane.d)
	_face_material.set_shader_parameter(&"cut_vanish", 0.0)

func set_color(new_color: Color, is_dot: bool) -> void:
	_material.set_shader_parameter(&"color", new_color)
	_face_material.set_shader_parameter(&"color", new_color)
	mesh.material_override.set_shader_parameter(&"is_dot", is_dot)
	mesh.material_override.set_shader_parameter(&"arrows_enabled", Settings.arrows_enabled)
	
func set_chain_head(is_chain_head: bool) -> void:
	_face_material.set_shader_parameter(&"is_chain_head", is_chain_head)
	mesh.material_override.set_shader_parameter(&"is_chain_head", is_chain_head)

func hide_piece() -> void:
	visible = false
	# disable processing on this node and all children to help with performance
	process_mode = Node.PROCESS_MODE_DISABLED

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime >= MAX_LIFETIME:
		hide_piece()
		parent_cube._on_cut_piece_died()
	else:
		var fade := lifetime / MAX_LIFETIME
		_material.set_shader_parameter(&"cut_vanish", fade)
		_face_material.set_shader_parameter(&"cut_vanish", fade)

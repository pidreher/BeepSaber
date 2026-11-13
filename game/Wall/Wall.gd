extends Node3D
class_name Wall

var despawn_z: float
var speed: float
var _fly_time_left := 0.0
var _fly_extra := 0.0

# Shared geometry: only the size/color uniforms differ between wall instances.
static var _edge_mesh: ArrayMesh
const DEFAULT_WALL_COLOR := Color(1.8, -0.2, -0.2, 0.0)

func _ready() -> void:
	var edges := $WallMeshOrientation/WallEdges as MeshInstance3D
	if edges.mesh == null:
		_update_visuals(($WallMeshOrientation/WallMesh.mesh as BoxMesh).size, DEFAULT_WALL_COLOR)

func _physics_process(delta: float) -> void:
	if Scoreboard.paused: return
	
	#transform.origin.z += speed * delta
	
	# remove children that go to far
	#if transform.origin.z > despawn_z:
	#	queue_free()
	
	transform.origin += speed * delta * transform.basis.z
	if _fly_time_left > 0.0:
		_fly_time_left = maxf(_fly_time_left - delta, 0.0)
		_set_fly_extra(Map.fly_in_extra_distance(_fly_time_left, speed))
	var rz := global_transform.origin.dot(transform.basis.z)
	
	if rz > despawn_z:
		queue_free()

	#transform.origin.x += speed * delta * sin(rotation.y)
	#transform.origin.z += speed * delta * cos(rotation.y)
	#
	#var rz := global_transform.rotated(Vector3(0,1,0), -rotation.y).origin.z
	#if rz > despawn_z:
	#	queue_free()
	

func spawn(wall_info: ObstacleInfo, current_beat: float) -> void:
	var mesh := $WallMeshOrientation/WallMesh as MeshInstance3D
	var m := mesh.mesh as BoxMesh
	var shape := ($WallMeshOrientation/WallArea/CollisionShape3D as CollisionShape3D).shape as BoxShape3D
	
	# The bottom sits 0.15 m below the note line, at least 0.1 m above the floor, and the
	# top never exceeds 3.1 m.
	# Rows are 0.6 m apart, so this matches 0.1/0.7/1.3 m for layers 0-2 and continues
	# linearly for Mapping Extensions' precise walls.
	var bottom := maxf(Constants.WALL_MIN_Y + wall_info.line_layer * Constants.WALL_LAYER_HEIGHT
		+ Map.jump_offset_y, Constants.WALL_MIN_Y)
	var x_size := wall_info.width * Settings.LANE_DISTANCE_X
	var y_size := wall_info.height * Constants.WALL_LAYER_HEIGHT
	if bottom < Constants.WALL_TOP_Y: y_size = minf(y_size, Constants.WALL_TOP_Y - bottom)
	y_size = maxf(y_size, 0.01)
	var z_size := wall_info.duration * Map.beat_distance
	var depth := z_size * 0.5
	m.size.x = x_size
	shape.size.x = x_size
	m.size.y = y_size
	shape.size.y = y_size
	m.size.z = z_size
	shape.size.z = z_size
	despawn_z = Constants.MISS_Z + depth
	var wall_color := DEFAULT_WALL_COLOR
	if wall_info.custom_color.a > 0: # Chroma
		# the default wall albedo is an over-saturated red (1.8, -0.2, -0.2); map
		# the custom color into the same range so it looks equally bright
		var c := wall_info.custom_color
		wall_color = Color(c.r * 2. - .2, c.g * 2. - .2, c.b * 2. - .2, 0.)
	_update_visuals(Vector3(x_size, y_size, z_size), wall_color)
	
	var x := (0.5 * wall_info.width + wall_info.line_index - 2) * Settings.LANE_DISTANCE_X
	var y := bottom + 0.5 * y_size
	var z := (current_beat - wall_info.beat) * Map.beat_distance - depth
	
	var c := cos(wall_info.rotation)
	var s := sin(wall_info.rotation)
	
	transform.origin.x = c * x - s * z
	transform.origin.y = y
	transform.origin.z = s * x + c * z
		
	rotation.y = -wall_info.rotation
	
	speed = Map.beat_distance * Map.current_info.beats_per_minute / 60.0
	_fly_time_left = Map.fly_in_time_left(wall_info.beat, current_beat)
	_set_fly_extra(Map.fly_in_extra_distance(_fly_time_left, speed))
	($AnimationPlayer as AnimationPlayer).play(&"Spawn")

func _set_fly_extra(extra: float) -> void:
	transform.origin -= transform.basis.z * (extra - _fly_extra)
	_fly_extra = extra

func _update_visuals(box_size: Vector3, wall_color: Color) -> void:
	var body := $WallMeshOrientation/WallMesh as MeshInstance3D
	var edges := $WallMeshOrientation/WallEdges as MeshInstance3D
	if _edge_mesh == null:
		_edge_mesh = _make_edge_mesh()
	edges.mesh = _edge_mesh
	# The halo stays world-sized even while Spawn squashes its parent to 0.1 on Y.
	# Include that expansion in the CPU bounds so edge strips cannot pop offscreen.
	var margin := Vector3(0.12, 1.2, 0.12)
	edges.custom_aabb = AABB(-box_size * 0.5 - margin, box_size + margin * 2.0)
	for instance: MeshInstance3D in [body, edges]:
		var material := instance.material_override as ShaderMaterial
		material.set_shader_parameter(&"size", box_size)
		material.set_shader_parameter(&"albedo_color", wall_color)

static func _make_edge_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Each axis has four parallel edges. Duplicated endpoints expand into quads
	# in the shader, keeping both the bright core and the halo constant in metres.
	for axis_index: int in range(3):
		var axis := Vector3.ZERO
		axis[axis_index] = 1.0
		for side_a: int in [-1, 1]:
			for side_b: int in [-1, 1]:
				var midpoint := Vector3.ZERO
				midpoint[(axis_index + 1) % 3] = side_a * 0.5
				midpoint[(axis_index + 2) % 3] = side_b * 0.5
				var start := vertices.size()
				for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
					vertices.append(midpoint + axis * (corner.y - 0.5))
					normals.append(axis)
					uvs.append(corner)
				indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 2, start + 1, start + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

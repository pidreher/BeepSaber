extends Node3D
class_name StageGeometry

# The player pad ends at z=0. The track starts StagePresets.TRACK_NEAR (7.65 m) in front
# of the player (Constants.PLAYER_Z = 1), across an open gap of 6.65 m.
const STAGE_FRONT := 1.0 - StagePresets.TRACK_NEAR
const STAGE_LENGTH := 48.0
const SCAFFOLD_DEPTH := 1.6
const PAD_WIDTH := 3.0
var _geometry := Node3D.new()
var _stage_collider := BoxShape3D.new()
var _collision := CollisionShape3D.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	add_child(_geometry)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 8
	_collision.shape = _stage_collider
	body.add_child(_collision)
	add_child(body)
	Settings.changed.connect(_on_settings_changed)
	_setup.call_deferred()

func _setup() -> void:
	var game := GlobalReferences.main_game_scene
	if game != null:
		var level := game.get_node_or_null("event_driver/Level")
		if level != null:
			# Preserve the existing lightshow materials and lane-width handling.
			(level.get_node("floor") as Node3D).position.z = STAGE_FRONT - STAGE_LENGTH * 0.5
			for bar_name in ["TrackLights/Bar1", "TrackLights/Bar2"]:
				var bar := level.get_node(bar_name) as MeshInstance3D
				var half_length := bar.get_aabb().size.z * bar.scale.z * 0.5
				bar.position.z = STAGE_FRONT - half_length
	_rebuild()

func _on_settings_changed(key: StringName) -> void:
	if key == &"width": _rebuild()
	if key == &"mixed_reality": visible = not Settings.mixed_reality

func _material(color: Color, metal: float, roughness: float, glow := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = roughness
	mat.emission_enabled = glow > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = glow
	return mat

func _box(batch: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	batch.append_from(mesh, 0, Transform3D(Basis.IDENTITY, center))

func _beam(batch: SurfaceTool, start: Vector3, end: Vector3, thickness: float) -> void:
	var direction := end - start
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, direction.length(), thickness)
	var up := direction.normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.01: side = up.cross(Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	batch.append_from(mesh, 0, Transform3D(basis, (start + end) * 0.5))

func _batch() -> SurfaceTool:
	var batch := SurfaceTool.new()
	batch.begin(Mesh.PRIMITIVE_TRIANGLES)
	return batch

func _finish(batch: SurfaceTool, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.layers = 3
	instance.mesh = batch.commit()
	instance.material_override = material
	_geometry.add_child(instance)

func _rebuild() -> void:
	for child in _geometry.get_children():
		_geometry.remove_child(child)
		child.queue_free()
	visible = not Settings.mixed_reality
	var lanes_width := 4.0 * Settings.LANE_DISTANCE_X
	# The decorative track is wider than the note lanes.
	var width := maxf(StagePresets.TRACK_HALF_WIDTH * 2.0, lanes_width + 0.3)
	var half := width * 0.5
	_stage_collider.size = Vector3(lanes_width, 0.14, STAGE_LENGTH)
	_collision.position = Vector3(0, -0.08, STAGE_FRONT - STAGE_LENGTH * 0.5)
	var deck := _batch()
	# A substantial lip makes the runway read as a suspended platform.
	_box(deck, Vector3(0, -0.085, STAGE_FRONT - 0.08), Vector3(width + 0.14, 0.15, 0.16))
	# The player platform is 3 m wide and 2 m deep. The 2 m burn surface and its
	# collision sit in the middle.
	_box(deck, Vector3(0, -0.12, Constants.PLAYER_Z), Vector3(PAD_WIDTH + 0.08, 0.22, 2.08))
	_finish(deck, _material(Color("18202e"), 0.72, 0.3, 0.09))
	var frame := _batch()
	var front_z := STAGE_FRONT - 0.12
	var back_z := front_z - 12.0
	for x in [-half, half]:
		_beam(frame, Vector3(x, -0.2, front_z), Vector3(x, -0.2, back_z), 0.09)
		_beam(frame, Vector3(x, -SCAFFOLD_DEPTH, front_z), Vector3(x, -SCAFFOLD_DEPTH, back_z), 0.075)
		for bay in 5:
			var z := front_z - bay * 3.0
			_beam(frame, Vector3(x, -0.2, z), Vector3(x, -SCAFFOLD_DEPTH, z), 0.085)
			if bay < 4:
				_beam(frame, Vector3(x, -0.22, z), Vector3(x, -SCAFFOLD_DEPTH, z - 3.0), 0.055)
				_beam(frame, Vector3(x, -SCAFFOLD_DEPTH, z), Vector3(x, -0.22, z - 3.0), 0.055)
	for bay in 5:
		var z := front_z - bay * 3.0
		_beam(frame, Vector3(-half, -SCAFFOLD_DEPTH, z), Vector3(half, -SCAFFOLD_DEPTH, z), 0.075)
	# The exposed front face is visibly cross-braced across the gap.
	_beam(frame, Vector3(-half, -0.2, front_z), Vector3(half, -SCAFFOLD_DEPTH, front_z), 0.065)
	_beam(frame, Vector3(-half, -SCAFFOLD_DEPTH, front_z), Vector3(half, -0.2, front_z), 0.065)
	_finish(frame, _material(Color("2b3646"), 0.65, 0.4, 0.17))
	var trim := _batch()
	var pad_half := PAD_WIDTH * 0.5 + 0.015
	_box(trim, Vector3(0, -0.015, Constants.PLAYER_Z - 1.016), Vector3(PAD_WIDTH - 0.04, 0.014, 0.018))
	_box(trim, Vector3(-pad_half, -0.015, Constants.PLAYER_Z), Vector3(0.014, 0.014, 1.98))
	_box(trim, Vector3(pad_half, -0.015, Constants.PLAYER_Z), Vector3(0.014, 0.014, 1.98))
	_box(trim, Vector3(0, -0.015, STAGE_FRONT - 0.008), Vector3(width, 0.014, 0.018))
	_finish(trim, _material(Color("547aab"), 0.1, 0.4, 1.8))
	# Dark glass over the track and, for some stages, a large floor. The light shaders
	# draw reflections underneath (StagePresets mirror areas).
	var preset := StagePresets.current
	if preset.get("glass_track", false):
		var glass := _batch()
		var length := StagePresets.TRACK_LENGTH
		_box(glass, Vector3(0, -0.012, STAGE_FRONT - length * 0.5), Vector3(width, 0.02, length))
		_finish(glass, _glass_material())
	if preset.has("glass_floor"):
		var area: Dictionary = preset.glass_floor
		var floor_glass := _batch()
		var near := Constants.PLAYER_Z - float(area.near)
		var far := Constants.PLAYER_Z - float(area.far)
		_box(floor_glass, Vector3(0, -0.03, (near + far) * 0.5), Vector3(float(area.half_width) * 2.0, 0.02, near - far))
		_finish(floor_glass, _glass_material())

# Reflections are drawn first (render priority -10) and seen through this.
func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.02, 0.03, 0.05, 0.35)
	mat.metallic = 0.9
	mat.roughness = 0.12
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.render_priority = -2
	return mat

# Called when a map picks its stage preset.
func rebuild() -> void:
	_rebuild()

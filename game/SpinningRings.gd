extends MultiMeshInstance3D
class_name SpinningRings

# A row of rings around the track that spin on ring rotation events (type 8) and
# optionally move together or apart on ring zoom events (type 9).
# A spin turns the rings by rotation_angle plus a random per-ring twist. It starts at the
# front ring and reaches one more ring per physics step, so the twist travels down the row.
# The rings are placed along -z, starting at the node's position.
# A ring can carry light bars. Those use the ring light material (event type 1), a glow
# halo and its reflection.

# The ring state advances in fixed steps and is interpolated in between.
const FIXED_DT := 1.0 / 30.0
const STARTUP_ANGLE := 45.0
const STARTUP_FLEXY_SPEED := 10.0
const PROPAGATION_SPEED := 1
# How the random per-ring twist of a spin is picked.
enum StepType { POSITIVE, SYMMETRIC, ALL_OR_NOTHING }

var _count := 0
var _rotation_angle := 90.0
var _rotation_step := 0.0
var _step_type := StepType.SYMMETRIC
var _flexy_speed := 0.0
var _zoom_min_step := 0.0
var _zoom_max_step := 0.0
var _zoom_move_speed := 0.0

var _rot := PackedFloat32Array()
var _prev_rot := PackedFloat32Array()
var _dest_rot := PackedFloat32Array()
var _rot_speed := PackedFloat32Array()
var _pos := PackedFloat32Array()
var _prev_pos := PackedFloat32Array()
var _dest_pos := PackedFloat32Array()
var _move_speed := 0.0
# Each effect is [progress, angle, step, flexy_speed].
var _effects: Array[PackedFloat32Array] = []
var _accumulator := 0.0
var _zoom_events := 0
var _initial_step := 0.0
# Extra layers that follow the rings: light bars and their glow.
var _layers: Array[MultiMesh] = []

# Builds the rings from a StagePresets ring entry. Light bars, if any, use
# light_material and glow_material.
func setup_from(config: Dictionary, material: Material, light_material: Material,
		glow_material: Material) -> void:
	var shape := RingShapes.build(config)
	_count = config.count
	_initial_step = config.step
	_rotation_angle = config.get("rotation_angle", 90.0)
	_rotation_step = config.rotation_step
	_step_type = config.get("step_type", StepType.SYMMETRIC)
	_flexy_speed = config.flexy_speed
	var zoom: Vector3 = config.zoom
	_zoom_min_step = zoom.x
	_zoom_max_step = zoom.y
	_zoom_move_speed = zoom.z
	for array: PackedFloat32Array in [_rot, _prev_rot, _dest_rot, _rot_speed, _pos, _prev_pos, _dest_pos]:
		array.resize(_count)
		array.fill(0.0)
	for i in _count:
		_pos[i] = i * _initial_step
		_prev_pos[i] = _pos[i]
		_dest_pos[i] = _pos[i]
	multimesh = _multimesh(shape.solid)
	material_override = material
	for child in get_children(): child.queue_free()
	_layers.clear()
	if shape.lights != null:
		_add_layer(shape.lights, light_material)
		_add_layer(shape.glow, glow_material)
	_effects.clear()
	_add_effect(STARTUP_ANGLE, config.startup_step, STARTUP_FLEXY_SPEED)
	_apply(0.0)

func _multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _count if mesh != null else 0
	return mm

func _add_layer(mesh: Mesh, material: Material) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh(mesh)
	instance.material_override = material
	instance.layers = 3
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = extra_cull_margin
	add_child(instance)
	_layers.append(instance.multimesh)

# Back to the initial spacing for a new map. The rotation carries on.
func reset_events() -> void:
	_zoom_events = 0
	_move_speed = 0.0
	for i in _count:
		_pos[i] = i * _initial_step
		_prev_pos[i] = _pos[i]
		_dest_pos[i] = _pos[i]

# Ring rotation event (type 8).
func spin() -> void:
	var step := 0.0
	match _step_type:
		StepType.POSITIVE: step = randf_range(0.0, _rotation_step)
		StepType.SYMMETRIC: step = randf_range(-_rotation_step, _rotation_step)
		StepType.ALL_OR_NOTHING: step = _rotation_step if randi() % 2 == 0 else 0.0
	var direction := -1.0 if randi() % 2 == 0 else 1.0
	_add_effect(_dest_rot[0] + _rotation_angle * direction, step, _flexy_speed)

# Ring zoom event (type 9). Even events spread the rings, odd events pull them together.
func zoom() -> void:
	if _zoom_max_step <= 0.0: return
	var step := _zoom_max_step if _zoom_events % 2 == 0 else _zoom_min_step
	_zoom_events += 1
	for i in _count:
		_dest_pos[i] = i * step
	_move_speed = _zoom_move_speed

func _add_effect(angle: float, step: float, flexy_speed: float) -> void:
	_effects.append(PackedFloat32Array([0.0, angle, step, flexy_speed]))

func _process(delta: float) -> void:
	if _count == 0 or not is_visible_in_tree(): return
	_accumulator += minf(delta, 0.25)
	while _accumulator >= FIXED_DT:
		_accumulator -= FIXED_DT
		_fixed_step()
	_apply(_accumulator / FIXED_DT)

func _fixed_step() -> void:
	for i in _count:
		_prev_rot[i] = _rot[i]
		_rot[i] = lerpf(_rot[i], _dest_rot[i], FIXED_DT * _rot_speed[i])
		_prev_pos[i] = _pos[i]
		_pos[i] = lerpf(_pos[i], _dest_pos[i], FIXED_DT * _move_speed)
	for e in range(_effects.size() - 1, -1, -1):
		var effect := _effects[e]
		var progress := int(effect[0])
		for i in range(progress, mini(progress + PROPAGATION_SPEED, _count)):
			_dest_rot[i] = effect[1] + i * effect[2]
			_rot_speed[i] = effect[3]
		effect[0] = progress + PROPAGATION_SPEED
		_effects[e] = effect
		if int(effect[0]) >= _count:
			_effects.remove_at(e)

func _apply(t: float) -> void:
	for i in _count:
		var angle := deg_to_rad(lerpf(_prev_rot[i], _rot[i], t))
		var z := -lerpf(_prev_pos[i], _pos[i], t)
		var xf := Transform3D(Basis(Vector3.FORWARD, angle), Vector3(0, 0, z))
		if multimesh.instance_count > 0:
			multimesh.set_instance_transform(i, xf)
		for layer in _layers:
			layer.set_instance_transform(i, xf)

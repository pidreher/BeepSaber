extends Node3D
## Two small instanced batches: head-centred dust and distant, floor-level haze.
## Particle movement stays in the shader; the CPU only follows the head and lights.

const DUST_SHADER := preload("res://game/environment/AtmosphereDust.gdshader")
const HAZE_SHADER := preload("res://game/environment/AtmosphereHaze.gdshader")
const DUST_COUNT := 288
const HAZE_PAIRS := 4
const BASE_TINT := Color(0.008, 0.010, 0.018)

var _dust: MultiMeshInstance3D
var _dust_material := ShaderMaterial.new()
var _haze_material := ShaderMaterial.new()
var _target_left := BASE_TINT
var _target_right := BASE_TINT
var _left := BASE_TINT
var _right := BASE_TINT


func _ready() -> void:
	name = &"Atmosphere"
	_dust_material.shader = DUST_SHADER
	_haze_material.shader = HAZE_SHADER
	var random := RandomNumberGenerator.new()
	random.seed = 731029
	_dust = _make_batch(DUST_COUNT, _dust_material)
	_dust.name = &"Dust"
	# A world-aligned box follows translation only, including a rotated XR origin.
	_dust.top_level = true
	_dust.global_transform = Transform3D.IDENTITY
	_dust.multimesh.custom_aabb = AABB(Vector3(-3.1, -3.1, -3.1), Vector3.ONE * 6.2)
	for i in DUST_COUNT:
		_dust.multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		_dust.multimesh.set_instance_custom_data(i, Color(random.randf(), random.randf(),
			random.randf(), random.randf()))
	var haze := _make_batch(HAZE_PAIRS * 2, _haze_material)
	haze.name = &"DistantHaze"
	haze.multimesh.custom_aabb = AABB(Vector3(-30, -3, -82), Vector3(60, 9, 56))
	for pair in HAZE_PAIRS:
		for side in 2:
			var distance_down_track := 34.0 + pair * 14.0
			var width := 14.0 + pair * 2.0
			var height := 3.0 + pair * 0.5
			var center := Vector3((8.5 + pair * 2.8) * (-1.0 if side == 0 else 1.0),
				1.0 + pair * 0.15, Constants.PLAYER_Z - distance_down_track)
			haze.multimesh.set_instance_transform(pair * 2 + side,
				Transform3D(Basis.from_scale(Vector3(width, height, 1)), center))
			haze.multimesh.set_instance_custom_data(pair * 2 + side,
				Color(random.randf(), float(side), random.randf(), 1.0))
	Settings.changed.connect(_on_settings_changed)
	_update_settings()


func _make_batch(count: int, material: ShaderMaterial) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = quad
	instances.instance_count = count
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = instances
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.layers = 3
	add_child(batch)
	return batch


## The driver's colours already include event brightness; do not multiply alpha again.
func set_light_colors(colors: Array[Color]) -> void:
	if colors.size() < 5:
		return
	_target_left = BASE_TINT + (colors[0] + colors[2] + colors[4] * 0.4) / 2.4
	_target_right = BASE_TINT + (colors[1] + colors[3] + colors[4] * 0.4) / 2.4
	# Keep unusually bright custom events from washing out the play area.
	_target_left = _target_left.clamp(Color.BLACK, Color.WHITE)
	_target_right = _target_right.clamp(Color.BLACK, Color.WHITE)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	# A spectator camera can be current while the headset remains the player's head.
	if is_instance_valid(vr.vrCamera) and vr.vrCamera.is_inside_tree():
		camera = vr.vrCamera
	if camera:
		_dust.global_position = camera.global_position
	var blend := clampf(delta * 5.0, 0.0, 1.0)
	_left = _left.lerp(_target_left, blend)
	_right = _right.lerp(_target_right, blend)
	for material: ShaderMaterial in [_dust_material, _haze_material]:
		material.set_shader_parameter(&"left_tint", _left)
		material.set_shader_parameter(&"right_tint", _right)


func _on_settings_changed(key: StringName) -> void:
	if key == &"mixed_reality" or key == &"background":
		_update_settings()


func _update_settings() -> void:
	visible = not Settings.mixed_reality and Settings.background != "simple"
	set_process(visible)
	var motion := 1.0 if Settings.background == "dynamic" else 0.0
	_dust_material.set_shader_parameter(&"motion", motion)
	_haze_material.set_shader_parameter(&"motion", motion)

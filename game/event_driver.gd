extends Node3D
class_name EventDriver

var left_color: Color
var right_color: Color

@onready var ring_holder := $Level/rings as Node3D
@onready var diagonal_lasers_holder := $Level/DiagonalLasers as Node3D
@onready var diagonal_lasers := [
	$Level/DiagonalLasers/laser1,
	$Level/DiagonalLasers/laser2,
	$Level/DiagonalLasers/laser3,
	$Level/DiagonalLasers/laser4,
	$Level/DiagonalLasers/laser5,
	$Level/DiagonalLasers/laser6,
	$Level/DiagonalLasers/laser7,
	$Level/DiagonalLasers/laser8,
	$Level/DiagonalLasers/laser9,
	$Level/DiagonalLasers/laser10
]
@onready var square_lasers_holder := $Level/SquareLasers as Node3D
@onready var left_waving_lasers_holder := $Level/LeftWavingLasers as Node3D
@onready var right_waving_lasers_holder := $Level/RightWavingLasers as Node3D
@onready var track_lights_holder := $Level/TrackLights as Node3D

@onready var sphere_material := ($Level/Sphere as MeshInstance3D).material_override as ShaderMaterial
@onready var diagonal_lasers_material := ($Level/DiagonalLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var square_lasers_material := ($Level/SquareLasers/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var left_waving_lasers_material := ($Level/LeftWavingLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var right_waving_lasers_material := ($Level/RightWavingLasers/laser1/Bar7 as MeshInstance3D).material_override as StandardMaterial3D
@onready var track_lights_material := ($Level/TrackLights/Bar1 as MeshInstance3D).material_override as StandardMaterial3D
@onready var floor_mesh := ($Level/floor as MeshInstance3D).mesh as PlaneMesh
@onready var floor_material := ($Level/floor as MeshInstance3D).material_override as StandardMaterial3D
@onready var track_lights_right := $Level/TrackLights/Bar1 as MeshInstance3D
@onready var track_lights_left := $Level/TrackLights/Bar2 as MeshInstance3D
@onready var end_path := $Level/Endpath as MeshInstance3D

@onready var left_laser_anim_player := $Level/LeftWavingLasers/AnimationPlayer as AnimationPlayer
@onready var right_laser_anim_player := $Level/RightWavingLasers/AnimationPlayer as AnimationPlayer

@export var disabled := false

# Haze: distance + ground fog whose color follows the current light colors,
# so flashes bleed into the atmosphere.
const FOG_BASE_COLOR := Color(0.008, 0.009, 0.022)
const FOG_LIGHT_INFLUENCE := 0.22
var _light_colors: Array[Color] = [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]
var _environment: Environment
@onready var _atmosphere := preload("res://game/environment/Atmosphere.gd").new()

# Rings come from the stage preset of the map's environment (StagePresets).
const RING_COLOR := Color(0.0941176, 0.0941176, 0.0941176)
var rings: Array[SpinningRings] = []
var preset: Dictionary = StagePresets.DEFAULT
var _ring_material := StandardMaterial3D.new()
# Light bars on rings belong to event type 1 (ring lights).
var _ring_light_material := StandardMaterial3D.new()
var _ring_glow_material := ShaderMaterial.new()

# Picks the stage layout for a map: rings and reflective floor areas.
func apply_environment(environment_name: String) -> void:
	var new_preset := StagePresets.for_environment(environment_name)
	if new_preset != preset or rings.is_empty():
		preset = new_preset
		_build_rings()
	for r in rings: r.reset_events()
	StagePresets.current = preset
	StagePresets.apply_mirrors(preset)
	if not _group_holders.is_empty():
		_set_light(EventInfo.TYPE_FLOOR_LIGHTS, _light_state[EventInfo.TYPE_FLOOR_LIGHTS])

func _build_rings() -> void:
	ring_holder.transform = Transform3D.IDENTITY
	for r in rings:
		r.queue_free()
	rings.clear()
	for config: Dictionary in preset.rings:
		var r := SpinningRings.new()
		r.layers = 3
		r.extra_cull_margin = REFLECTION_CULL_MARGIN
		r.setup_from(config, _ring_material, _ring_light_material, _ring_glow_material)
		r.position = Vector3(0, config.height, Constants.PLAYER_Z - float(config.distance))
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring_holder.add_child(r)
		rings.append(r)

func _ready() -> void:
	add_child(_atmosphere)
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = RING_COLOR
	_ring_light_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_light_material.albedo_color = Color.BLACK
	_ring_glow_material.shader = GLOW_SHADER
	_ring_glow_material.set_shader_parameter(&"width", GLOW_WIDTH)
	apply_environment("")
	_build_light_groups()
	# Draw order of the floor: reflections (-10), glass (-2), this lit stripe (-1).
	floor_material.render_priority = -1
	Settings.changed.connect(_on_settings_changed)
	track_lights_holder.hide()
	var world_env := get_tree().get_first_node_in_group(&"enviroment") as WorldEnvironment
	if world_env and world_env.environment:
		_environment = world_env.environment
		_environment.fog_enabled = true
		_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		_environment.fog_density = 0.043
		_environment.fog_light_color = FOG_BASE_COLOR
		_environment.fog_light_energy = 1.0
		_environment.fog_sun_scatter = 0.0
		_environment.fog_sky_affect = 0.0
		_environment.fog_height = 0.9
		_environment.fog_height_density = 0.32
	
	set_background_texture()
	
	# get_rendering_device() returns null in opengl, meaning this block is skipped in vulkan
	
	set_background()
	
	if not RenderingServer.get_rendering_device():
		sphere_material.set_shader_parameter("contrast", 1)
		for background_side in 5:
			var shader_param := StringName("bg_%s_intensity_mult" % background_side)
			sphere_material.set_shader_parameter(
				shader_param,
				(sphere_material.get_shader_parameter(shader_param) as float) * 2.2
			)

func set_background_texture() -> void:
	if not Settings.background_texture.begins_with("res:"):
		var img := Image.new()
		if OK == img.load(Constants.APPDATA_PATH + "Backgrounds/" + Settings.background_texture):
			img.flip_x()
			sphere_material.set_shader_parameter("bg_base", ImageTexture.create_from_image(img))
			return
		Settings.background_texture = Settings.default_values["background_texture"]
	var texture : Resource = null
	texture = load(Settings.background_texture)
	sphere_material.set_shader_parameter("bg_base", texture)	

func set_background() -> void:
	var width_scale := 2 * Settings.LANE_DISTANCE_X / 3.
	var track_lights_width := track_lights_right.get_aabb().size.x
	track_lights_right.global_transform.origin.x = track_lights_width / 2 + 2 * Settings.LANE_DISTANCE_X - .01
	track_lights_left.global_transform.origin.x = -track_lights_right.transform.origin.x
	end_path.scale.z = track_lights_right.global_transform.origin.x + track_lights_width / 2 - .01
	floor_mesh.size.y = 4 * Settings.LANE_DISTANCE_X
	($Level/floor/line1).global_transform.origin.x = Settings.LANE_DISTANCE_X
	($Level/floor/line2).global_transform.origin.x = -Settings.LANE_DISTANCE_X
	($Level/floor/line3).global_transform.origin.x = 2 * Settings.LANE_DISTANCE_X
	($Level/floor/line4).global_transform.origin.x = -2 * Settings.LANE_DISTANCE_X
	($Level/floor).scale.z = 1
	for laser in diagonal_lasers:
		laser.transform.origin.x = 4.5 * width_scale * sign(laser.transform.origin.x)
	
	if Settings.background == "simple":
		ring_holder.hide()
		diagonal_lasers_holder.hide()
		square_lasers_holder.hide()
		left_waving_lasers_holder.hide()
		right_waving_lasers_holder.hide()
		($Level/DiagonalLasers/laser1).hide()
		($Level/DiagonalLasers/laser2).hide()
		($Level/DiagonalLasers/laser3).hide()
		($Level/DiagonalLasers/laser4).hide()
		($Level/DiagonalLasers/laser5).hide()
		($Level/DiagonalLasers/laser6).hide()
		($Level/DiagonalLasers/laser7).hide()
		($Level/DiagonalLasers/laser8).hide()
		($Level/DiagonalLasers/laser9).hide()
		($Level/DiagonalLasers/laser10).hide()
		track_lights_holder.hide()
		set_all_off()
		turn_light_on(EventInfo.TYPE_FLOOR_LIGHTS, Color.WHITE)
		disabled = true
	else:
		ring_holder.show()
		diagonal_lasers_holder.show()
		square_lasers_holder.show()
		left_waving_lasers_holder.show()
		right_waving_lasers_holder.show()
		($Level/DiagonalLasers/laser1).show()
		($Level/DiagonalLasers/laser2).show()
		($Level/DiagonalLasers/laser3).show()
		($Level/DiagonalLasers/laser4).show()
		($Level/DiagonalLasers/laser5).show()
		($Level/DiagonalLasers/laser6).show()
		($Level/DiagonalLasers/laser7).show()
		($Level/DiagonalLasers/laser8).show()
		($Level/DiagonalLasers/laser9).show()
		($Level/DiagonalLasers/laser10).show()
		track_lights_holder.hide()
		if Settings.background == "dynamic":
			disabled = false
			set_all_on(Settings.color_left, Settings.color_right)
		else:
			disabled = true
			set_all_off()
			turn_light_on(EventInfo.TYPE_FLOOR_LIGHTS, Color.WHITE)

func _process(delta: float) -> void:
	_atmosphere.set_light_colors(_light_colors)
	if _environment:
		var lights := Color.BLACK
		for c in _light_colors:
			lights += c
		var target := FOG_BASE_COLOR + lights * (FOG_LIGHT_INFLUENCE / _light_colors.size())
		_environment.fog_light_color = _environment.fog_light_color.lerp(target, clampf(delta * 8.0, 0.0, 1.0))
		sphere_material.set_shader_parameter(&"haze_color", _environment.fog_light_color * 1.1)

func update_left_color(color: Color) -> void:
	left_color = color
	turn_light_on(EventInfo.TYPE_DIAGONAL_LASERS, color)
	turn_light_on(EventInfo.TYPE_LEFT_WAVING_LASERS, color)
	turn_light_on(EventInfo.TYPE_RIGHT_WAVING_LASERS, color)

func update_right_color(color: Color) -> void:
	right_color = color
	turn_light_on(EventInfo.TYPE_SQUARE_LASERS, color)
	turn_light_on(EventInfo.TYPE_FLOOR_LIGHTS, color)

func set_all_off() -> void:
	if disabled:
		for i in range(1,4):
			turn_light_off(i)
		ring_holder.visible = false
	else:
		for i in range(5):
			turn_light_off(i)

func set_all_on(left: Color, right: Color) -> void:
	if !disabled:
		update_left_color(left)
		update_right_color(right)
		ring_holder.visible = true

func process_event(data: EventInfo) -> void:
	if disabled: return
	if data.type in range(0,5):
		_process_light_event(data)
	else:
		match data.type:
			8:
				for r in rings: r.spin()
			9:
				for r in rings: r.zoom()
			12:
				var val := float(data.value) * 0.125
				left_laser_anim_player.speed_scale = val
				left_laser_anim_player.seek(randf_range(0.0, left_laser_anim_player.current_animation_length), true)
			13:
				var val := float(data.value) * 0.125
				right_laser_anim_player.speed_scale = val
				right_laser_anim_player.seek(randf_range(0.0, right_laser_anim_player.current_animation_length), true)

# --- Lights ---------------------------------------------------------------------
# Each light group (event types 0-4) has a color whose alpha is its brightness.
# "On" is NORMAL_BRIGHTNESS. Flashes start at HIGHLIGHT_BRIGHTNESS and settle to
# normal in FLASH_DURATION; fades start at the highlight and go dark in FADE_DURATION.
# An event followed by a "fade to" event blends into that event's color until it starts.
const NORMAL_BRIGHTNESS := 1.0
const HIGHLIGHT_BRIGHTNESS := 1.0 / 0.75
const FLASH_DURATION := 0.6
const FADE_DURATION := 1.5
const GLOW_WIDTH := 1.1
const REFLECTION_CULL_MARGIN := 40.0
const GLOW_SHADER := preload("res://game/environment/LightGlow.gdshader")
const REFLECTION_SHADER := preload("res://game/environment/Reflection.gdshader")

var _light_state: Array[Color] = [Color(0,0,0,0), Color(0,0,0,0), Color(0,0,0,0), Color(0,0,0,0), Color(0,0,0,0)]
var prev_tweeners: Array[Tween] = [null,null,null,null,null]
# Per light type: materials of the bars, their reflection passes and the glow materials.
var _group_holders: Array[Node3D] = []
var _group_materials: Array[Array] = []
var _group_reflections: Array[Array] = []
var _group_glows: Array[Array] = []

func _group_holder(type: int) -> Node3D:
	match type:
		EventInfo.TYPE_DIAGONAL_LASERS: return diagonal_lasers_holder
		EventInfo.TYPE_SQUARE_LASERS: return square_lasers_holder
		EventInfo.TYPE_LEFT_WAVING_LASERS: return left_waving_lasers_holder
		EventInfo.TYPE_RIGHT_WAVING_LASERS: return right_waving_lasers_holder
	return track_lights_holder

static func _glow_strip(length: float) -> ArrayMesh:
	var half := length * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, -half), Vector3(0, 0, -half), Vector3(0, 0, half), Vector3(0, 0, half)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _bars(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			out.append(child)
		_bars(child, out)

func _build_light_groups() -> void:
	for type in 5:
		var holder := _group_holder(type)
		_group_holders.append(holder)
		var materials: Array = []
		var reflections: Array = []
		var glows: Array = []
		if type == EventInfo.TYPE_FLOOR_LIGHTS:
			materials = [track_lights_material, floor_material]
		else:
			var glow := ShaderMaterial.new()
			glow.shader = GLOW_SHADER
			glow.set_shader_parameter(&"width", GLOW_WIDTH)
			var glow_reflection := glow.duplicate() as ShaderMaterial
			glow_reflection.set_shader_parameter(&"mirrored", true)
			glow_reflection.render_priority = -10
			glows = [glow, glow_reflection]
			if type == EventInfo.TYPE_SQUARE_LASERS:
				var ring_glow_reflection := _ring_glow_material.duplicate() as ShaderMaterial
				ring_glow_reflection.set_shader_parameter(&"mirrored", true)
				ring_glow_reflection.render_priority = -10
				glows.append_array([_ring_glow_material, ring_glow_reflection])
				materials.append(_ring_light_material)
				var ring_reflection := ShaderMaterial.new()
				ring_reflection.shader = REFLECTION_SHADER
				ring_reflection.render_priority = -10
				reflections.append(ring_reflection)
			var bars: Array[MeshInstance3D] = []
			_bars(holder, bars)
			for bar in bars:
				var material := bar.material_override as StandardMaterial3D
				if material and not material in materials:
					materials.append(material)
					var reflection := ShaderMaterial.new()
					reflection.shader = REFLECTION_SHADER
					reflection.render_priority = -10
					reflections.append(reflection)
				# Keep bars drawn while only their reflection below the floor is in view.
				bar.extra_cull_margin = REFLECTION_CULL_MARGIN
				var strip := MeshInstance3D.new()
				strip.mesh = _glow_strip((bar.mesh as BoxMesh).size.z)
				strip.material_override = glow
				strip.layers = bar.layers
				strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				strip.extra_cull_margin = REFLECTION_CULL_MARGIN
				bar.add_child(strip)
		_group_materials.append(materials)
		_group_reflections.append(reflections)
		_group_glows.append(glows)
	_update_reflection_passes()

func _update_reflection_passes() -> void:
	for type in 5:
		var materials: Array = _group_materials[type]
		var reflections: Array = _group_reflections[type]
		for i in reflections.size():
			(materials[i] as StandardMaterial3D).next_pass = reflections[i] if Settings.reflections else null
		var glows: Array = _group_glows[type]
		for i in range(0, glows.size(), 2):
			(glows[i] as ShaderMaterial).next_pass = glows[i + 1] if Settings.reflections else null

func _on_settings_changed(key: StringName) -> void:
	if key == &"reflections":
		_update_reflection_passes()
		StagePresets.apply_mirrors(preset)

# Sets a light group. color.a is the brightness.
func _set_light(type: int, color: Color) -> void:
	_light_state[type] = color
	var lit := Color(color.r * color.a, color.g * color.a, color.b * color.a)
	var on := maxf(lit.r, maxf(lit.g, lit.b)) > 0.002
	if type != EventInfo.TYPE_FLOOR_LIGHTS or on:
		_group_holders[type].visible = on
	elif type == EventInfo.TYPE_FLOOR_LIGHTS:
		_group_holders[type].visible = false
	for material: StandardMaterial3D in _group_materials[type]:
		material.albedo_color = lit
	# On a glass track the lit stripe is see-through so the reflections show.
	if type == EventInfo.TYPE_FLOOR_LIGHTS:
		floor_material.albedo_color.a = 0.45 if preset.get("glass_track", false) else 1.0
	for reflection: ShaderMaterial in _group_reflections[type]:
		reflection.set_shader_parameter(&"color", lit)
	for glow: ShaderMaterial in _group_glows[type]:
		glow.set_shader_parameter(&"color", Color(color.r, color.g, color.b))
		glow.set_shader_parameter(&"intensity", color.a)
	_light_colors[type] = lit
	sphere_material.set_shader_parameter("bg_%d_intensity" % type, lit.v)

func _tween_light(type: int, from: Color, to: Color, duration: float,
		trans: Tween.TransitionType, ease: Tween.EaseType) -> void:
	stop_prev_tween(type)
	_set_light(type, from)
	var tween := create_tween()
	@warning_ignore("return_value_discarded")
	tween.set_trans(trans).set_ease(ease)
	@warning_ignore("return_value_discarded")
	tween.tween_method(_set_light_from_tween.bind(type), from, to, maxf(duration, 0.001))
	prev_tweeners[type] = tween

func _set_light_from_tween(color: Color, type: int) -> void:
	_set_light(type, color)

func _event_color(data: EventInfo) -> Color:
	if data.custom_color.a > 0: # Chroma: replaces the left/right/white color of this event only
		return Color(data.custom_color.r, data.custom_color.g, data.custom_color.b)
	if data.value >= EventInfo.VALUE_LIGHTS_WHITE_ON: return Color.WHITE
	if data.value >= EventInfo.VALUE_LIGHTS_LEFT_ON: return left_color
	return right_color

static func _event_brightness(data: EventInfo) -> float:
	return data.float_value if data.float_value >= 0.0 else 1.0

static func _is_fade_to(value: int) -> bool:
	return value == EventInfo.VALUE_LIGHTS_FADE_TO_RIGHT or value == EventInfo.VALUE_LIGHTS_FADE_TO_LEFT \
		or value == EventInfo.VALUE_LIGHTS_FADE_TO_WHITE

func _process_light_event(data: EventInfo) -> void:
	var type := data.type
	var color := _event_color(data)
	var brightness := _event_brightness(data)
	sphere_material.set_shader_parameter("bg_%d_tint" % type, color)
	match data.value:
		EventInfo.VALUE_LIGHTS_OFF:
			stop_prev_tween(type)
			_set_light(type, Color(0, 0, 0, 0))
			_blend_into_next(data)
		EventInfo.VALUE_LIGHTS_RIGHT_ON, EventInfo.VALUE_LIGHTS_LEFT_ON, EventInfo.VALUE_LIGHTS_WHITE_ON, \
		EventInfo.VALUE_LIGHTS_FADE_TO_RIGHT, EventInfo.VALUE_LIGHTS_FADE_TO_LEFT, EventInfo.VALUE_LIGHTS_FADE_TO_WHITE:
			stop_prev_tween(type)
			_set_light(type, Color(color, NORMAL_BRIGHTNESS * brightness))
			_blend_into_next(data)
		EventInfo.VALUE_LIGHTS_RIGHT_FLASH, EventInfo.VALUE_LIGHTS_LEFT_FLASH, EventInfo.VALUE_LIGHTS_WHITE_FLASH:
			_tween_light(type, Color(color, HIGHLIGHT_BRIGHTNESS * brightness),
				Color(color, NORMAL_BRIGHTNESS * brightness), FLASH_DURATION, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		EventInfo.VALUE_LIGHTS_RIGHT_FADE, EventInfo.VALUE_LIGHTS_LEFT_FADE, EventInfo.VALUE_LIGHTS_WHITE_FADE:
			_tween_light(type, Color(color, HIGHLIGHT_BRIGHTNESS * brightness),
				Color(color, 0.0), FADE_DURATION, Tween.TRANS_EXPO, Tween.EASE_OUT)

# If the next event of this type is a "fade to" event, blend towards it until it starts.
func _blend_into_next(data: EventInfo) -> void:
	var next := data.next_same_type
	if next == null or not _is_fade_to(next.value) or Map.current_info == null: return
	var to := Color(_event_color(next), NORMAL_BRIGHTNESS * _event_brightness(next))
	var from := _light_state[data.type]
	if from.a <= 0.0: from = Color(to.r, to.g, to.b, 0.0)
	var seconds := (next.beat - data.beat) * 60.0 / maxf(Map.current_info.beats_per_minute, 1.0)
	_tween_light(data.type, from, to, seconds, Tween.TRANS_LINEAR, Tween.EASE_IN)

func stop_prev_tween(type: int) -> void:
	if prev_tweeners[type] != null:
		prev_tweeners[type].kill()
		prev_tweeners[type] = null

func turn_light_off(type: int) -> void:
	stop_prev_tween(type)
	_set_light(type, Color(0, 0, 0, 0))

func turn_light_on(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter("bg_%d_tint" % type, color)
	stop_prev_tween(type)
	_set_light(type, Color(color, NORMAL_BRIGHTNESS))

func flash_light_then_fade_off(type: int, color: Color) -> void:
	sphere_material.set_shader_parameter("bg_%d_tint" % type, color)
	_tween_light(type, Color(color, HIGHLIGHT_BRIGHTNESS), Color(color, 0.0), FADE_DURATION,
		Tween.TRANS_EXPO, Tween.EASE_OUT)

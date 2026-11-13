extends Node3D
## A single batched ribbon mesh supplies the distant crown, light fans and runway.
## The five beatmap light groups remain authoritative, including blackouts/Chroma.

const LIGHT_SHADER := preload("res://game/environment/StageLightshow.gdshader")
var _material := ShaderMaterial.new()
var _reflection := ShaderMaterial.new()
var _mesh := MeshInstance3D.new()
var _clock := 0.0
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _details := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	name = &"StageLightshow"
	_material.shader = LIGHT_SHADER
	_reflection.shader = LIGHT_SHADER
	_reflection.set_shader_parameter(&"mirrored", true)
	_reflection.render_priority = -10
	_mesh.layers = 3
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 40.0
	_mesh.material_override = _material
	add_child(_mesh)
	_rebuild()
	Settings.changed.connect(_on_settings_changed)
	_update_settings()


func _ribbon(a: Vector3, b: Vector3, width: float, group: int, style: float,
		seed := 0.0, energy := 1.0) -> void:
	var base := _vertices.size()
	for point: Vector3 in [a, a, b, b]: _vertices.append(point)
	for i in 4:
		_normals.append((b - a).normalized())
		_details.append(Vector2(width, style))
		_colors.append(Color(float(group) / 4.0, seed, energy, 1.0))
	_uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	_indices.append_array([base, base + 1, base + 2, base + 2, base + 1, base + 3])


func _rebuild() -> void:
	_vertices.clear()
	_normals.clear()
	_uvs.clear()
	_details.clear()
	_colors.clear()
	_indices.clear()
	# Elevated fans stay outside the note corridor, even at the ends of their sweep.
	for side in [-1.0, 1.0]:
		var group := 2 if side < 0.0 else 3
		for i in 6:
			var start := Vector3(side * (7.0 + i * 0.5), 0.2, -18.0 - i * 3.5)
			var end := Vector3(side * (4.5 + i * 4.3), 19.0 + i * 1.8, -55.0 - i * 3.5)
			_ribbon(start, end, 3.2, group, 0.0, float(i) / 6.0, 0.8)
		# Short runway markers and continuous rails frame the suspended track.
		var x: float = side * maxf(StagePresets.TRACK_HALF_WIDTH + 0.08, 2.0 * Settings.LANE_DISTANCE_X + 0.23)
		_ribbon(Vector3(x, 0.045, -6.65), Vector3(x, 0.045, -98), 0.24, 4, 1.0)
		for i in 16:
			var z := -8.0 - i * 5.0
			_ribbon(Vector3(x, 0.045, z), Vector3(x + side * 0.65, 0.045, z - 0.85),
				0.18, group, 2.0, 0.0, 0.65)
		# Freestanding light fins give the stage a readable silhouette in the periphery.
		for i in 8:
			var x_fin: float = side * (7.5 + i * 0.75)
			var z := -16.0 - i * 7.0
			_ribbon(Vector3(x_fin, -0.5, z), Vector3(x_fin + side * 1.3, 3.0 + i * 0.45, z),
				0.65, 0 if side < 0.0 else 1, 2.0, 0.0, 0.55)
	# Three broken concentric arcs form a distant crown around the vanishing point.
	# Their centres are empty so incoming arrows always have a quiet background.
	for ring in 3:
		var radius := 10.0 + ring * 3.0
		for segment in 72:
			if segment % 12 < 2: continue
			var angle := TAU * segment / 72.0 + ring * 0.12
			var end_angle := angle + TAU / 72.0 * 0.94
			var center := Vector3(0, 3.0, -48.0 - ring * 4.0)
			var a := center + Vector3(cos(angle), sin(angle), 0) * radius
			var b := center + Vector3(cos(end_angle), sin(end_angle), 0) * radius
			_ribbon(a, b, 1.0 if ring == 0 else 0.65, 0 if cos(angle) < 0 else 1,
				2.0, 0.0, 1.0 if ring == 0 else 0.65)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _details
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = mesh


func set_light_colors(colors: Array[Color]) -> void:
	for i in mini(colors.size(), 5):
		for mat: ShaderMaterial in [_material, _reflection]:
			mat.set_shader_parameter("light_%d" % i, colors[i])


func _process(delta: float) -> void:
	if Settings.background == "dynamic" and not Scoreboard.paused:
		_clock += delta
		for mat: ShaderMaterial in [_material, _reflection]:
			mat.set_shader_parameter(&"stage_time", _clock)


func _on_settings_changed(key: StringName) -> void:
	if key == &"width": _rebuild()
	if key in [&"mixed_reality", &"background", &"reflections", &"glare"]:
		_update_settings()


func _update_settings() -> void:
	visible = not Settings.mixed_reality and Settings.background != "simple"
	set_process(visible)
	_material.next_pass = _reflection if Settings.reflections else null
	for mat: ShaderMaterial in [_material, _reflection]:
		mat.set_shader_parameter(&"halo_strength", 1.0 if Settings.glare else 0.65)

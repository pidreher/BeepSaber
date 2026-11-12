extends Node3D
class_name SaberHilt

const SEGMENTS := 40
var _accent: StandardMaterial3D

func _ready() -> void:
	var metal := _body_material(Color("617080"), 0.85, 0.23, 0.035, 0.8)
	var grip := _body_material(Color("151c28"), 0.55, 0.38, 0.15, 0.18)
	_accent = _material(Color("5da7ff"), 0.2, 0.25, 1.5)
	# Rounded shoulders and small bevels, with smooth normals around the entire hilt.
	_add_profile([
		Vector2(-0.128, 0), Vector2(-0.128, 0.014), Vector2(-0.126, 0.019),
		Vector2(-0.122, 0.021), Vector2(-0.113, 0.021), Vector2(-0.109, 0.019),
		Vector2(-0.106, 0.017), Vector2(-0.007, 0.017), Vector2(-0.003, 0.019),
		Vector2(0.0, 0.022), Vector2(0.006, 0.023), Vector2(0.011, 0.022),
		Vector2(0.016, 0.019), Vector2(0.028, 0.019), Vector2(0.033, 0.022),
		Vector2(0.042, 0.0235), Vector2(0.047, 0.022), Vector2(0.050, 0.018),
		Vector2(0.050, 0.012), Vector2(0.047, 0.010), Vector2(0.045, 0)
	], metal)
	var grip_profile: Array[Vector2] = [Vector2(-0.108, 0.0172)]
	for i in 11:
		var y := -0.104 + i * 0.009
		grip_profile.append(Vector2(y, 0.018))
		grip_profile.append(Vector2(y + 0.0015, 0.0187))
		grip_profile.append(Vector2(y + 0.004, 0.0187))
		grip_profile.append(Vector2(y + 0.006, 0.018))
	grip_profile.append(Vector2(-0.006, 0.0172))
	_add_profile(grip_profile, grip)
	var rings := SurfaceTool.new()
	rings.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spec in [Vector3(-0.115, 0.0213, 0.0023), Vector3(0.005, 0.0233, 0.002), Vector3(0.038, 0.0236, 0.002)]:
		var y: float = spec.x
		var r: float = spec.y
		var h: float = spec.z
		var ring := _lathe([Vector2(y - h, r - 0.001), Vector2(y - h * 0.5, r), Vector2(y + h * 0.5, r), Vector2(y + h, r - 0.001)])
		rings.append_from(ring, 0, Transform3D.IDENTITY)
	_add_mesh(rings.commit(), _accent)

func set_color(color: Color) -> void:
	if _accent == null: return
	_accent.albedo_color = color.lightened(0.08)
	_accent.emission = color.lightened(0.08)

func _material(color: Color, metallic: float, roughness: float, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	return material

func _body_material(color: Color, metallic: float, roughness: float, visibility: float, reflection: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/sabers/default/HiltMetal.gdshader")
	material.set_shader_parameter(&"base_color", color)
	material.set_shader_parameter(&"metallic_value", metallic)
	material.set_shader_parameter(&"roughness_value", roughness)
	material.set_shader_parameter(&"dark_visibility", visibility)
	material.set_shader_parameter(&"reflection_strength", reflection)
	return material

func _add_profile(profile: Array[Vector2], material: Material) -> void:
	_add_mesh(_lathe(profile), material)

func _add_mesh(mesh: Mesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.layers = 3
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)

func _lathe(profile: Array[Vector2]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in profile.size():
		var tangent := profile[mini(j + 1, profile.size() - 1)] - profile[maxi(j - 1, 0)]
		for i in SEGMENTS + 1:
			var angle := TAU * i / SEGMENTS
			vertices.append(Vector3(cos(angle) * profile[j].y, profile[j].x, sin(angle) * profile[j].y))
			normals.append(Vector3(cos(angle) * tangent.x, -tangent.y, sin(angle) * tangent.x).normalized())
	for j in profile.size() - 1:
		for i in SEGMENTS:
			var a := j * (SEGMENTS + 1) + i
			var b := a + SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

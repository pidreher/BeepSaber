extends Node3D
class_name SaberTail

const MAX_AGE := 0.24
const MAX_SAMPLES := 32
const SUBDIVISIONS := 2

@export var size := 1.0

@onready var material := ($Mesh as MeshInstance3D).material_override as ShaderMaterial
@onready var imm_geo := ($Mesh as MeshInstance3D).mesh as ImmediateMesh

class HistoricalPositions:
	extends RefCounted

	var base_pos: Vector3
	var tip_pos: Vector3
	var age := 0.0

	func _init(base: Vector3, tip: Vector3) -> void:
		base_pos = base
		tip_pos = tip

var last_pos: Array[HistoricalPositions] = []

func _ready() -> void:
	# World-space vertices, but keep ownership and visibility with the saber.
	var ribbon := $Mesh as MeshInstance3D
	ribbon.set_as_top_level(true)
	ribbon.global_transform = Transform3D.IDENTITY

func set_color(color: Color) -> void:
	material.set_shader_parameter(&"color", color)

func _process(delta: float) -> void:
	imm_geo.clear_surfaces()
	if not is_visible_in_tree() or size <= 0.003:
		last_pos.clear()
		return

	for sample in last_pos:
		sample.age += delta
	while not last_pos.is_empty() and last_pos.back().age >= MAX_AGE:
		last_pos.pop_back()

	var current := HistoricalPositions.new(global_position, to_global(Vector3(0.0, size, 0.0)))
	# Tracking resets should never leave a ribbon spanning the room.
	if not last_pos.is_empty() and current.tip_pos.distance_to(last_pos[0].tip_pos) > 1.5:
		last_pos.clear()
	last_pos.push_front(current)
	if last_pos.size() > MAX_SAMPLES:
		last_pos.resize(MAX_SAMPLES)
	if last_pos.size() < 2:
		return

	var drawing := false
	for i in range(last_pos.size() - 1):
		var a := last_pos[i]
		var b := last_pos[i + 1]
		if a.base_pos.distance_squared_to(b.base_pos) + a.tip_pos.distance_squared_to(b.tip_pos) < 0.000001:
			continue
		if not drawing:
			imm_geo.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drawing = true
		var before := last_pos[maxi(i - 1, 0)]
		var after := last_pos[mini(i + 2, last_pos.size() - 1)]
		for step in SUBDIVISIONS:
			var t0 := float(step) / SUBDIVISIONS
			var t1 := float(step + 1) / SUBDIVISIONS
			var base_a := _curve(before.base_pos, a.base_pos, b.base_pos, after.base_pos, t0)
			var tip_a := _curve(before.tip_pos, a.tip_pos, b.tip_pos, after.tip_pos, t0)
			var base_b := _curve(before.base_pos, a.base_pos, b.base_pos, after.base_pos, t1)
			var tip_b := _curve(before.tip_pos, a.tip_pos, b.tip_pos, after.tip_pos, t1)
			var age_a := lerpf(a.age, b.age, t0) / MAX_AGE
			var age_b := lerpf(a.age, b.age, t1) / MAX_AGE
			_vertex(base_a, age_a, 0.0)
			_vertex(tip_a, age_a, 1.0)
			_vertex(tip_b, age_b, 1.0)
			_vertex(base_a, age_a, 0.0)
			_vertex(tip_b, age_b, 1.0)
			_vertex(base_b, age_b, 0.0)
	if drawing:
		imm_geo.surface_end()

func _vertex(point: Vector3, age: float, along: float) -> void:
	imm_geo.surface_set_uv(Vector2(age, along))
	imm_geo.surface_add_vertex(point)

func _curve(before: Vector3, a: Vector3, b: Vector3, after: Vector3, t: float) -> Vector3:
	# Catmull-Rom interpolation softens the turn between frame samples.
	return a.cubic_interpolate(b, before, after, t)

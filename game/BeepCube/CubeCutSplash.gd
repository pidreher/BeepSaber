extends Node3D
class_name CubeCutSplash

# A fixed pool outside the recycled cubes, so hiding/reusing a cube does not
# freeze or move its splash. CPU particles work on Pico's Compatibility renderer.
# Each splash has two layers: a bright flash at the cut and a spray of spark
# streaks thrown along the swing.
const POOL_SIZE := 16
const SPARKS_PER_CUT := 40
const SPARK_LIFETIME := 0.45
const FLASH_LIFETIME := 0.16
const LIFETIME := SPARK_LIFETIME
var _sparks: Array[CPUParticles3D] = []
var _flashes: Array[CPUParticles3D] = []
var _remaining: Array[float] = []
var _next := 0

static func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	curve.max_value = 2.0
	for p: Vector2 in points:
		curve.add_point(p)
	return curve

static func _flash_material(ring_width: float, intensity: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/BeepCube/CubeCutFlash.gdshader")
	material.set_shader_parameter(&"ring_width", ring_width)
	material.set_shader_parameter(&"intensity", intensity)
	return material

static func _single(lifetime: float, mesh: Mesh, scale_curve: Curve) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 1
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.0
	particles.initial_velocity_max = 0.0
	particles.scale_amount_curve = scale_curve
	particles.mesh = mesh
	particles.color_ramp = Gradient.new()
	return particles

func _ready() -> void:
	var spark_material := ShaderMaterial.new()
	spark_material.shader = preload("res://game/BeepCube/CubeCutSplash.gdshader")
	# Long thin streaks; align_y points them along their flight.
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.012, 0.085, 0.012)
	spark_mesh.material = spark_material
	var spark_shrink := _curve([Vector2(0.0, 1.0), Vector2(0.35, 0.85), Vector2(1.0, 0.0)])

	var flash_mesh := QuadMesh.new()
	flash_mesh.size = Vector2(0.55, 0.55)
	flash_mesh.material = _flash_material(0.0, 2.2)
	var flash_scale := _curve([Vector2(0.0, 0.6), Vector2(0.25, 1.25), Vector2(1.0, 1.6)])

	for i in POOL_SIZE:
		var sparks := CPUParticles3D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.amount = SPARKS_PER_CUT
		sparks.lifetime = SPARK_LIFETIME
		sparks.explosiveness = 1.0
		sparks.randomness = 0.3
		sparks.local_coords = false
		sparks.spread = 70.0
		sparks.gravity = Vector3(0, -4.0, 0)
		sparks.damping_min = 2.0
		sparks.damping_max = 4.0
		sparks.particle_flag_align_y = true
		sparks.scale_amount_min = 0.6
		sparks.scale_amount_max = 1.5
		sparks.scale_amount_curve = spark_shrink
		sparks.mesh = spark_mesh
		sparks.color_ramp = Gradient.new()
		add_child(sparks)
		_sparks.append(sparks)

		var flash := _single(FLASH_LIFETIME, flash_mesh, flash_scale)
		add_child(flash)
		_flashes.append(flash)

		_remaining.append(0.0)

static func _fire(particles: CPUParticles3D, point: Vector3, start: Color, end: Color) -> void:
	particles.global_position = point
	particles.color_ramp.set_color(0, start)
	particles.color_ramp.set_color(1, end)
	particles.speed_scale = 1.0
	particles.visible = true
	particles.restart()
	particles.emitting = true

func splash(point: Vector3, velocity: Vector3, color: Color) -> void:
	var index := _next
	_next = (_next + 1) % POOL_SIZE
	var strength := clampf((velocity.length() - 1.5) / 7.5, 0.0, 1.0)

	var sparks := _sparks[index]
	sparks.direction = velocity.normalized() if velocity.length_squared() > 0.01 else Vector3.DOWN
	sparks.initial_velocity_min = lerpf(1.6, 3.0, strength)
	sparks.initial_velocity_max = lerpf(3.4, 6.5, strength)
	var bright := color.lerp(Color.WHITE, 0.3)
	bright.a = 1.0
	var faded := color
	faded.a = 0.0
	_fire(sparks, point, bright, faded)

	var core := color.lerp(Color.WHITE, 0.6)
	core.a = 1.0
	var core_end := color
	core_end.a = 0.0
	_fire(_flashes[index], point, core, core_end)

	_remaining[index] = LIFETIME

func _process(delta: float) -> void:
	var scale := 0.0 if Scoreboard.paused else 1.0
	for i in _sparks.size():
		_sparks[i].speed_scale = scale
		_flashes[i].speed_scale = scale
		if not Scoreboard.paused and _remaining[i] > 0.0:
			_remaining[i] = maxf(0.0, _remaining[i] - delta)
			if _remaining[i] <= 0.0:
				_sparks[i].visible = false
				_flashes[i].visible = false

func clear() -> void:
	for i in _sparks.size():
		_remaining[i] = 0.0
		for particles: CPUParticles3D in [_sparks[i], _flashes[i]]:
			particles.emitting = false
			particles.visible = false

extends Node3D
class_name CubeCutSplash

# A fixed pool outside the recycled cubes, so hiding/reusing a cube does not
# freeze or move its splash. CPU particles work on Pico's Compatibility renderer.
const POOL_SIZE := 20
const PARTICLES_PER_CUT := 20
const LIFETIME := 0.32
var _emitters: Array[CPUParticles3D] = []
var _remaining: Array[float] = []
var _next := 0

func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/BeepCube/CubeCutSplash.gdshader")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, 0.045)
	mesh.material = material
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.3, 0.8))
	shrink.add_point(Vector2(1.0, 0.0))
	for i in POOL_SIZE:
		var particles := CPUParticles3D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.amount = PARTICLES_PER_CUT
		particles.lifetime = LIFETIME
		particles.explosiveness = 1.0
		particles.randomness = 0.25
		particles.local_coords = false
		particles.spread = 65.0
		particles.gravity = Vector3(0, -2.5, 0)
		particles.scale_amount_min = 0.4
		particles.scale_amount_max = 1.15
		particles.scale_amount_curve = shrink
		particles.angle_min = -180
		particles.angle_max = 180
		particles.mesh = mesh
		particles.color_ramp = Gradient.new()
		add_child(particles)
		_emitters.append(particles)
		_remaining.append(0.0)

func splash(point: Vector3, velocity: Vector3, color: Color) -> void:
	var index := _next
	_next = (_next + 1) % POOL_SIZE
	var particles := _emitters[index]
	particles.global_position = point
	particles.direction = velocity.normalized() if velocity.length_squared() > 0.01 else Vector3.DOWN
	var strength := clampf((velocity.length() - 1.5) / 7.5, 0.0, 1.0)
	particles.initial_velocity_min = lerpf(0.8, 1.6, strength)
	particles.initial_velocity_max = lerpf(1.8, 3.6, strength)
	var bright := color.lightened(0.35)
	bright.a = 1.0
	var faded := color
	faded.a = 0.0
	particles.color_ramp.set_color(0, bright)
	particles.color_ramp.set_color(1, faded)
	particles.speed_scale = 1.0
	particles.restart()
	particles.emitting = true
	_remaining[index] = LIFETIME

func _process(delta: float) -> void:
	for i in _emitters.size():
		_emitters[i].speed_scale = 0.0 if Scoreboard.paused else 1.0
		if not Scoreboard.paused:
			_remaining[i] = maxf(0.0, _remaining[i] - delta)
			if _remaining[i] <= 0.0:
				_emitters[i].visible = false
			else:
				_emitters[i].visible = true

func clear() -> void:
	for i in _emitters.size():
		_remaining[i] = 0.0
		_emitters[i].emitting = false
		_emitters[i].visible = false

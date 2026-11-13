extends Node
## --headless --xr-mode off res://tests/cut_validation.tscn
## Use a temporary XDG_DATA_HOME to isolate saved game data.

var _game: BeepSaber_Game
var _saber: LightSaber
var _awards: Array[String] = []

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func() -> void: get_tree().quit(2))
	_run.call_deferred()

func _run() -> void:
	_game = preload("res://game/BeepSaber_Game.tscn").instantiate() as BeepSaber_Game
	get_tree().root.add_child(_game)
	for i in 8: await get_tree().process_frame
	var song := _game.menu.get_songs()[0]
	_game.start_map(song, song.difficulty_beatmaps[0])
	_game.song_player.stop()
	_game.set_physics_process(false)
	_game._clear_track()
	_saber = _game.left_saber
	for saber: LightSaber in [_game.left_saber, _game.right_saber]:
		saber.set_physics_process(false)
		saber._swing_cast.set_physics_process(false)
	Settings.cube_cuts_falloff = false
	Settings.arrows_enabled = true
	Settings.handedness = 0
	Settings.explain = true
	Map.one_saber = false
	Scoreboard.paused = false
	Scoreboard.points_awarded.connect(func(_p: Vector3, _r: float, amount: String) -> void: _awards.append(amount))
	assert(_test_angles())
	assert(_test_speed_filter())
	assert(_test_hitbox_policy())
	assert(await _test_physics_rays())
	assert(_test_other_targets())
	print("CUT VALIDATION PASSED")
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit()

func _reset_score() -> void:
	_saber.score_queue.clear()
	_game.current_health = Constants.HEALTH_START
	Scoreboard.restart()
	_awards.clear()

func _spawn(roll := 0.0, yaw := 0.0, dot := false, color := 0) -> BeepCube:
	var cube := GlobalReferences.cube_pool.acquire() as BeepCube
	cube.spawn(ColorNoteInfo.new(0, 1, 1, color, Constants.DIRECTION8_OFFSET if dot else 0.0, 0), 0)
	cube.set_physics_process(false)
	cube.is_dot = dot
	cube._lane_basis = Basis(Vector3.UP, deg_to_rad(yaw))
	cube.global_transform = Transform3D(cube._lane_basis * Basis(Vector3.BACK, deg_to_rad(roll)), Vector3(0, 1.4, 0))
	cube.set_collision_disabled(false)
	return cube

func _velocity(cube: BeepCube, deviation: float, speed := 5.0) -> Vector3:
	return -cube.global_basis.y.rotated(cube._lane_basis.z, deg_to_rad(deviation)) * speed

func _flush_score() -> void:
	while not _saber.score_queue.is_empty():
		_saber._update_score(_saber.score_queue.pop_front())

func _test_angles() -> bool:
	# Exercise actual cube cuts and both score paths, including all arrow rotations
	# and rotated lanes. Boundary cuts may earn zero legacy angle points, but count.
	for swing_scoring in [false, true]:
		Settings.swing_scoring = swing_scoring
		for roll in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
			for deviation in [0.0, 50.0, 59.9, 60.0, 60.1, 90.0, 180.0]:
				_reset_score()
				var cube := _spawn(roll, 35.0)
				var velocity := _velocity(cube, deviation)
				var good: bool = deviation <= 60.0
				assert(cube.is_bad_cut(0, velocity) == not good, "Detector disagrees at %s / %s" % [roll, deviation])
				cube.cut(_saber, velocity, Plane(Vector3.RIGHT, 0), _game.left_controller)
				_flush_score()
				assert(Scoreboard.full_combo == good, "Scoring disagrees at %s / %s" % [roll, deviation])
				assert(_awards.size() == 1)
				assert(Scoreboard.combo == (1 if good else 0))
	print("PASS: both scoring modes accept 0-60 degrees, reject beyond, for eight arrows and rotated lanes")
	# Dot notes and no-arrow mode ignore direction, but still require speed/color.
	for dot in [false, true]:
		var cube := _spawn(0, 0, dot)
		Settings.arrows_enabled = dot
		assert(not cube.is_bad_cut(0, Vector3.UP * 5.0))
		assert(cube.is_bad_cut(1, Vector3.DOWN * 5.0))
		assert(cube.is_bad_cut(0, Vector3.DOWN * 2.0))
		assert(cube.is_bad_cut(0, Vector3.ZERO))
		cube.clear_from_track()
	Settings.arrows_enabled = true
	print("PASS: dot/no-arrow direction exceptions preserve wrong-color and low-speed failures")
	return true

func _test_speed_filter() -> bool:
	for hz in [72.0, 90.0, 120.0]:
		_saber._reset_cut_motion()
		var dt: float = 1.0 / hz
		for i in int(hz * 0.2): _saber._update_blade_speed(6.0, dt)
		assert(_saber._blade_speed > 5.8)
		_saber._update_blade_speed(0.5, dt)
		var cube := _spawn()
		assert(not cube.is_bad_cut(0, Vector3.DOWN * 0.5, _saber._blade_speed))
		# Filtering the magnitude must never turn an opposite swing into a good cut.
		assert(cube.is_bad_cut(0, Vector3.UP * 0.5, _saber._blade_speed))
		for i in int(hz): _saber._update_blade_speed(0.0, dt)
		assert(cube.is_bad_cut(0, Vector3.DOWN * 0.5, _saber._blade_speed))
		cube.clear_from_track()
		_saber.set_swingcast_enabled(false)
		assert(_saber._blade_speed == 0 and not _saber._has_motion_sample)
		_saber.set_swingcast_enabled(true)
		assert(_saber._blade_speed == 0 and not _saber._has_motion_sample)
	print("PASS: speed filtering handles brief dips, settles at rest, preserves direction and resets across pause")
	return true

func _has_both_note_layers(area: Area3D) -> bool:
	return area.get_collision_layer_value(CollisionLayerConstants.LeftNote_bit) and area.get_collision_layer_value(CollisionLayerConstants.RightNote_bit)

func _test_hitbox_policy() -> bool:
	for ignore_color in [false, true]:
		Map.one_saber = ignore_color
		var cube := _spawn()
		var outer := cube.collision_big.get_parent() as Area3D
		var inner := cube.collision_small.get_parent() as Area3D
		assert(_has_both_note_layers(inner))
		assert(cube.accepts_cut_from(outer, 0, Vector3.DOWN * 5, 5))
		assert(not cube.accepts_cut_from(outer, 0, Vector3.UP * 5, 5))
		assert(not cube.accepts_cut_from(outer, 0, Vector3.DOWN, 1))
		assert(cube.accepts_cut_from(inner, 0, Vector3.UP * 5, 5))
		assert(cube.accepts_cut_from(outer, 1, Vector3.DOWN * 5, 5) == ignore_color)
		if ignore_color: assert(_has_both_note_layers(outer))
		cube.clear_from_track()
	Map.one_saber = false
	Settings.handedness = Constants.HANDEDNESS_IGNORE
	var cube := _spawn()
	assert(_has_both_note_layers(cube.collision_big.get_parent() as Area3D))
	cube.clear_from_track()
	Settings.handedness = 0
	print("PASS: outer hitboxes forgive invalid swings; inner hitboxes see both sabers; one-saber modifiers retain reach")
	return true

func _prime_saber(velocity: Vector3, speed: float) -> void:
	_saber._cut_velocity = velocity
	_saber._blade_speed = speed
	_saber.last_dt = 1.0 / 72.0
	_saber.saber_end = Vector3(0, 1.4, 0)
	_saber.saber_end_past = _saber.saber_end - velocity * _saber.last_dt

func _test_physics_rays() -> bool:
	Settings.swing_scoring = false
	var ray := RayCast3D.new()
	ray.enabled = false
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	ray.collision_mask = 0
	ray.set_collision_mask_value(CollisionLayerConstants.LeftNote_bit, true)
	ray.target_position = Vector3(4, 0, 0)
	add_child(ray)
	# A wrong-direction outer-edge graze produces no cut, feedback or points.
	_reset_score()
	var cube := _spawn()
	_prime_saber(Vector3.UP * 5, 5)
	ray.position = Vector3(-2, 1.62, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var splash_index := _game.cut_splashes._next
	assert(not _saber._swing_cast._check_ray(ray))
	assert(cube.mi.visible and _awards.is_empty() and Scoreboard.full_combo)
	assert(_game.cut_splashes._next == splash_index)
	ray.force_raycast_update()
	assert(ray.get_collider() == cube.collision_big.get_parent(), "Ignored collider exception leaked across queries")
	# The same query through the centre must skip the ignored outer hitbox, hit
	# the inner one, and issue exactly one bad cut despite duplicate callbacks.
	ray.position.y = 1.4
	assert(_saber._swing_cast._check_ray(ray))
	assert(not Scoreboard.full_combo and _awards.size() == 1)
	assert(_game.cut_splashes._next != splash_index)
	_saber._handle_area_collided(cube.collision_small.get_parent() as Area3D)
	assert(_awards.size() == 1)
	# A valid outer hit remains generous and is scored once by the full callback.
	_reset_score()
	cube = _spawn()
	_prime_saber(_velocity(cube, 50.0), 5)
	ray.position.y = 1.62
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(_saber._swing_cast._check_ray(ray))
	assert(Scoreboard.full_combo and Scoreboard.combo == 1 and _awards.size() == 1)
	_saber._handle_area_collided(cube.collision_big.get_parent() as Area3D)
	assert(_awards.size() == 1)
	# Verify that filtered speed actually reaches the scoring callback, while
	# pauses suppress it and a genuinely slow swing still fails on the core.
	_reset_score()
	cube = _spawn()
	_prime_saber(Vector3.DOWN * 0.5, 5.0)
	var outer := cube.collision_big.get_parent() as Area3D
	Scoreboard.paused = true
	_saber._handle_area_collided(outer)
	assert(cube.mi.visible and _awards.is_empty())
	Scoreboard.paused = false
	_saber._handle_area_collided(outer)
	assert(Scoreboard.full_combo and _awards.size() == 1)
	_reset_score()
	cube = _spawn()
	_prime_saber(Vector3.DOWN * 5.0, 1.0)
	_saber._handle_area_collided(cube.collision_big.get_parent() as Area3D)
	assert(cube.mi.visible and _awards.is_empty())
	_saber._handle_area_collided(cube.collision_small.get_parent() as Area3D)
	assert(not Scoreboard.full_combo and _awards.size() == 1)
	# An opposite-color note is still detected as a core bad cut.
	_reset_score()
	cube = _spawn(0, 0, false, 1)
	_prime_saber(Vector3.DOWN * 5, 5)
	ray.position.y = 1.4
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(_saber._swing_cast._check_ray(ray))
	assert(not Scoreboard.full_combo and _awards.size() == 1 and _awards[0] == "wrong saber")
	ray.queue_free()
	print("PASS: real physics rays ignore grazes, reach inner errors, retain generous good cuts and prevent duplicates")
	return true

func _test_other_targets() -> bool:
	# Chain links keep their color-only rule, and bombs still trigger at rest.
	_reset_score()
	var link := GlobalReferences.link_pool.acquire() as ChainLink
	link.spawn(ChainInfo.new(0, 0, 1, 1, 0, 0.1, 1, 0, 2, 1, 0), 0,
		Vector2.ZERO, Vector2.DOWN, Vector2.DOWN * 0.5, 1)
	link.set_physics_process(false)
	_prime_saber(Vector3.ZERO, 0)
	_saber._handle_area_collided(link.get_node("Area3D") as Area3D)
	assert(Scoreboard.full_combo and Scoreboard.combo == 1 and _awards.size() == 1)
	_saber._handle_area_collided(link.get_node("Area3D") as Area3D)
	assert(_awards.size() == 1)
	_reset_score()
	var bomb := preload("res://game/Bomb/Bomb.tscn").instantiate() as Bomb
	_game.track.add_child(bomb)
	bomb.spawn(BombInfo.new(0, 1, 1, 0), 0)
	bomb.set_physics_process(false)
	_saber._handle_area_collided(bomb.get_node("Area3D") as Area3D)
	assert(_awards.size() == 1 and _awards[0] == "bomb")
	_saber._handle_area_collided(bomb.get_node("Area3D") as Area3D)
	assert(_awards.size() == 1)
	print("PASS: chain and bomb callbacks keep their rules and suppress duplicate contacts")
	return true

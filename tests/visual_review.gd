extends Node
## Run with --xr-mode off --rendering-method gl_compatibility (or mobile).
## Screenshots and a small integration check of the stage's user-facing controls.

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func() -> void: get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	Settings.background = "dynamic"
	Settings.mixed_reality = false
	Settings.reflections = true
	Settings.glare = true
	var game := preload("res://game/BeepSaber_Game.tscn").instantiate() as BeepSaber_Game
	get_tree().root.add_child(game)
	await get_tree().create_timer(2.0).timeout
	game.set_physics_process(false)
	for canvas in game.find_children("*", "OQ_UI2DCanvas", true, false):
		(canvas as Node3D).hide()
	game.left_saber._hide()
	game.right_saber._hide()
	game.left_controller.hide()
	game.right_controller.hide()
	# Hide the desktop simulator's instruction overlay in review images.
	for label in get_tree().root.find_children("*", "Label", true, false):
		if "VR Simulator" in (label as Label).text:
			label.get_parent().get_parent().set_process(false)
			label.get_parent().get_parent().set_physics_process(false)
			(label as Label).get_parent().hide()
	var camera := Camera3D.new()
	camera.cull_mask = 1
	camera.fov = 78
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.75, 1), Vector3(0, 1.7, -30))
	camera.make_current()
	var driver := game.event_driver
	driver.set_all_on(Color("ff245b"), Color("278bff"))
	await get_tree().create_timer(0.5).timeout
	await _capture("stage")
	# Render the game's actual note mesh/material at several approach distances.
	var note_scene := preload("res://game/BeepCube/BeepCube.tscn").instantiate()
	var note_source := note_scene.get_node("BeepCubeMesh") as MeshInstance3D
	var notes := Node3D.new()
	add_child(notes)
	for i in 6:
		var note := MeshInstance3D.new()
		note.mesh = note_source.mesh
		note.layers = 3
		var mat := note_source.material_override.duplicate() as ShaderMaterial
		mat.set_shader_parameter(&"color", Color("ff245b") if i % 2 == 0 else Color("278bff"))
		note.material_override = mat
		note.position = Vector3(-0.6 if i % 2 == 0 else 0.6, 1.0 + (i % 3) * 0.35, -1.5 - i * 2.5)
		note.rotation.z = float(i % 3 - 1) * PI * 0.25
		notes.add_child(note)
	note_scene.free()
	Settings.glare = false
	await _capture("gameplay-no-glow")
	notes.queue_free()
	Settings.glare = true
	var show: Node3D = driver.get_node("StageLightshow")
	assert(show.visible)
	# Blackout must reach all five shader uniforms (including the crown/fans).
	driver.set_all_off()
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 5:
		var tint: Color = show._material.get_shader_parameter("light_%d" % i)
		assert(tint.r == 0 and tint.g == 0 and tint.b == 0)
	await _capture("blackout")
	driver.set_all_on(Color("ffaa35"), Color("37efb3"))
	await get_tree().create_timer(0.3).timeout
	await _capture("custom-colors")
	Settings.reflections = false
	assert(show._material.next_pass == null)
	Settings.reflections = true
	assert(show._material.next_pass != null)
	Settings.background = "static"
	var clock_value: float = show._clock
	await get_tree().create_timer(0.1).timeout
	assert(is_equal_approx(show._clock, clock_value))
	Settings.background = "simple"
	assert(not show.visible)
	Settings.background = "dynamic"
	Settings.mixed_reality = true
	assert(not show.visible)
	Settings.mixed_reality = false
	assert(show.visible)
	Scoreboard.paused = true
	clock_value = show._clock
	await get_tree().create_timer(0.1).timeout
	assert(is_equal_approx(show._clock, clock_value))
	Scoreboard.paused = false
	# Geometry rebuilds must stay bounded when users adjust lane width.
	var vertex_count: int = show._vertices.size()
	Settings.width = 150
	Settings.width = 100
	assert(show._vertices.size() == vertex_count)
	for environment_name in ["TriangleEnvironment", "KDAEnvironment", "DefaultEnvironment"]:
		driver.apply_environment(environment_name)
		game.standing_ground.update_stage()
		await get_tree().create_timer(0.2).timeout
		await _capture(environment_name)
	print("VISUAL REVIEW PASSED: blackouts, custom colors, reflection toggle, static/simple/MR, pause, width and stage changes")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _capture(file_name: String) -> void:
	for i in 4: await RenderingServer.frame_post_draw
	var output := "res://build/visual-review/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output + "/" + file_name + ".png")

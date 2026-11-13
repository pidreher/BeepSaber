extends Node
# Run with --headless --xr-mode off res://tests/pcvr_validation.tscn.
# Set XDG_DATA_HOME to a temporary directory to isolate saved game data.

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		push_error("PCVR validation timed out")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	assert(_validate_bindings())
	assert(_validate_controller_input())
	print("Renderer configuration: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		" effective=", ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"),
		" running=", RenderingServer.get_current_rendering_method())
	var game := (load("res://game/BeepSaber_Game.tscn") as PackedScene).instantiate() as BeepSaber_Game
	get_tree().root.add_child(game)
	for i in 8:
		await get_tree().process_frame
	assert(not vr.inVR and not get_viewport().use_xr)
	assert(game.gamestate == game.gamestate_mapselection)
	game._on_xr_focus_lost()
	assert(game.gamestate == game.gamestate_mapselection)
	var songs := game.menu.get_songs()
	assert(not songs.is_empty(), "The desktop export needs its bundled demo map")
	var song := songs[0]
	assert(not song.difficulty_beatmaps.is_empty())
	game.start_map(song, song.difficulty_beatmaps[0])
	await get_tree().create_timer(0.15).timeout
	assert(game.gamestate == game.gamestate_playing and game.song_player.playing)
	game._on_xr_focus_lost()
	assert(game.gamestate == game.gamestate_paused and Scoreboard.paused)
	assert(not game.song_player.playing and game.pause_menu.visible)
	var stopped_at := game.pause_position
	game._on_xr_focus_lost()
	assert(is_equal_approx(stopped_at, game.pause_position))
	print("PASS: focus loss pauses the song once and preserves its position")
	vr.inVR = true
	assert(not game._xr_has_focus())
	game._unpause_button()
	assert(not game.pause_countdown.visible and game.pause_menu.visible)
	vr.inVR = false
	print("PASS: resume is blocked while the XR session has no focus")

	game._unpause_button()
	assert(game.pause_countdown.visible)
	var generation := game._resume_countdown_generation
	game._unpause_button()
	assert(game._resume_countdown_generation == generation)
	game._on_xr_focus_lost()
	assert(not game.pause_countdown.visible and game.pause_menu.visible)
	await get_tree().create_timer(1.7).timeout
	assert(game.gamestate == game.gamestate_paused and not game.song_player.playing)
	print("PASS: dashboard interruption cancels resume; duplicate resumes are ignored")

	game._unpause_button()
	await get_tree().create_timer(1.7).timeout
	assert(game.gamestate == game.gamestate_playing and game.song_player.playing)
	assert(not game.pause_countdown.visible and not Scoreboard.paused)
	assert(game.song_player.get_playback_position() >= stopped_at)
	print("PASS: explicit resume finishes its countdown and continues the song")

	game._on_xr_focus_lost()
	game._unpause_button()
	game._main_menu_button()
	await get_tree().create_timer(1.7).timeout
	assert(game.gamestate == game.gamestate_mapselection)
	assert(not game.song_player.playing and not game.pause_countdown.visible)
	print("PASS: leaving pause cancels the countdown without restarting a song")
	game.queue_free()
	await get_tree().process_frame
	print("PCVR VALIDATION PASSED")
	get_tree().quit()

func _validate_bindings() -> bool:
	var action_map := preload("res://openxr_action_map.tres")
	for path: String in ["/interaction_profiles/valve/index_controller", "/interaction_profiles/htc/vive_controller", "/interaction_profiles/oculus/touch_controller"]:
		var profile := action_map.find_interaction_profile(path)
		assert(profile != null)
		var pose_hands := {}
		var trigger_hands := {}
		var haptic_hands := {}
		var pause_hands := {}
		for binding: OpenXRIPBinding in profile.get_bindings():
			var action: String = binding.action.resource_name
			var hand := "left" if "/left/" in binding.binding_path else "right"
			match action:
				"aim_pose", "grip_pose": pose_hands[hand] = true
				"trigger_click": trigger_hands[hand] = true
				"haptic": haptic_hands[hand] = true
				"menu_button", "by_button":
					if binding.binding_path.ends_with("/system/click"):
						assert(not path.ends_with("/index_controller"))
						continue
					pause_hands[hand] = true
		assert(pose_hands.size() == 2 and trigger_hands.size() == 2 and haptic_hands.size() == 2)
		assert(not pause_hands.is_empty())
	print("PASS: Index, Vive and Touch have poses, triggers, haptics and accessible pause")
	return true

func _validate_controller_input() -> bool:
	var tracker := XRControllerTracker.new()
	tracker.name = &"pcvr_validation"
	tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tracker)
	var controller := BeepSaberController.new()
	controller.tracker = tracker.name
	add_child(controller)
	tracker.set_input(&"trigger", 0.0)
	tracker.set_input(&"trigger_click", false)
	tracker.set_input(&"select_button", false)
	controller._update_buttons_and_sticks()
	assert(not controller.trigger_pressed())
	tracker.set_input(&"trigger", 0.75)
	controller._update_buttons_and_sticks()
	assert(controller.trigger_just_pressed())
	controller._update_buttons_and_sticks()
	assert(controller.trigger_pressed() and not controller.trigger_just_pressed())
	tracker.set_input(&"trigger", 0.0)
	controller._update_buttons_and_sticks()
	assert(controller.trigger_just_released())
	tracker.set_input(&"trigger_click", true)
	controller._update_buttons_and_sticks()
	assert(controller.trigger_just_pressed())
	tracker.set_input(&"trigger_click", false)
	tracker.set_input(&"select_button", true)
	controller._update_buttons_and_sticks()
	assert(controller.trigger_pressed())
	controller.free()
	XRServer.remove_tracker(tracker)
	print("PASS: analog trigger, digital click, select fallback and press/release edges")
	return true

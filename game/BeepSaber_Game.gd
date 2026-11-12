# This is a stand-alone version of the demo game Beep Saber. It started (and is still included)
# in the godot oculus quest toolkit (https://github.com/NeoSpark314/godot_oculus_quest_toolkit)
# But this stand-alone version as additional features and will be developed independently
# This file contains the main game logic for the BeepSaber demo implementation
extends Node3D
class_name BeepSaber_Game

var version : String = ProjectSettings.get_setting("application/config/version", "0.0.0")
var gamestate_bootup := GameState.new()
var gamestate_mapcomplete := GameStateMapComplete.new()
var gamestate_mapselection := GameStateMapSelection.new()
var gamestate_newhighscore := GameStateNewHighScore.new()
var gamestate_paused := GameStatePaused.new()
var gamestate_playing := GameStatePlaying.new()
var gamestate_settings := GameStateSettings.new()
var gamestate: GameState = gamestate_bootup
var current_health := Constants.HEALTH_START
var effects_audio: SaberEffectsAudio
var cut_splashes: CubeCutSplash

@onready var xr_origin := $XROrigin3D as XROrigin3D
@onready var left_controller := $XROrigin3D/LeftController as BeepSaberController
@onready var right_controller := $XROrigin3D/RightController as BeepSaberController
@onready var left_saber := $XROrigin3D/LeftController/LeftLightSaber as LightSaber
@onready var right_saber := $XROrigin3D/RightController/RightLightSaber as LightSaber
@onready var left_ui_raycast := $XROrigin3D/LeftController/LeftLightSaber/UIRaycast as UIRaycast
@onready var right_ui_raycast := $XROrigin3D/RightController/RightLightSaber/UIRaycast as UIRaycast
@onready var goggles_shader := ($XROrigin3D/XRCamera3D/VRGoggles as MeshInstance3D).material_override as ShaderMaterial
@onready var debug_info_label := $XROrigin3D/XRCamera3D/PlayerHead/DebugInfoLabel as MeshInstance3D

@onready var main_menu := $MainMenu_OQ_UI2DCanvas as OQ_UI2DCanvas
@onready var pause_menu := $PauseMenu_canvas as OQ_UI2DCanvas
@onready var pause_countdown := $Pause_countdown as OQ_UI2DLabel
@onready var settings_canvas := $Settings_canvas as OQ_UI2DCanvas
@onready var settings_panel := settings_canvas.ui_control as SettingsPanel
@onready var highscore_canvas := $Highscores_Canvas as OQ_UI2DCanvas
@onready var highscore_panel := highscore_canvas.ui_control as HighscorePanel
@onready var name_selector_canvas := $NameSelector_Canvas as OQ_UI2DCanvas
@onready var highscore_keyboard := $Keyboard_highscore as OQ_UI2DKeyboard
@onready var endscore := $EndScore as EndScore

@onready var points_label_driver := $Points_label_driver as PointsLabelDriver
@onready var event_driver := $event_driver as EventDriver

@onready var multiplier_label := $Multiplier_Label as MeshInstance3D
@onready var point_label := $Point_Label as MeshInstance3D
@onready var percent_indicator := $Percent_Indicator as PercentIndicator

@onready var library_canvas := $Library_Canvas as OQ_UI2DCanvas
@onready var library := library_canvas.ui_control as LibraryPanel
# other online map sources (Beat Sage / YouTube), opened from the library
@onready var map_source_dialogs := $MapSourceDialogs as Node3D
@onready var online_search_keyboard := $Keyboard_online_search as OQ_UI2DKeyboard

@onready var cube_template := preload("res://game/BeepCube/BeepCube.tscn").instantiate() as BeepCube

@onready var track := $Track as Node3D
@onready var standing_ground := $StandingGround as Floor

@onready var song_player := $SongPlayer as AudioStreamPlayer

@onready var menu := main_menu.ui_control as MainMenu


# There's an interesting issue where the AudioStreamPlayer's playback_position
# doesn't immediately return to 0.0 after restarting the song_player. This
# causes issues with restarting a map because the process_physics routine will
# execute for a times and attempt to process the map up to the playback_position
# prior to the AudioStreamPlayer restart. This bug can presents itself as notes
# persisting between map restarts.
# To remidy this issue, this flag is set to true when the map is restarted. The
# process_physics routine won't begin processing the map until after the
# AudioStreamPlayer has reset it's playback_position to zero. This flag is set
# to false once the AudioStreamPlayer reset is detected.
var _audio_synced_after_restart := false

var _in_wall := false

#prevents the song for starting from the start when pausing and unpausing
var pause_position := 0.0

func start_map(info: MapInfo, map_difficulty: DifficultyInfo) -> void:
	var map_data := Utils.binary_to_json(Utils.read_binary_file(info.filepath, map_difficulty.beatmap_filename))
	
	if (map_data.is_empty()):
		vr.log_error("Could not read map data from " + info.filepath + "/" + map_difficulty.beatmap_filename)
	if not Map.load_beatmap(info, map_difficulty, map_data):
		return
		
	event_driver.set_background_texture()
	
	update_left_color(Map.color_left)
	update_right_color(Map.color_right)
	event_driver.set_background()
	
	if Map.event_stack.is_empty():
		event_driver.set_all_on(Map.color_left, Map.color_right)
	else:
		event_driver.set_all_off()
	
	var filename := info.filepath + info.song_filename
	vr.log_info("loading: " + filename)
	if FileAccess.file_exists(filename):
		song_player.stream = AudioStreamOggVorbis.load_from_file(filename)
	else:
		var audio_data : PackedByteArray
		audio_data = Utils.read_binary_file(info.filepath, info.song_filename)
		if len(audio_data) > 0:
			song_player.stream = AudioStreamOggVorbis.load_from_buffer(audio_data)
		else:
			vr.log_info("playing silence")
			var wav := AudioStreamWAV.new()
			wav.set_stereo(false)
			wav.set_format(AudioStreamWAV.FORMAT_8_BITS)
			wav.set_mix_rate(11025)
			var length := ceili((Map.current_info.get_length_seconds() + 2) * wav.mix_rate)
			var data := PackedByteArray()
			data.resize(length) 
			data.fill(0)
			wav.set_data(data)
			song_player.stream = wav
	
	_reset_fail_effect()
	_audio_synced_after_restart = false
	song_player.play(0.0)
	song_player.volume_db = 0.0
	song_player.pitch_scale = Settings.music_speed / 100.
	_in_wall = false
	Scoreboard.restart()
	
	_display_points()
	percent_indicator.start_map()
	percent_indicator.set_health_mode(Settings.health_mode)
	if Settings.health_mode:
		current_health = Constants.HEALTH_START
		percent_indicator.update_percent(current_health / Constants.HEALTH_MAX)
	
	_clear_track()
	_transition_game_state(gamestate_playing)

func update_health(delta: float) -> void:
	if Settings.health_mode and not _failing:
		current_health += delta
		if current_health > Constants.HEALTH_MAX:
			current_health = Constants.HEALTH_MAX
		percent_indicator.update_percent(current_health / Constants.HEALTH_MAX)
		if current_health < 0:
			_fail_song()

# Failing a song: instead of cutting straight to the score screen, the music
# "tape-stops" while the whole game slows down, the lights flash red and die
# and a power-down sound plays.
const FAIL_DURATION := 1.6
var _failing := false
var _fail_player: AudioStreamPlayer

func _fail_song() -> void:
	if _failing: return
	_failing = true
	if _fail_player == null:
		_fail_player = AudioStreamPlayer.new()
		_fail_player.stream = preload("res://game/data/sfx/fail.wav")
		_fail_player.bus = &"SFX"
		add_child(_fail_player)
	_fail_player.play()
	for controller: BeepSaberController in [left_controller, right_controller]:
		controller.simple_rumble(1.0, 0.6)
	for light_type in 5:
		event_driver.flash_light_then_fade_off(light_type, Color(1.0, 0.08, 0.05))
	var tween := create_tween().set_ignore_time_scale(true).set_parallel()
	tween.tween_property(song_player, ^"pitch_scale", song_player.pitch_scale * 0.15, FAIL_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(song_player, ^"volume_db", -40.0, FAIL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(Engine, ^"time_scale", 0.15, FAIL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	_reset_fail_effect()
	if gamestate == gamestate_playing:
		_on_song_ended()

func _reset_fail_effect() -> void:
	_failing = false
	Engine.time_scale = 1.0
	song_player.pitch_scale = Settings.music_speed / 100.
			
# This function will transitioning the game from it's current state into
# the provided 'next_state'.
func _transition_game_state(next_state: GameState) -> void:
	effects_audio.stop_all()
	if next_state != gamestate_playing and next_state != gamestate_paused:
		cut_splashes.clear()
	gamestate = next_state
	gamestate._ready(self)

# shows / hides the song library (left of the player); hiding also closes the
# dialogs of the other map sources that can be opened from the library
func show_library(showing: bool = true) -> void:
	if showing:
		library_canvas._show()
	else:
		library_canvas._hide()
	map_source_dialogs.visible = showing
	if not showing:
		for c in map_source_dialogs.get_children():
			if c is OQ_UI2DCanvas:
				(c as OQ_UI2DCanvas)._hide()

# old name, still used by some game states
func show_MapSourceDialogs(showing: bool = true) -> void:
	show_library(showing)

# call this method to submit a new highscore to the database
func _submit_highscore(player_name: String) -> void:
	player_name = player_name.strip_edges()
	if gamestate != gamestate_newhighscore or player_name.is_empty():
		return
	Highscores.rename_record(Map.current_info, Map.current_difficulty.difficulty_rank, _new_record_epoch, player_name)
	highscore_panel.load_highscores(Map.current_info, Map.current_difficulty.difficulty_rank)
	endscore.show_saved_name(player_name)
	name_selector_canvas._hide()
	highscore_keyboard._hide()

# Sabers are Area3Ds without a collision layer, so the physics engine never
# reports them touching each other; check the distance between the blades.
const SABER_CLASH_DISTANCE := 0.05
var _saber_clash_active := false
var _clash_last_relative := Vector3.ZERO
var _clash_motion_ready := false

func _update_saber_clash() -> void:
	var touching := false
	var point := Vector3.ZERO
	var impact_strength := 0.4
	if left_saber.is_extended() and right_saber.is_extended():
		var l := _saber_blade(left_saber)
		var r := _saber_blade(right_saber)
		var closest := Geometry3D.get_closest_points_between_segments(l[0], l[1], r[0], r[1])
		touching = closest[0].distance_to(closest[1]) < SABER_CLASH_DISTANCE
		point = (closest[0] + closest[1]) * 0.5
		var relative := l[1] - r[1]
		if _clash_motion_ready:
			var speed := relative.distance_to(_clash_last_relative) / maxf(get_physics_process_delta_time(), 0.001)
			impact_strength = clampf(speed / 8.0, 0.4, 1.0)
		_clash_last_relative = relative
		_clash_motion_ready = true
	else:
		_clash_motion_ready = false
	effects_audio.set_clash(touching and gamestate != gamestate_paused and not _failing, point, impact_strength)
	if touching:
		# strong hit when the blades meet, then a lighter buzz while they stay in contact
		var first_contact := not _saber_clash_active
		for controller: BeepSaberController in [left_controller, right_controller]:
			if first_contact:
				controller.simple_rumble(1.0, 0.12)
			elif not controller.is_simple_rumbling():
				controller.simple_rumble(0.45, 0.06)
	_saber_clash_active = touching

func _saber_blade(saber: LightSaber) -> PackedVector3Array:
	var base := saber.collision_shape.global_transform * Vector3(0, -saber.collision_cylinder.height * 0.5, 0)
	return PackedVector3Array([base, saber.saber_visual.tip.global_transform.origin])

func _check_and_update_saber(controller: BeepSaberController, saber: LightSaber) -> void:
	# to allow extending/sheething the saber while not playing a song
	if ((not song_player.playing)
		and (controller.ax_just_pressed() or controller.by_just_pressed())
		and (not saber._anim.is_playing())):
		if (saber.is_extended()): saber._hide()
		else: saber._show()
		
	if _in_wall:
		Scoreboard.enter_wall()
	
	# check for saber rumble (only when extended and not already rumbling)
	# this check is necessary to not overwrite a rumble set from somewhere else
	# (in this case it can come from cutting cubes)
	if not controller.is_simple_rumbling(): 
		if _in_wall:
			# weak rumble on both controllers when player is inside wall
			controller.simple_rumble(0.3, 0.3)
		elif saber.get_overlapping_areas().size() > 0 or saber.get_overlapping_bodies().size() > 0:
			# strong rumble when saber is cutting into wall or other saber
			controller.simple_rumble(0.5, 0.1)


func _physics_process(_dt: float) -> void:
	Scoreboard.score_changed.emit()
	
	if debug_info_label.visible:
		var dbg_text := "FPS: %d\nCube Pool: %d free of %d\nLink Pool: %d free of %d" % [
			Engine.get_frames_per_second(),
			GlobalReferences.cube_pool.free_count(), GlobalReferences.cube_pool.total_count(),
			GlobalReferences.link_pool.free_count(), GlobalReferences.link_pool.total_count()]
		(debug_info_label.mesh as TextMesh).text = dbg_text
	
	gamestate._physics_process(self)
	
	_update_saber_clash()
	_check_and_update_saber(left_controller, left_saber)
	_check_and_update_saber(right_controller, right_saber)

func _enter_tree() -> void:
	GlobalReferences.main_game_scene = self
	
	@warning_ignore("return_value_discarded")
	Settings.changed.connect(on_settings_changed)

func _ready() -> void:
	effects_audio = SaberEffectsAudio.new()
	add_child(effects_audio)
	cut_splashes = CubeCutSplash.new()
	add_child(cut_splashes)
	# pre-allocate scenes in our scene pools
	GlobalReferences.cube_pool = $BeepCubePool
	GlobalReferences.link_pool = $ChainLinkPool
	GlobalReferences.cube_pool.presize(100)
	GlobalReferences.link_pool.presize(100)
	
	var xr_camera := $XROrigin3D/XRCamera3D as XRCamera3D
	vr.initialize(
		xr_origin,
		xr_camera,
		left_controller,
		right_controller
	)
	
	vr.pose_recentered.connect(recenter)

	debug_info_label.visible = Settings.show_debug_info
	set_colors_from_settings()
	($WorldEnvironment as WorldEnvironment).environment.glow_enabled = Settings.glare
	
	if not vr.inVR:
		xr_origin.add_child(preload("res://OQ_Toolkit/OQ_ARVROrigin/Feature_VRSimulator.tscn").instantiate())
	
	UI_AudioEngine.attach_children(highscore_keyboard)
	highscore_keyboard.text_input_cancel.connect(func() -> void:
		name_selector_canvas._hide()
		highscore_keyboard._hide())
	endscore.change_name.connect(_change_highscore_name)
	UI_AudioEngine.attach_children(online_search_keyboard)
	for canvas in map_source_dialogs.get_children():
		canvas.visibility_changed.connect(_on_map_source_visibility_changed)
	
	_transition_game_state(gamestate_mapselection)
	
	@warning_ignore("return_value_discarded")
	Scoreboard.score_changed.connect(_display_points)
	@warning_ignore("return_value_discarded")
	Scoreboard.points_awarded.connect(points_label_driver.show_points)
	
	#render common assets for a couple of frames to prevent performance issues when loading them mid game
	($pre_renderer as Node3D).visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	($pre_renderer as Node3D).queue_free()
	
	set_background_texture()
	
	recenter()

func set_background_texture() -> void:
	var environment : Environment = $WorldEnvironment.environment
	var panorama : PanoramaSkyMaterial = environment.sky.sky_material 
	panorama.panorama = load(Settings.background_texture)	
	
func on_settings_changed(key: StringName) -> void:
	# ensures proper initialization of tree for proper first frame setting loading
	await get_tree().process_frame
	match key:
		&"left_handed":
			if Settings.left_handed:
				left_ui_raycast.active = true
				right_ui_raycast.active = false
			else:
				left_ui_raycast.active = false
				right_ui_raycast.active = true
		&"color_left":
			update_left_color(Settings.color_left)
		&"color_right":
			update_right_color(Settings.color_right)
		&"width":
			event_driver.set_background()
		&"background":
			event_driver.set_background()
		&"background_texture":
			set_background_texture()
			event_driver.set_background_texture()
		&"show_debug_info":
			debug_info_label.visible = Settings.show_debug_info
		&"glare":
			($WorldEnvironment as WorldEnvironment).environment.glow_enabled = Settings.glare
		&"player_height_offset":
			xr_origin.transform.origin.y = Settings.player_height_offset

func set_colors_from_settings() -> void:
	update_left_color(Settings.color_left)
	update_right_color(Settings.color_right)
	event_driver.set_background()

func update_left_color(color: Color) -> void:
	if !left_saber:
		await get_tree().process_frame
	left_saber.set_color(color)
	Arc.left_material.set_shader_parameter(&"color", color)
	Arc.left_material_magnet.set_shader_parameter(&"color", color)
	goggles_shader.set_shader_parameter(&"left_color", color)
	event_driver.update_left_color(color)
	standing_ground.update_left_color(color)

func update_right_color(color: Color) -> void:
	if !left_saber:
		await get_tree().process_frame
	right_saber.set_color(color)
	Arc.right_material.set_shader_parameter(&"color", color)
	Arc.right_material_magnet.set_shader_parameter(&"color", color)
	goggles_shader.set_shader_parameter(&"right_color", color)
	event_driver.update_right_color(color)
	standing_ground.update_right_color(color)

func _clear_track() -> void:
	cut_splashes.clear()
	for c in track.get_children():
		if c.has_method("clear_from_track"):
			c.clear_from_track()
		else:
			track.remove_child(c)
			c.queue_free()

func _display_points() -> void:
	var hit_rate: float
	if Scoreboard.right_notes+Scoreboard.wrong_notes > 0:
		hit_rate = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes)
	else:
		hit_rate = 1.0
	
	var minutes = 0
	var seconds = 0
	if Map.current_info != null:
		var time_left = Map.current_info.get_length_seconds() - get_current_time()
		if time_left < 0:
			time_left = 0
		minutes = int(time_left) / 60
		seconds = int(time_left) % 60
	var display = "Score %6d\n%02d:%02d" % [Scoreboard.points,minutes,seconds]
	if (point_label.mesh as TextMesh).text != display:
		(point_label.mesh as TextMesh).text = display
	display = "x %d\nCombo %d" % [Scoreboard.multiplier, Scoreboard.combo]
	if (multiplier_label.mesh as TextMesh).text != display:
		(multiplier_label.mesh as TextMesh).text = display
	if not Settings.health_mode:
		percent_indicator.update_percent(hit_rate)

# accessor method for the player name selector UI element
func _name_selector() -> NameSelector:
	return name_selector_canvas.ui_control

func _on_PlayerHead_area_entered(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = -15.0
		_in_wall = true
		Scoreboard.enter_wall()

func _on_PlayerHead_area_exited(area: Area3D) -> void:
	if area.is_in_group(&"wall"):
		song_player.volume_db = 0.0
		_in_wall = false
		Scoreboard.exit_wall()
		
func get_current_time() -> float:
	return song_player.get_playback_position()

# when the song ended we want to display the current score and
# the high score
func _on_song_ended() -> void:
	song_player.stop()
	PlayCount.increment_play_count(Map.current_info,Map.current_difficulty.difficulty_rank)
	
	var new_record := false
	var highscore := Highscores.get_highscore(Map.current_info,Map.current_difficulty.difficulty_rank)
	if highscore == -1:
		# no highscores exist yet
		highscore = Scoreboard.points
	elif Scoreboard.points > highscore:
		# player's score is the new highscore!
		highscore = Scoreboard.points
		new_record = true

	var current_percent : float
	if Settings.health_mode and current_health <= 0:
		current_percent = -1
	else:
		current_percent = Scoreboard.right_notes/(Scoreboard.right_notes+Scoreboard.wrong_notes) 
	endscore.show_score(
		Scoreboard.points,
		highscore,
		current_percent,
		"%s By %s\n%s     Map author: %s" % [
			Map.current_info.song_name,
			Map.current_info.song_author_name,
			Map.current_difficulty.get_display_name(),
			Map.current_info.level_author_name],
		Scoreboard.full_combo,
		new_record
	)
	
	# a new highscore is saved right away under the most recent player name;
	# the score screen offers to change the name (failed runs are not saved)
	var rank := Map.current_difficulty.difficulty_rank
	if current_percent >= 0 and Highscores.is_new_highscore(Map.current_info, rank, Scoreboard.points):
		var player_name := Highscores.get_last_player_name()
		if player_name.is_empty():
			player_name = "Player"
		var record := Highscores.add_highscore(Map.current_info, rank, player_name, Scoreboard.points)
		_new_record_epoch = float(record.epoch_time)
		endscore.show_saved_name(player_name)
		_transition_game_state(gamestate_newhighscore)
	else:
		endscore.show_saved_name("")
		_transition_game_state(gamestate_mapcomplete)

var _new_record_epoch := 0.0

# "Change name" on the score screen: show the recent names and the keyboard
func _change_highscore_name() -> void:
	if gamestate != gamestate_newhighscore:
		return
	name_selector_canvas._show()
	highscore_keyboard._show()

func _restart_button() -> void:
	start_map(Map.current_info, Map.current_difficulty)
	endscore.visible = false
	pause_menu.visible = false

func _main_menu_button() -> void:
	_clear_track()
	_transition_game_state(gamestate_mapselection)

func _unpause_button() -> void:
	pause_menu.visible = false
	pause_countdown.visible = true
	track.visible = true
	pause_countdown.set_label_text("3")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("2")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.set_label_text("1")
	await get_tree().create_timer(0.5).timeout
	pause_countdown.visible = false
	
	# continue game play
	song_player.play(pause_position)
	_transition_game_state(gamestate_playing)

func _on_BeepSaberMainMenu_difficulty_changed(map_info: MapInfo, diff_rank: int) -> void:
	if diff_rank < 0:
		if highscore_canvas:
			highscore_canvas.hide()
		return
		
	# menu loads playlist in _ready(), must yield until scene is loaded
	if not highscore_canvas:
		await self.ready
	
	# Downloads can finish and rescan songs during a run. Only the menu owns
	# this panel; the optional map-source dialog uses the same space.
	if gamestate != gamestate_mapselection or _map_source_visible():
		return
	highscore_canvas._show()
	highscore_panel.load_highscores(map_info,diff_rank)

func _map_source_visible() -> bool:
	for canvas in map_source_dialogs.get_children():
		if canvas.is_visible_in_tree(): return true
	return false

func _on_map_source_visibility_changed() -> void:
	if _map_source_visible():
		highscore_canvas._hide()
	elif gamestate == gamestate_mapselection:
		menu.update_view()

func _settings_button() -> void:
	settings_panel._update_backgrounds()
	_transition_game_state(gamestate_settings)

func _on_settings_Panel_apply() -> void:
	set_colors_from_settings()
	_transition_game_state(gamestate_mapselection)

func _on_ScenePool_new_scene_instanced(obj: Node3D, during_presizing: bool) -> void:
	# add obj to the track. it will reside inside the track for eternity, only
	# to be reposition and made visible again when it is acquired and spawned.
	track.add_child(obj)
	
	# make obj visible and wait for a frame to be processed. this tricks
	# shaders to be loaded at startup time.
	if during_presizing:
		obj.position.z = -2.0
		await get_tree().process_frame
		
		if obj is BeepCube:
			obj.hide_cube()
		elif obj is ChainLink:
			obj.hide_cube()
		else:
			obj.visible = false

func recenter():
	var xr_camera := $XROrigin3D/XRCamera3D as XRCamera3D
	xr_origin.rotation.y -= xr_camera.global_rotation.y
	xr_origin.position -= (xr_camera.global_position * Vector3(1,0,1)) - Vector3(0,0,1)

func _set_hand(right: bool, hand: bool) -> void:
	var angle_offset := -45. if hand else 0.
	if right:
		right_saber.second_extra_offset_rot.x=angle_offset
		right_saber._update_size_and_angle()
	else:
		left_saber.second_extra_offset_rot.x=angle_offset
		left_saber._update_size_and_angle()

func _on_right_controller_profile_changed(role: String) -> void:
	if role.ends_with("/simple_controller"):
		_set_hand(true, true)
	else:
		_set_hand(true, false)

func _on_left_controller_profile_changed(role: String) -> void:
	if role.ends_with("/simple_controller"):
		_set_hand(false, true)
	else:
		_set_hand(false, false)

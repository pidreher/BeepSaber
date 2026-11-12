# The "Now Playing" panel in front of the player: the currently loaded track,
# its difficulty and the modifiers, plus Play / Settings / Exit.
# Songs are browsed, searched, downloaded and chosen in the library panel
# (game/ui/Library) which calls load_song() to make a song the current track.
#
# This node also owns the local song database (discovery of the songs folder,
# sorting, favorites, deleting, cover cache) and the song preview player, which
# the library, the BeatSaver browser and the song uploader use.
#
# This file also contains the logic to load a beatmap in the format that
# normal Beat Saber uses. So you can load here custom beat saber songs too
extends Panel
class_name MainMenu

# emitted when a new map difficulty is selected
signal difficulty_changed(map_info: MapInfo, diff_rank: int)
# emitted when the settings button is pressed
signal settings_requested()
signal start_map(info: MapInfo, difficulty: DifficultyInfo)
# emitted whenever the song list changes: songs added / removed / reloaded, or
# the order changed (favorites are sorted first)
signal song_list_changed()
# emitted when another song became the current track (null: none)
signal current_song_changed(map: MapInfo)
# emitted when a cover finished loading (see request_cover())
signal cover_loaded(map_path: String, texture: Texture2D)

const FAVORITE_MASK := 0x4000000000000000
const FAVORITE_COLOR := SongDetails.FAVORITE_COLOR
const SUPPORTED_MAP_MODS := SongDetails.SUPPORTED_MAP_MODS

@export var main_song_player_ref: AudioStreamPlayer
@export var beepsaber_game : BeepSaber_Game
@export var song_uploader_ref: SongUploader

@onready var _bg_img_loader := preload("res://game/scripts/BackgroundImgLoader.gd").new()

@onready var song_card := %SongCard as SongDetails
@onready var characteristic_row := %CharacteristicRow as HFlowContainer
@onready var difficulty_row := %DifficultyRow as HFlowContainer
@onready var play_button := %Play_Button as Button
@onready var health_control := %Health as CheckButton
@onready var bombs_control := %Bombs as CheckButton
@onready var arrows_control := %Arrows as CheckButton
@onready var flip_control := %Flip as OptionButton
@onready var handedness_control := %Handedness as OptionButton
@onready var claws_control := %Claws as CheckButton
@onready var size_control := %Size as OptionButton
@onready var width_control := %Width as OptionButton
@onready var speed_control := %Speed as OptionButton
@onready var reset_button := %Reset_Button as Button

@onready var song_preview := $song_prev as AudioStreamPlayer
var song_preview_transition_time := 1.0
var licenses_showing := false

enum PlaylistOptions {
	AllSongs,
	RecentlyAdded,
	MostPlayed
}

# several different lists of maps, for the sort options of the library
var _all_songs: Array[MapInfo] # favorites first
var _recently_added_songs: Array[MapInfo] # newest is first, oldest is last
var _most_played_songs: Array[MapInfo] # most played is first, least played is last

# keep a record of all song hashes so we can check if the song is already in our local database
var all_song_hashes: Array[String]

# the track shown in this panel and started by Play
var current_map: MapInfo = null
var _map_difficulty := 0 # index into current_map.difficulty_beatmaps
var _characteristic_group := ButtonGroup.new()
var _difficulty_group := ButtonGroup.new()

# covers of local songs: map filepath -> Texture2D (null while loading)
var _covers := {}
const MAX_COVER_CACHE := 600

# what the preview player is playing (a map path or a BeatSaver hash)
var _preview_key := ""

# stop the preview player if the main song player is going
func _physics_process(_delta: float) -> void:
	if main_song_player_ref.playing:
		song_preview.stop()

# --- song database --------------------------------------------------------------

class MapInfoWithSort:
	var num: int
	var info: MapInfo

	func _init(n: int, i: MapInfo) -> void:
		num = n
		info = i

static func compare(a: MapInfoWithSort, b: MapInfoWithSort) -> bool:
	return a.num > b.num

# the local songs in the given PlaylistOptions order
func get_songs(order: int = PlaylistOptions.AllSongs) -> Array[MapInfo]:
	match order:
		PlaylistOptions.RecentlyAdded: return _recently_added_songs
		PlaylistOptions.MostPlayed: return _most_played_songs
	return _all_songs

func find_song_by_path(path: String) -> MapInfo:
	for song in _all_songs:
		if song.filepath == path: return song
	return null

# songs downloaded from BeatSaver are stored in a folder named by their hash
func find_song_by_hash(hash: String) -> MapInfo:
	var h := hash.to_lower()
	for song in _all_songs:
		var folder := song.filepath.trim_suffix("/").get_file().to_lower()
		if folder == h or folder == h + ".zip": return song
	return null

static func song_added_time(map: MapInfo) -> int:
	return FileAccess.get_modified_time(map.filepath)

func _sort_songs() -> void:
	var songs_with_modify_times: Array[MapInfoWithSort] = []
	var songs_with_play_count: Array[MapInfoWithSort] = []
	var songs_favorite: Array[MapInfo] = []
	var songs_unfavorite: Array[MapInfo] = []
	for song in _all_songs:
		var modified_time := song_added_time(song)
		var play_count := PlayCount.get_total_play_count(song)
		var favorite := PlayCount.is_favorite(song)
		if favorite:
			modified_time |= FAVORITE_MASK
			play_count |= FAVORITE_MASK
			songs_favorite.append(song)
		else:
			songs_unfavorite.append(song)
		songs_with_modify_times.append(MapInfoWithSort.new(modified_time, song))
		songs_with_play_count.append(MapInfoWithSort.new(play_count, song))

	songs_with_modify_times.sort_custom(compare)
	songs_with_play_count.sort_custom(compare)
	_recently_added_songs = []
	_most_played_songs = []
	_all_songs = []
	for song in songs_with_modify_times:
		_recently_added_songs.append(song.info)
	for song in songs_with_play_count:
		_most_played_songs.append(song.info)
	_all_songs.append_array(songs_favorite)
	_all_songs.append_array(songs_unfavorite)
	song_list_changed.emit()

func _load_playlists() -> void:
	#copy sample songs to main playlist folder on first run
	if not Settings.preloaded_songs:
		const maps_path := "res://game/data/maps/"
		var dir := DirAccess.open(maps_path + "Songs/")
		@warning_ignore("return_value_discarded")
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if dir.current_is_dir():
				var new_dir := maps_path+"Songs/"+file_name
				@warning_ignore("return_value_discarded")
				DirAccess.make_dir_recursive_absolute(Constants.APPDATA_PATH+"Songs/"+file_name)
				var copy := DirAccess.open(new_dir)
				@warning_ignore("return_value_discarded")
				copy.list_dir_begin()
				var copy_file_name := copy.get_next()
				while not copy_file_name.is_empty():
					var copy_new_dir := new_dir+"/"+copy_file_name
					@warning_ignore("return_value_discarded")
					dir.copy(copy_new_dir,Constants.APPDATA_PATH+"Songs/"+file_name+"/"+copy_file_name)
					copy_file_name = copy.get_next()
			file_name = dir.get_next()
		Settings.preloaded_songs = true

	_discover_all_songs(Constants.APPDATA_PATH+"Songs/")
	_sort_songs()

	# the MapInfo objects were recreated, look up the current track again
	var current_path := current_map.filepath if current_map != null else Settings.last_map
	var map := find_song_by_path(current_path)
	if map == null and current_map == null and not _all_songs.is_empty():
		map = _all_songs[0]
	_set_current_map(map, current_map == null or map == null or map.filepath != current_map.filepath)
	_redraw()

func _discover_all_songs(seek_path: String) -> void:
	_all_songs.clear()
	all_song_hashes.clear()
	var dir := DirAccess.open(seek_path)
	if dir:
		@warning_ignore("return_value_discarded")
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if dir.current_is_dir() or file_name.to_lower().ends_with(".zip"):
				var path : String
				if dir.current_is_dir():
					path = seek_path+file_name+"/"
				else:
					path = seek_path+file_name
				var song := Map.load_map_info(path)
				if song:
					_all_songs.append(song)
				# record all hashes, even those that have unsupported versions
				all_song_hashes.append(file_name)
			file_name = dir.get_next()

# rescans the songs folder (after downloads, uploads or the Refresh button)
func reload_songs() -> void:
	_on_LoadPlaylists_Button_pressed()

func _on_LoadPlaylists_Button_pressed() -> void:
	# Note: this call is non-blocking; so a user has to click again after
	#       granting the permissions; we need to find a solutio for this
	#       maybe polling after the button press?
	_check_and_request_permission()
	_load_playlists()

func set_favorite(map: MapInfo, favorite: bool) -> void:
	PlayCount.set_favorite(map, favorite)
	if map == current_map:
		song_card.set_favorite(favorite)
		_redraw()
	_sort_songs()

func delete_song(map: MapInfo) -> void:
	if _preview_key == map.filepath:
		stop_preview()
	Highscores.remove_map(map)
	PlayCount.remove_map(map)
	_covers.erase(map.filepath)

	if not map.filepath.is_empty():
		var dir := DirAccess.open(map.filepath)
		if dir:
			@warning_ignore("return_value_discarded")
			dir.list_dir_begin()
			var current_file := dir.get_next()
			while current_file != "":
				@warning_ignore("return_value_discarded")
				DirAccess.remove_absolute(map.filepath+current_file)
				current_file = dir.get_next()
		@warning_ignore("return_value_discarded")
		DirAccess.remove_absolute(map.filepath)
	if map == current_map:
		current_map = null
		Settings.last_map = ""
	_on_LoadPlaylists_Button_pressed()

# --- covers -------------------------------------------------------------------

# returns the cover if it is cached; otherwise starts loading it in the
# background and returns null, cover_loaded is emitted when it is ready
func request_cover(map: MapInfo) -> Texture2D:
	if _covers.has(map.filepath):
		return _covers[map.filepath]
	if map.cover_image_filename.is_empty():
		return null
	if _covers.size() >= MAX_COVER_CACHE:
		_covers.clear()
	_covers[map.filepath] = null
	_bg_img_loader.load_texture(map.filepath, map.cover_image_filename, _on_cover_loaded_threaded.bind(map.filepath), false, -1)
	return null

# called from the image loading thread
func _on_cover_loaded_threaded(img_tex: Texture2D, _is_main_cover: bool, _idx: int, path: String) -> void:
	_on_cover_loaded.call_deferred(path, img_tex)

func _on_cover_loaded(path: String, img_tex: Texture2D) -> void:
	if img_tex == null:
		return
	_covers[path] = img_tex
	if current_map != null and current_map.filepath == path:
		song_card.set_cover(img_tex)
	cover_loaded.emit(path, img_tex)
	_redraw()

func _redraw() -> void:
	# the panel is reparented into the canvas' SubViewport when the canvas is ready
	var canvas := get_parent().get_parent() if get_parent() != null else null
	if canvas is OQ_UI2DCanvas and canvas.is_node_ready():
		(canvas as OQ_UI2DCanvas)._input_update()

# --- preview --------------------------------------------------------------------

# key identifies what is previewed (see is_previewing())
func play_preview(buffer: PackedByteArray, start_time: float = 0.0, duration: float = -1.0, buffer_data_type_hint: String = 'ogg', key: String = "") -> void:
	var stream: AudioStream
	# take song preview data from buffer as-is. trust passed type hint
	if buffer_data_type_hint == 'ogg':
		stream = AudioStreamOggVorbis.load_from_buffer(buffer)
	elif buffer_data_type_hint == 'mp3':
		stream = AudioStreamMP3.new()
		(stream as AudioStreamMP3).data = buffer

	if not stream: return

	if duration <= 0.0:
		# assume preview duration based on parsed audio length
		duration = stream.get_length()

	_preview_key = key

	# fade out preview if ones already running
	if song_preview.playing:
		await _on_stop_prev_timeout()
		if _preview_key != key: return # another preview was requested meanwhile

	# start the requested preview, if still on song select
	if not main_song_player_ref.playing:
		song_preview.stream = stream
		var song_prev_Tween := song_preview.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		@warning_ignore("return_value_discarded")
		# TODO: is this a good idea with higher speeds?
		song_prev_Tween.tween_property(song_preview, ^"volume_db", 0, song_preview_transition_time)
		song_prev_Tween.play()
		song_preview.play(start_time)
		song_preview.pitch_scale = Settings.music_speed / 100.
		($song_prev/stop_prev as Timer).start(duration)

# previews a local song (from its preview start time)
func play_map_preview(map: MapInfo) -> void:
	if not map.have_song: return
	play_preview(Utils.read_binary_file(map.filepath, map.song_filename), map.preview_start_time, map.preview_duration, 'ogg', map.filepath)

func is_previewing(key: String) -> bool:
	return song_preview.playing and not key.is_empty() and _preview_key == key

func stop_preview() -> void:
	_preview_key = ""
	if song_preview.playing:
		_on_stop_prev_timeout()

func _on_stop_prev_timeout() -> void:
	var song_prev_Tween := song_preview.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	@warning_ignore("return_value_discarded")
	song_prev_Tween.tween_property(song_preview, "volume_db", -50, song_preview_transition_time)
	song_prev_Tween.play()
	await get_tree().create_timer(song_preview_transition_time).timeout
	song_preview.stop()

# --- now playing ------------------------------------------------------------------

# makes map the current track (called by the library)
func load_song(map: MapInfo) -> void:
	if map == null: return
	if current_map != null and map.filepath == current_map.filepath:
		return
	_set_current_map(map, true)
	Settings.last_map = map.filepath
	Settings.save()

func _set_current_map(map: MapInfo, pick_difficulty: bool) -> void:
	var changed := map != current_map
	current_map = map
	if map == null:
		song_card.show_empty("No song loaded")
		song_card.info_label.text = "Pick a song in the library on your left"
		song_card.info_label.visible = true
		_clear_children(characteristic_row)
		_clear_children(difficulty_row)
		characteristic_row.visible = false
		play_button.disabled = true
		if changed: current_song_changed.emit(null)
		update_view()
		return

	song_card.show_local(map, PlayCount.is_favorite(map), PlayCount.get_total_play_count(map), song_added_time(map))
	var tex := request_cover(map)
	if tex != null: song_card.set_cover(tex)
	play_button.disabled = map.difficulty_beatmaps.is_empty()

	var index := _map_difficulty
	if pick_difficulty:
		index = _last_difficulty_index(map)
	_select_difficulty(clampi(index, 0, maxi(0, map.difficulty_beatmaps.size() - 1)))
	if changed: current_song_changed.emit(map)

# index of the difficulty played last (falls back to the first one)
func _last_difficulty_index(map: MapInfo) -> int:
	var rank := PlayCount.get_last_difficulty(map)
	if rank < 0: return 0
	rank &= Constants.DIFFICULTY_MASK
	var found := -1
	for i in map.difficulty_beatmaps.size():
		var d := map.difficulty_beatmaps[i]
		if d.difficulty_rank == rank:
			if d.characteristic == "Standard" or d.characteristic.is_empty():
				return i
			if found < 0: found = i
	return maxi(found, 0)

func _select_difficulty(index: int) -> void:
	_map_difficulty = index
	_rebuild_difficulty_buttons()
	update_view()

func _rebuild_difficulty_buttons() -> void:
	_clear_children(characteristic_row)
	_clear_children(difficulty_row)
	if current_map == null or current_map.difficulty_beatmaps.is_empty():
		characteristic_row.visible = false
		return
	var selected := current_map.difficulty_beatmaps[_map_difficulty]
	var selected_char := selected.characteristic if not selected.characteristic.is_empty() else "Standard"
	var by_char := SongDetails.local_diffs_by_characteristic(current_map)

	characteristic_row.visible = by_char.size() > 1
	for ch: String in by_char:
		var b := _make_toggle(SongDetails.characteristic_name(ch), _characteristic_group, ch == selected_char)
		# switching the characteristic keeps the difficulty if possible
		b.pressed.connect(_on_characteristic_pressed.bind(ch))
		characteristic_row.add_child(b)

	for d: DifficultyInfo in by_char[selected_char]:
		var b := _make_toggle(SongDetails.difficulty_label(d), _difficulty_group, d == selected)
		var col := SongDetails.difficulty_color(d.difficulty)
		b.add_theme_color_override("font_color", col.lightened(0.35))
		b.add_theme_color_override("font_hover_color", col.lightened(0.5))
		b.tooltip_text = "%s %s" % [SongDetails.characteristic_name(selected_char), BeatSaverMap.DIFFICULTY_NAMES.get(d.difficulty, d.difficulty)]
		b.pressed.connect(_select_difficulty.bind(current_map.difficulty_beatmaps.find(d)))
		difficulty_row.add_child(b)
	_redraw()

func _on_characteristic_pressed(ch: String) -> void:
	var current := current_map.difficulty_beatmaps[_map_difficulty]
	var best := -1
	for i in current_map.difficulty_beatmaps.size():
		var d := current_map.difficulty_beatmaps[i]
		var dch := d.characteristic if not d.characteristic.is_empty() else "Standard"
		if dch != ch: continue
		if best < 0 or absi(SongDetails.difficulty_order(d) - SongDetails.difficulty_order(current)) < absi(SongDetails.difficulty_order(current_map.difficulty_beatmaps[best]) - SongDetails.difficulty_order(current)):
			best = i
	if best >= 0:
		_select_difficulty(best)

func _make_toggle(text: String, group: ButtonGroup, pressed: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 64)
	UI_AudioEngine.attach_button(b)
	return b

static func _clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func _load_map_and_start(map: MapInfo) -> void:
	if map.is_empty(): return

	var set0 := map.difficulty_beatmaps
	if (set0.size() == 0):
		vr.log_error("No _difficultyBeatmaps in set")
		return

	var diff_info := set0[_map_difficulty]

	start_map.emit(map, diff_info)

func _on_Play_Button_pressed() -> void:
	if current_map != null:
		Settings.last_map = current_map.filepath
		stop_preview()
		song_preview.stop()
		Settings.save()
		_load_map_and_start(current_map)

func _on_card_favorite_toggled(favorite: bool) -> void:
	if current_map != null:
		set_favorite(current_map, favorite)

func update_view() -> void:
	if current_map != null and not current_map.difficulty_beatmaps.is_empty():
		if _map_difficulty >= current_map.difficulty_beatmaps.size():
			_map_difficulty = 0
		var difficulty := current_map.difficulty_beatmaps[_map_difficulty]
		difficulty_changed.emit(current_map, difficulty.difficulty_rank)
	else:
		difficulty_changed.emit(null, -1)
	_set_reset_icon()

# lists the mods (SongCore requirements/suggestions) used by any difficulty of the map
func _describe_map_mods(map: MapInfo) -> String:
	var described: Array[String] = []
	for mod in SongDetails.local_map_mods(map):
		described.append(mod if mod in SUPPORTED_MAP_MODS else mod + " (unsupported)")
	return "" if described.is_empty() else "\nMods: " + ", ".join(described)

# --- modifiers ---------------------------------------------------------------------

func _drop_down(control: OptionButton, list: Array, value: Variant, defaultIndex: int) -> void:
	control.clear()
	var index := defaultIndex
	for i in range(list.size()):
		control.add_item(list[i][1])
		if list[i][0] == value:
			index = i
	control.selected = index

func _update_mod_controls() -> void:
	health_control.button_pressed = Settings.health_mode
	arrows_control.button_pressed = Settings.arrows_enabled

	_drop_down(flip_control, Constants.FLIPS, Settings.flip, 0)
	_drop_down(handedness_control, Constants.HANDEDNESSES, Settings.handedness, 0)
	_drop_down(width_control, Constants.WIDTHS, Settings.width, 0)
	_drop_down(size_control, Constants.SIZES, Settings.block_size, 1)
	_drop_down(speed_control, Constants.SPEEDS, Settings.music_speed, 1)

	bombs_control.button_pressed = Settings.bombs_enabled
	claws_control.button_pressed = Settings.claws

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(Constants.APPDATA_PATH+"Backgrounds/")
	DirAccess.make_dir_recursive_absolute(Constants.APPDATA_PATH+"Songs/")

	Settings.changed.connect(on_settings_changed)

	_update_mod_controls()
	_characteristic_group.allow_unpress = false
	_difficulty_group.allow_unpress = false
	song_card.favorite_toggled.connect(_on_card_favorite_toggled)

	UI_AudioEngine.attach_children(self)

	_load_playlists()

	if song_uploader_ref and song_uploader_ref.active:
		%upload_url.text = "Upload songs & backgrounds: %s"%[
			song_uploader_ref.get_server_url()
		]
	else:
		%upload_url.text = ""

	%version.text = beepsaber_game.version if beepsaber_game else ""
	if OS.get_name() == &"Web":
		%Exit_Button.hide()

func on_settings_changed(key: StringName) -> void:
	match key:
		&"music_speed":
			song_preview.pitch_scale = Settings.music_speed / 100.

func _on_Exit_Button_pressed() -> void:
	get_tree().quit()

func _on_Settings_Button_pressed() -> void:
	settings_requested.emit()

const READ_PERMISSION = "android.permission.READ_EXTERNAL_STORAGE"

func is_in_array(arr: Array, val: Variant) -> bool:
	for e: Variant in arr:
		if (e == val): return true
	return false

func _check_required_permissions() -> bool:
	if not vr.inVR: return true # desktop is always allowed

	var permissions := OS.get_granted_permissions()
	var read_storage_permission := is_in_array(permissions, READ_PERMISSION)

	vr.log_info(str(permissions))

	if not read_storage_permission:
		return false

	return true

func _check_and_request_permission() -> bool:
	vr.log_info("Checking permissions")

	if not _check_required_permissions():
		vr.log_info("Requesting permissions")
		OS.request_permissions()
		return false
	else:
		return true

func _on_licenses_pressed() -> void:
	var license := FileAccess.open("res://LICENSE", FileAccess.READ).get_as_text()
	%LicensePopup.get_node("ScrollContainer/Label").text = license
	if licenses_showing:
		%LicensePopup.hide()
	else:
		%LicensePopup.show()
	licenses_showing = not licenses_showing

func _on_health_toggled(value: bool) -> void:
	Settings.health_mode = value
	update_view()

func _on_claws_toggled(value: bool) -> void:
	Settings.claws = value
	update_view()

func _on_bombs_toggled(value: bool) -> void:
	Settings.bombs_enabled = value
	update_view()

func _on_arrows_toggled(value: bool) -> void:
	Settings.arrows_enabled = value
	update_view()

func _are_mods_default() -> bool:
	if Settings.health_mode or not Settings.bombs_enabled or not Settings.arrows_enabled:
		return false
	if Settings.claws or Settings.block_size != 100:
		return false
	if Settings.width != 100 or Settings.flip != 0 or Settings.music_speed != 100:
		return false
	if Settings.handedness != 0:
		return false
	return true

func _set_reset_icon() -> void:
	reset_button.visible = not _are_mods_default()

func _on_width_item_selected(index: int) -> void:
	Settings.width = Constants.WIDTHS[index][0]
	update_view()

func _on_size_item_selected(index: int) -> void:
	Settings.block_size = Constants.SIZES[index][0]
	update_view()

func _on_speed_item_selected(index: int) -> void:
	Settings.music_speed = Constants.SPEEDS[index][0]
	update_view()

func _on_flip_item_selected(index: int) -> void:
	Settings.flip = Constants.FLIPS[index][0]
	update_view()

func _on_handedness_item_selected(index: int) -> void:
	Settings.handedness = Constants.HANDEDNESSES[index][0]
	update_view()

func _on_reset_button_pressed() -> void:
	Settings.health_mode = false
	Settings.bombs_enabled = true
	Settings.claws = false
	Settings.block_size = 100
	Settings.width = 100
	Settings.flip = 0
	Settings.music_speed = 100
	Settings.handedness = 0
	_update_mod_controls()
	update_view()

# "My Songs" tab of the library: the local songs with covers, sorted by
# All / Recently Added / Most Played, searchable with the in-game keyboard.
# The selected song is shown in the shared SongDetails pane, where it can be
# previewed, (un)favorited, deleted and loaded into the Now Playing panel.
# Selecting the selected song again loads it, too.
extends Control
class_name LocalSongsPanel

const SEARCH_PLACEHOLDER := "Search my songs…"
const MIN_SIMILARITY := 0.45
const RowScene := preload("res://game/ui/Library/LocalSongRow.tscn")

var main_menu: MainMenu
var keyboard: OQ_UI2DKeyboard

@onready var search_button := %SearchButton as Button
@onready var clear_button := %ClearButton as Button
@onready var sort_selector := %SortSelector as OptionButton
@onready var refresh_button := %RefreshButton as Button
@onready var results := %Results as ScrollContainer
@onready var results_list := %ResultsList as VBoxContainer
@onready var list_message := %ListMessage as Label
@onready var details := %Details as SongDetails
@onready var status_label := %StatusLabel as Label

var _songs: Array[MapInfo] = [] # as shown in the list
var _rows: Array[LocalSongRow] = [] # reused between rebuilds; the first _songs.size() are used
var _index_by_path := {}
var _row_group := ButtonGroup.new()
var _selected: MapInfo = null
var _current_path := "" # of the track in the Now Playing panel
var _query := ""
var _query_before_keyboard := ""
var _awaiting_keyboard := false
var _preview_shown := true # forces the first button update

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	search_button.icon = BeatSaverIcons.get_icon("search")
	clear_button.icon = BeatSaverIcons.get_icon("close")
	sort_selector.clear()
	sort_selector.add_item("All Songs", MainMenu.PlaylistOptions.AllSongs)
	sort_selector.add_item("Recently Added", MainMenu.PlaylistOptions.RecentlyAdded)
	sort_selector.add_item("Most Played", MainMenu.PlaylistOptions.MostPlayed)
	sort_selector.select(MainMenu.PlaylistOptions.RecentlyAdded)

	search_button.pressed.connect(_on_search_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	sort_selector.item_selected.connect(func(_i: int) -> void: _rebuild(true))
	refresh_button.pressed.connect(_on_refresh_pressed)
	_row_group.allow_unpress = false
	details.primary_pressed.connect(_on_load_pressed)
	details.preview_pressed.connect(_on_preview_pressed)
	details.favorite_toggled.connect(_on_favorite_toggled)
	details.delete_confirmed.connect(_on_delete_confirmed)
	_update_query_controls()

# called by the library once both panels are ready
func setup(menu: MainMenu, kb: OQ_UI2DKeyboard) -> void:
	main_menu = menu
	keyboard = kb
	if not main_menu.is_node_ready():
		await main_menu.ready
	main_menu.song_list_changed.connect(_rebuild)
	main_menu.cover_loaded.connect(_on_cover_loaded)
	main_menu.current_song_changed.connect(_on_current_song_changed)
	if keyboard != null:
		if not keyboard.is_node_ready():
			await keyboard.ready
		keyboard.text_input_enter.connect(_text_input_enter)
		keyboard.text_input_cancel.connect(_text_input_cancel)
		keyboard._text_edit.text_changed.connect(_text_input_changed)
	_rebuild()
	select_map(main_menu.current_map)

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or main_menu == null: return
	var playing := _selected != null and main_menu.is_previewing(_selected.filepath)
	if playing != _preview_shown:
		_preview_shown = playing
		details.set_preview_playing(playing)
		_redraw()

# --- list ---------------------------------------------------------------------

func _rebuild(scroll_to_top := false) -> void:
	if main_menu == null: return
	var keep := _selected.filepath if _selected != null else ""
	var source := main_menu.get_songs(sort_selector.get_selected_id())
	_songs = _filter(source, _query) if not _query.is_empty() else source.duplicate()
	_current_path = main_menu.current_map.filepath if main_menu.current_map != null else ""

	_index_by_path.clear()
	while _rows.size() < _songs.size():
		var row := RowScene.instantiate() as LocalSongRow
		row.button_group = _row_group
		results_list.add_child(row)
		row.pressed.connect(_on_row_pressed.bind(row))
		UI_AudioEngine.attach_button(row)
		_rows.append(row)
	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < _songs.size()
		if not row.visible: continue
		var map := _songs[i]
		row.setup(map, PlayCount.is_favorite(map), main_menu.request_cover(map))
		row.set_current(map.filepath == _current_path)
		row.set_pressed_no_signal(false)
		_index_by_path[map.filepath] = i
	list_message.visible = _songs.is_empty()
	list_message.text = "No songs match \"%s\"." % _query if not _query.is_empty() else "No songs yet. Download some in the BeatSaver tab."

	_selected = null
	if _index_by_path.has(keep):
		_select_index(_index_by_path[keep] as int, false)
	else:
		details.show_empty("Select a song" if not _songs.is_empty() else "No songs found")
	if scroll_to_top and _selected == null:
		results.scroll_vertical = 0
	_update_status()
	_redraw()

# songs matching the query: prefix / substring matches of title, artist or
# mapper first, then similar titles (typos)
static func _filter(songs: Array[MapInfo], query: String) -> Array[MapInfo]:
	var q := query.to_upper()
	var scored: Array = []
	for i in songs.size():
		var map := songs[i]
		var best := 0.0
		for field: String in [map.song_name, map.song_sub_name, map.song_author_name, map.level_author_name]:
			var f := field.to_upper()
			if f.is_empty(): continue
			if f.begins_with(q): best = maxf(best, 3.0)
			elif f.contains(q): best = maxf(best, 2.0)
			else: best = maxf(best, f.similarity(q))
		if best >= MIN_SIMILARITY:
			scored.append([best, i, map])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[MapInfo] = []
	for e: Array in scored:
		out.append(e[2] as MapInfo)
	return out

func _update_status() -> void:
	var total := main_menu.get_songs().size() if main_menu != null else 0
	var parts: Array[String] = []
	if _query.is_empty():
		parts.append("%d %s" % [total, "song" if total == 1 else "songs"])
	else:
		parts.append("%d of %d songs match" % [_songs.size(), total])
	parts.append("select a song twice to load it")
	status_label.text = "  ·  ".join(parts)

func _on_cover_loaded(path: String, tex: Texture2D) -> void:
	if _index_by_path.has(path):
		_rows[_index_by_path[path] as int].set_cover(tex)
	if _selected != null and _selected.filepath == path:
		details.set_cover(tex)
	_redraw()

func _on_current_song_changed(map: MapInfo) -> void:
	var old_path := _current_path
	_current_path = map.filepath if map != null else ""
	for path: String in [old_path, _current_path]:
		if _index_by_path.has(path):
			_rows[_index_by_path[path] as int].set_current(path == _current_path)
	_update_load_button()
	_redraw()

func _redraw() -> void:
	var n: Node = self
	while n != null:
		if n is OQ_UI2DCanvas:
			if n.is_node_ready(): (n as OQ_UI2DCanvas)._input_update()
			return
		n = n.get_parent()

# --- selection ------------------------------------------------------------------

# selects map in the list (clears the search if it hides the map)
func select_map(map: MapInfo) -> void:
	if map == null: return
	if not _index_by_path.has(map.filepath) and not _query.is_empty():
		_query = ""
		_update_query_controls()
		_rebuild()
	if _index_by_path.has(map.filepath):
		_select_index(_index_by_path[map.filepath] as int, false)

func _select_index(index: int, preview: bool) -> void:
	if index < 0 or index >= _songs.size(): return
	# set_pressed_no_signal() doesn't release the other buttons of the group
	for r in _rows:
		if r.button_pressed and r != _rows[index]: r.set_pressed_no_signal(false)
	_rows[index].set_pressed_no_signal(true)
	_ensure_visible.call_deferred(_rows[index])
	var map := _songs[index]
	var changed := _selected != map
	_selected = map
	details.show_local(map, PlayCount.is_favorite(map), PlayCount.get_total_play_count(map), MainMenu.song_added_time(map))
	var tex := main_menu.request_cover(map)
	if tex != null: details.set_cover(tex)
	_update_load_button()
	_preview_shown = not _preview_shown # force a button refresh
	if preview and changed and map.have_song and Settings.audio_master > 0 and Settings.audio_music_preview > 0:
		main_menu.play_map_preview(map)

func _update_load_button() -> void:
	if _selected == null: return
	if main_menu.current_map != null and main_menu.current_map.filepath == _selected.filepath:
		details.set_primary("Now playing", "check", true)
	else:
		details.set_primary("Load", "play", _selected.difficulty_beatmaps.is_empty())

func _ensure_visible(row: Control) -> void:
	if is_instance_valid(row) and row.visible:
		results.ensure_control_visible(row)
		_redraw()

# selecting the selected song again loads it
func _on_row_pressed(row: LocalSongRow) -> void:
	var index := _songs.find(row.map)
	if index < 0: return
	if row.map == _selected:
		_on_load_pressed()
	else:
		_select_index(index, true)

func _on_load_pressed() -> void:
	if _selected == null: return
	main_menu.load_song(_selected)
	_update_load_button()

func _on_preview_pressed() -> void:
	if _selected == null: return
	if main_menu.is_previewing(_selected.filepath):
		main_menu.stop_preview()
	else:
		main_menu.play_map_preview(_selected)

func _on_favorite_toggled(favorite: bool) -> void:
	if _selected == null: return
	main_menu.set_favorite(_selected, favorite) # resorts, which rebuilds the list

func _on_delete_confirmed() -> void:
	if _selected == null: return
	var index := maxi(0, _songs.find(_selected))
	var map := _selected
	_selected = null
	main_menu.delete_song(map) # reloads, which rebuilds the list
	# select the song that took its place
	if not _songs.is_empty():
		_select_index(mini(index, _songs.size() - 1), false)

func _on_refresh_pressed() -> void:
	main_menu.reload_songs()

# --- search ----------------------------------------------------------------------

func _update_query_controls() -> void:
	search_button.text = SEARCH_PLACEHOLDER if _query.is_empty() else _query
	search_button.add_theme_color_override("font_color", SongDetails.MUTED if _query.is_empty() else Color("e9edf5"))
	clear_button.disabled = _query.is_empty()

func _on_search_pressed() -> void:
	if keyboard == null: return
	keyboard.set_meta(&"search_owner", self)
	_awaiting_keyboard = true
	_query_before_keyboard = _query
	keyboard._show()
	keyboard._text_edit.text = _query
	keyboard._text_edit.set_caret_column(_query.length())
	keyboard._text_edit.grab_focus()

# the shared keyboard is now used by someone else
func cancel_keyboard() -> void:
	_awaiting_keyboard = false

func _text_input_changed() -> void:
	if not _awaiting_keyboard or keyboard.get_meta(&"search_owner", null) != self: return
	_set_query(keyboard._text_edit.text)

func _text_input_enter(text: String) -> void:
	if not _awaiting_keyboard or keyboard.get_meta(&"search_owner", null) != self: return
	_awaiting_keyboard = false
	keyboard._hide()
	_set_query(text)

func _text_input_cancel() -> void:
	if not _awaiting_keyboard or keyboard.get_meta(&"search_owner", null) != self: return
	_awaiting_keyboard = false
	keyboard._hide()
	_set_query(_query_before_keyboard)

func _on_clear_pressed() -> void:
	_set_query("")

func _set_query(text: String) -> void:
	text = text.strip_edges()
	if text == _query: return
	_query = text
	_update_query_controls()
	_rebuild(true)

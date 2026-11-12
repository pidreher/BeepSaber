# The song library, a canvas to the left of the player: browse, search,
# download and choose songs. "My Songs" lists the local songs, "BeatSaver" is
# the online browser; both show their selection in the shared SongDetails pane
# and hand the chosen song to the Now Playing panel (MainMenu.load_song()).
extends Panel
class_name LibraryPanel

enum Tab { MY_SONGS, BEATSAVER }

@export var main_menu_ref: MainMenu
# shared in-game keyboard for the search fields of both tabs
@export var keyboard: OQ_UI2DKeyboard
# dialog for the other online sources (Beat Sage, which can also search YouTube)
@export var more_sources_canvas: OQ_UI2DCanvas

@onready var my_songs_tab := %MySongsTab as Button
@onready var beat_saver_tab := %BeatSaverTab as Button
@onready var more_sources_button := %MoreSourcesButton as Button
@onready var local_songs := %LocalSongs as LocalSongsPanel
@onready var beat_saver := %BeatSaver as BeatSaverPanel

var current_tab := Tab.MY_SONGS

func _ready() -> void:
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for b: Button in [my_songs_tab, beat_saver_tab]:
		b.button_group = group
		UI_AudioEngine.attach_button(b)
	UI_AudioEngine.attach_button(more_sources_button)
	my_songs_tab.pressed.connect(show_tab.bind(Tab.MY_SONGS))
	beat_saver_tab.pressed.connect(show_tab.bind(Tab.BEATSAVER))
	more_sources_button.pressed.connect(_on_more_sources_pressed)
	more_sources_button.visible = more_sources_canvas != null

	local_songs.setup(main_menu_ref, keyboard)
	beat_saver.setup(main_menu_ref, keyboard)
	beat_saver.load_requested.connect(_on_beat_saver_load_requested)
	show_tab(Tab.MY_SONGS)

func show_tab(tab: Tab) -> void:
	current_tab = tab
	# the keyboard belongs to the search field of the tab that opened it
	local_songs.cancel_keyboard()
	beat_saver.cancel_keyboard()
	if keyboard != null and keyboard.visible:
		keyboard._hide()
	local_songs.visible = tab == Tab.MY_SONGS
	beat_saver.visible = tab == Tab.BEATSAVER
	my_songs_tab.set_pressed_no_signal(tab == Tab.MY_SONGS)
	beat_saver_tab.set_pressed_no_signal(tab == Tab.BEATSAVER)
	_redraw()

# a downloaded BeatSaver map becomes the current track and is shown in My Songs
func _on_beat_saver_load_requested(version_hash: String) -> void:
	var map := main_menu_ref.find_song_by_hash(version_hash)
	if map == null:
		# downloaded while other downloads were still running: not scanned yet
		main_menu_ref.reload_songs()
		map = main_menu_ref.find_song_by_hash(version_hash)
	if map == null:
		vr.log_warning("Downloaded map %s not found in the songs folder" % version_hash)
		return
	main_menu_ref.load_song(map)
	show_tab(Tab.MY_SONGS)
	local_songs.select_map(map)

func _on_more_sources_pressed() -> void:
	if more_sources_canvas.visible:
		more_sources_canvas._hide()
	else:
		more_sources_canvas._show()

func _redraw() -> void:
	var n: Node = self
	while n != null:
		if n is OQ_UI2DCanvas:
			if n.is_node_ready(): (n as OQ_UI2DCanvas)._input_update()
			return
		n = n.get_parent()

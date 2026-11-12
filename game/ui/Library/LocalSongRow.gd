# One row of the "My Songs" list, styled like the BeatSaver result rows:
# cover, title (+ favorite star), artist / mapper, difficulty chips and a
# "Now playing" note for the current track.
extends Button
class_name LocalSongRow

const DEFAULT_COVER := preload("res://game/data/beepsaber_logo.png")

var map: MapInfo

@onready var _cover := %Cover as TextureRect
@onready var _title := %Title as Label
@onready var _star := %Star as TextureRect
@onready var _sub := %Sub as Label
@onready var _diffs := %Diffs as HBoxContainer
@onready var _status := %Status as Label

func _ready() -> void:
	_star.texture = get_theme_icon(&"star_on", &"MainMenu")

func setup(m: MapInfo, favorite: bool, cover: Texture2D) -> void:
	map = m
	var title := m.song_name if m.song_sub_name.is_empty() else "%s %s" % [m.song_name, m.song_sub_name]
	_title.text = title
	tooltip_text = title
	var artist := m.song_author_name if not m.song_author_name.is_empty() else "Unknown artist"
	_sub.text = "%s  ·  %s" % [artist, m.level_author_name] if not m.level_author_name.is_empty() else artist
	_star.visible = favorite
	set_cover(cover)
	for c in _diffs.get_children():
		_diffs.remove_child(c)
		c.queue_free()
	for d in BeatSaverMap.DIFFICULTY_ORDER:
		for diff in m.difficulty_beatmaps:
			if diff.difficulty == d:
				_diffs.add_child(BeatSaverMapRow.make_chip(BeatSaverMap.DIFFICULTY_SHORT[d], BeatSaverMap.DIFFICULTY_COLORS[d]))
				break
	if not m.have_song:
		_diffs.add_child(BeatSaverMapRow.make_chip("No audio", SongDetails.UNSUPPORTED, false))
	set_current(false)

func set_cover(tex: Texture2D) -> void:
	_cover.texture = tex if tex != null else DEFAULT_COVER

func set_current(current: bool) -> void:
	_status.visible = current

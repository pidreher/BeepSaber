# One result row of the BeatSaver browser: cover, title, artist/mapper,
# length/BPM/NPS, difficulties, mods, rating and votes, download state.
extends Button
class_name BeatSaverMapRow

const BADGE_RANKED := Color("e0a526")
const BADGE_CURATED := Color("1fa59a")
const UNSUPPORTED := Color("ff5468")
const SUPPORTED_MOD := Color("5a6a8c")
const STATUS_DOWNLOADED := Color("4cd07d")
const STATUS_ACTIVE := Color("6b9bff")
const MUTED := Color(0.55, 0.584, 0.659, 1)

var map: BeatSaverMap

@onready var _cover := %Cover as TextureRect
@onready var _title := %Title as Label
@onready var _badges := %Badges as HBoxContainer
@onready var _sub := %Sub as Label
@onready var _mods := %Mods as HBoxContainer
@onready var _stats := %Stats as Label
@onready var _diffs := %Diffs as HBoxContainer
@onready var _rating := %Rating as Label
@onready var _up := %Up as Label
@onready var _down := %Down as Label
@onready var _status := %Status as Label

func _ready() -> void:
	(%UpIcon as TextureRect).texture = BeatSaverIcons.get_icon("up", 22)
	(%DownIcon as TextureRect).texture = BeatSaverIcons.get_icon("down", 22)

func setup(m: BeatSaverMap) -> void:
	map = m
	_title.text = m.title()
	_sub.text = "%s  ·  %s" % [m.song_author_name if not m.song_author_name.is_empty() else "Unknown artist", m.level_author_name]
	var nps := "%.1f NPS" % m.max_nps()
	if m.max_nps() - m.min_nps() >= 0.1:
		nps = "%.1f–%.1f NPS" % [m.min_nps(), m.max_nps()]
	_stats.text = "%s  ·  %s BPM  ·  %s" % [BeatSaverMap.format_duration(m.duration), _format_bpm(m.bpm), nps]
	_rating.text = "%d%%" % roundi(m.score * 100.0)
	_rating.add_theme_color_override("font_color", BeatSaverMap.rating_color(m.score))
	_up.text = BeatSaverMap.format_count(m.upvotes)
	_down.text = BeatSaverMap.format_count(m.downvotes)

	for c in _badges.get_children(): c.queue_free()
	if m.ranked: _badges.add_child(make_chip("Ranked", BADGE_RANKED))
	elif m.qualified: _badges.add_child(make_chip("Qualified", BADGE_RANKED, false))
	if m.curated: _badges.add_child(make_chip("Curated", BADGE_CURATED))

	for c in _mods.get_children(): c.queue_free()
	for mod in m.mods():
		_mods.add_child(make_chip(short_mod_name(mod), SUPPORTED_MOD if BeatSaverMap.is_mod_supported(mod) else UNSUPPORTED))
	if m.automapper: _mods.add_child(make_chip("Auto", SUPPORTED_MOD, false))

	for c in _diffs.get_children(): c.queue_free()
	for d in m.difficulties():
		_diffs.add_child(make_chip(BeatSaverMap.DIFFICULTY_SHORT[d], BeatSaverMap.DIFFICULTY_COLORS[d]))
	set_status("", false)

func set_cover(tex: Texture2D) -> void:
	if tex != null: _cover.texture = tex

# status text replaces the upload date (e.g. "Downloaded", "Queued", "45%")
func set_status(text: String, downloaded: bool) -> void:
	if text.is_empty() and downloaded:
		text = "Downloaded"
	if text.is_empty():
		_status.text = map.upload_date() if map else ""
		_status.add_theme_color_override("font_color", MUTED)
	else:
		_status.text = text
		_status.add_theme_color_override("font_color", STATUS_DOWNLOADED if downloaded else STATUS_ACTIVE)
	_cover.modulate = Color(1, 1, 1, 0.55) if downloaded else Color.WHITE

static func short_mod_name(mod: String) -> String:
	match mod:
		BeatSaverMap.MOD_ME: return "ME"
		BeatSaverMap.MOD_NOODLE: return "Noodle"
	return mod

static func _format_bpm(bpm: float) -> String:
	return str(roundi(bpm)) if absf(bpm - roundf(bpm)) < 0.05 else "%.1f" % bpm

# small colored tag; filled = solid background, else outlined
static func make_chip(text: String, color: Color, filled := true, font_size := 24) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	if filled:
		sb.bg_color = color.darkened(0.15)
		l.add_theme_color_override("font_color", Color.WHITE)
	else:
		sb.bg_color = Color(color, 0.12)
		sb.set_border_width_all(2)
		sb.border_color = color
		l.add_theme_color_override("font_color", color.lightened(0.25))
	l.add_theme_stylebox_override("normal", sb)
	return l

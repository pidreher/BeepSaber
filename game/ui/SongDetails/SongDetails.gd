# Song details pane shared by the library tabs ("My Songs" and "BeatSaver")
# and, in compact mode, by the Now Playing panel. It is a pure view: the owner
# fills it with show_local() / show_online(), reacts to its signals and keeps
# the buttons up to date (set_primary(), set_progress(), set_preview_playing()).
extends VBoxContainer
class_name SongDetails

# the main action: "Load" for local songs, "Download" / "Load" for online maps
signal primary_pressed()
signal preview_pressed()
signal favorite_toggled(favorite: bool)
# emitted after the delete button was pressed twice (first press asks "Sure?")
signal delete_confirmed()
signal mapper_pressed()

const DEFAULT_COVER := preload("res://game/data/beepsaber_logo.png")
const MUTED := Color(0.55, 0.584, 0.659, 1)
const UNSUPPORTED := Color("ff5468")
const MOD_CHIP := Color("5a6a8c")
const FAVORITE_COLOR := Color("ffc93d")
# mods the game can play (BeatSaverMap.is_mod_supported() is the online twin)
const SUPPORTED_MAP_MODS := ["Chroma", "Mapping Extensions"]
const DELETE_CONFIRM_SECONDS := 5.0

# compact mode only shows the song card (Now Playing panel)
@export var compact := false:
	set(value):
		compact = value
		if is_node_ready(): _apply_mode()

@onready var song_card := %SongCard as PanelContainer
@onready var cover := %Cover as TextureRect
@onready var title_label := %Title as Label
@onready var favorite_button := %FavoriteButton as Button
@onready var subtitle_label := %SubTitle as Label
@onready var artist_label := %Artist as Label
@onready var mapper_label := %Mapper as Label
@onready var info_label := %Info as Label
@onready var badges := %Badges as HFlowContainer
@onready var stats_grid := %StatsGrid as GridContainer
@onready var diffs_title := %DiffsTitle as Label
@onready var diffs_label := %Diffs as RichTextLabel
@onready var description := %Description as RichTextLabel
@onready var spacer := %Spacer as Control
@onready var download_status := %DownloadStatus as Control
@onready var download_progress := %DownloadProgress as ProgressBar
@onready var download_label := %DownloadLabel as Label
@onready var actions := %Actions as HBoxContainer
@onready var preview_button := %PreviewButton as Button
@onready var mapper_button := %MapperButton as Button
@onready var delete_button := %DeleteButton as Button
@onready var primary_button := %PrimaryButton as Button

var _favorite := false
var _has_song := false
var _is_online := false
var _preview_playing := false
var _delete_armed := 0 # counts presses, so an old timer doesn't disarm a new request

func _ready() -> void:
	preview_button.pressed.connect(func() -> void: preview_pressed.emit())
	mapper_button.pressed.connect(func() -> void: mapper_pressed.emit())
	primary_button.pressed.connect(func() -> void: primary_pressed.emit())
	favorite_button.pressed.connect(_on_favorite_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	mapper_button.icon = BeatSaverIcons.get_icon("user")
	set_preview_playing(false)
	_apply_mode()
	show_empty()

func _apply_mode() -> void:
	var c := compact
	cover.custom_minimum_size = Vector2(220, 220) if c else Vector2(176, 176)
	title_label.add_theme_font_size_override("font_size", 36 if c else 32)
	for n: Control in [stats_grid, diffs_title, diffs_label, description, spacer, download_status, actions]:
		if c: n.visible = false
	info_label.visible = c and _has_song
	if not c and _has_song:
		_set_full_parts_visible(true)

func _set_full_parts_visible(on: bool) -> void:
	if compact: return
	stats_grid.visible = on
	diffs_title.visible = on
	diffs_label.visible = on
	actions.visible = on
	description.visible = on and _is_online
	spacer.visible = not description.visible

# --- filling ------------------------------------------------------------------

# placeholder when nothing is selected
func show_empty(text := "Select a song") -> void:
	_has_song = false
	_is_online = false
	cover.texture = DEFAULT_COVER
	title_label.text = text
	subtitle_label.visible = false
	artist_label.text = ""
	artist_label.visible = false
	mapper_label.visible = false
	info_label.visible = false
	favorite_button.visible = false
	_clear(badges)
	_clear(stats_grid)
	_set_full_parts_visible(false)
	download_status.visible = false
	if not compact:
		spacer.visible = true

func show_local(map: MapInfo, favorite: bool, plays: int, added_unix_time: int = 0) -> void:
	_has_song = true
	_is_online = false
	_fill_header(map.song_name, map.song_sub_name, map.song_author_name, map.level_author_name, "")
	favorite_button.visible = true
	set_favorite(favorite)

	var plays_text := "Not played yet" if plays == 0 else ("Played once" if plays == 1 else "Played %d times" % plays)
	info_label.text = plays_text
	info_label.visible = compact

	_clear(badges)
	for mod in local_map_mods(map):
		var supported := mod in SUPPORTED_MAP_MODS
		badges.add_child(BeatSaverMapRow.make_chip(BeatSaverMapRow.short_mod_name(mod) + ("" if supported else " (unsupported)"),
			MOD_CHIP if supported else UNSUPPORTED, supported))
	if not map.have_song:
		badges.add_child(BeatSaverMapRow.make_chip("No audio", UNSUPPORTED, false))

	var stats := [
		["BPM", BeatSaverMapRow._format_bpm(map.beats_per_minute)],
		["Played", "never" if plays == 0 else ("once" if plays == 1 else "%d times" % plays)],
		["Added", Time.get_date_string_from_unix_time(added_unix_time) if added_unix_time > 0 else "–"],
		["Scene", map.environment_name.trim_suffix("Environment") if not map.environment_name.is_empty() else "Default"],
	]
	_fill_stats(stats)

	diffs_title.text = "DIFFICULTIES  ·  NOTE JUMP SPEED"
	var lines: Array[String] = []
	var by_char := local_diffs_by_characteristic(map)
	for ch: String in by_char:
		var entries: Array[String] = []
		for d: DifficultyInfo in by_char[ch]:
			entries.append("[color=#%s]%s[/color]\u00a0[color=#8c95a8]%s[/color]" % [
				difficulty_color(d.difficulty).lightened(0.2).to_html(false), _escape(difficulty_label(d)),
				BeatSaverMapRow._format_bpm(d.note_jump_movement_speed)])
		lines.append("[color=#8c95a8]%s:[/color]  %s" % [characteristic_name(ch), "   ".join(entries)])
	diffs_label.text = "\n".join(lines)
	description.text = ""

	preview_button.disabled = not map.have_song
	mapper_button.visible = false
	delete_button.visible = true
	_reset_delete_button()
	download_status.visible = false
	set_primary("Load", "play", false)
	_set_full_parts_visible(true)

func show_online(m: BeatSaverMap, downloaded: bool, mapper_enabled: bool) -> void:
	_has_song = true
	_is_online = true
	var mapper := m.level_author_name
	var uploader := ""
	if m.uploader_name != m.level_author_name and not m.uploader_name.is_empty():
		uploader = "  (uploaded by %s)" % m.uploader_name
	_fill_header(m.song_name, m.song_sub_name, m.song_author_name, mapper, uploader)
	favorite_button.visible = false
	info_label.visible = false

	_clear(badges)
	if m.ranked: badges.add_child(BeatSaverMapRow.make_chip("Ranked", BeatSaverMapRow.BADGE_RANKED))
	elif m.qualified: badges.add_child(BeatSaverMapRow.make_chip("Qualified", BeatSaverMapRow.BADGE_RANKED, false))
	if m.curated: badges.add_child(BeatSaverMapRow.make_chip("Curated", BeatSaverMapRow.BADGE_CURATED))
	if m.uploader_verified: badges.add_child(BeatSaverMapRow.make_chip("Verified mapper", BeatSaverMapRow.BADGE_CURATED, false))
	if m.automapper: badges.add_child(BeatSaverMapRow.make_chip("Auto-mapped", MOD_CHIP, false))
	for mod in m.mods():
		var supported := BeatSaverMap.is_mod_supported(mod)
		badges.add_child(BeatSaverMapRow.make_chip(BeatSaverMapRow.short_mod_name(mod) + ("" if supported else " (unsupported)"),
			MOD_CHIP if supported else UNSUPPORTED, supported))
	if downloaded: badges.add_child(BeatSaverMapRow.make_chip("Downloaded", BeatSaverMapRow.STATUS_DOWNLOADED))

	var nps := "%.1f" % m.max_nps()
	if m.max_nps() - m.min_nps() >= 0.1:
		nps = "%.1f – %.1f" % [m.min_nps(), m.max_nps()]
	var stats := [
		["Length", BeatSaverMap.format_duration(m.duration)], ["BPM", BeatSaverMapRow._format_bpm(m.bpm)],
		["Rating", "%d%%" % roundi(m.score * 100.0)], ["Votes", "%s up  ·  %s down" % [format_thousands(m.upvotes), format_thousands(m.downvotes)]],
		["NPS", nps], ["Uploaded", m.upload_date()],
		["Key", m.id],
	]
	_fill_stats(stats)
	for i in stats_grid.get_child_count():
		var l := stats_grid.get_child(i) as Label
		if l.text == "Rating" and i + 1 < stats_grid.get_child_count():
			(stats_grid.get_child(i + 1) as Label).add_theme_color_override("font_color", BeatSaverMap.rating_color(m.score))

	diffs_title.text = "DIFFICULTIES  ·  NOTES PER SECOND"
	var lines: Array[String] = []
	var by_char := m.diffs_by_characteristic()
	for ch: String in by_char:
		var entries: Array[String] = []
		for d: BeatSaverMap.Diff in by_char[ch]:
			var extra := ""
			if d.ne or d.vivify:
				extra = " [color=#ff5468](%s)[/color]" % ("Vivify" if d.vivify else "Noodle")
			entries.append("[color=#%s]%s[/color]\u00a0[color=#8c95a8]%.1f[/color]%s" % [
				difficulty_color(d.difficulty).lightened(0.2).to_html(false),
				BeatSaverMap.DIFFICULTY_NAMES.get(d.difficulty, d.difficulty), d.nps, extra])
		lines.append("[color=#8c95a8]%s:[/color]  %s" % [characteristic_name(ch), "   ".join(entries)])
	diffs_label.text = "\n".join(lines)
	description.text = m.description if not m.description.strip_edges().is_empty() else "No description."
	description.scroll_to_line(0)

	preview_button.disabled = m.preview_url.is_empty()
	mapper_button.visible = true
	mapper_button.disabled = not mapper_enabled
	mapper_button.tooltip_text = "More maps by %s" % m.uploader_name
	delete_button.visible = false
	_set_full_parts_visible(true)

func _fill_header(song: String, sub: String, artist: String, mapper: String, mapper_suffix: String) -> void:
	title_label.text = song if not song.is_empty() else "Unknown song"
	subtitle_label.text = sub
	subtitle_label.visible = not sub.strip_edges().is_empty()
	artist_label.text = artist if not artist.is_empty() else "Unknown artist"
	artist_label.visible = true
	mapper_label.text = "Mapped by %s%s" % [mapper if not mapper.is_empty() else "unknown", mapper_suffix]
	mapper_label.visible = true
	cover.texture = DEFAULT_COVER

func _fill_stats(stats: Array) -> void:
	_clear(stats_grid)
	for s: Array in stats:
		var k := Label.new()
		k.text = s[0]
		k.theme_type_variation = &"MutedLabel"
		k.add_theme_font_size_override("font_size", 24)
		var v := Label.new()
		v.text = s[1]
		v.add_theme_font_size_override("font_size", 24)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.custom_minimum_size.x = 60
		v.tooltip_text = s[1]
		stats_grid.add_child(k)
		stats_grid.add_child(v)

static func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

# --- buttons --------------------------------------------------------------------

func set_cover(tex: Texture2D) -> void:
	cover.texture = tex if tex != null else DEFAULT_COVER

func set_primary(text: String, icon_name: String, disabled: bool) -> void:
	primary_button.text = text
	primary_button.icon = BeatSaverIcons.get_icon(icon_name) if not icon_name.is_empty() else null
	primary_button.disabled = disabled

func set_progress(shown: bool, frac := 0.0, text := "") -> void:
	if compact: return
	download_status.visible = shown
	download_progress.value = frac
	download_label.text = text

func set_preview_playing(playing: bool) -> void:
	_preview_playing = playing
	preview_button.text = "Stop" if playing else "Preview"
	preview_button.icon = BeatSaverIcons.get_icon("stop" if playing else "play")

func set_favorite(favorite: bool) -> void:
	_favorite = favorite
	favorite_button.icon = get_theme_icon(&"star_on" if favorite else &"star_off", &"MainMenu")
	favorite_button.tooltip_text = "Remove from favorites" if favorite else "Add to favorites"

func _on_favorite_pressed() -> void:
	set_favorite(not _favorite)
	favorite_toggled.emit(_favorite)

func _on_delete_pressed() -> void:
	if delete_button.text != "Sure?":
		delete_button.text = "Sure?"
		_delete_armed += 1
		var armed := _delete_armed
		await get_tree().create_timer(DELETE_CONFIRM_SECONDS).timeout
		if armed == _delete_armed:
			_reset_delete_button()
	else:
		_reset_delete_button()
		delete_confirmed.emit()

func _reset_delete_button() -> void:
	_delete_armed += 1
	delete_button.text = "Delete"

# --- helpers for local maps (MapInfo) -------------------------------------------

# mods (SongCore requirements/suggestions) used by any difficulty of the map
static func local_map_mods(map: MapInfo) -> Array[String]:
	var mods: Array[String] = []
	for diff in map.difficulty_beatmaps:
		for key: String in ["_requirements", "_suggestions", "requirements", "suggestions"]:
			for mod: Variant in Utils.get_array(diff.custom_data, key, []):
				if mod is String and not mods.has(mod):
					mods.append(mod as String)
	return mods

# characteristic -> difficulties (as in the map, easiest first); Standard first
static func local_diffs_by_characteristic(map: MapInfo) -> Dictionary:
	var out := {}
	for d in map.difficulty_beatmaps:
		var ch := d.characteristic if not d.characteristic.is_empty() else "Standard"
		if not out.has(ch):
			out[ch] = []
		(out[ch] as Array).append(d)
	for k: String in out:
		(out[k] as Array).sort_custom(func(a: DifficultyInfo, b: DifficultyInfo) -> bool:
			return difficulty_order(a) < difficulty_order(b))
	if out.has("Standard") and out.keys()[0] != "Standard":
		var sorted := {"Standard": out["Standard"]}
		for k: String in out:
			if k != "Standard": sorted[k] = out[k]
		return sorted
	return out

static func difficulty_order(d: DifficultyInfo) -> int:
	var i := BeatSaverMap.DIFFICULTY_ORDER.find(d.difficulty)
	return d.difficulty_rank if i < 0 else i * 2 + 1

static func difficulty_color(difficulty: String) -> Color:
	return BeatSaverMap.DIFFICULTY_COLORS.get(difficulty, Color("8c95a8"))

# the custom label of a difficulty if the mapper gave one, else "Expert+" etc.
static func difficulty_label(d: DifficultyInfo) -> String:
	var base: String = BeatSaverMap.DIFFICULTY_NAMES.get(d.difficulty, d.difficulty)
	if not d.custom_name.is_empty() and d.custom_name != d.difficulty:
		return d.custom_name
	return base

static func characteristic_name(ch: String) -> String:
	return BeatSaverMap.CHARACTERISTIC_NAMES.get(ch, ch)

static func format_thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

# In-game BeatSaver browser, modelled after the PC mod "BetterSongSearch":
# search the BeatSaver catalog with filters and sorting, see the important
# facts of every map at a glance, preview and download with one click.
extends Panel
class_name BeatSaverPanel

const API_URL := "https://api.beatsaver.com/search/text/%d?%s"
const PAGE_SIZE := 20
# stop auto-fetching further pages when the client side filters hide
# everything on this many pages in a row
const MAX_EMPTY_PAGES := 5
# fetch the next page once fewer than this many rows are below the viewport
const PREFETCH_ROWS := 4
const COVER_REQUESTS := 4
const MAX_COVER_CACHE := 400
const MAX_BACK_STACK_DEPTH := 10
const SEARCH_PLACEHOLDER := "Search songs, artists, mappers…"
const HTTP_HEADERS: PackedStringArray = ["User-Agent: OpenSaber (in-game map browser)"]

const RowScene := preload("res://game/ui/BeatSaverPanel/BeatSaverMapRow.tscn")

# reference to the main menu (downloaded songs list, song preview player)
@export var main_menu_ref: MainMenu
@export var keyboard: OQ_UI2DKeyboard

# what is being searched: free text and/or the maps of one mapper
class Query extends RefCounted:
	var text := ""
	var mapper_id := -1
	var mapper_name := ""
	func duplicate_query() -> Query:
		var q := Query.new()
		q.text = text
		q.mapper_id = mapper_id
		q.mapper_name = mapper_name
		return q

var filters := BeatSaverFilters.new()
var query := Query.new()
var back_stack: Array[Query] = []

var _maps: Array[BeatSaverMap] = [] # everything loaded for the current query
var _rows: Array[BeatSaverMapRow] = [] # visible (filtered) rows
var _selected: BeatSaverMap = null
var _next_page := 0
var _total := 0
var _end_reached := false
var _loading := false
var _empty_pages := 0
var _error := ""
var _row_group := ButtonGroup.new()

# downloads
var _download_queue: Array[BeatSaverMap] = []
var _downloaded_now := {} # hashes downloaded in this session
var _last_download_message := ""

# covers
var _cover_cache := {} # url -> Texture2D
var _cover_queue: Array[String] = []
var _cover_requests: Array[HTTPRequest] = []
var _cover_busy := {} # HTTPRequest -> url

# preview
var _preview_map: BeatSaverMap = null
var _preview_shown_playing := true # forces the first button update

var _awaiting_keyboard := false
var _updating_controls := false
var _is_first_show := true

@onready var back_button := %BackButton as Button
@onready var search_button := %SearchButton as Button
@onready var clear_button := %ClearButton as Button
@onready var sort_selector := %SortSelector as OptionButton
@onready var results := %Results as ScrollContainer
@onready var results_list := %ResultsList as VBoxContainer
@onready var list_message := %ListMessage as Label
@onready var load_more_button := %LoadMoreButton as Button
@onready var details_tab := %DetailsTab as Button
@onready var filters_tab := %FiltersTab as Button
@onready var details_page := %DetailsPage as Control
@onready var filters_page := %FiltersPage as Control
@onready var detail_cover := %DetailCover as TextureRect
@onready var detail_title := %DetailTitle as Label
@onready var detail_artist := %DetailArtist as Label
@onready var detail_mapper := %DetailMapper as Label
@onready var detail_badges := %DetailBadges as HFlowContainer
@onready var stats_grid := %StatsGrid as GridContainer
@onready var diffs_label := %Diffs as RichTextLabel
@onready var description := %Description as RichTextLabel
@onready var download_status := %DownloadStatus as Control
@onready var download_progress := %DownloadProgress as ProgressBar
@onready var download_label := %DownloadLabel as Label
@onready var preview_button := %PreviewButton as Button
@onready var mapper_button := %MapperButton as Button
@onready var download_button := %DownloadButton as Button
@onready var min_nps := %MinNps as OptionButton
@onready var max_nps := %MaxNps as OptionButton
@onready var min_length := %MinLength as OptionButton
@onready var max_length := %MaxLength as OptionButton
@onready var min_rating := %MinRating as OptionButton
@onready var difficulty := %Difficulty as OptionButton
@onready var hide_unsupported := %HideUnsupported as CheckButton
@onready var hide_downloaded := %HideDownloaded as CheckButton
@onready var only_ranked := %OnlyRanked as CheckButton
@onready var only_curated := %OnlyCurated as CheckButton
@onready var only_verified := %OnlyVerified as CheckButton
@onready var include_auto := %IncludeAuto as CheckButton
@onready var status_label := %StatusLabel as Label
@onready var queue_label := %QueueLabel as Label
@onready var search_request := $SearchRequest as HTTPRequest
@onready var download_request := $DownloadRequest as HTTPRequest
@onready var preview_request := $PreviewRequest as HTTPRequest
@onready var filter_debounce := $FilterDebounce as Timer

func _ready() -> void:
	UI_AudioEngine.attach_children(self)
	var use_threads := OS.get_name() != "Web"
	for r: HTTPRequest in [search_request, download_request, preview_request]:
		r.use_threads = use_threads
	for i in COVER_REQUESTS:
		var r := HTTPRequest.new()
		r.use_threads = use_threads
		r.timeout = 20.0
		add_child(r)
		r.request_completed.connect(_on_cover_completed.bind(r))
		_cover_requests.append(r)

	search_request.request_completed.connect(_on_search_completed)
	download_request.request_completed.connect(_on_download_completed)
	preview_request.request_completed.connect(_on_preview_completed)
	filter_debounce.timeout.connect(_on_filter_debounce)

	back_button.icon = BeatSaverIcons.get_icon("back")
	search_button.icon = BeatSaverIcons.get_icon("search")
	clear_button.icon = BeatSaverIcons.get_icon("close")
	mapper_button.icon = BeatSaverIcons.get_icon("user")
	download_button.icon = BeatSaverIcons.get_icon("download")
	var tab_group := ButtonGroup.new()
	details_tab.button_group = tab_group
	filters_tab.button_group = tab_group
	_row_group.allow_unpress = false

	back_button.pressed.connect(_on_back_pressed)
	search_button.pressed.connect(_on_search_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	(%CloseButton as Button).pressed.connect(_on_close_pressed)
	load_more_button.pressed.connect(_request_next_page)
	details_tab.pressed.connect(_show_tab.bind(false))
	filters_tab.pressed.connect(_show_tab.bind(true))
	preview_button.pressed.connect(_on_preview_pressed)
	mapper_button.pressed.connect(_on_mapper_pressed)
	download_button.pressed.connect(_on_download_pressed)
	(%ResetFilters as Button).pressed.connect(_on_reset_filters)
	results.get_v_scroll_bar().value_changed.connect(_on_results_scrolled)
	results.get_v_scroll_bar().changed.connect(_on_results_scrolled.bind(0.0))

	_init_filter_controls()
	filters.load_saved()
	_sync_filter_controls()

	if keyboard != null:
		keyboard.text_input_enter.connect(_text_input_enter)
		keyboard.text_input_cancel.connect(_text_input_cancel)

	var canvas := _get_canvas()
	if canvas != null:
		canvas.visibility_changed.connect(_on_BeatSaverPanel_visibility_changed)

	if main_menu_ref != null:
		main_menu_ref.song_list_changed.connect(on_song_list_changed)

	_update_query_controls()
	_update_details()
	_update_status()

func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	if not _download_queue.is_empty():
		_update_download_progress()
	var playing := _is_preview_playing()
	if playing != _preview_shown_playing:
		_preview_shown_playing = playing
		preview_button.text = "Stop" if playing else "Preview"
		preview_button.icon = BeatSaverIcons.get_icon("stop" if playing else "play")

func _get_canvas() -> OQ_UI2DCanvas:
	var n: Node = self
	while n != null:
		if n is OQ_UI2DCanvas: return n as OQ_UI2DCanvas
		n = n.get_parent()
	return null

# override hide() method to handle case where UI is inside a OQ_UI2DCanvas
func _hide() -> void:
	var canvas := _get_canvas()
	if canvas != null:
		canvas.hide()
	else:
		visible = false

# override show() method to handle case where UI is inside a OQ_UI2DCanvas
func _show() -> void:
	var canvas := _get_canvas()
	if canvas != null:
		canvas.show()
	else:
		visible = true
	_on_BeatSaverPanel_visibility_changed()

func _redraw() -> void:
	var canvas := _get_canvas()
	if canvas != null: canvas._input_update()

func _on_BeatSaverPanel_visibility_changed() -> void:
	if _is_first_show:
		_is_first_show = false
		_start_search()

func _on_close_pressed() -> void:
	if _is_preview_playing() and _preview_map != null:
		main_menu_ref._on_stop_prev_timeout()
	_hide()

# --- search ---------------------------------------------------------------

func is_downloaded(m: BeatSaverMap) -> bool:
	if _downloaded_now.has(m.version_hash): return true
	return main_menu_ref != null and main_menu_ref.all_song_hashes.has(m.version_hash)

# runs a text search; also used by tests
func search(text: String) -> void:
	_push_back_stack()
	query = Query.new()
	query.text = text.strip_edges()
	_start_search()

func _push_back_stack() -> void:
	back_stack.push_back(query.duplicate_query())
	if back_stack.size() > MAX_BACK_STACK_DEPTH:
		back_stack.pop_front()

func _start_search() -> void:
	search_request.cancel_request()
	_maps.clear()
	_clear_rows()
	_cover_queue.clear()
	_next_page = 0
	_total = 0
	_end_reached = false
	_loading = false
	_empty_pages = 0
	_error = ""
	results.scroll_vertical = 0
	_select(null)
	_update_query_controls()
	_request_next_page()

func _request_next_page() -> void:
	if _loading or _end_reached: return
	var url := API_URL % [_next_page, filters.to_query(query.text, query.mapper_id, PAGE_SIZE)]
	var err := search_request.request(url, HTTP_HEADERS)
	if err != OK:
		_error = "Could not start the request (%d)" % err
		_update_list_footer()
		return
	_loading = true
	_error = ""
	_update_list_footer()
	_update_status()

func _on_search_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_loading = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_error = "BeatSaver is not reachable (%s)" % (("HTTP %d" % response_code) if result == HTTPRequest.RESULT_SUCCESS else "error %d" % result)
		vr.log_warning("BeatSaver search failed: result %d, HTTP %d" % [result, response_code])
		_update_list_footer()
		_update_status()
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not json is Dictionary:
		_error = "Unexpected answer from BeatSaver"
		_update_list_footer()
		return
	var data := json as Dictionary
	var info := Utils.get_dict(data, "info", {})
	_total = int(Utils.get_float(info, "total", _total))
	var docs := Utils.get_array(data, "docs", [])
	_next_page += 1
	if docs.size() < PAGE_SIZE:
		_end_reached = true
	var added := 0
	for doc: Variant in docs:
		if not doc is Dictionary: continue
		var m := BeatSaverMap.from_json(doc as Dictionary)
		if m == null: continue
		_maps.append(m)
		if filters.accepts(m, is_downloaded(m)):
			_add_row(m)
			added += 1
	_empty_pages = 0 if added > 0 else _empty_pages + 1
	_update_list_footer()
	_update_status()
	_redraw()
	# keep loading while the page is not filled (client side filters may hide
	# most of a page), but don't scan the whole catalog for nothing
	if not _end_reached and _empty_pages < MAX_EMPTY_PAGES:
		_check_prefetch.call_deferred()

func _check_prefetch() -> void:
	if _loading or _end_reached or _empty_pages >= MAX_EMPTY_PAGES or not _error.is_empty(): return
	if not is_visible_in_tree(): return
	var bar := results.get_v_scroll_bar()
	var row_h := 140.0
	var remaining := bar.max_value - (bar.value + bar.page)
	if remaining < row_h * PREFETCH_ROWS:
		_request_next_page()

func _on_results_scrolled(_value: float) -> void:
	if _empty_pages >= MAX_EMPTY_PAGES:
		return
	_check_prefetch()

func _clear_rows() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()

func _add_row(m: BeatSaverMap) -> void:
	var row := RowScene.instantiate() as BeatSaverMapRow
	row.button_group = _row_group
	results_list.add_child(row)
	# keep the message / "load more" button at the end
	results_list.move_child(row, _rows.size())
	row.setup(m)
	row.set_status(_download_state_text(m), is_downloaded(m))
	row.pressed.connect(_select.bind(m))
	_rows.append(row)
	UI_AudioEngine.attach_button(row)
	if _cover_cache.has(m.cover_url):
		row.set_cover(_cover_cache[m.cover_url] as Texture2D)
	elif not m.cover_url.is_empty():
		_cover_queue.append(m.cover_url)
		_pump_covers()

# re-applies the client side filters to everything loaded so far
func _refilter() -> void:
	var selected := _selected
	_clear_rows()
	for m in _maps:
		if filters.accepts(m, is_downloaded(m)):
			_add_row(m)
	if selected != null and _row_for(selected) != null:
		_row_for(selected).set_pressed_no_signal(true)
	_empty_pages = 0
	_update_list_footer()
	_update_status()
	_check_prefetch.call_deferred()

func _row_for(m: BeatSaverMap) -> BeatSaverMapRow:
	for r in _rows:
		if r.map == m: return r
	return null

func _update_list_footer() -> void:
	var msg := ""
	if not _error.is_empty():
		msg = _error
	elif _loading:
		msg = "Loading…"
	elif _rows.is_empty():
		if _maps.is_empty():
			msg = "No maps found. Try other search words or fewer filters."
		else:
			msg = "All %d loaded maps are hidden by the filters." % _maps.size()
	elif _end_reached:
		msg = "End of results"
	list_message.text = msg
	list_message.visible = not msg.is_empty()
	# loading continues automatically when scrolling; the button is a fallback
	load_more_button.visible = not _loading and not _end_reached
	load_more_button.text = "Retry" if not _error.is_empty() else "Load more"

func _update_status() -> void:
	var parts: Array[String] = []
	if _total > 0 or not _maps.is_empty():
		parts.append("%s %s" % [_format_thousands(_total), "result" if _total == 1 else "results"])
		parts.append("%d shown" % _rows.size())
		var hidden := _maps.size() - _rows.size()
		if hidden > 0:
			parts.append("%d hidden by filters" % hidden)
	elif _loading:
		parts.append("Searching…")
	status_label.text = "  ·  ".join(parts)

	if not _download_queue.is_empty():
		var current := _download_queue[0]
		queue_label.text = "Downloading %s%s" % [current.title(),
			("  (+%d queued)" % (_download_queue.size() - 1)) if _download_queue.size() > 1 else ""]
	else:
		queue_label.text = _last_download_message

static func _format_thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

# --- query controls (search box, back, mapper) -----------------------------

func _update_query_controls() -> void:
	back_button.disabled = back_stack.is_empty()
	var label := ""
	if query.mapper_id >= 0:
		label = "Maps by %s" % query.mapper_name
		if not query.text.is_empty(): label += ":  " + query.text
	else:
		label = query.text
	search_button.text = SEARCH_PLACEHOLDER if label.is_empty() else label
	search_button.add_theme_color_override("font_color", Color(0.55, 0.584, 0.659) if label.is_empty() else Color("e9edf5"))
	clear_button.disabled = label.is_empty()

func _on_search_pressed() -> void:
	if keyboard == null: return
	_awaiting_keyboard = true
	keyboard._show()
	keyboard._text_edit.text = query.text
	keyboard._text_edit.set_caret_column(query.text.length())
	keyboard._text_edit.grab_focus()

func _text_input_enter(text: String) -> void:
	if not _awaiting_keyboard: return # the keyboard is shared with other panels
	_awaiting_keyboard = false
	keyboard._hide()
	var q := query.duplicate_query()
	q.text = text.strip_edges()
	_push_back_stack()
	query = q
	_start_search()

func _text_input_cancel() -> void:
	if not _awaiting_keyboard: return
	_awaiting_keyboard = false
	keyboard._hide()

func _on_clear_pressed() -> void:
	if query.text.is_empty() and query.mapper_id < 0: return
	_push_back_stack()
	query = Query.new()
	_start_search()

func _on_back_pressed() -> void:
	if back_stack.is_empty(): return
	query = back_stack.pop_back()
	_start_search()

func _on_mapper_pressed() -> void:
	if _selected == null or _selected.uploader_id < 0: return
	_push_back_stack()
	query = Query.new()
	query.mapper_id = _selected.uploader_id
	query.mapper_name = _selected.uploader_name
	_start_search()

# --- details ----------------------------------------------------------------

func _show_tab(show_filters: bool) -> void:
	filters_page.visible = show_filters
	details_page.visible = not show_filters
	filters_tab.set_pressed_no_signal(show_filters)
	details_tab.set_pressed_no_signal(not show_filters)

func _select(m: BeatSaverMap) -> void:
	_selected = m
	details_tab.disabled = m == null
	if m == null:
		_show_tab(true)
		_update_details()
		return
	_show_tab(false)
	_update_details()
	if Settings.audio_master > 0 and Settings.audio_music_preview > 0:
		_play_preview(m)

func _update_details() -> void:
	var m := _selected
	if m == null:
		return
	detail_title.text = m.title()
	detail_artist.text = m.song_author_name if not m.song_author_name.is_empty() else "Unknown artist"
	detail_mapper.text = "Mapped by %s" % m.level_author_name
	if m.uploader_name != m.level_author_name and not m.uploader_name.is_empty():
		detail_mapper.text += "  (uploaded by %s)" % m.uploader_name
	detail_cover.texture = _cover_cache.get(m.cover_url, preload("res://game/data/beepsaber_logo.png"))
	mapper_button.disabled = m.uploader_id < 0 or query.mapper_id == m.uploader_id
	mapper_button.tooltip_text = "More maps by %s" % m.uploader_name

	for c in detail_badges.get_children(): c.queue_free()
	if m.ranked: detail_badges.add_child(BeatSaverMapRow.make_chip("Ranked", BeatSaverMapRow.BADGE_RANKED))
	elif m.qualified: detail_badges.add_child(BeatSaverMapRow.make_chip("Qualified", BeatSaverMapRow.BADGE_RANKED, false))
	if m.curated: detail_badges.add_child(BeatSaverMapRow.make_chip("Curated", BeatSaverMapRow.BADGE_CURATED))
	if m.uploader_verified: detail_badges.add_child(BeatSaverMapRow.make_chip("Verified mapper", BeatSaverMapRow.BADGE_CURATED, false))
	if m.automapper: detail_badges.add_child(BeatSaverMapRow.make_chip("Auto-mapped", BeatSaverMapRow.SUPPORTED_MOD, false))
	if is_downloaded(m): detail_badges.add_child(BeatSaverMapRow.make_chip("Downloaded", BeatSaverMapRow.STATUS_DOWNLOADED))

	for c in stats_grid.get_children(): c.queue_free()
	var nps := "%.1f" % m.max_nps()
	if m.max_nps() - m.min_nps() >= 0.1:
		nps = "%.1f – %.1f" % [m.min_nps(), m.max_nps()]
	var mods := m.mods()
	var mods_text := "none"
	if not mods.is_empty():
		var parts: Array[String] = []
		for mod in mods:
			parts.append(BeatSaverMapRow.short_mod_name(mod) + ("" if BeatSaverMap.is_mod_supported(mod) else " (unsupported)"))
		mods_text = ", ".join(parts)
	var stats := [
		["Length", BeatSaverMap.format_duration(m.duration)], ["BPM", BeatSaverMapRow._format_bpm(m.bpm)],
		["Rating", "%d%%" % roundi(m.score * 100.0)], ["Votes", "%s up  ·  %s down" % [_format_thousands(m.upvotes), _format_thousands(m.downvotes)]],
		["NPS", nps], ["Uploaded", m.upload_date()],
		["Key", m.id], ["Mods", mods_text],
	]
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
		if s[0] == "Rating":
			v.add_theme_color_override("font_color", BeatSaverMap.rating_color(m.score))
		if s[0] == "Mods" and not mods.is_empty():
			v.tooltip_text = mods_text
			if m.needs_unsupported_mod():
				v.add_theme_color_override("font_color", BeatSaverMapRow.UNSUPPORTED)
		stats_grid.add_child(k)
		stats_grid.add_child(v)

	var lines: Array[String] = []
	var by_char := m.diffs_by_characteristic()
	for ch: String in by_char:
		var entries: Array[String] = []
		for d: BeatSaverMap.Diff in by_char[ch]:
			var col := (BeatSaverMap.DIFFICULTY_COLORS.get(d.difficulty, Color.WHITE) as Color).lightened(0.2)
			var extra := ""
			if d.ne or d.vivify:
				extra = " [color=#ff5468](%s)[/color]" % ("Vivify" if d.vivify else "Noodle")
			entries.append("[color=#%s]%s[/color] [color=#8c95a8]%.1f[/color]%s" % [
				col.to_html(false), BeatSaverMap.DIFFICULTY_NAMES.get(d.difficulty, d.difficulty), d.nps, extra])
		lines.append("[color=#8c95a8]%s:[/color]  %s" % [BeatSaverMap.CHARACTERISTIC_NAMES.get(ch, ch), "   ".join(entries)])
	diffs_label.text = "\n".join(lines)
	description.text = m.description if not m.description.strip_edges().is_empty() else "No description."
	description.scroll_to_line(0)
	_update_download_controls()

# --- downloads ---------------------------------------------------------------

func _download_state_text(m: BeatSaverMap) -> String:
	var idx := _download_queue.find(m)
	if idx == 0: return "Downloading"
	if idx > 0: return "Queued"
	return ""

func _update_download_controls() -> void:
	var m := _selected
	if m == null: return
	var idx := _download_queue.find(m)
	if is_downloaded(m):
		download_button.text = "Downloaded"
		download_button.icon = BeatSaverIcons.get_icon("check")
		download_button.disabled = true
	elif idx >= 0:
		# while downloading the button shows the progress (see _update_download_progress)
		download_button.text = "0%" if idx == 0 else "Queued"
		download_button.icon = BeatSaverIcons.get_icon("download")
		download_button.disabled = true
	else:
		download_button.text = "Download"
		download_button.icon = BeatSaverIcons.get_icon("download")
		download_button.disabled = m.download_url.is_empty()
	download_status.visible = idx >= 0
	if idx > 0:
		download_progress.value = 0.0
		download_label.text = "queued"

func _update_download_progress() -> void:
	var total := download_request.get_body_size()
	var done := download_request.get_downloaded_bytes()
	var frac := clampf(float(done) / total, 0.0, 1.0) if total > 0 else 0.0
	var text := ("%d%%" % roundi(frac * 100.0)) if total > 0 else "%.1f MB" % (done / 1048576.0)
	var current := _download_queue[0]
	var row := _row_for(current)
	if row != null: row.set_status(text, false)
	if _selected == current:
		download_progress.value = frac
		download_label.text = text
		download_button.text = text

func _on_download_pressed() -> void:
	if _selected == null or is_downloaded(_selected) or _download_queue.has(_selected): return
	OS.request_permissions()
	_download_queue.append(_selected)
	var row := _row_for(_selected)
	if row != null: row.set_status(_download_state_text(_selected), false)
	if _download_queue.size() == 1:
		_download_next()
	_update_download_controls()
	_update_status()

func _download_next() -> void:
	while not _download_queue.is_empty():
		var m := _download_queue[0]
		var err := download_request.request(m.download_url, HTTP_HEADERS)
		if err == OK:
			_last_download_message = ""
			break
		_last_download_message = "Download of %s failed (%d)" % [m.title(), err]
		_download_queue.pop_front()
		_refresh_map_state(m)
	_update_status()

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _download_queue.is_empty(): return
	var m: BeatSaverMap = _download_queue.pop_front()
	if body.slice(0, 15) == "<!DOCTYPE html>".to_utf8_buffer():
		result = -1
	var error := ""
	if result != HTTPRequest.RESULT_SUCCESS:
		error = "error %d%s" % [result, " (invalid URL or server down)" if result == -1 else ""]
	elif response_code != 200:
		error = "HTTP %d" % response_code
	else:
		error = _install_zip(m, body)

	if error.is_empty():
		_downloaded_now[m.version_hash] = true
		_last_download_message = "Downloaded %s" % m.title()
	else:
		_last_download_message = "Download of %s failed: %s" % [m.title(), error]
		vr.log_info("BeatSaver download failed: " + _last_download_message)

	_refresh_map_state(m)
	if _download_queue.is_empty():
		# reload the song list of the main menu (emits song_list_changed)
		if not _downloaded_now.is_empty() and main_menu_ref != null:
			main_menu_ref._on_LoadPlaylists_Button_pressed()
	_download_next()
	_update_status()
	_redraw()

func _refresh_map_state(m: BeatSaverMap) -> void:
	var row := _row_for(m)
	if row != null:
		row.set_status(_download_state_text(m), is_downloaded(m))
	if _selected == m:
		_update_details()

# writes the zip into the songs folder, named by the map hash so there are
# no clashes or issues with special characters in names. Returns an error.
func _install_zip(m: BeatSaverMap, body: PackedByteArray) -> String:
	var tempdir := Constants.APPDATA_PATH + "temp"
	if DirAccess.make_dir_recursive_absolute(tempdir) != OK:
		return "can't create '%s'" % tempdir
	var zippath := tempdir + "/%s.zip" % m.version_hash
	var file := FileAccess.open(zippath, FileAccess.WRITE)
	if file == null:
		vr.log_file_error(FileAccess.get_open_error(), zippath, "BeatSaverPanel._install_zip")
		return "can't write '%s'" % zippath
	file.store_buffer(body)
	file.close()
	var song_out_dir := Constants.APPDATA_PATH + "Songs/%s/" % m.version_hash
	var error := ""
	if DirAccess.make_dir_recursive_absolute(song_out_dir) != OK:
		error = "can't create '%s'" % song_out_dir
	else:
		Utils.unzip(zippath, song_out_dir)
	DirAccess.remove_absolute(zippath)
	return error

func on_song_list_changed() -> void:
	if filters.hide_downloaded:
		_refilter()
		return
	for r in _rows:
		r.set_status(_download_state_text(r.map), is_downloaded(r.map))
	if _selected != null:
		_update_details()

# --- preview ------------------------------------------------------------------

func _is_preview_playing() -> bool:
	return main_menu_ref != null and main_menu_ref.song_preview.playing and _preview_map != null

func _on_preview_pressed() -> void:
	if _is_preview_playing():
		preview_request.cancel_request()
		main_menu_ref._on_stop_prev_timeout()
		_preview_map = null
	elif _selected != null:
		_play_preview(_selected)

func _play_preview(m: BeatSaverMap) -> void:
	if m.preview_url.is_empty(): return
	preview_request.cancel_request()
	_preview_map = m
	preview_request.request(m.preview_url, HTTP_HEADERS)

func _on_preview_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and main_menu_ref != null:
		# BeatSaver has all its previews in mp3 format
		main_menu_ref.play_preview(body, 0, -1, "mp3")

# --- covers ---------------------------------------------------------------------

func _pump_covers() -> void:
	for r in _cover_requests:
		if _cover_queue.is_empty(): return
		if _cover_busy.has(r): continue
		var url: String = _cover_queue.pop_front()
		if _cover_cache.has(url):
			_apply_cover(url)
			continue
		if r.request(url, HTTP_HEADERS) == OK:
			_cover_busy[r] = url

func _on_cover_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, r: HTTPRequest) -> void:
	var url: String = _cover_busy.get(r, "")
	_cover_busy.erase(r)
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and not url.is_empty():
		var img := Image.new()
		var err := img.load_jpg_from_buffer(body)
		if err != OK: err = img.load_png_from_buffer(body)
		if err != OK: err = img.load_webp_from_buffer(body)
		if err == OK:
			if _cover_cache.size() >= MAX_COVER_CACHE:
				_cover_cache.clear()
			img.generate_mipmaps()
			_cover_cache[url] = ImageTexture.create_from_image(img)
			_apply_cover(url)
	_pump_covers()
	_redraw()

func _apply_cover(url: String) -> void:
	var tex := _cover_cache.get(url) as Texture2D
	for row in _rows:
		if row.map.cover_url == url: row.set_cover(tex)
	if _selected != null and _selected.cover_url == url:
		detail_cover.texture = tex

# --- filters ----------------------------------------------------------------------

func _init_filter_controls() -> void:
	sort_selector.clear()
	for s: Array in BeatSaverFilters.SORTS:
		sort_selector.add_item(s[0])
	min_nps.clear()
	for v in BeatSaverFilters.NPS_MIN_OPTIONS:
		min_nps.add_item("Any" if v == 0 else "%d" % v)
	max_nps.clear()
	for v in BeatSaverFilters.NPS_MAX_OPTIONS:
		max_nps.add_item("Any" if v == 0 else "%d" % v)
	min_length.clear()
	for v in BeatSaverFilters.LENGTH_MIN_OPTIONS:
		min_length.add_item("Any" if v == 0 else BeatSaverMap.format_duration(v))
	max_length.clear()
	for v in BeatSaverFilters.LENGTH_MAX_OPTIONS:
		max_length.add_item("Any" if v == 0 else BeatSaverMap.format_duration(v))
	min_rating.clear()
	for v in BeatSaverFilters.RATING_OPTIONS:
		min_rating.add_item("Any" if v == 0 else "%d%% or better" % roundi(v * 100))
	difficulty.clear()
	for v in BeatSaverFilters.DIFFICULTY_OPTIONS:
		difficulty.add_item("Any" if v.is_empty() else "Has " + str(BeatSaverMap.DIFFICULTY_NAMES[v]))

	# bind() appends the flag after unbind() dropped the signal argument
	sort_selector.item_selected.connect(_on_filter_control_changed.bind(true).unbind(1))
	for o: OptionButton in [min_nps, max_nps, min_length, max_length, min_rating]:
		o.item_selected.connect(_on_filter_control_changed.bind(true).unbind(1))
	difficulty.item_selected.connect(_on_filter_control_changed.bind(false).unbind(1))
	for c: CheckButton in [hide_unsupported, only_ranked, only_curated, only_verified, include_auto]:
		c.toggled.connect(_on_filter_control_changed.bind(true).unbind(1))
	hide_downloaded.toggled.connect(_on_filter_control_changed.bind(false).unbind(1))

func _sync_filter_controls() -> void:
	_updating_controls = true
	sort_selector.select(filters.sort)
	min_nps.select(maxi(0, BeatSaverFilters.NPS_MIN_OPTIONS.find(filters.min_nps)))
	max_nps.select(maxi(0, BeatSaverFilters.NPS_MAX_OPTIONS.find(filters.max_nps)))
	min_length.select(maxi(0, BeatSaverFilters.LENGTH_MIN_OPTIONS.find(filters.min_length)))
	max_length.select(maxi(0, BeatSaverFilters.LENGTH_MAX_OPTIONS.find(filters.max_length)))
	min_rating.select(maxi(0, BeatSaverFilters.RATING_OPTIONS.find(filters.min_rating)))
	difficulty.select(maxi(0, BeatSaverFilters.DIFFICULTY_OPTIONS.find(filters.difficulty)))
	hide_unsupported.button_pressed = filters.hide_unsupported_mods
	hide_downloaded.button_pressed = filters.hide_downloaded
	only_ranked.button_pressed = filters.only_ranked
	only_curated.button_pressed = filters.only_curated
	only_verified.button_pressed = filters.only_verified
	include_auto.button_pressed = filters.include_automapped
	_updating_controls = false
	_update_filters_tab()

func _read_filter_controls() -> void:
	filters.sort = sort_selector.selected
	filters.min_nps = BeatSaverFilters.NPS_MIN_OPTIONS[maxi(0, min_nps.selected)]
	filters.max_nps = BeatSaverFilters.NPS_MAX_OPTIONS[maxi(0, max_nps.selected)]
	filters.min_length = BeatSaverFilters.LENGTH_MIN_OPTIONS[maxi(0, min_length.selected)]
	filters.max_length = BeatSaverFilters.LENGTH_MAX_OPTIONS[maxi(0, max_length.selected)]
	filters.min_rating = BeatSaverFilters.RATING_OPTIONS[maxi(0, min_rating.selected)]
	filters.difficulty = BeatSaverFilters.DIFFICULTY_OPTIONS[maxi(0, difficulty.selected)]
	filters.hide_unsupported_mods = hide_unsupported.button_pressed
	filters.hide_downloaded = hide_downloaded.button_pressed
	filters.only_ranked = only_ranked.button_pressed
	filters.only_curated = only_curated.button_pressed
	filters.only_verified = only_verified.button_pressed
	filters.include_automapped = include_auto.button_pressed

var _pending_server_refresh := false

func _on_filter_control_changed(needs_new_search: bool) -> void:
	if _updating_controls: return
	_read_filter_controls()
	filters.save()
	_update_filters_tab()
	if needs_new_search:
		# coalesce quick changes into one request
		_pending_server_refresh = true
		filter_debounce.start()
	elif not _pending_server_refresh:
		_refilter()

func _on_filter_debounce() -> void:
	_pending_server_refresh = false
	_start_search()

func _on_reset_filters() -> void:
	var sort := filters.sort
	filters.reset()
	filters.sort = sort
	filters.save()
	_sync_filter_controls()
	_start_search()

func _update_filters_tab() -> void:
	var n := filters.active_count()
	filters_tab.text = "Filters" if n == 0 else "Filters (%d)" % n

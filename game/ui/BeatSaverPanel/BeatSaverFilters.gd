# Search filters of the in-game BeatSaver browser. Most are sent to the
# /search/text endpoint of api.beatsaver.com, the rest (hide downloaded,
# difficulty) are applied to the results on the client.
# The last used filters are stored in user://beatsaver_filters.json.
extends RefCounted
class_name BeatSaverFilters

const SAVE_PATH := "user://beatsaver_filters.json"

# label, API "order", ascending
const SORTS: Array[Array] = [
	["Best rated", "Rating", false],
	["Newest", "Latest", false],
	["Oldest", "Latest", true],
	["Recently curated", "Curated", false],
	["Relevance", "Relevance", false],
	["Random", "Random", false],
]
# 0 means "any" for all the option lists below
const NPS_MIN_OPTIONS: Array[float] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10]
const NPS_MAX_OPTIONS: Array[float] = [0, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15]
const LENGTH_MIN_OPTIONS: Array[int] = [0, 60, 90, 120, 150, 180, 240]
const LENGTH_MAX_OPTIONS: Array[int] = [0, 120, 150, 180, 240, 300, 420, 600]
const RATING_OPTIONS: Array[float] = [0, 0.5, 0.6, 0.7, 0.8, 0.9]
const DIFFICULTY_OPTIONS: Array[String] = ["", "Easy", "Normal", "Hard", "Expert", "ExpertPlus"]

var sort := 0 # index into SORTS
var min_nps := 0.0
var max_nps := 0.0
var min_length := 0
var max_length := 0
var min_rating := 0.0
var difficulty := ""
var hide_unsupported_mods := true
var hide_downloaded := false
var only_ranked := false
var only_curated := false
var only_verified := false
var include_automapped := false

const _KEYS: Array[String] = [
	"sort", "min_nps", "max_nps", "min_length", "max_length", "min_rating", "difficulty",
	"hide_unsupported_mods", "hide_downloaded", "only_ranked", "only_curated",
	"only_verified", "include_automapped",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in _KEYS:
		d[k] = get(k)
	return d

func from_dict(d: Dictionary) -> void:
	var defaults := BeatSaverFilters.new()
	for k in _KEYS:
		var def: Variant = defaults.get(k)
		var v: Variant = d.get(k, def)
		if typeof(def) == TYPE_INT and typeof(v) == TYPE_FLOAT:
			v = int(v)
		if typeof(v) == typeof(def):
			set(k, v)
	sort = clampi(sort, 0, SORTS.size() - 1)
	if not DIFFICULTY_OPTIONS.has(difficulty): difficulty = ""

func reset() -> void:
	from_dict({})

func load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		from_dict(data as Dictionary)

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		vr.log_warning("could not save %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))

func sort_label() -> String:
	return SORTS[sort][0]

# number of filters that differ from the defaults (shown on the Filters tab)
func active_count() -> int:
	var defaults := BeatSaverFilters.new()
	var n := 0
	for k in _KEYS:
		if k != "sort" and get(k) != defaults.get(k): n += 1
	return n

# query string for /search/text/{page}, see https://api.beatsaver.com/docs/
#  automapper: omitted = no AI maps, true = both, false = only AI maps
#  noodle=false excludes Noodle Extensions maps (incl. Vivify ones); don't
#  combine it with other mod flags, the API then ORs them.
func to_query(text: String, collaborator_id: int, page_size: int) -> String:
	var p: Array[String] = []
	p.append("q=" + text.uri_encode())
	p.append("order=" + str(SORTS[sort][1]))
	if SORTS[sort][2]: p.append("ascending=true")
	p.append("pageSize=%d" % page_size)
	if collaborator_id >= 0: p.append("collaborator=%d" % collaborator_id)
	if min_nps > 0: p.append("minNps=%s" % min_nps)
	if max_nps > 0: p.append("maxNps=%s" % max_nps)
	if min_length > 0: p.append("minDuration=%d" % min_length)
	if max_length > 0: p.append("maxDuration=%d" % max_length)
	if min_rating > 0: p.append("minRating=%s" % min_rating)
	if hide_unsupported_mods: p.append("noodle=false")
	if only_ranked: p.append("leaderboard=Ranked")
	if only_curated: p.append("curated=true")
	if only_verified: p.append("verified=true")
	if include_automapped: p.append("automapper=true")
	return "&".join(p)

# filters the API can't do
func accepts(map: BeatSaverMap, downloaded: bool) -> bool:
	if hide_downloaded and downloaded: return false
	if hide_unsupported_mods and map.needs_unsupported_mod(): return false
	if difficulty != "" and not map.has_difficulty(difficulty): return false
	return true

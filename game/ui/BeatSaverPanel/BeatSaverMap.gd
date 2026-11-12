# One map ("beatmap") as returned by the BeatSaver API (api.beatsaver.com),
# reduced to what the in-game browser needs.
extends RefCounted
class_name BeatSaverMap

const DIFFICULTY_ORDER: Array[String] = ["Easy", "Normal", "Hard", "Expert", "ExpertPlus"]
const DIFFICULTY_NAMES := {
	"Easy": "Easy", "Normal": "Normal", "Hard": "Hard", "Expert": "Expert", "ExpertPlus": "Expert+",
}
const DIFFICULTY_SHORT := {
	"Easy": "E", "Normal": "N", "Hard": "H", "Expert": "Ex", "ExpertPlus": "Ex+",
}
const DIFFICULTY_COLORS := {
	"Easy": Color("3cb371"), "Normal": Color("4a9bff"), "Hard": Color("ff9a3c"),
	"Expert": Color("ff4f5e"), "ExpertPlus": Color("b061ff"),
}
const CHARACTERISTIC_NAMES := {
	"Standard": "Standard", "OneSaber": "One Saber", "NoArrows": "No Arrows",
	"90Degree": "90°", "360Degree": "360°", "Lightshow": "Lightshow", "Lawless": "Lawless",
	"Legacy": "Legacy",
}

# mods the game can play (keep in sync with MainMenu.SUPPORTED_MAP_MODS)
const MOD_CHROMA := "Chroma"
const MOD_ME := "Mapping Extensions"
const MOD_NOODLE := "Noodle Extensions"
const MOD_VIVIFY := "Vivify"
const MOD_CINEMA := "Cinema"

class Diff extends RefCounted:
	var characteristic: String
	var difficulty: String
	var nps: float
	var njs: float
	var notes: int
	var seconds: float
	var chroma: bool
	var me: bool
	var ne: bool
	var vivify: bool
	var cinema: bool

var id: String
var name: String
var description: String
var song_name: String
var song_sub_name: String
var song_author_name: String
var level_author_name: String
var bpm: float
var duration: int
var uploader_id := -1
var uploader_name: String
var uploader_verified := false
var upvotes: int
var downvotes: int
var score: float # 0..1 (BeatSaver's rating)
var uploaded: String # ISO date
var automapper := false
var ranked := false # ScoreSaber or BeatLeader ranked
var qualified := false
var curated := false
var tags: PackedStringArray

var version_hash: String
var download_url: String
var cover_url: String
var preview_url: String
var diffs: Array[Diff] = []

static func from_json(doc: Dictionary) -> BeatSaverMap:
	var versions := Utils.get_array(doc, "versions", [])
	if versions.is_empty() or not versions[0] is Dictionary:
		return null
	var m := BeatSaverMap.new()
	m.id = Utils.get_str(doc, "id", "")
	m.name = Utils.get_str(doc, "name", "")
	m.description = Utils.get_str(doc, "description", "")
	var uploader := Utils.get_dict(doc, "uploader", {})
	m.uploader_id = int(Utils.get_float(uploader, "id", -1))
	m.uploader_name = Utils.get_str(uploader, "name", "")
	m.uploader_verified = Utils.get_bool(uploader, "verifiedMapper", false)
	var metadata := Utils.get_dict(doc, "metadata", {})
	m.song_name = Utils.get_str(metadata, "songName", m.name)
	m.song_sub_name = Utils.get_str(metadata, "songSubName", "")
	m.song_author_name = Utils.get_str(metadata, "songAuthorName", "")
	m.level_author_name = Utils.get_str(metadata, "levelAuthorName", m.uploader_name)
	m.bpm = Utils.get_float(metadata, "bpm", 0.0)
	m.duration = int(Utils.get_float(metadata, "duration", 0.0))
	var stats := Utils.get_dict(doc, "stats", {})
	m.upvotes = int(Utils.get_float(stats, "upvotes", 0))
	m.downvotes = int(Utils.get_float(stats, "downvotes", 0))
	m.score = Utils.get_float(stats, "score", 0.0)
	m.uploaded = Utils.get_str(doc, "uploaded", Utils.get_str(doc, "createdAt", ""))
	m.automapper = Utils.get_bool(doc, "automapper", false)
	m.ranked = Utils.get_bool(doc, "ranked", false) or Utils.get_bool(doc, "blRanked", false)
	m.qualified = Utils.get_bool(doc, "qualified", false) or Utils.get_bool(doc, "blQualified", false)
	m.curated = doc.get("curator") is Dictionary or Utils.get_str(doc, "curatedAt", "") != ""
	for t: Variant in Utils.get_array(doc, "tags", []):
		if t is String: m.tags.append(t as String)

	# the first version is the current published one
	var version := versions[0] as Dictionary
	m.version_hash =Utils.get_str(version, "hash", "").to_lower()
	m.download_url = Utils.get_str(version, "downloadURL", "")
	m.cover_url = Utils.get_str(version, "coverURL", "")
	m.preview_url = Utils.get_str(version, "previewURL", "")
	for d: Variant in Utils.get_array(version, "diffs", []):
		if not d is Dictionary: continue
		var dd := d as Dictionary
		var diff := Diff.new()
		diff.characteristic = Utils.get_str(dd, "characteristic", "Standard")
		diff.difficulty = Utils.get_str(dd, "difficulty", "")
		diff.nps = Utils.get_float(dd, "nps", 0.0)
		diff.njs = Utils.get_float(dd, "njs", 0.0)
		diff.notes = int(Utils.get_float(dd, "notes", 0))
		diff.seconds = Utils.get_float(dd, "seconds", 0.0)
		diff.chroma = Utils.get_bool(dd, "chroma", false)
		diff.me = Utils.get_bool(dd, "me", false)
		diff.ne = Utils.get_bool(dd, "ne", false)
		diff.vivify = Utils.get_bool(dd, "vivify", false)
		diff.cinema = Utils.get_bool(dd, "cinema", false)
		m.diffs.append(diff)
	return m

func title() -> String:
	return song_name if song_sub_name.is_empty() else "%s %s" % [song_name, song_sub_name]

func min_nps() -> float:
	var v := INF
	for d in diffs:
		if d.characteristic != "Lightshow": v = minf(v, d.nps)
	return 0.0 if v == INF else v

func max_nps() -> float:
	var v := 0.0
	for d in diffs:
		v = maxf(v, d.nps)
	return v

func has_difficulty(difficulty: String) -> bool:
	for d in diffs:
		if d.difficulty == difficulty: return true
	return false

# difficulties present in any characteristic, easiest first
func difficulties() -> Array[String]:
	var out: Array[String] = []
	for name_ in DIFFICULTY_ORDER:
		if has_difficulty(name_): out.append(name_)
	return out

# characteristic name -> diffs sorted easiest first; Standard comes first
func diffs_by_characteristic() -> Dictionary:
	var out := {}
	for d in diffs:
		if not out.has(d.characteristic):
			out[d.characteristic] = []
		(out[d.characteristic] as Array).append(d)
	for k: String in out:
		(out[k] as Array).sort_custom(func(a: Diff, b: Diff) -> bool:
			return DIFFICULTY_ORDER.find(a.difficulty) < DIFFICULTY_ORDER.find(b.difficulty))
	if out.has("Standard"):
		var sorted := {"Standard": out["Standard"]}
		for k: String in out:
			if k != "Standard": sorted[k] = out[k]
		return sorted
	return out

# mods used by any difficulty, in display order
func mods() -> Array[String]:
	var out: Array[String] = []
	var flags := {MOD_CHROMA: false, MOD_ME: false, MOD_NOODLE: false, MOD_VIVIFY: false, MOD_CINEMA: false}
	for d in diffs:
		flags[MOD_CHROMA] = flags[MOD_CHROMA] or d.chroma
		flags[MOD_ME] = flags[MOD_ME] or d.me
		flags[MOD_NOODLE] = flags[MOD_NOODLE] or d.ne
		flags[MOD_VIVIFY] = flags[MOD_VIVIFY] or d.vivify
		flags[MOD_CINEMA] = flags[MOD_CINEMA] or d.cinema
	for k: String in flags:
		if flags[k]: out.append(k)
	return out

# true if the map needs a mod the game can't play (Noodle Extensions / Vivify)
func needs_unsupported_mod() -> bool:
	for d in diffs:
		if d.ne or d.vivify: return true
	return false

static func is_mod_supported(mod: String) -> bool:
	return mod != MOD_NOODLE and mod != MOD_VIVIFY

static func format_duration(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]

static func format_count(n: int) -> String:
	if n >= 1000000: return "%.1fM" % (n / 1000000.0)
	if n >= 10000: return "%dk" % (n / 1000)
	if n >= 1000: return "%.1fk" % (n / 1000.0)
	return str(n)

static func rating_color(score_: float) -> Color:
	if score_ >= 0.8: return Color("4cd07d")
	if score_ >= 0.6: return Color("e6c84a")
	return Color("ff6b6b")

func upload_date() -> String:
	return uploaded.substr(0, 10)

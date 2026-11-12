extends Node3D
class_name EndScore
# Score screen shown after a song: song info, grade, accuracy, score and record,
# badges, the name the highscore was saved under (with "Change name") and the
# Repeat / Main Menu buttons. Rendered on an OQ_UI2DCanvas.

signal mainmenu
signal repeat
signal change_name

const GRADE_COLORS := {
	"S": Color("ffd84d"), "A": Color("4dff9a"), "B": Color("4dc3ff"), "C": Color("b48cff"),
	"D": Color("ffa04d"), "E": Color("ff7a4d"), "F": Color("ff4d5e"),
}

@onready var canvas := $Canvas as OQ_UI2DCanvas
@onready var _title := _n("Title") as Label
@onready var _subtitle := _n("Subtitle") as Label
@onready var _grade := _n("Grade") as Label
@onready var _grade_caption := _n("GradeCaption") as Label
@onready var _ring := _n("AccuracyRing") as AccuracyRing
@onready var _score := _n("Score") as Label
@onready var _record := _n("Record") as Label
@onready var _full_combo := _n("FullComboBadge") as Control
@onready var _new_record := _n("NewRecordBadge") as Control
@onready var _name_row := _n("NameRow") as Control
@onready var _saved_as := _n("SavedAs") as Label
@onready var _repeat := _n("Repeat") as Button
@onready var _main_menu := _n("MainMenu") as Button
var _tween: Tween

# OQ_UI2DCanvas moves the panel into its SubViewport, which breaks %unique
# name lookups, so find the nodes by name below the canvas instead
func _n(node_name: String) -> Node:
	return ($Canvas as Node).find_child(node_name, true, false)

func _ready() -> void:
	_repeat.pressed.connect(func() -> void: repeat.emit())
	_main_menu.pressed.connect(func() -> void:
		set_buttons_disabled(true)
		mainmenu.emit())
	(_n("ChangeName") as Button).pressed.connect(func() -> void: change_name.emit())
	set_buttons_disabled(true)

func _show() -> void:
	show()
	canvas._show()

func _hide() -> void:
	canvas._hide()
	hide()

func set_buttons_disabled(disabled: bool) -> void:
	_repeat.disabled = disabled
	_main_menu.disabled = disabled

# player_name: the name the new highscore was saved under, "" if none was saved
func show_saved_name(player_name: String) -> void:
	_name_row.visible = not player_name.is_empty()
	_saved_as.text = "Saved as %s" % player_name

func show_score(score: int, record: int, percent: float, _song_string: String, is_full_combo: bool, is_new_record: bool) -> void:
	var info := Map.current_info
	var diff := Map.current_difficulty
	_title.text = info.song_name if info.song_sub_name.is_empty() else "%s %s" % [info.song_name, info.song_sub_name]
	_subtitle.text = "%s  ·  %s  ·  mapped by %s" % [info.song_author_name, diff.get_display_name(), info.level_author_name]

	var failed := percent < 0
	var grade := "F" if failed else _grade_for(percent)
	_grade.text = grade
	_grade.add_theme_color_override(&"font_color", GRADE_COLORS[grade.left(1)])
	_grade_caption.text = "FAILED" if failed else ("PERFECT" if percent >= 0.999 else "")
	_ring.ring_color = GRADE_COLORS[grade.left(1)]
	_ring.text_override = "–" if failed else ""
	_score.text = _format_int(score)
	_record.text = "Best  %s" % _format_int(maxi(record, score))
	_full_combo.visible = is_full_combo and not failed
	_new_record.visible = is_new_record

	# count the accuracy up and fade the details in
	_ring.value = 0.0
	_grade.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_ring, ^"value", maxf(percent, 0.0), 1.6)
	_tween.tween_property(_grade, ^"modulate:a", 1.0, 0.5)

static func _grade_for(percent: float) -> String:
	if percent >= 0.98: return "S"
	if percent >= 0.90: return "A"
	if percent >= 0.80: return "B"
	if percent >= 0.70: return "C"
	if percent >= 0.60: return "D"
	if percent >= 0.50: return "E"
	return "F"

static func _format_int(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if value < 0 else "") + s + out

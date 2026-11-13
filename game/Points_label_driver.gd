extends Node3D
class_name PointsLabelDriver

const HUD_PANEL = preload("res://game/ui/hud/HudPanel.gd")
const POINTS_SCENE: PackedScene = preload("res://game/points_label.tscn")

var points_label: Array[Node3D] = []
var current_point_label: int = 0
var _left_panel: HUD_PANEL
var _right_panel: HUD_PANEL
var _refresh_pending := false

func _ready() -> void:
	for i in range(4):
		var instance := POINTS_SCENE.instantiate() as Node3D
		points_label.append(instance)
		add_child(instance)
	_build_hud()

func _build_hud() -> void:
	var left_anchor := get_parent().get_node_or_null("Point_Label") as MeshInstance3D
	var right_anchor := get_parent().get_node_or_null("Multiplier_Label") as MeshInstance3D
	if left_anchor == null or right_anchor == null:
		return
	# Keep the existing TextMesh interfaces and game-state visibility controls.
	# Only their native child panels render; the old meshes remain valid sinks.
	left_anchor.layers = 0
	right_anchor.layers = 0
	left_anchor.look_at(Vector3(0.0, 1.65, Constants.PLAYER_Z), Vector3.UP, true)
	right_anchor.look_at(Vector3(0.0, 1.65, Constants.PLAYER_Z), Vector3.UP, true)
	_left_panel = HUD_PANEL.new()
	left_anchor.add_child(_left_panel)
	_left_panel.setup(false)
	_right_panel = HUD_PANEL.new()
	right_anchor.add_child(_right_panel)
	_right_panel.setup(true)
	Scoreboard.score_changed.connect(_queue_score_refresh)
	# A quarter-second cadence is sufficient for the song bar and avoids work
	# between hits. Glyph geometry is updated only when its displayed text changes.
	var clock := Timer.new()
	clock.wait_time = 0.25
	clock.autostart = true
	clock.timeout.connect(_refresh_song)
	add_child(clock)
	_refresh_score()
	_refresh_song()

func _queue_score_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	# Accuracy counters are updated after score_changed in the scoring singleton.
	# Read them after that call completes, without changing scoring order.
	_refresh_score.call_deferred()

func _refresh_score() -> void:
	_refresh_pending = false
	if not is_instance_valid(_left_panel) or not _left_panel.is_visible_in_tree():
		return
	var total := Scoreboard.right_notes + Scoreboard.wrong_notes
	var accuracy := clampf(Scoreboard.right_notes / total, 0.0, 1.0) if total > 0.0 else 1.0
	_left_panel.update_score(Scoreboard.points, Scoreboard.combo, accuracy)
	_right_panel.update_multiplier(Scoreboard.multiplier, Scoreboard.combo)
	_left_panel.set_accent(Map.color_left if Map.current_info != null else Settings.color_left)
	_right_panel.set_accent(Map.color_right if Map.current_info != null else Settings.color_right)

func _refresh_song() -> void:
	if not is_instance_valid(_right_panel) or not _right_panel.is_visible_in_tree():
		return
	var game := GlobalReferences.main_game_scene
	var duration := Map.current_info.get_length_seconds() if Map.current_info != null else 0.0
	var elapsed := 0.0
	if is_instance_valid(game) and game.is_node_ready():
		# Pausing stops the audio player, so its playback position is then zero.
		elapsed = game.pause_position if Scoreboard.paused else game.get_current_time()
	_right_panel.update_song(elapsed, duration)

func show_points(_position: Vector3, _rotation: float, value: String) -> void:
	if value == "0":
		value = "x"
	var color := Color(1,0,0) if value == "x" else Color(1,1,1)
	points_label[current_point_label].call(&"show_points", _position, _rotation, value, color)
	current_point_label += 1
	current_point_label %= 4

extends MeshInstance3D
## A single panel quad and native 3D glyphs: no offscreen viewport or redraw loop.

const PANEL_SHADER: Shader = preload("res://game/ui/hud/HudPanel.gdshader")
const BASE_FONT: FontFile = preload("res://OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf")
const WHITE := Color(0.95, 0.97, 1.0)
const MUTED := Color(0.63, 0.70, 0.81)

static var _hud_font: FontFile

var _surface: ShaderMaterial
var _combo: Label3D
var _score: Label3D
var _accuracy: Label3D
var _multiplier: Label3D
var _next_step: Label3D
var _hits: Label3D
var _elapsed: Label3D
var _duration: Label3D
var _last_ring := -1.0
var _last_song := -1.0
var _last_accent := Color.TRANSPARENT
var _last_points := -1
var _last_combo := -1
var _last_accuracy := -1.0
var _last_multiplier := -1
var _last_multiplier_combo := -1

func setup(is_multiplier: bool) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 0.8)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Draw the backing before its glyphs within the shared UI priority, even
	# when the tilted panel puts a label's origin farther from the camera.
	sorting_offset = -1.0
	_surface = ShaderMaterial.new()
	_surface.shader = PANEL_SHADER
	_surface.render_priority = 10
	_surface.set_shader_parameter(&"multiplier_panel", is_multiplier)
	material_override = _surface
	if is_multiplier:
		_multiplier = _label("x1", Vector2(-0.34, 0.08), 0.16)
		_label("MULTIPLIER", Vector2(0.235, 0.265), 0.052, MUTED)
		_next_step = _label("NEXT x2", Vector2(0.235, 0.115), 0.075)
		_hits = _label("0 / 10 HITS", Vector2(0.235, -0.015), 0.052, MUTED)
		_elapsed = _label("0:00", Vector2(-0.55, -0.305), 0.075, WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		_duration = _label("/ 0:00", Vector2(0.55, -0.305), 0.075, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_label("COMBO", Vector2(0.0, 0.29), 0.06, MUTED)
		_combo = _label("0", Vector2(0.0, 0.135), 0.22)
		_label("SCORE", Vector2(-0.55, -0.115), 0.052, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		_score = _label("0", Vector2(0.55, -0.115), 0.105, WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		_label("ACCURACY", Vector2(-0.55, -0.285), 0.052, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		_accuracy = _label("100.0%  S", Vector2(0.55, -0.285), 0.09, WHITE, HORIZONTAL_ALIGNMENT_RIGHT)

func _label(value: String, at: Vector2, height: float, color: Color = WHITE,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label3D:
	var glyphs := Label3D.new()
	glyphs.text = value
	glyphs.font = _get_hud_font()
	glyphs.font_size = 128
	glyphs.pixel_size = height / 128.0
	glyphs.position = Vector3(at.x, at.y, 0.006)
	glyphs.horizontal_alignment = alignment
	glyphs.modulate = color
	glyphs.outline_size = 0
	glyphs.shaded = false
	glyphs.double_sided = false
	glyphs.render_priority = 10
	glyphs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glyphs)
	return glyphs

static func _get_hud_font() -> FontFile:
	if _hud_font == null:
		# Share one MSDF atlas across both panels without changing the menu font
		# resource or requiring a font reimport.
		_hud_font = BASE_FONT.duplicate() as FontFile
		_hud_font.multichannel_signed_distance_field = true
		_hud_font.msdf_size = 64
	return _hud_font

func set_accent(color: Color) -> void:
	if color == _last_accent:
		return
	_last_accent = color
	# A small white lift keeps dark custom saber colours legible on the panel.
	_surface.set_shader_parameter(&"accent", color.lightened(0.22))

func update_score(points: int, combo: int, accuracy: float) -> void:
	if points == _last_points and combo == _last_combo and accuracy == _last_accuracy:
		return
	_last_points = points
	_last_combo = combo
	_last_accuracy = accuracy
	_set_text(_combo, str(combo))
	_set_text(_score, _format_score(points))
	_set_text(_accuracy, "%.1f%%  %s" % [accuracy * 100.0, _grade(accuracy)])

func update_multiplier(multiplier: int, combo: int) -> void:
	if multiplier == _last_multiplier and combo == _last_multiplier_combo:
		return
	_last_multiplier = multiplier
	_last_multiplier_combo = combo
	var factor := clampi(multiplier, 1, 8)
	_set_text(_multiplier, "x%d" % factor)
	# The current score model advances every ten hits, through all integer factors.
	var remaining_hits := maxi(combo, 0) % 10
	var progress := 1.0 if factor == 8 else float(remaining_hits) / 10.0
	_set_text(_next_step, "MAX" if factor == 8 else "NEXT x%d" % (factor + 1))
	_set_text(_hits, "MULTIPLIER" if factor == 8 else "%d / 10 HITS" % remaining_hits)
	if progress != _last_ring:
		_last_ring = progress
		_surface.set_shader_parameter(&"ring_progress", progress)

func update_song(elapsed: float, duration: float) -> void:
	var length := maxf(duration, 0.0)
	var time := clampf(elapsed, 0.0, length)
	_set_text(_elapsed, _format_time(time))
	_set_text(_duration, "/ %s" % _format_time(length))
	var progress := time / length if length > 0.0 else 0.0
	if progress != _last_song:
		_last_song = progress
		_surface.set_shader_parameter(&"song_progress", progress)

func _set_text(label: Label3D, value: String) -> void:
	if label.text != value:
		label.text = value

static func _format_time(time: float) -> String:
	var seconds := maxi(floori(time), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [seconds / 60, seconds % 60]

static func _format_score(points: int) -> String:
	var digits := str(absi(points))
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return ("-" if points < 0 else "") + digits + result

static func _grade(accuracy: float) -> String:
	# Match the thresholds used by the result screen.
	if accuracy >= 0.98: return "S"
	if accuracy >= 0.90: return "A"
	if accuracy >= 0.80: return "B"
	if accuracy >= 0.70: return "C"
	if accuracy >= 0.60: return "D"
	if accuracy >= 0.50: return "E"
	return "F"

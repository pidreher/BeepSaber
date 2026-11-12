@tool
extends Control
class_name AccuracyRing
# Circular progress ring with the percentage in the middle (score screen).

@export_range(0.0, 1.0) var value := 0.0:
	set(v):
		value = v
		queue_redraw()
@export var ring_color := Color("3f7cff"):
	set(v):
		ring_color = v
		queue_redraw()
@export var track_color := Color(1, 1, 1, 0.08)
@export var thickness := 22.0
@export var font_size := 44
@export var caption := "accuracy"
# shown instead of the percentage when not empty (e.g. "–" for a failed run)
@export var text_override := "":
	set(v):
		text_override = v
		queue_redraw()

func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - thickness / 2.0 - 2.0
	draw_arc(center, radius, 0.0, TAU, 96, track_color, thickness, true)
	if value > 0.0:
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * value, 96, ring_color, thickness, true)
	var font := get_theme_default_font()
	var text := text_override if not text_override.is_empty() else "%d%%" % roundi(value * 100.0)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(center.x - text_size.x / 2.0, center.y + font_size * 0.3), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	var cap_size := 20
	var cap := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, cap_size)
	draw_string(font, Vector2(center.x - cap.x / 2.0, center.y + font_size * 0.3 + cap_size + 6), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size, Color(0.55, 0.58, 0.66))

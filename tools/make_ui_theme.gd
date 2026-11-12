extends SceneTree
# Generates the Open Saber UI theme (game/ui/theme/open_saber_theme.tres) and its icons.
#   godot --headless --path . -s tools/make_ui_theme.gd
#
# All UI panels are rendered into SubViewports that are shown on quads in VR,
# so everything is sized generously: big fonts, big hit targets, thick scrollbars.

const OUT_DIR := "res://game/ui/theme/"

const BG := Color("0b0e16")
const CARD := Color("151a26")
const CARD_HI := Color("1d2433")
const LINE := Color(1, 1, 1, 0.07)
const TEXT := Color("e9edf5")
const MUTED := Color("8c95a8")
const ACCENT := Color("3f7cff")
const ACCENT_HI := Color("6b9bff")
const PLAY := Color("ff3d5a")
const PLAY_HI := Color("ff6b80")

const FONT_SIZE := 26

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var t := Theme.new()

	var font := load("res://OQ_Toolkit/OQ_UI2D/theme/Roboto-Medium.ttf") as FontFile
	t.default_font = font
	t.default_font_size = FONT_SIZE
	var bold := FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.6
	ResourceSaver.save(bold, OUT_DIR + "open_saber_bold.tres")
	bold = load(OUT_DIR + "open_saber_bold.tres")

	var icons := {
		"toggle_on": _pill_icon(true), "toggle_off": _pill_icon(false),
		"check_on": _box_icon(true), "check_off": _box_icon(false),
		"grabber": _circle_icon(34, TEXT), "grabber_hl": _circle_icon(34, ACCENT_HI),
		"arrow": _arrow_icon(),
		"star_on": _star_icon(true), "star_off": _star_icon(false),
	}
	var tex := {}
	for k: String in icons:
		tex[k] = ImageTexture.create_from_image(icons[k])

	# --- panels -------------------------------------------------------------
	t.set_stylebox("panel", "Panel", _box(BG, 28, 0, 2, Color(1, 1, 1, 0.10)))
	t.set_stylebox("panel", "PanelContainer", _box(CARD, 20, 20))
	t.set_stylebox("panel", "PopupPanel", _box(CARD, 20, 20, 2, LINE))
	t.set_stylebox("panel", "PopupMenu", _box(CARD_HI, 18, 12, 2, LINE))
	t.set_stylebox("panel", "TooltipPanel", _box(CARD_HI, 12, 12))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 22)
	# "Card" variation for grouping blocks inside a panel
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(CARD, 20, 20))

	# --- labels -------------------------------------------------------------
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 6)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", bold)
	t.set_font_size("font_size", "HeaderLabel", 38)
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", MUTED)
	t.set_font_size("font_size", "MutedLabel", 22)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 24)

	# --- buttons ------------------------------------------------------------
	for type in ["Button", "OptionButton", "MenuButton", "ColorPickerButton"]:
		t.set_stylebox("normal", type, _box(CARD_HI, 16, 14, 0, Color(), 22))
		t.set_stylebox("hover", type, _box(CARD_HI.lightened(0.12), 16, 14, 2, ACCENT, 22))
		t.set_stylebox("pressed", type, _box(ACCENT, 16, 14, 0, Color(), 22))
		t.set_stylebox("hover_pressed", type, _box(ACCENT_HI, 16, 14, 0, Color(), 22))
		t.set_stylebox("disabled", type, _box(Color(CARD, 0.6), 16, 14, 0, Color(), 22))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.6))
		t.set_constant("h_separation", type, 12)
	# dropdowns need the room for their text more than for padding
	t.set_stylebox("normal", "OptionButton", _box(CARD_HI, 16, 14, 0, Color(), 14))
	t.set_stylebox("hover", "OptionButton", _box(CARD_HI.lightened(0.12), 16, 14, 2, ACCENT, 14))
	t.set_stylebox("pressed", "OptionButton", _box(ACCENT, 16, 14, 0, Color(), 14))
	t.set_stylebox("disabled", "OptionButton", _box(Color(CARD, 0.6), 16, 14, 0, Color(), 14))
	t.set_icon("arrow", "OptionButton", tex["arrow"])
	t.set_constant("arrow_margin", "OptionButton", 14)
	# icons used by the main menu script (get_theme_icon(name, "MainMenu"))
	t.set_icon("star_on", "MainMenu", tex["star_on"])
	t.set_icon("star_off", "MainMenu", tex["star_off"])

	# primary call to action (Play)
	t.set_type_variation("PlayButton", "Button")
	t.set_stylebox("normal", "PlayButton", _box(PLAY, 18, 16))
	t.set_stylebox("hover", "PlayButton", _box(PLAY_HI, 18, 16, 3, Color.WHITE))
	t.set_stylebox("pressed", "PlayButton", _box(PLAY.darkened(0.2), 18, 16))
	t.set_stylebox("disabled", "PlayButton", _box(Color(PLAY, 0.35), 18, 16))
	t.set_font("font", "PlayButton", bold)
	t.set_font_size("font_size", "PlayButton", 34)
	t.set_color("font_color", "PlayButton", Color.WHITE)
	# icon-only buttons without background
	t.set_type_variation("IconButton", "Button")
	for s in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(s, "IconButton", StyleBoxEmpty.new())

	# --- toggles ------------------------------------------------------------
	for type in ["CheckButton", "CheckBox"]:
		for s in ["normal", "pressed", "hover_pressed", "disabled", "focus"]:
			t.set_stylebox(s, type, _box(Color(0, 0, 0, 0), 14, 10, 0, Color(), 12))
		t.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.05), 14, 10, 0, Color(), 12))
		t.set_stylebox("hover_pressed", type, _box(Color(1, 1, 1, 0.05), 14, 10, 0, Color(), 12))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
		t.set_constant("h_separation", type, 16)
	t.set_icon("checked", "CheckButton", tex["toggle_on"])
	t.set_icon("unchecked", "CheckButton", tex["toggle_off"])
	t.set_icon("checked_disabled", "CheckButton", tex["toggle_on"])
	t.set_icon("unchecked_disabled", "CheckButton", tex["toggle_off"])
	t.set_icon("checked", "CheckBox", tex["check_on"])
	t.set_icon("unchecked", "CheckBox", tex["check_off"])
	t.set_icon("checked_disabled", "CheckBox", tex["check_on"])
	t.set_icon("unchecked_disabled", "CheckBox", tex["check_off"])

	# --- lists --------------------------------------------------------------
	t.set_stylebox("panel", "ItemList", _box(CARD, 20, 10))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _box(Color(ACCENT, 0.45), 14, 0))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(ACCENT, 0.45), 14, 0))
	t.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.06), 14, 0))
	t.set_stylebox("hovered_selected", "ItemList", _box(Color(ACCENT, 0.55), 14, 0))
	t.set_stylebox("hovered_selected_focus", "ItemList", _box(Color(ACCENT, 0.55), 14, 0))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "ItemList", 28)
	t.set_constant("v_separation", "ItemList", 18)
	t.set_constant("h_separation", "ItemList", 18)
	t.set_constant("icon_margin", "ItemList", 18)
	t.set_constant("line_separation", "ItemList", 4)

	t.set_font_size("font_size", "PopupMenu", 26)
	t.set_constant("v_separation", "PopupMenu", 18)
	t.set_constant("h_separation", "PopupMenu", 14)
	t.set_constant("item_start_padding", "PopupMenu", 14)
	t.set_constant("item_end_padding", "PopupMenu", 14)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.45), 10, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_icon("radio_checked", "PopupMenu", tex["check_on"])
	t.set_icon("radio_unchecked", "PopupMenu", _empty_tex(28))
	t.set_icon("checked", "PopupMenu", tex["check_on"])
	t.set_icon("unchecked", "PopupMenu", tex["check_off"])

	# --- inputs -------------------------------------------------------------
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _box(CARD_HI, 14, 14, 2, LINE))
		t.set_stylebox("focus", type, _box(CARD_HI, 14, 14, 2, ACCENT))
		t.set_stylebox("read_only", type, _box(CARD, 14, 14))
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, ACCENT_HI)
		t.set_color("selection_color", type, Color(ACCENT, 0.4))
	t.set_color("font_placeholder_color", "LineEdit", MUTED)

	var track := _box(CARD_HI, 6, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var track_fill := _box(ACCENT, 6, 0)
	track_fill.content_margin_top = 5
	track_fill.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_fill)
	t.set_icon("grabber", "HSlider", tex["grabber"])
	t.set_icon("grabber_highlight", "HSlider", tex["grabber_hl"])
	t.set_icon("tick", "HSlider", _empty_tex(2))

	var pb_bg := _box(CARD_HI, 10, 0)
	pb_bg.content_margin_top = 8
	pb_bg.content_margin_bottom = 8
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 10, 0))
	t.set_color("font_color", "ProgressBar", TEXT)

	# --- scrollbars: wide, easy to grab with a laser pointer -------------------
	for type in ["VScrollBar", "HScrollBar"]:
		var bar := _box(Color(1, 1, 1, 0.04), 12, 0)
		bar.content_margin_left = 10
		bar.content_margin_right = 10
		bar.content_margin_top = 10
		bar.content_margin_bottom = 10
		t.set_stylebox("scroll", type, bar)
		t.set_stylebox("scroll_focus", type, bar)
		t.set_stylebox("grabber", type, _box(Color(1, 1, 1, 0.25), 10, 0))
		t.set_stylebox("grabber_highlight", type, _box(Color(1, 1, 1, 0.4), 10, 0))
		t.set_stylebox("grabber_pressed", type, _box(ACCENT, 10, 0))
	t.set_constant("scroll_speed", "ScrollContainer", 120)

	for type in ["HSeparator", "VSeparator"]:
		var sep := StyleBoxLine.new()
		sep.color = LINE
		sep.thickness = 2
		sep.vertical = type == "VSeparator"
		t.set_stylebox("separator", type, sep)
		t.set_constant("separation", type, 24)

	for type in ["HBoxContainer", "VBoxContainer"]:
		t.set_constant("separation", type, 16)
	t.set_constant("h_separation", "GridContainer", 16)
	t.set_constant("v_separation", "GridContainer", 12)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		t.set_constant(m, "MarginContainer", 0)

	var err := ResourceSaver.save(t, OUT_DIR + "open_saber_theme.tres")
	print("saved theme: ", err)
	quit()

func _box(bg: Color, radius: int, padding: int, border := 0, border_color := Color(), pad_h := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	s.content_margin_left = padding if pad_h < 0 else pad_h
	s.content_margin_right = padding if pad_h < 0 else pad_h
	return s

func _empty_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)

# antialiased coverage of a signed distance (negative = inside)
func _cov(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)

func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if a <= 0.0: return
	var dst := img.get_pixel(x, y)
	var out_a := a + dst.a * (1.0 - a)
	if out_a <= 0.0: return
	var rgb := (Color(c.r, c.g, c.b) * a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - a)) / out_a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, out_a))

func _rounded_rect_sd(p: Vector2, center: Vector2, half: Vector2, r: float) -> float:
	var q := (p - center).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - r

func _pill_icon(on: bool) -> Image:
	var w := 72; var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color("3a4254")
	var knob_x := w - h / 2.0 if on else h / 2.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			_blend(img, x, y, track, _cov(_rounded_rect_sd(p, Vector2(w, h) / 2.0, Vector2(w, h) / 2.0, h / 2.0)))
			_blend(img, x, y, Color.WHITE, _cov(p.distance_to(Vector2(knob_x, h / 2.0)) - (h / 2.0 - 5)))
	return img

func _box_icon(on: bool) -> Image:
	var s := 36
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _rounded_rect_sd(p, Vector2(s, s) / 2.0, Vector2(s, s) / 2.0 - Vector2(1, 1), 8)
			if on:
				_blend(img, x, y, ACCENT, _cov(d))
			else:
				_blend(img, x, y, Color("5a6378"), _cov(absf(d + 1.5) - 1.5))
	if on: # check mark
		var a := Vector2(9, 18.5); var b := Vector2(15.5, 25); var c := Vector2(27, 11)
		for y in s:
			for x in s:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := minf(_seg_dist(p, a, b), _seg_dist(p, b, c)) - 2.5
				_blend(img, x, y, Color.WHITE, _cov(d))
	return img

func _circle_icon(s: int, c: Color) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(s, s) / 2.0) - (s / 2.0 - 1)
			_blend(img, x, y, c, _cov(d))
	return img

func _arrow_icon() -> Image:
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var a := Vector2(7, 10); var b := Vector2(14, 18); var c := Vector2(21, 10)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			_blend(img, x, y, MUTED, _cov(minf(_seg_dist(p, a, b), _seg_dist(p, b, c)) - 1.8))
	return img

func _star_icon(filled: bool) -> Image:
	var s := 56
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var pts := PackedVector2Array()
	for i in 10:
		var r := 26.0 if i % 2 == 0 else 11.0
		var ang := -PI / 2 + i * PI / 5
		pts.append(Vector2(s / 2.0, s / 2.0 + 2) + Vector2(cos(ang), sin(ang)) * r)
	var gold := Color("ffc93d")
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var edge := INF
			for i in pts.size():
				edge = minf(edge, _seg_dist(p, pts[i], pts[(i + 1) % pts.size()]))
			var inside := Geometry2D.is_point_in_polygon(p, pts)
			if filled:
				_blend(img, x, y, gold, _cov(-edge if inside else edge))
			else:
				_blend(img, x, y, Color("aab2c4"), _cov(edge - 1.6))
	return img

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.dot(ab), 0.0, 1.0)
	return p.distance_to(a + ab * t)

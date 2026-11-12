# Small antialiased white icons for the BeatSaver browser, drawn at runtime
# (the UI font has no symbol glyphs). Tint them with modulate / icon colors.
extends RefCounted
class_name BeatSaverIcons

static var _cache := {}

static func get_icon(icon_name: String, size := 40) -> Texture2D:
	var key := "%s_%d" % [icon_name, size]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_draw(icon_name, size))
	return _cache[key]

static func _draw(icon_name: String, s: int) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var k := s / 40.0 # shapes are designed on a 40x40 grid
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) / k
			var d := _sd(icon_name, p) * k
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return img

# signed distance (in 40px grid units, negative inside) of the icon shape
static func _sd(icon_name: String, p: Vector2) -> float:
	match icon_name:
		"play":
			return _sd_poly(p, [Vector2(12, 8), Vector2(32, 20), Vector2(12, 32)]) - 1.5
		"stop":
			return _sd_box(p, Vector2(20, 20), Vector2(10, 10)) - 2.0
		"download":
			var shaft := _sd_seg(p, Vector2(20, 6), Vector2(20, 25)) - 2.6
			var head := minf(_sd_seg(p, Vector2(11, 17), Vector2(20, 26)), _sd_seg(p, Vector2(29, 17), Vector2(20, 26))) - 2.6
			var tray := minf(minf(_sd_seg(p, Vector2(7, 27), Vector2(7, 33)), _sd_seg(p, Vector2(7, 33), Vector2(33, 33))), _sd_seg(p, Vector2(33, 33), Vector2(33, 27))) - 2.6
			return minf(minf(shaft, head), tray)
		"check":
			return minf(_sd_seg(p, Vector2(8, 21), Vector2(16, 29)), _sd_seg(p, Vector2(16, 29), Vector2(32, 11))) - 3.0
		"up":
			return _sd_poly(p, [Vector2(20, 9), Vector2(33, 29), Vector2(7, 29)]) - 1.0
		"down":
			return _sd_poly(p, [Vector2(7, 11), Vector2(33, 11), Vector2(20, 31)]) - 1.0
		"back":
			return minf(minf(_sd_seg(p, Vector2(9, 20), Vector2(31, 20)), _sd_seg(p, Vector2(9, 20), Vector2(19, 10))), _sd_seg(p, Vector2(9, 20), Vector2(19, 30))) - 2.8
		"search":
			var ring := absf(p.distance_to(Vector2(17, 17)) - 9.5) - 2.6
			return minf(ring, _sd_seg(p, Vector2(24, 24), Vector2(33, 33)) - 3.2)
		"close":
			return minf(_sd_seg(p, Vector2(10, 10), Vector2(30, 30)), _sd_seg(p, Vector2(30, 10), Vector2(10, 30))) - 2.8
		"filter":
			var l1 := _sd_seg(p, Vector2(6, 11), Vector2(34, 11)) - 2.0
			var l2 := _sd_seg(p, Vector2(6, 20), Vector2(34, 20)) - 2.0
			var l3 := _sd_seg(p, Vector2(6, 29), Vector2(34, 29)) - 2.0
			var k1 := p.distance_to(Vector2(26, 11)) - 5.0
			var k2 := p.distance_to(Vector2(13, 20)) - 5.0
			var k3 := p.distance_to(Vector2(22, 29)) - 5.0
			return minf(minf(minf(l1, l2), minf(l3, k1)), minf(k2, k3))
		"user":
			var head := p.distance_to(Vector2(20, 13)) - 7.0
			var body := _sd_box(p, Vector2(20, 31), Vector2(12, 6)) - 3.0
			return minf(head, body)
		"info":
			var dot := p.distance_to(Vector2(20, 11)) - 3.2
			return minf(dot, _sd_seg(p, Vector2(20, 18), Vector2(20, 31)) - 3.0)
	return 1.0

static func _sd_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.dot(ab), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _sd_box(p: Vector2, center: Vector2, half: Vector2) -> float:
	var q := (p - center).abs() - half
	return Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0)

static func _sd_poly(p: Vector2, pts: Array[Vector2]) -> float:
	var edge := INF
	for i in pts.size():
		edge = minf(edge, _sd_seg(p, pts[i], pts[(i + 1) % pts.size()]))
	return -edge if Geometry2D.is_point_in_polygon(p, PackedVector2Array(pts)) else edge

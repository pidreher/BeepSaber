extends RefCounted
class_name RingShapes

# Builds the meshes of one ring from a StagePresets ring entry. A ring lies in the
# xy plane. It has a solid frame (may be empty) and light bars. Light bars get a glow
# strip each; the strip's vertices sit on the bar's axis, NORMAL is the axis direction
# and UV.x runs across (see LightGlow.gdshader).
#
# Shapes:
#   square:   frame between `outer` and `inner` half sizes
#   rect:     frame of half size `half_w` x `half_h`, bars `bar` thick
#   triangle: triangular frame, `outer` = half height, `inner` = bar thickness
#   panels:   `panels` boxes of `panel_size` (x, y) at `radius` around the centre
#   spokes:   two arms from `radius` to `outer`, `bar` wide
#   none:     lights only
# Lights (`lights`):
#   edge_strips:  one bar of `light_length` in the middle of each inner edge of a square
#   outline:      bars along the inner edges of the frame
#   square_bars:  four bars of `light_length` on a square of half size `outer`
#   center_beams: vertical bars from +-`light_start` out to +-(`light_start` + `light_length`)
#   panel_beams:  a bar from each panel outward, `light_length` long
#   panel_lights: a short bar on each panel

const LIGHT_DEPTH_OFFSET := 0.05

static func build(config: Dictionary) -> Dictionary:
	var depth: float = config.get("depth", 0.5)
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_solid := true
	var outline: Array[Vector4] = [] # inner edges as segments
	var panel_centres: Array[Vector2] = []
	match config.shape:
		&"square":
			var outer: float = config.outer
			var inner: float = config.inner
			var bar := outer - inner
			var middle := (outer + inner) * 0.5
			for side in [-1.0, 1.0]:
				_box(solid, Vector2(0, side * middle), Vector2(outer * 2.0, bar), 0.0, depth)
				_box(solid, Vector2(side * middle, 0), Vector2(bar, inner * 2.0), 0.0, depth)
			outline = _polygon_edges([Vector2(-inner, -inner), Vector2(inner, -inner), Vector2(inner, inner), Vector2(-inner, inner)])
		&"rect":
			var w: float = config.half_w
			var h: float = config.half_h
			var bar: float = config.bar
			for side in [-1.0, 1.0]:
				_box(solid, Vector2(0, side * (h - bar * 0.5)), Vector2(w * 2.0, bar), 0.0, depth)
				_box(solid, Vector2(side * (w - bar * 0.5), 0), Vector2(bar, h * 2.0 - bar * 2.0), 0.0, depth)
			var iw := w - bar
			var ih := h - bar
			outline = _polygon_edges([Vector2(-iw, -ih), Vector2(iw, -ih), Vector2(iw, ih), Vector2(-iw, ih)])
		&"triangle":
			var half_height: float = config.outer
			var thickness: float = config.inner
			var corners: Array[Vector2] = [Vector2(0.67, 0.0) * half_height,
				Vector2(-0.87, 1.0) * half_height, Vector2(-0.87, -1.0) * half_height]
			for edge in _polygon_edges(corners):
				var a := Vector2(edge.x, edge.y)
				var b := Vector2(edge.z, edge.w)
				_box(solid, (a + b) * 0.5, Vector2(a.distance_to(b) + thickness, thickness), (b - a).angle(), depth)
			# The light runs along the inside of each bar.
			var centre := (corners[0] + corners[1] + corners[2]) / 3.0
			var shrink := 1.0 - thickness * 1.2 / half_height
			var inner_corners: Array[Vector2] = []
			for c in corners: inner_corners.append(centre + (c - centre) * shrink)
			outline = _polygon_edges(inner_corners)
		&"panels":
			var count: int = config.panels
			var radius: float = config.radius
			var size: Vector2 = config.panel_size
			for i in count:
				var angle := TAU * i / count
				var centre := Vector2(0, radius).rotated(angle)
				_box(solid, centre, size, angle, depth)
				panel_centres.append(centre)
		&"spokes":
			var from: float = config.radius
			var to: float = config.outer
			var bar: float = config.bar
			for side in [-1.0, 1.0]:
				_box(solid, Vector2(0, side * (from + to) * 0.5), Vector2(bar, to - from), 0.0, depth)
				panel_centres.append(Vector2(0, side * to))
		_:
			has_solid = false

	var segments: Array[Vector4] = []
	var light_length: float = config.get("light_length", 1.0)
	match config.get("lights", &""):
		&"edge_strips":
			for edge in outline:
				var middle := Vector2((edge.x + edge.z) * 0.5, (edge.y + edge.w) * 0.5)
				var dir := Vector2(edge.z - edge.x, edge.w - edge.y).normalized() * light_length * 0.5
				segments.append(Vector4(middle.x - dir.x, middle.y - dir.y, middle.x + dir.x, middle.y + dir.y))
		&"outline":
			segments = outline
		&"square_bars":
			var half: float = config.outer
			for edge in _polygon_edges([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]):
				var middle := Vector2((edge.x + edge.z) * 0.5, (edge.y + edge.w) * 0.5)
				var dir := Vector2(edge.z - edge.x, edge.w - edge.y).normalized() * light_length * 0.5
				segments.append(Vector4(middle.x - dir.x, middle.y - dir.y, middle.x + dir.x, middle.y + dir.y))
		&"center_beams":
			var start: float = config.get("light_start", 0.0)
			for side in [-1.0, 1.0]:
				segments.append(Vector4(0, side * start, 0, side * (start + light_length)))
		&"panel_beams":
			for c in panel_centres:
				var dir := c.normalized()
				var a := c + dir * 0.3
				var b := a + dir * light_length
				segments.append(Vector4(a.x, a.y, b.x, b.y))
		&"panel_lights":
			for c in panel_centres:
				var across := c.normalized().orthogonal() * light_length * 0.5
				segments.append(Vector4(c.x - across.x, c.y - across.y, c.x + across.x, c.y + across.y))

	var result := { solid = solid.commit() if has_solid else null, lights = null, glow = null }
	if not segments.is_empty():
		var thickness: float = config.get("light_thickness", 0.14)
		var lights := SurfaceTool.new()
		lights.begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg in segments:
			var a := Vector2(seg.x, seg.y)
			var b := Vector2(seg.z, seg.w)
			_box(lights, (a + b) * 0.5, Vector2(a.distance_to(b), thickness), (b - a).angle(),
				thickness, depth * 0.5 + LIGHT_DEPTH_OFFSET)
		result.lights = lights.commit()
		result.glow = glow_strips(segments, depth * 0.5 + LIGHT_DEPTH_OFFSET)
	return result

# Glow strips along 2D segments in the xy plane at the given z.
static func glow_strips(segments: Array[Vector4], z: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for seg in segments:
		var a := Vector3(seg.x, seg.y, z)
		var b := Vector3(seg.z, seg.w, z)
		var axis := (b - a).normalized()
		var base := vertices.size()
		for p: Vector3 in [a, a, b, b]: vertices.append(p)
		for i in 4: normals.append(axis)
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
		indices.append_array([base, base + 1, base + 2, base + 2, base + 1, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _polygon_edges(points: Array[Vector2]) -> Array[Vector4]:
	var edges: Array[Vector4] = []
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		edges.append(Vector4(a.x, a.y, b.x, b.y))
	return edges

static func _box(surface: SurfaceTool, centre: Vector2, size: Vector2, angle: float,
		depth: float, z := 0.0) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, depth)
	surface.append_from(box, 0, Transform3D(Basis(Vector3.FORWARD, -angle), Vector3(centre.x, centre.y, z)))

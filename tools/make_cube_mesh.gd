extends SceneTree
# Generates the rounded note cube mesh (game/BeepCube/BeepCubeRounded.res).
#   godot --headless --path . -s tools/make_cube_mesh.gd
#
# A cube grid that is dense near the edges is projected onto a rounded box
# (inner box of half size HALF - RADIUS, inflated by RADIUS). UVs are a planar
# projection along z that matches the original BeepCubeMesh front face
# (u = 0.25 - x, v = 0.25 - y), so BeepCubeEmission.png still puts the arrow /
# dot on the front; the shader masks the emission by the surface normal.

const HALF := 0.25
const RADIUS := 0.075
const EDGE_SEGMENTS := 4

func _init() -> void:
	# coordinates along one face axis: flat middle part + angle-uniform edge band
	var coords := PackedFloat32Array()
	var inner := HALF - RADIUS
	for i in range(EDGE_SEGMENTS, 0, -1):
		coords.append(-(inner + RADIUS * tan(i / float(EDGE_SEGMENTS) * PI / 4)))
	coords.append(-inner)
	coords.append(inner)
	for i in range(1, EDGE_SEGMENTS + 1):
		coords.append(inner + RADIUS * tan(i / float(EDGE_SEGMENTS) * PI / 4))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# each face: normal axis, the two in-plane axes (ordered for outward winding)
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	var n := coords.size()
	for f in faces:
		var normal: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var grid := []
		for j in n:
			var row := []
			for i in n:
				row.append(_rounded(normal * HALF + a * coords[i] + b * coords[j]))
			grid.append(row)
		for j in n - 1:
			for i in n - 1:
				var q := [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				for idx in [0, 1, 2, 0, 2, 3]:
					var v: Array = q[idx]
					st.set_normal(v[1])
					st.set_uv(Vector2(0.25 - v[0].x, 0.25 - v[0].y))
					st.add_vertex(v[0])
	st.index()
	var mesh := st.commit()
	# make sure triangles face outwards: flip if the first triangle points inwards
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idxs: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tri_n := (verts[idxs[1]] - verts[idxs[0]]).cross(verts[idxs[2]] - verts[idxs[0]])
	# Godot uses clockwise winding for front faces
	if tri_n.dot(verts[idxs[0]]) > 0:
		for t in range(0, idxs.size(), 3):
			var tmp := idxs[t + 1]
			idxs[t + 1] = idxs[t + 2]
			idxs[t + 2] = tmp
		arrays[Mesh.ARRAY_INDEX] = idxs
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	print("vertices: ", verts.size(), " triangles: ", idxs.size() / 3)
	print("saved: ", ResourceSaver.save(mesh, "res://game/BeepCube/BeepCubeRounded.res"))
	quit()

func _rounded(p: Vector3) -> Array:
	var inner := HALF - RADIUS
	var q := p.clamp(Vector3(-inner, -inner, -inner), Vector3(inner, inner, inner))
	var d := p - q
	var normal := d.normalized() if d.length() > 1e-6 else p.normalized()
	return [q + normal * RADIUS, normal]

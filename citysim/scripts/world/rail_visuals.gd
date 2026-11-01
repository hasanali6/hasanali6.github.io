class_name RailVisuals
extends RefCounted
## Meshes of the elevated train (TransitSystem "elevated" types): the viaduct
## deck with parapets and rails along a path, its pillars, the station
## platform and a train car. Deck top at DECK_Y metres.

const DECK_Y := 8.0
const DECK_WIDTH := 7.0
const DECK_THICK := 0.9
const RAIL_GAUGE := 1.435
const CAR_LENGTH := 20.0
const CAR_GAP := 1.2
const CONCRETE := Color(0.74, 0.73, 0.7)


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Deck, side faces, parapets and rails along a polyline (Vector2 points).
static func add_viaduct(st: SurfaceTool, pts: Array) -> void:
	var half := DECK_WIDTH * 0.5
	_band(st, pts, -half, half, DECK_Y, DECK_Y, CONCRETE, Vector3.UP)
	_band(st, pts, -half, half, DECK_Y - DECK_THICK, DECK_Y - DECK_THICK, CONCRETE.darkened(0.25), Vector3.DOWN)
	for side in [-1.0, 1.0]:
		var o: float = side * half
		_band(st, pts, o, o, DECK_Y - DECK_THICK, DECK_Y + 1.0, CONCRETE.darkened(0.08), Vector3.ZERO, side)
		_band(st, pts, o - side * 0.25, o - side * 0.25, DECK_Y, DECK_Y + 1.0, CONCRETE.darkened(0.15), Vector3.ZERO, -side)
		_band(st, pts, o - side * 0.25, o, DECK_Y + 1.0, DECK_Y + 1.0, CONCRETE.lightened(0.05), Vector3.UP)
	# Two tracks, two rails each.
	for track in [-1.6, 1.6]:
		_band(st, pts, track - 1.2, track + 1.2, DECK_Y + 0.03, DECK_Y + 0.03, Color(0.42, 0.38, 0.34), Vector3.UP)
		for rail in [-0.5, 0.5]:
			var r: float = track + rail * RAIL_GAUGE
			_band(st, pts, r - 0.05, r + 0.05, DECK_Y + 0.18, DECK_Y + 0.18, Color(0.75, 0.76, 0.78), Vector3.UP)


## A band between two offsets (left of the direction of travel is negative)
## at heights y0 (at o0) and y1 (at o1). normal = UP/DOWN for flat bands;
## ZERO with `side` for vertical ones (normal points that way sideways).
static func _band(st: SurfaceTool, pts: Array, o0: float, o1: float, y0: float, y1: float, color: Color,
		normal: Vector3, side: float = 1.0) -> void:
	var n := pts.size()
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	var prev_n := Vector3.ZERO
	for k in n:
		var p: Vector2 = pts[k]
		var d := ((pts[mini(k + 1, n - 1)] as Vector2) - (pts[maxi(k - 1, 0)] as Vector2)).normalized()
		if d == Vector2.ZERO:
			continue
		var right := Vector2(-d.y, d.x)
		var a := Vector3(p.x + right.x * o0, y0, p.y + right.y * o0)
		var b := Vector3(p.x + right.x * o1, y1, p.y + right.y * o1)
		var nv := normal if normal != Vector3.ZERO else Vector3(right.x, 0, right.y) * side
		if k > 0 and prev_a.distance_to(a) < 40.0:
			for v: Array in [[prev_a, prev_n], [b, nv], [prev_b, prev_n], [prev_a, prev_n], [a, nv], [b, nv]]:
				st.set_color(color)
				st.set_normal(v[1])
				st.add_vertex(v[0])
		prev_a = a
		prev_b = b
		prev_n = nv


## Pillar: a unit-height box with a wider cap, origin at its base.
static func pillar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 1.8), CONCRETE.darkened(0.05))
	var m := st.commit()
	m.surface_set_material(0, material())
	return m


## Station platform across the viaduct (long side = local z), deck level.
static func platform_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(side * 5.2, DECK_Y + 0.5, 0), Vector3(3.4, 1.0, 70.0), Color(0.8, 0.79, 0.76))
		_box(st, Vector3(side * 6.4, DECK_Y + 1.0 + 1.6, 0), Vector3(0.12, 3.2, 66.0), Color(0.62, 0.8, 0.86))
		for z in [-28.0, -9.0, 9.0, 28.0]:
			_box(st, Vector3(side * 5.6, DECK_Y + 2.6, z), Vector3(0.25, 3.2, 0.25), Color(0.4, 0.42, 0.45))
			_box(st, Vector3(side * 6.2, DECK_Y * 0.5, z), Vector3(1.0, DECK_Y, 1.0), CONCRETE)
	_box(st, Vector3(0, DECK_Y + 4.3, 0), Vector3(14.6, 0.3, 64.0), Color(0.9, 0.9, 0.92))
	# Stair and lift tower down to the street.
	_box(st, Vector3(8.6, DECK_Y * 0.5 + 1.0, 0), Vector3(3.0, DECK_Y + 2.0, 6.0), Color(0.86, 0.85, 0.82))
	_box(st, Vector3(8.6, DECK_Y + 2.3, 0), Vector3(3.4, 0.3, 6.6), Color(0.85, 0.3, 0.2))
	var m := st.commit()
	m.surface_set_material(0, material())
	return m


## One car (length along local z), white body tinted by the instance colour.
static func car_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 0.75, 0), Vector3(2.9, 0.9, CAR_LENGTH), Color(0.25, 0.26, 0.28))
	_box(st, Vector3(0, 2.15, 0), Vector3(3.0, 1.9, CAR_LENGTH - 0.2), Color(0.97, 0.97, 0.97))
	_box(st, Vector3(0, 2.45, 0), Vector3(3.04, 0.75, CAR_LENGTH - 1.6), Color(0.16, 0.2, 0.26))
	_box(st, Vector3(0, 3.2, 0), Vector3(2.7, 0.3, CAR_LENGTH - 0.6), Color(0.7, 0.72, 0.75))
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.metallic = 0.2
	m.surface_set_material(0, mat)
	return m


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, color: Color) -> void:
	var h := s * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		var q: Array[Vector3] = [corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]]]
		var out := ((q[0] + q[1] + q[2] + q[3]) * 0.25 - c).normalized()
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var a := q[tri[0]]
			var b := q[tri[1]]
			var cc := q[tri[2]]
			# Godot front faces are clockwise: their winding normal points inwards.
			if (b - a).cross(cc - a).dot(out) > 0.0:
				var t := b
				b = cc
				cc = t
			for v: Vector3 in [a, b, cc]:
				st.set_color(color)
				st.set_normal(out)
				st.add_vertex(v)


## Position (x, y, z) and heading (unit Vector2) at distance s along pts,
## using cumulative distances cum (same size as pts).
static func sample(pts: Array, cum: PackedFloat32Array, s: float) -> Array:
	var n := pts.size()
	if n < 2:
		return [pts[0] if n == 1 else Vector2.ZERO, Vector2.RIGHT]
	s = clampf(s, 0.0, cum[n - 1])
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var a: Vector2 = pts[lo]
	var b: Vector2 = pts[hi]
	var span := maxf(cum[hi] - cum[lo], 1e-4)
	return [a.lerp(b, (s - cum[lo]) / span), (b - a).normalized()]


static func cumulative(pts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var acc := 0.0
	for k in pts.size():
		if k > 0:
			acc += (pts[k] as Vector2).distance_to(pts[k - 1])
		out.append(acc)
	return out

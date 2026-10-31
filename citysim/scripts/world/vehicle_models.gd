class_name VehicleModels
extends RefCounted
## Procedural low-poly vehicles and traffic lights. Every face carries a
## material id in UV.x that the shaders turn into a colour:
##   0 paint, 1 glass, 2 headlight, 3 tail light, 4 tyre, 5 dark trim,
##   6 second colour (lower body / cargo box), 7 contact shadow, 8 beacon.
## Vehicles face +z with their wheels on y = 0, about real size in metres.
## Traffic light ids: 0 pole, 1 housing, 2 red, 3 amber, 4 green lamp.

const PAINT := 0
const GLASS := 1
const HEADLIGHT := 2
const TAILLIGHT := 3
const TYRE := 4
const TRIM := 5
const SECOND := 6
const SHADOW := 7
const BEACON := 8

const NAMES: Array[String] = ["sedan", "hatch", "van", "truck", "police", "ambulance", "fire", "bus", "tram"]


static func build(name: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	match name:
		"sedan", "police":
			_car(st, 4.5, 1.8, [Vector2(-2.25, 0.62), Vector2(2.25, 0.62), Vector2(2.25, 0.68), Vector2(2.05, 0.86),
				Vector2(0.9, 0.92), Vector2(-1.6, 0.94), Vector2(-2.25, 0.86)],
				[Vector2(-1.55, 0.92), Vector2(0.95, 0.92), Vector2(0.35, 1.38), Vector2(-1.15, 1.4)], 1.35)
			if name == "police":
				_box(st, Vector3(0, 1.46, -0.3), Vector3(1.2, 0.12, 0.32), BEACON)
		"hatch":
			_car(st, 4.2, 1.8, [Vector2(-2.1, 0.64), Vector2(2.1, 0.64), Vector2(2.1, 0.74), Vector2(1.75, 0.92),
				Vector2(0.8, 0.96), Vector2(-2.1, 0.98)],
				[Vector2(-2.05, 0.96), Vector2(0.75, 0.96), Vector2(0.2, 1.52), Vector2(-1.95, 1.55)], 1.3)
		"van", "ambulance":
			_van(st)
			if name == "ambulance":
				_box(st, Vector3(0, 2.07, 1.35), Vector3(1.3, 0.14, 0.3), BEACON)
		"truck", "fire":
			_truck(st, name == "fire")
		"bus":
			_bus(st)
		"tram":
			_tram(st)
	st.generate_normals()
	return st.commit()


static func traffic_light() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_box(st, Vector3(0, 0.1, 0), Vector3(0.32, 0.2, 0.32), 0)
	_box(st, Vector3(0, 2.15, 0), Vector3(0.14, 4.3, 0.14), 0)
	_box(st, Vector3(0, 4.5, 0.05), Vector3(0.42, 1.15, 0.32), 1)
	for k in 3:
		_box(st, Vector3(0, 4.85 - k * 0.35, 0.23), Vector3(0.26, 0.26, 0.05), 2 + k)
	st.generate_normals()
	return st.commit()


## Bus shelter facing +z (the road): roof, glass back wall, bench and a
## sign post whose disc takes the line colour. Ids: 0 metal, 1 glass,
## 2 line colour, 3 bench, 4 concrete.
static func bus_stop() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_box(st, Vector3(0, 0.06, 0), Vector3(4.2, 0.12, 2.0), 4)
	_box(st, Vector3(0, 2.5, -0.2), Vector3(3.6, 0.1, 1.6), 0)
	_box(st, Vector3(0, 1.3, -0.95), Vector3(3.4, 2.2, 0.05), 1)
	for sx in [-1.7, 1.7]:
		_box(st, Vector3(sx, 1.3, -0.9), Vector3(0.08, 2.4, 0.08), 0)
	_box(st, Vector3(0, 0.5, -0.6), Vector3(2.4, 0.08, 0.45), 3)
	_box(st, Vector3(2.4, 1.4, 0.6), Vector3(0.08, 2.8, 0.08), 0)
	_box(st, Vector3(2.4, 2.75, 0.6), Vector3(0.05, 0.6, 0.6), 2)
	st.generate_normals()
	return st.commit()


## Tram platform along the curb with a small shelter.
static func tram_stop() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_box(st, Vector3(0, 0.15, 0), Vector3(18.0, 0.3, 2.6), 4)
	_box(st, Vector3(0, 0.31, 1.15), Vector3(18.0, 0.02, 0.25), 2)
	_box(st, Vector3(0, 2.7, -0.4), Vector3(6.0, 0.1, 1.6), 0)
	_box(st, Vector3(0, 1.5, -1.15), Vector3(5.8, 2.2, 0.05), 1)
	for sx in [-2.9, 2.9]:
		_box(st, Vector3(sx, 1.5, -1.1), Vector3(0.1, 2.4, 0.1), 0)
	_box(st, Vector3(0, 0.75, -0.8), Vector3(3.6, 0.08, 0.45), 3)
	st.generate_normals()
	return st.commit()


# --- Bodies ---------------------------------------------------------------------

## Car: two-tone body (lower part second colour), glass cabin with a painted
## roof, bumpers, wheels, lights and a contact shadow.
static func _car(st: SurfaceTool, length: float, width: float, upper: Array, cabin: Array, axle: float) -> void:
	var h := length * 0.5
	var w := width * 0.5
	_prism(st, [Vector2(-h, 0.32), Vector2(h, 0.32), Vector2(h, 0.62), Vector2(-h, 0.62)], -w, w, SECOND, SECOND)
	_prism(st, upper, -w, w, PAINT, PAINT)
	_prism(st, cabin, -w + 0.12, w - 0.12, GLASS, PAINT)
	_box(st, Vector3(0, 0.42, h - 0.04), Vector3(width, 0.16, 0.12), TRIM)
	_box(st, Vector3(0, 0.42, -h + 0.04), Vector3(width, 0.16, 0.12), TRIM)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(st, Vector3(sx * (w - 0.1), 0.31, sz * axle), Vector3(0.24, 0.62, 0.62), TYRE)
		_box(st, Vector3(sx * (w - 0.28), 0.66, h + 0.005), Vector3(0.32, 0.1, 0.02), HEADLIGHT)
		_box(st, Vector3(sx * (w - 0.24), 0.76, -h - 0.005), Vector3(0.3, 0.1, 0.02), TAILLIGHT)
	_shadow(st, width + 0.3, length + 0.4)


static func _van(st: SurfaceTool) -> void:
	var w := 0.97
	_prism(st, [Vector2(-2.5, 0.35), Vector2(2.5, 0.35), Vector2(2.5, 0.7), Vector2(-2.5, 0.7)], -w, w, SECOND, SECOND)
	_prism(st, [Vector2(-2.5, 0.7), Vector2(2.5, 0.7), Vector2(2.5, 0.95), Vector2(2.05, 1.15), Vector2(1.55, 1.95), Vector2(-2.5, 2.0)],
		-w, w, PAINT, PAINT, [3])
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * (w + 0.005), 1.5, 1.25), Vector3(0.02, 0.5, 0.6), GLASS)
		for sz in [-1.75, 1.75]:
			_box(st, Vector3(sx * (w - 0.12), 0.34, sz), Vector3(0.26, 0.68, 0.68), TYRE)
		_box(st, Vector3(sx * 0.66, 0.78, 2.505), Vector3(0.34, 0.12, 0.02), HEADLIGHT)
		_box(st, Vector3(sx * 0.78, 0.9, -2.505), Vector3(0.18, 0.4, 0.02), TAILLIGHT)
	_box(st, Vector3(0, 0.45, 2.48), Vector3(1.95, 0.18, 0.1), TRIM)
	_box(st, Vector3(0, 0.45, -2.48), Vector3(1.95, 0.18, 0.1), TRIM)
	_shadow(st, 2.3, 5.4)


static func _truck(st: SurfaceTool, fire: bool) -> void:
	_box(st, Vector3(0, 1.4, 2.9), Vector3(2.3, 2.3, 1.9), PAINT)
	_box(st, Vector3(0, 2.05, 3.86), Vector3(2.0, 0.65, 0.04), GLASS)
	_box(st, Vector3(0, 0.55, 0.3), Vector3(2.0, 0.3, 7.4), TRIM)
	_box(st, Vector3(0, 1.75, -1.0), Vector3(2.45, 2.7, 5.6), SECOND)
	for sx in [-1.0, 1.0]:
		for sz in [2.7, -1.8, -3.0]:
			_box(st, Vector3(sx * 1.02, 0.47, sz), Vector3(0.36, 0.94, 0.94), TYRE)
		_box(st, Vector3(sx * 0.85, 0.75, 3.865), Vector3(0.34, 0.14, 0.02), HEADLIGHT)
		_box(st, Vector3(sx * 0.95, 0.7, -3.805), Vector3(0.3, 0.16, 0.02), TAILLIGHT)
	if fire:
		_box(st, Vector3(0, 3.18, -1.2), Vector3(0.7, 0.16, 5.6), TRIM)
		_box(st, Vector3(0, 2.62, 2.9), Vector3(1.6, 0.14, 0.32), BEACON)
	_shadow(st, 2.8, 8.4)


## City bus: white body with the line colour along the bottom, a band of
## windows, roof units.
static func _bus(st: SurfaceTool) -> void:
	_box(st, Vector3(0, 0.75, 0), Vector3(2.5, 0.8, 12.0), SECOND)
	_box(st, Vector3(0, 2.0, 0), Vector3(2.5, 1.7, 12.0), PAINT)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 1.255, 2.0, -0.4), Vector3(0.02, 0.85, 10.4), GLASS)
		for sz in [3.9, -3.6]:
			_box(st, Vector3(sx * 1.08, 0.5, sz), Vector3(0.36, 1.0, 1.0), TYRE)
		_box(st, Vector3(sx * 0.9, 0.85, 6.005), Vector3(0.36, 0.14, 0.02), HEADLIGHT)
		_box(st, Vector3(sx * 1.0, 1.0, -6.005), Vector3(0.24, 0.4, 0.02), TAILLIGHT)
	_box(st, Vector3(0, 2.05, 6.01), Vector3(2.3, 1.1, 0.03), GLASS)
	_box(st, Vector3(0, 3.0, -2.5), Vector3(1.6, 0.35, 3.0), TRIM)
	_shadow(st, 2.9, 12.6)


## Tram: line-coloured body over a light skirt, long window band, bogies
## and a pantograph on the roof.
static func _tram(st: SurfaceTool) -> void:
	_box(st, Vector3(0, 0.75, 0), Vector3(2.5, 0.7, 18.0), SECOND)
	_box(st, Vector3(0, 2.05, 0), Vector3(2.5, 1.9, 18.0), PAINT)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 1.255, 2.15, 0.0), Vector3(0.02, 0.95, 16.4), GLASS)
		_box(st, Vector3(sx * 0.85, 1.0, 9.005), Vector3(0.32, 0.14, 0.02), HEADLIGHT)
		_box(st, Vector3(sx * 0.95, 1.1, -9.005), Vector3(0.22, 0.3, 0.02), TAILLIGHT)
	for sz in [-6.5, 0.0, 6.5]:
		_box(st, Vector3(0, 0.38, sz), Vector3(2.2, 0.62, 2.4), TYRE)
	_box(st, Vector3(0, 2.2, 9.01), Vector3(2.3, 1.2, 0.03), GLASS)
	_box(st, Vector3(0, 2.2, -9.01), Vector3(2.3, 1.2, 0.03), GLASS)
	_box(st, Vector3(0, 3.1, 1.0), Vector3(1.8, 0.2, 3.0), TRIM)
	_box(st, Vector3(0, 3.55, 1.0), Vector3(0.1, 0.7, 1.6), TRIM)
	_shadow(st, 2.9, 18.6)


static func _shadow(st: SurfaceTool, width: float, length: float) -> void:
	var w := width * 0.5
	var h := length * 0.5
	var y := 0.015
	_quad(st, Vector3(-w, y, -h), Vector3(w, y, -h), Vector3(w, y, h), Vector3(-w, y, h), Vector3.UP, SHADOW)


# --- Primitives -------------------------------------------------------------------

## Side profile (z, y points, convex) extruded across x from x0 to x1. Faces
## pointing up use `top_id`; profile edges listed in `glass_edges` (index of
## their first point) are glass.
static func _prism(st: SurfaceTool, profile: Array, x0: float, x1: float, side_id: int, top_id: int, glass_edges: Array = []) -> void:
	var n := profile.size()
	var centre := Vector2.ZERO
	for p: Vector2 in profile:
		centre += p
	centre /= n
	for i in n:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % n]
		var mid := (a + b) * 0.5 - centre
		var out := Vector3(0.0, mid.y, mid.x)
		var edge := (b - a).normalized()
		var normal := Vector2(-edge.y, edge.x)
		if normal.dot(mid) < 0.0:
			normal = -normal
		var id := top_id if normal.y > 0.85 else side_id
		if i in glass_edges:
			id = GLASS
		_quad(st, Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x), out, id)
	for side in [x0, x1]:
		var out := Vector3(signf(side), 0, 0)
		var c3 := Vector3(side, centre.y, centre.x)
		for i in n:
			var a: Vector2 = profile[i]
			var b: Vector2 = profile[(i + 1) % n]
			_tri(st, c3, Vector3(side, a.y, a.x), Vector3(side, b.y, b.x), out, GLASS if side_id == GLASS else side_id)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, id: int) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		corners.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	# Corner bits: 1 = +x, 2 = +y, 4 = +z; each face lists its corners in order.
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var cc: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		var out := ((a + b + cc + d) * 0.25) - c
		_quad(st, a, b, cc, d, out, id)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, id: int) -> void:
	_tri(st, a, b, c, out, id)
	_tri(st, a, c, d, out, id)


## Triangle wound for Godot (clockwise seen from the side it faces).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, id: int) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
	var uv := Vector2(float(id), 0.0)
	for p in [a, b, c]:
		st.set_uv(uv)
		st.add_vertex(p)

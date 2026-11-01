class_name RoadMeshBuilder
extends RefCounted
## Builds road geometry from a RoadGraph: segment ribbons (asphalt, raised
## sidewalks with curbs, optional median) and junction patches with rounded
## curb corners. Output is a Parts bundle per piece so the renderer can merge
## many pieces into one mesh per chunk (few draw calls on mobile).
##
## Plan coordinates are Vector2(x, z). Asphalt vertices carry CUSTOM0 =
## (lanes per direction, one-way, median width, lane width) and UV2.x = distance
## to a junction mouth, so one shader draws lane markings and crosswalks for
## every road type.

const ASPHALT := "asphalt"
const SIDEWALK := "sidewalk"
const CURB := "curb"
const MEDIAN := "median"
const NO_JUNCTION := 10000.0


class Parts:
	extends RefCounted
	## key -> {v, n, uv, uv2, custom, i}
	var data: Dictionary = {}

	func _get_arrays(key: String) -> Dictionary:
		if not data.has(key):
			data[key] = {
				"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
				"uv2": PackedVector2Array(), "custom": PackedFloat32Array(), "i": PackedInt32Array(),
			}
		return data[key]

	func add_vertex(key: String, v: Vector3, n: Vector3, uv: Vector2, uv2: Vector2, custom: Color) -> int:
		# Packed arrays must be modified through a typed local reference.
		var d := _get_arrays(key)
		var v_arr: PackedVector3Array = d["v"]
		var n_arr: PackedVector3Array = d["n"]
		var uv_arr: PackedVector2Array = d["uv"]
		var uv2_arr: PackedVector2Array = d["uv2"]
		var idx := v_arr.size()
		v_arr.append(v)
		n_arr.append(n)
		uv_arr.append(uv)
		uv2_arr.append(uv2)
		var c: PackedFloat32Array = d["custom"]
		c.append(custom.r)
		c.append(custom.g)
		c.append(custom.b)
		c.append(custom.a)
		return idx

	## Adds a triangle wound so that its front side faces `facing`.
	## Godot treats clockwise triangles (seen from the front) as front faces,
	## i.e. the cross product of their edges points away from the viewer.
	func add_face(key: String, i0: int, i1: int, i2: int, facing: Vector3) -> void:
		var d := _get_arrays(key)
		var v: PackedVector3Array = d["v"]
		var idx: PackedInt32Array = d["i"]
		var g := (v[i1] - v[i0]).cross(v[i2] - v[i0])
		if g.dot(facing) > 0.0:
			idx.append(i0)
			idx.append(i2)
			idx.append(i1)
		else:
			idx.append(i0)
			idx.append(i1)
			idx.append(i2)

	func append(other: Parts) -> void:
		for key: String in other.data:
			var src: Dictionary = other.data[key]
			var dst := _get_arrays(key)
			var v_arr: PackedVector3Array = dst["v"]
			var n_arr: PackedVector3Array = dst["n"]
			var uv_arr: PackedVector2Array = dst["uv"]
			var uv2_arr: PackedVector2Array = dst["uv2"]
			var c_arr: PackedFloat32Array = dst["custom"]
			var idx: PackedInt32Array = dst["i"]
			var base := v_arr.size()
			v_arr.append_array(src["v"])
			n_arr.append_array(src["n"])
			uv_arr.append_array(src["uv"])
			uv2_arr.append_array(src["uv2"])
			c_arr.append_array(src["custom"])
			for i: int in src["i"]:
				idx.append(base + i)

	func is_empty() -> bool:
		return data.is_empty()

	## One surface per key, in the order of `keys`, each with its material.
	func to_mesh(keys: PackedStringArray, materials: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		for key in keys:
			if not data.has(key) or (data[key]["i"] as PackedInt32Array).is_empty():
				continue
			var d: Dictionary = data[key]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = d["v"]
			arrays[Mesh.ARRAY_NORMAL] = d["n"]
			arrays[Mesh.ARRAY_TEX_UV] = d["uv"]
			arrays[Mesh.ARRAY_TEX_UV2] = d["uv2"]
			arrays[Mesh.ARRAY_CUSTOM0] = d["custom"]
			arrays[Mesh.ARRAY_INDEX] = d["i"]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		return mesh


# --- Junction analysis --------------------------------------------------------

## Two segments of the same type meeting almost straight are joined seamlessly
## (mitred) instead of getting a junction patch.
static func is_joint(graph: RoadGraph, node_id: int, cfg: Dictionary) -> bool:
	var node: RoadGraph.RoadNode = graph.nodes[node_id]
	if node.segments.size() != 2:
		return false
	var s0: RoadGraph.RoadSegment = graph.segments[node.segments[0]]
	var s1: RoadGraph.RoadSegment = graph.segments[node.segments[1]]
	if s0.type != s1.type:
		return false
	var d0 := graph.leaving_direction(s0.id, node_id)
	var d1 := graph.leaving_direction(s1.id, node_id)
	return d0.dot(d1) <= -cos(deg_to_rad(float(cfg["joint_max_deviation_deg"])))


static func is_junction(graph: RoadGraph, node_id: int, cfg: Dictionary) -> bool:
	var deg := (graph.nodes[node_id] as RoadGraph.RoadNode).segments.size()
	return deg >= 3 or (deg == 2 and not is_joint(graph, node_id, cfg))


## How far segments are cut back from a junction node to leave room for the
## junction patch and its curb corners.
static func junction_radius(graph: RoadGraph, node_id: int, types: Dictionary, cfg: Dictionary) -> float:
	if not is_junction(graph, node_id, cfg):
		return 0.0
	var node: RoadGraph.RoadNode = graph.nodes[node_id]
	var max_hw := 0.0
	var min_len := INF
	var angles: Array[float] = []
	for sid in node.segments:
		var seg: RoadGraph.RoadSegment = graph.segments[sid]
		max_hw = maxf(max_hw, RoadTypes.half_width(types[seg.type]))
		min_len = minf(min_len, seg.length)
		var d := graph.leaving_direction(sid, node_id)
		angles.append(atan2(d.y, d.x))
	angles.sort()
	var min_gap := TAU
	for i in angles.size():
		var next := angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		min_gap = minf(min_gap, next - angles[i])
	var radius := max_hw + float(cfg["corner_radius_m"])
	if min_gap < PI * 0.5:
		radius = max_hw / tan(min_gap * 0.5) + float(cfg["corner_radius_m"])
	radius += float(cfg["junction_extra_m"])
	return minf(radius, min_len * 0.45)


# --- Segments -------------------------------------------------------------------

static func build_segment(graph: RoadGraph, seg_id: int, types: Dictionary, cfg: Dictionary) -> Parts:
	var parts := Parts.new()
	var seg: RoadGraph.RoadSegment = graph.segments[seg_id]
	var t: Dictionary = types[seg.type]
	var c := graph.curve_of(seg)
	var trim_a := junction_radius(graph, seg.a, types, cfg)
	var trim_b := junction_radius(graph, seg.b, types, cfg)
	var table := arc_table(c[0], c[1], c[2], graph.sample_step * 0.5)
	var length: float = table[table.size() - 1].y
	var s0 := trim_a
	var s1 := length - trim_b
	if s1 - s0 < 0.25:
		return parts

	var turn := RoadGraph.bezier_tangent(c[0], c[1], c[2], 0.0).angle_to(RoadGraph.bezier_tangent(c[0], c[1], c[2], 1.0))
	var count := maxi(ceili((s1 - s0) / float(cfg["sample_step_m"])), ceili(absf(turn) / deg_to_rad(float(cfg["max_angle_per_sample_deg"]))))
	count = maxi(count, 1)
	var joint_a := trim_a == 0.0 and is_joint(graph, seg.a, cfg)
	var joint_b := trim_b == 0.0 and is_joint(graph, seg.b, cfg)

	var points := PackedVector2Array()
	var lefts := PackedVector2Array()  # left normal, scaled for mitred ends
	var dist := PackedFloat32Array()
	var to_junction := PackedFloat32Array()
	for i in count + 1:
		var s := lerpf(s0, s1, float(i) / count)
		var tt := t_at(table, s)
		var p := RoadGraph.bezier(c[0], c[1], c[2], tt)
		var d := RoadGraph.bezier_tangent(c[0], c[1], c[2], tt).normalized()
		var left := Vector2(-d.y, d.x)
		if i == 0 and joint_a:
			left = _mitre_left(graph, seg_id, seg.a, d)
		elif i == count and joint_b:
			left = _mitre_left(graph, seg_id, seg.b, d)
		points.append(p)
		lefts.append(left)
		dist.append(s)
		var j := NO_JUNCTION
		if trim_a > 0.0:
			j = minf(j, s - s0)
		if trim_b > 0.0:
			j = minf(j, s1 - s)
		to_junction.append(j)

	var custom := Color(float(t["lanes_per_dir"]), 1.0 if bool(t["oneway"]) else 0.0,
		float(t["median_width_m"]), float(t["lane_width_m"]))
	var cw := RoadTypes.carriageway_width(t) * 0.5
	var hw := RoadTypes.half_width(t)
	var hm := float(t["median_width_m"]) * 0.5
	var curb_h := float(cfg["curb_height_m"])
	var road_h := float(cfg["asphalt_height_m"])
	# Over water the deck rises just above the surface on short ramps, and
	# gets parapets and a concrete edge (a bridge).
	var lifts := PackedFloat32Array()
	var over := PackedFloat32Array()
	var any_bridge := false
	var lift_h := float(cfg.get("bridge_lift_m", 0.14))
	var ramp := float(cfg.get("bridge_ramp_m", 5.0))
	var raised := graph.is_elevated(seg_id)
	for i in points.size():
		var p := points[i]
		var wd := MapWater.shared().distance(p) - hw
		var k := 1.0 - smoothstep(0.0, ramp, wd)
		var up := RoadGraph.ramp_lift(dist[i], length, graph.overpass_height, graph.overpass_ramp) if raised else 0.0
		lifts.append(maxf(lift_h * k, up))
		over.append(1.0 if wd < 1.0 or up > 0.8 else 0.0)
		if k > 0.0 or up > 0.0:
			any_bridge = true
	if not any_bridge:
		lifts = PackedFloat32Array()

	# Asphalt (split around a median if there is one). The last argument is
	# the facing: 0 = top face, +1 / -1 = vertical face towards +left / -left.
	if hm > 0.0:
		_strip(parts, ASPHALT, points, lefts, dist, to_junction, -cw, -hm, road_h, road_h, custom, 0, lifts)
		_strip(parts, ASPHALT, points, lefts, dist, to_junction, hm, cw, road_h, road_h, custom, 0, lifts)
		_strip(parts, MEDIAN, points, lefts, dist, to_junction, -hm, hm, curb_h, curb_h, custom, 0, lifts)
		_strip(parts, CURB, points, lefts, dist, to_junction, -hm, -hm, road_h, curb_h, custom, -1, lifts)
		_strip(parts, CURB, points, lefts, dist, to_junction, hm, hm, road_h, curb_h, custom, 1, lifts)
	else:
		_strip(parts, ASPHALT, points, lefts, dist, to_junction, -cw, cw, road_h, road_h, custom, 0, lifts)
	# Sidewalks: top, inner curb face, outer face down to the ground.
	_strip(parts, SIDEWALK, points, lefts, dist, to_junction, -hw, -cw, curb_h, curb_h, custom, 0, lifts)
	_strip(parts, SIDEWALK, points, lefts, dist, to_junction, cw, hw, curb_h, curb_h, custom, 0, lifts)
	_strip(parts, CURB, points, lefts, dist, to_junction, -cw, -cw, road_h, curb_h, custom, 1, lifts)
	_strip(parts, CURB, points, lefts, dist, to_junction, cw, cw, road_h, curb_h, custom, -1, lifts)
	_strip(parts, CURB, points, lefts, dist, to_junction, -hw, -hw, 0.0, curb_h, custom, -1, lifts)
	_strip(parts, CURB, points, lefts, dist, to_junction, hw, hw, 0.0, curb_h, custom, 1, lifts)
	if any_bridge:
		_bridge_parts(parts, points, lefts, dist, to_junction, hw, curb_h, lifts, over, float(cfg.get("bridge_railing_m", 0.9)), custom)
	return parts


## Parapets along both edges and the deck's side down into the water, only
## where the road is over water.
static func _bridge_parts(parts: Parts, points: PackedVector2Array, lefts: PackedVector2Array, dist: PackedFloat32Array,
		to_junction: PackedFloat32Array, hw: float, curb_h: float, lifts: PackedFloat32Array, over: PackedFloat32Array,
		railing: float, custom: Color) -> void:
	var start := -1
	for i in points.size() + 1:
		var wet := i < points.size() and over[i] > 0.5
		if wet and start < 0:
			start = maxi(i - 1, 0)
		elif not wet and start >= 0:
			var end := mini(i, points.size() - 1)
			var pts := points.slice(start, end + 1)
			var ls := lefts.slice(start, end + 1)
			var ds := dist.slice(start, end + 1)
			var tj := to_junction.slice(start, end + 1)
			var lf := lifts.slice(start, end + 1)
			for side: float in [-1.0, 1.0]:
				var inner := (hw - 0.25) * side
				var outer := hw * side
				var top := curb_h + railing
				# Parapet: inner face, top, outer face.
				_strip(parts, CURB, pts, ls, ds, tj, inner, inner, curb_h, top, custom, -int(side), lf)
				_strip(parts, CURB, pts, ls, ds, tj, inner, outer, top, top, custom, 0, lf)
				_strip(parts, CURB, pts, ls, ds, tj, outer, outer, -2.0, top, custom, int(side), lf)
			# Underside of the deck (seen from below an overpass).
			_strip(parts, CURB, pts, ls, ds, tj, hw, -hw, -1.2, -1.2, custom, 0, lf)
			start = -1


## A strip between two cross-section lines (offset along the left normal,
## height). facing 0 = top face, +1/-1 = vertical face towards +left/-left.
static func _strip(parts: Parts, key: String, points: PackedVector2Array, lefts: PackedVector2Array,
		dist: PackedFloat32Array, to_junction: PackedFloat32Array, off0: float, off1: float,
		h0: float, h1: float, custom: Color, facing: int, lifts: PackedFloat32Array = PackedFloat32Array()) -> void:
	var base := -1
	for i in points.size():
		var l := lefts[i]
		var p0 := points[i] + l * off0
		var p1 := points[i] + l * off1
		var lift := lifts[i] if i < lifts.size() else 0.0
		var n := Vector3.UP
		if facing != 0:
			n = Vector3(l.x, 0.0, l.y).normalized() * float(facing)
		var uv2 := Vector2(to_junction[i], 0.0)
		var a := parts.add_vertex(key, Vector3(p0.x, h0 + lift, p0.y), n, Vector2(off0, dist[i]), uv2, custom)
		var b := parts.add_vertex(key, Vector3(p1.x, h1 + lift, p1.y), n, Vector2(off1, dist[i]), uv2, custom)
		if base >= 0:
			parts.add_face(key, base, a, base + 1, n)
			parts.add_face(key, base + 1, a, b, n)
		base = a


static func _mitre_left(graph: RoadGraph, seg_id: int, node_id: int, own_dir: Vector2) -> Vector2:
	var node: RoadGraph.RoadNode = graph.nodes[node_id]
	var other := node.segments[0] if node.segments[1] == seg_id else node.segments[1]
	var seg: RoadGraph.RoadSegment = graph.segments[seg_id]
	var other_leaving := graph.leaving_direction(other, node_id)
	# Continue in this segment's a -> b orientation through the node.
	var cont := other_leaving if seg.b == node_id else -other_leaving
	var mitre := (own_dir + cont).normalized()
	var left := Vector2(-mitre.y, mitre.x)
	var own_left := Vector2(-own_dir.y, own_dir.x)
	return left / maxf(left.dot(own_left), 0.5)


## Cumulative arc length table: Vector2(t, s) samples.
static func arc_table(a: Vector2, c: Vector2, b: Vector2, step: float) -> PackedVector2Array:
	var n := RoadGraph.sample_count(a, c, b, step)
	var table := PackedVector2Array([Vector2(0.0, 0.0)])
	var prev := a
	var s := 0.0
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := RoadGraph.bezier(a, c, b, t)
		s += prev.distance_to(p)
		table.append(Vector2(t, s))
		prev = p
	return table


static func t_at(table: PackedVector2Array, s: float) -> float:
	var lo := 0
	var hi := table.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if table[mid].y < s:
			lo = mid
		else:
			hi = mid
	var span := table[hi].y - table[lo].y
	var f := 0.0 if span <= 0.0 else (s - table[lo].y) / span
	return lerpf(table[lo].x, table[hi].x, clampf(f, 0.0, 1.0))


# --- Junctions ------------------------------------------------------------------

static func build_junction(graph: RoadGraph, node_id: int, types: Dictionary, cfg: Dictionary) -> Parts:
	var parts := Parts.new()
	if not is_junction(graph, node_id, cfg):
		return parts
	var node: RoadGraph.RoadNode = graph.nodes[node_id]
	var radius := junction_radius(graph, node_id, types, cfg)
	var centre := node.pos
	var arms: Array[Dictionary] = []
	for sid in node.segments:
		var seg: RoadGraph.RoadSegment = graph.segments[sid]
		var t: Dictionary = types[seg.type]
		var c := graph.curve_of(seg)
		var table := arc_table(c[0], c[1], c[2], graph.sample_step * 0.5)
		var length: float = table[table.size() - 1].y
		var s := radius if seg.a == node_id else length - radius
		var tt := t_at(table, s)
		var e := RoadGraph.bezier(c[0], c[1], c[2], tt)
		var d := RoadGraph.bezier_tangent(c[0], c[1], c[2], tt).normalized()
		if seg.b == node_id:
			d = -d
		var l := Vector2(-d.y, d.x)
		var cw := RoadTypes.carriageway_width(t) * 0.5
		var hw := RoadTypes.half_width(t)
		var lead := graph.leaving_direction(sid, node_id)
		arms.append({
			"angle": atan2(lead.y, lead.x), "dir": d,
			"rc": e - l * cw, "lc": e + l * cw, "ro": e - l * hw, "lo": e + l * hw,
		})
	arms.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["angle"] < y["angle"])

	var road_h := float(cfg["asphalt_height_m"])
	var curb_h := float(cfg["curb_height_m"])
	var steps := int(cfg["corner_steps"])
	var limit := radius * 3.0
	var none := Color(0, 0, 0, 0)
	var far := Vector2(NO_JUNCTION, 0.0)

	# Asphalt ring: each arm mouth, then the curb corner to the next arm.
	var ring := PackedVector2Array()
	for i in arms.size():
		var arm: Dictionary = arms[i]
		var nxt: Dictionary = arms[(i + 1) % arms.size()]
		ring.append(arm["rc"])
		ring.append(arm["lc"])
		var k := _corner_control(arm["lc"], arm["dir"], nxt["rc"], nxt["dir"], centre, limit)
		for sidx in range(1, steps):
			ring.append(RoadGraph.bezier(arm["lc"], k, nxt["rc"], float(sidx) / steps))
	var ci := parts.add_vertex(ASPHALT, Vector3(centre.x, road_h, centre.y), Vector3.UP, centre, far, none)
	var first := -1
	var prev := -1
	for p in ring:
		var vi := parts.add_vertex(ASPHALT, Vector3(p.x, road_h, p.y), Vector3.UP, p, far, none)
		if prev >= 0:
			parts.add_face(ASPHALT, ci, prev, vi, Vector3.UP)
		else:
			first = vi
		prev = vi
	parts.add_face(ASPHALT, ci, prev, first, Vector3.UP)

	# Sidewalk corners with curb and outer faces.
	for i in arms.size():
		var arm: Dictionary = arms[i]
		var nxt: Dictionary = arms[(i + 1) % arms.size()]
		var kc := _corner_control(arm["lc"], arm["dir"], nxt["rc"], nxt["dir"], centre, limit)
		var ko := _corner_control(arm["lo"], arm["dir"], nxt["ro"], nxt["dir"], centre, limit)
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for sidx in steps + 1:
			var f := float(sidx) / steps
			inner.append(RoadGraph.bezier(arm["lc"], kc, nxt["rc"], f))
			outer.append(RoadGraph.bezier(arm["lo"], ko, nxt["ro"], f))
		_corner_strip(parts, SIDEWALK, outer, inner, curb_h, curb_h, centre, 0)
		_corner_strip(parts, CURB, inner, inner, road_h, curb_h, centre, -1)
		_corner_strip(parts, CURB, outer, outer, 0.0, curb_h, centre, 1)
	return parts


## Bezier control for a curb corner: where the two curb lines meet, if that
## lies behind both arm mouths and not absurdly far; else a straight edge.
static func _corner_control(p0: Vector2, d0: Vector2, p1: Vector2, d1: Vector2, centre: Vector2, limit: float) -> Vector2:
	var denom := d0.cross(d1)
	if absf(denom) > 1e-4:
		var s0 := (p1 - p0).cross(d1) / denom
		var s1 := (p1 - p0).cross(d0) / denom
		var k := p0 + d0 * s0
		if s0 <= 0.0 and s1 <= 0.0 and k.distance_to(centre) < limit:
			return k
	return (p0 + p1) * 0.5


## Strip between two corner polylines (same length). facing 0 = top face,
## +1 = vertical face pointing away from the junction centre, -1 = towards it.
static func _corner_strip(parts: Parts, key: String, line0: PackedVector2Array, line1: PackedVector2Array,
		h0: float, h1: float, centre: Vector2, facing: int) -> void:
	var base := -1
	for i in line0.size():
		var p0 := line0[i]
		var p1 := line1[i]
		var n := Vector3.UP
		if facing != 0:
			var out := (p0 - centre).normalized()
			n = Vector3(out.x, 0.0, out.y) * float(facing)
		var far := Vector2(NO_JUNCTION, 1.0)
		var a := parts.add_vertex(key, Vector3(p0.x, h0, p0.y), n, p0, far, Color(0, 0, 0, 0))
		var b := parts.add_vertex(key, Vector3(p1.x, h1, p1.y), n, p1, far, Color(0, 0, 0, 0))
		if base >= 0:
			parts.add_face(key, base, a, base + 1, n)
			parts.add_face(key, base + 1, a, b, n)
		base = a

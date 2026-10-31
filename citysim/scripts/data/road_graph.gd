class_name RoadGraph
extends RefCounted
## Road network topology in plan view (x/z metres as Vector2):
## nodes are junctions or road ends, segments are quadratic Bezier curves
## between two nodes. Pure data with no rendering, so it can be edited and
## tested headless. Lanes are derived from the segment's road type
## (see RoadTypes.lanes).
##
## Building a road is two steps: plan_road() validates and finds where the new
## curve crosses existing roads without changing anything; commit_road() then
## splits the crossed segments and inserts the new pieces, so every crossing
## becomes a junction node.


class RoadNode:
	extends RefCounted
	var id: int
	var pos: Vector2
	var segments: PackedInt32Array = PackedInt32Array()


class RoadSegment:
	extends RefCounted
	var id: int
	var a: int
	var b: int
	var control: Vector2
	var type: String
	var length: float


var nodes: Dictionary = {}     # id -> RoadNode
var segments: Dictionary = {}  # id -> RoadSegment

var sample_step: float
var merge_radius: float
var min_segment: float
var max_segment: float
var min_angle: float

var _next_node: int = 1
var _next_segment: int = 1


func _init(config: Dictionary) -> void:
	sample_step = float(config["sample_step_m"])
	merge_radius = float(config["merge_radius_m"])
	min_segment = float(config["min_segment_m"])
	max_segment = float(config["max_segment_m"])
	min_angle = deg_to_rad(float(config["min_angle_deg"]))


# --- Curve maths ------------------------------------------------------------

static func bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + c * (2.0 * u * t) + b * (t * t)


static func bezier_tangent(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var d := ((c - a) * (1.0 - t) + (b - c) * t) * 2.0
	return d if d.length_squared() > 1e-12 else (b - a)


## Control point of the part of curve (a, c, b) between t0 and t1.
static func sub_control(a: Vector2, c: Vector2, b: Vector2, t0: float, t1: float) -> Vector2:
	return a * ((1.0 - t0) * (1.0 - t1)) + c * ((1.0 - t0) * t1 + t0 * (1.0 - t1)) + b * (t0 * t1)


static func sample_count(a: Vector2, c: Vector2, b: Vector2, step: float) -> int:
	return clampi(ceili((a.distance_to(c) + c.distance_to(b)) / step), 2, 1024)


static func curve_length(a: Vector2, c: Vector2, b: Vector2, step: float) -> float:
	var n := sample_count(a, c, b, step)
	var total := 0.0
	var prev := a
	for i in range(1, n + 1):
		var p := bezier(a, c, b, float(i) / n)
		total += prev.distance_to(p)
		prev = p
	return total


func curve_of(seg: RoadSegment) -> Array[Vector2]:
	return [(nodes[seg.a] as RoadNode).pos, seg.control, (nodes[seg.b] as RoadNode).pos]


func point_on(seg_id: int, t: float) -> Vector2:
	var c := curve_of(segments[seg_id])
	return bezier(c[0], c[1], c[2], t)


func tangent_on(seg_id: int, t: float) -> Vector2:
	var c := curve_of(segments[seg_id])
	return bezier_tangent(c[0], c[1], c[2], t).normalized()


## Direction in which a segment leaves the given node.
func leaving_direction(seg_id: int, node_id: int) -> Vector2:
	var seg: RoadSegment = segments[seg_id]
	return tangent_on(seg_id, 0.0) if seg.a == node_id else -tangent_on(seg_id, 1.0)


func other_node(seg_id: int, node_id: int) -> int:
	var seg: RoadSegment = segments[seg_id]
	return seg.b if seg.a == node_id else seg.a


# --- Queries ------------------------------------------------------------------

func find_node_near(pos: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for node: RoadNode in nodes.values():
		var d := node.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = node.id
	return best


## Closest point on any segment within radius: {segment, t, point, distance} or {}.
func find_segment_near(pos: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for seg: RoadSegment in segments.values():
		var c := curve_of(seg)
		var lo := Vector2(minf(minf(c[0].x, c[1].x), c[2].x), minf(minf(c[0].y, c[1].y), c[2].y))
		var hi := Vector2(maxf(maxf(c[0].x, c[1].x), c[2].x), maxf(maxf(c[0].y, c[1].y), c[2].y))
		if pos.x < lo.x - radius or pos.x > hi.x + radius or pos.y < lo.y - radius or pos.y > hi.y + radius:
			continue
		var t := _closest_t(c[0], c[1], c[2], pos)
		var p := bezier(c[0], c[1], c[2], t)
		var d := p.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = {"segment": seg.id, "t": t, "point": p, "distance": d}
	return best


func _closest_t(a: Vector2, c: Vector2, b: Vector2, pos: Vector2) -> float:
	var n := sample_count(a, c, b, sample_step)
	var best_t := 0.0
	var best_d := INF
	for i in n + 1:
		var t := float(i) / n
		var d := bezier(a, c, b, t).distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_t = t
	# Refine around the best sample with a ternary search.
	var lo := maxf(best_t - 1.0 / n, 0.0)
	var hi := minf(best_t + 1.0 / n, 1.0)
	for i in 20:
		var m1 := lerpf(lo, hi, 1.0 / 3.0)
		var m2 := lerpf(lo, hi, 2.0 / 3.0)
		if bezier(a, c, b, m1).distance_squared_to(pos) < bezier(a, c, b, m2).distance_squared_to(pos):
			hi = m2
		else:
			lo = m1
	return (lo + hi) * 0.5


func are_connected(na: int, nb: int) -> bool:
	for sid in (nodes[na] as RoadNode).segments:
		if other_node(sid, na) == nb:
			return true
	return false


# --- Raw editing ------------------------------------------------------------

func add_node(pos: Vector2) -> int:
	var node := RoadNode.new()
	node.id = _next_node
	_next_node += 1
	node.pos = pos
	nodes[node.id] = node
	return node.id


func add_segment(na: int, nb: int, control: Vector2, type: String) -> int:
	var seg := RoadSegment.new()
	seg.id = _next_segment
	_next_segment += 1
	seg.a = na
	seg.b = nb
	seg.control = control
	seg.type = type
	seg.length = curve_length((nodes[na] as RoadNode).pos, control, (nodes[nb] as RoadNode).pos, sample_step)
	segments[seg.id] = seg
	(nodes[na] as RoadNode).segments.append(seg.id)
	(nodes[nb] as RoadNode).segments.append(seg.id)
	return seg.id


## Removes a segment and any node left without roads.
## Returns {"removed_nodes": PackedInt32Array, "touched_nodes": PackedInt32Array}.
func remove_segment(seg_id: int) -> Dictionary:
	var removed := PackedInt32Array()
	var touched := PackedInt32Array()
	if not segments.has(seg_id):
		return {"removed_nodes": removed, "touched_nodes": touched}
	var seg: RoadSegment = segments[seg_id]
	segments.erase(seg_id)
	for nid in [seg.a, seg.b]:
		var node: RoadNode = nodes[nid]
		var idx := node.segments.find(seg_id)
		if idx >= 0:
			node.segments.remove_at(idx)
		if node.segments.is_empty():
			nodes.erase(nid)
			removed.append(nid)
		elif not touched.has(nid):
			touched.append(nid)
	return {"removed_nodes": removed, "touched_nodes": touched}


## Splits a segment at parameter t; returns the new junction node id.
func split_segment(seg_id: int, t: float) -> int:
	var seg: RoadSegment = segments[seg_id]
	var c := curve_of(seg)
	var mid := bezier(c[0], c[1], c[2], t)
	var na := seg.a
	var nb := seg.b
	var type := seg.type
	var left_control := c[0].lerp(c[1], t)
	var right_control := c[1].lerp(c[2], t)
	remove_segment(seg_id)
	# remove_segment may have dropped the end nodes if they were dead ends.
	if not nodes.has(na):
		nodes[na] = _restore_node(na, c[0])
	if not nodes.has(nb):
		nodes[nb] = _restore_node(nb, c[2])
	var nm := add_node(mid)
	add_segment(na, nm, left_control, type)
	add_segment(nm, nb, right_control, type)
	return nm


func _restore_node(id: int, pos: Vector2) -> RoadNode:
	var node := RoadNode.new()
	node.id = id
	node.pos = pos
	return node


# --- Planning and committing a new road -----------------------------------

## Validates a road from start to end (control = null for a straight road)
## without touching the graph. Result has "ok"; on failure "error" holds a
## translation key; on success it carries what commit_road() needs.
func plan_road(start: Vector2, end: Vector2, control: Variant) -> Dictionary:
	var a_ref := _endpoint_ref(start)
	var b_ref := _endpoint_ref(end)
	var a: Vector2 = a_ref["point"]
	var b: Vector2 = b_ref["point"]
	var ctrl: Vector2 = control if control != null else (a + b) * 0.5
	var length := curve_length(a, ctrl, b, sample_step)
	if a.distance_to(b) < min_segment or length < min_segment:
		return _fail("ROAD_ERR_SHORT")
	if length > max_segment:
		return _fail("ROAD_ERR_LONG")
	if a_ref["kind"] == "node" and b_ref["kind"] == "node":
		if a_ref["id"] == b_ref["id"]:
			return _fail("ROAD_ERR_SHORT")
		if are_connected(a_ref["id"], b_ref["id"]) and control == null:
			return _fail("ROAD_ERR_EXISTS")
	if a_ref["kind"] == "segment" and b_ref["kind"] == "segment" and a_ref["id"] == b_ref["id"]:
		return _fail("ROAD_ERR_OVERLAP")

	if not _angle_ok(a_ref, bezier_tangent(a, ctrl, b, 0.0).normalized()):
		return _fail("ROAD_ERR_ANGLE")
	if not _angle_ok(b_ref, -bezier_tangent(a, ctrl, b, 1.0).normalized()):
		return _fail("ROAD_ERR_ANGLE")

	var hits: Array[Dictionary] = []
	for seg: RoadSegment in segments.values():
		var c := curve_of(seg)
		for hit in _curve_intersections(a, ctrl, b, c[0], c[1], c[2]):
			var p: Vector2 = hit["point"]
			if p.distance_to(a) < merge_radius or p.distance_to(b) < merge_radius:
				continue
			var d_new := bezier_tangent(a, ctrl, b, hit["t"]).normalized()
			var d_old := bezier_tangent(c[0], c[1], c[2], hit["t_other"]).normalized()
			if acos(clampf(absf(d_new.dot(d_old)), 0.0, 1.0)) < min_angle:
				return _fail("ROAD_ERR_ANGLE")
			hits.append({"t": hit["t"], "point": p})
	hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["t"] < y["t"])
	# A crossing on a shared polyline vertex is reported twice; keep one.
	var unique: Array[Dictionary] = []
	for hit in hits:
		if unique.is_empty() or (unique.back()["point"] as Vector2).distance_to(hit["point"]) > merge_radius:
			unique.append(hit)
	hits = unique

	# Junctions must not end up closer than half the minimum segment length.
	var stops: Array[Vector2] = [a]
	for hit in hits:
		stops.append(hit["point"])
	stops.append(b)
	for i in range(1, stops.size()):
		if stops[i - 1].distance_to(stops[i]) < min_segment * 0.5:
			return _fail("ROAD_ERR_TOO_CLOSE")

	return {"ok": true, "a": a, "b": b, "control": ctrl, "length": length, "hits": hits}


## Applies a successful plan. Returns the new segment ids.
func commit_road(plan: Dictionary, type: String) -> PackedInt32Array:
	var a: Vector2 = plan["a"]
	var b: Vector2 = plan["b"]
	var ctrl: Vector2 = plan["control"]
	var chain: Array[Dictionary] = [{"t": 0.0, "node": _node_at(a)}]
	for hit: Dictionary in plan["hits"]:
		chain.append({"t": hit["t"], "node": _node_at(hit["point"])})
	chain.append({"t": 1.0, "node": _node_at(b)})
	var created := PackedInt32Array()
	for i in range(1, chain.size()):
		var n0: int = chain[i - 1]["node"]
		var n1: int = chain[i]["node"]
		if n0 == n1:
			continue
		var sub := sub_control(a, ctrl, b, chain[i - 1]["t"], chain[i]["t"])
		created.append(add_segment(n0, n1, sub, type))
	return created


func _fail(key: String) -> Dictionary:
	return {"ok": false, "error": key}


## What a road end at `pos` attaches to: an existing node, a point on an
## existing segment (to be split), or free ground.
func _endpoint_ref(pos: Vector2) -> Dictionary:
	var nid := find_node_near(pos, merge_radius)
	if nid >= 0:
		return {"kind": "node", "id": nid, "point": (nodes[nid] as RoadNode).pos}
	var hit := find_segment_near(pos, merge_radius)
	if not hit.is_empty():
		return {"kind": "segment", "id": hit["segment"], "t": hit["t"], "point": hit["point"]}
	return {"kind": "free", "point": pos}


## The new road leaving an endpoint along `dir` must not run (almost) on top
## of a road already there.
func _angle_ok(ref: Dictionary, dir: Vector2) -> bool:
	var existing: Array[Vector2] = []
	match ref["kind"]:
		"node":
			for sid in (nodes[ref["id"]] as RoadNode).segments:
				existing.append(leaving_direction(sid, ref["id"]))
		"segment":
			var tangent := tangent_on(ref["id"], ref["t"])
			existing.append(tangent)
			existing.append(-tangent)
	for d in existing:
		if acos(clampf(dir.dot(d), -1.0, 1.0)) < min_angle:
			return false
	return true


func _node_at(pos: Vector2) -> int:
	var nid := find_node_near(pos, merge_radius)
	if nid >= 0:
		return nid
	var hit := find_segment_near(pos, merge_radius)
	if not hit.is_empty():
		return split_segment(hit["segment"], hit["t"])
	return add_node(pos)


## Crossings between two quadratic curves via their sampled polylines.
## Returns [{t, t_other, point}] with t on the first curve.
func _curve_intersections(a1: Vector2, c1: Vector2, b1: Vector2,
		a2: Vector2, c2: Vector2, b2: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lo1 := Vector2(minf(minf(a1.x, c1.x), b1.x), minf(minf(a1.y, c1.y), b1.y))
	var hi1 := Vector2(maxf(maxf(a1.x, c1.x), b1.x), maxf(maxf(a1.y, c1.y), b1.y))
	var lo2 := Vector2(minf(minf(a2.x, c2.x), b2.x), minf(minf(a2.y, c2.y), b2.y))
	var hi2 := Vector2(maxf(maxf(a2.x, c2.x), b2.x), maxf(maxf(a2.y, c2.y), b2.y))
	if hi1.x < lo2.x or hi2.x < lo1.x or hi1.y < lo2.y or hi2.y < lo1.y:
		return out
	var n1 := sample_count(a1, c1, b1, sample_step)
	var n2 := sample_count(a2, c2, b2, sample_step)
	var p2 := PackedVector2Array()
	for j in n2 + 1:
		p2.append(bezier(a2, c2, b2, float(j) / n2))
	var prev := a1
	for i in range(1, n1 + 1):
		var cur := bezier(a1, c1, b1, float(i) / n1)
		for j in range(1, n2 + 1):
			var uv: Variant = _segment_intersection(prev, cur, p2[j - 1], p2[j])
			if uv != null:
				var t := (i - 1 + (uv as Vector2).x) / n1
				var t_other := (j - 1 + (uv as Vector2).y) / n2
				out.append({"t": t, "t_other": t_other, "point": prev.lerp(cur, (uv as Vector2).x)})
		prev = cur
	return out


static func _segment_intersection(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Variant:
	var r := p2 - p1
	var s := p4 - p3
	var denom := r.cross(s)
	if absf(denom) < 1e-9:
		return null
	var q := p3 - p1
	var u := q.cross(s) / denom
	var v := q.cross(r) / denom
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return null
	return Vector2(u, v)

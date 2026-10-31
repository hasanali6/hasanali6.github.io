class_name LaneGeometry
extends RefCounted
## Driving lanes and junction connectors as polylines (x, z per sample),
## packed into one float buffer that the vehicle shader reads as an RGF
## texture with TEX_WIDTH texels per row.
##
## A piece is either a lane along a segment, running in travel direction
## between the two junction mouths (where the stop lines are), or a
## connector through a junction from an incoming lane to an outgoing lane.
## Traffic drives on the right; lane 0 is next to the centre line. Pieces of
## segments and junctions that did not change are reused between rebuilds.

const TEX_WIDTH := 1024
const LANE_STEP := 8.0
const CONN_STEP := 3.0
const MAX_LANE_SAMPLES := 128
const MAX_CONN_SAMPLES := 16

var piece_offset := PackedInt32Array()     # first texel of the piece
var piece_count := PackedInt32Array()      # samples
var piece_length := PackedFloat32Array()
var piece_dir_in := PackedVector2Array()   # travel direction at the start
var piece_dir_out := PackedVector2Array()  # travel direction at the end
var piece_key: Array = []                  # lane key (int) or connector key (Vector3i)
var lane_pieces: Dictionary = {}           # lane key -> piece id
var conn_pieces: Dictionary = {}           # Vector3i(node id, in lane key, out lane key) -> piece id
var buffer := PackedFloat32Array()
var rows: int = 1

var _seg_cache: Dictionary = {}    # segment id -> [signature, {lane key: [points, length]}]
var _node_cache: Dictionary = {}   # node id -> [signature, {connector key: [points, length]}]


static func lane_key(seg_id: int, dir: int, lane: int) -> int:
	return seg_id * 16 + dir * 8 + lane


static func key_segment(key: int) -> int:
	return key >> 4


static func key_dir(key: int) -> int:
	return (key >> 3) & 1


static func key_lane(key: int) -> int:
	return key & 7


func piece_total() -> int:
	return piece_offset.size()


func rebuild(graph: RoadGraph, types: Dictionary, mesh_cfg: Dictionary) -> void:
	var trims := {}
	for nid: int in graph.nodes:
		trims[nid] = RoadMeshBuilder.junction_radius(graph, nid, types, mesh_cfg)
	var lanes := {}
	var seg_sig := {}
	var seg_cache := {}
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		var sig := "%d|%d|%.3f|%.3f|%s|%.3f|%.3f" % [seg.a, seg.b, seg.control.x, seg.control.y, seg.type, trims[seg.a], trims[seg.b]]
		var cached: Array = _seg_cache.get(seg.id, [])
		var arrays: Dictionary
		if not cached.is_empty() and cached[0] == sig:
			arrays = cached[1]
		else:
			arrays = _segment_lanes(graph, seg, types[seg.type], trims)
		seg_cache[seg.id] = [sig, arrays]
		seg_sig[seg.id] = sig
		for k: int in arrays:
			lanes[k] = arrays[k]
	_seg_cache = seg_cache
	var conns := {}
	var node_cache := {}
	for node: RoadGraph.RoadNode in graph.nodes.values():
		if node.segments.size() < 2:
			continue
		var joint := RoadMeshBuilder.is_joint(graph, node.id, mesh_cfg)
		var parts := PackedStringArray(["j" if joint else "x"])
		var incident := node.segments.duplicate()
		incident.sort()
		for sid in incident:
			parts.append(seg_sig[sid])
		var sig := "/".join(parts)
		var cached: Array = _node_cache.get(node.id, [])
		var arrays: Dictionary
		if not cached.is_empty() and cached[0] == sig:
			arrays = cached[1]
		else:
			arrays = _junction_connectors(graph, node, types, lanes, joint)
		node_cache[node.id] = [sig, arrays]
		for k: Vector3i in arrays:
			conns[k] = arrays[k]
	_node_cache = node_cache
	_pack(lanes, conns)


## Points of a piece as Vector2s (tests and debugging).
func points(pid: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var o := piece_offset[pid] * 2
	for k in piece_count[pid]:
		out.append(Vector2(buffer[o + k * 2], buffer[o + k * 2 + 1]))
	return out


## Distance along a piece to the point on it closest to p.
func project(pid: int, p: Vector2) -> float:
	var o := piece_offset[pid] * 2
	var best := 0.0
	var best_d := INF
	var acc := 0.0
	for k in piece_count[pid] - 1:
		var a := Vector2(buffer[o + k * 2], buffer[o + k * 2 + 1])
		var b := Vector2(buffer[o + k * 2 + 2], buffer[o + k * 2 + 3])
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = acc + a.distance_to(q)
		acc += a.distance_to(b)
	return best * piece_length[pid] / maxf(acc, 0.001)


## The packed buffer as an RGF image for the vehicle shader.
func image() -> Image:
	return Image.create_from_data(TEX_WIDTH, rows, false, Image.FORMAT_RGF, buffer.to_byte_array())


func _segment_lanes(graph: RoadGraph, seg: RoadGraph.RoadSegment, t: Dictionary, trims: Dictionary) -> Dictionary:
	var c := graph.curve_of(seg)
	var table := RoadMeshBuilder.arc_table(c[0], c[1], c[2], 2.0)
	var total: float = table[table.size() - 1].y
	var s0 := minf(float(trims[seg.a]), total * 0.45)
	var s1 := maxf(total - float(trims[seg.b]), s0 + 0.5)
	var out := {}
	var fi := 0
	var bi := 0
	for lane: Dictionary in RoadTypes.lanes(t):
		var forward: bool = lane["forward"]
		var key := lane_key(seg.id, 0 if forward else 1, fi if forward else bi)
		if forward:
			fi += 1
		else:
			bi += 1
		out[key] = _sample_lane(c, table, s0, s1, float(lane["offset"]), forward)
	return out


func _sample_lane(c: Array[Vector2], table: PackedVector2Array, s0: float, s1: float, offset: float, forward: bool) -> Array:
	var n := clampi(ceili((s1 - s0) / LANE_STEP) + 1, 2, MAX_LANE_SAMPLES)
	var pts := PackedFloat32Array()
	pts.resize(n * 2)
	var length := 0.0
	var prev := Vector2.ZERO
	for k in n:
		var f := float(k) / (n - 1)
		var s := lerpf(s0, s1, f) if forward else lerpf(s1, s0, f)
		var t := RoadMeshBuilder.t_at(table, s)
		var p := RoadGraph.bezier(c[0], c[1], c[2], t)
		var d := RoadGraph.bezier_tangent(c[0], c[1], c[2], t).normalized()
		# Driver's left for travel a -> b (map z points down): forward lanes
		# have negative offsets, so they sit on the right of the driver.
		var q := p + Vector2(d.y, -d.x) * offset
		pts[k * 2] = q.x
		pts[k * 2 + 1] = q.y
		if k > 0:
			length += prev.distance_to(q)
		prev = q
	return [pts, length]


func _junction_connectors(graph: RoadGraph, node: RoadGraph.RoadNode, types: Dictionary, lanes: Dictionary, joint: bool) -> Dictionary:
	# Legs: [segment id, direction arriving here, direction leaving here].
	var legs := []
	for sid in node.segments:
		var seg: RoadGraph.RoadSegment = graph.segments[sid]
		legs.append([sid, 0 if seg.b == node.id else 1, 1 if seg.b == node.id else 0])
	var out := {}
	for in_leg: Array in legs:
		for out_leg: Array in legs:
			if out_leg[0] == in_leg[0]:
				continue
			var n_in := int(types[(graph.segments[in_leg[0]] as RoadGraph.RoadSegment).type]["lanes_per_dir"])
			var n_out := int(types[(graph.segments[out_leg[0]] as RoadGraph.RoadSegment).type]["lanes_per_dir"])
			for i in n_in:
				var in_key := lane_key(in_leg[0], in_leg[1], i)
				if not lanes.has(in_key):
					continue
				for j in n_out:
					if joint and i != j:
						continue
					var out_key := lane_key(out_leg[0], out_leg[2], j)
					if not lanes.has(out_key):
						continue
					out[Vector3i(node.id, in_key, out_key)] = _connector((lanes[in_key] as Array)[0], (lanes[out_key] as Array)[0])
	return out


## Curve from the end of one lane to the start of another, bending through
## the point where their directions meet (straight across if they do not).
func _connector(a: PackedFloat32Array, b: PackedFloat32Array) -> Array:
	var na := a.size() / 2
	var p0 := Vector2(a[na * 2 - 2], a[na * 2 - 1])
	var d0 := (p0 - Vector2(a[na * 2 - 4], a[na * 2 - 3])).normalized()
	var p2 := Vector2(b[0], b[1])
	var d2 := (Vector2(b[2], b[3]) - p2).normalized()
	var chord := p0.distance_to(p2)
	var pts := PackedFloat32Array()
	if chord < 0.05:
		# Seamless joint: a tiny piece that keeps the heading.
		var q := p0 + d0 * 0.05
		pts.append_array(PackedFloat32Array([p0.x, p0.y, q.x, q.y]))
		return [pts, 0.05]
	var ctrl := (p0 + p2) * 0.5
	var det := d0.x * d2.y - d0.y * d2.x
	if absf(det) > 1e-3:
		var diff := p2 - p0
		var u := (diff.x * d2.y - diff.y * d2.x) / det
		var w := (d0.x * diff.y - d0.y * diff.x) / det
		if u > 0.0 and w > 0.0 and u < chord * 2.0 and w < chord * 2.0:
			ctrl = p0 + d0 * u
	var n := clampi(ceili(chord / CONN_STEP) + 1, 2, MAX_CONN_SAMPLES)
	pts.resize(n * 2)
	var length := 0.0
	var prev := p0
	for k in n:
		var q := RoadGraph.bezier(p0, ctrl, p2, float(k) / (n - 1))
		pts[k * 2] = q.x
		pts[k * 2 + 1] = q.y
		if k > 0:
			length += prev.distance_to(q)
		prev = q
	return [pts, maxf(length, 0.05)]


func _pack(lanes: Dictionary, conns: Dictionary) -> void:
	piece_offset = PackedInt32Array()
	piece_count = PackedInt32Array()
	piece_length = PackedFloat32Array()
	piece_dir_in = PackedVector2Array()
	piece_dir_out = PackedVector2Array()
	piece_key = []
	lane_pieces = {}
	conn_pieces = {}
	buffer = PackedFloat32Array()
	for key: int in lanes:
		lane_pieces[key] = _add_piece(key, lanes[key])
	for key: Vector3i in conns:
		conn_pieces[key] = _add_piece(key, conns[key])
	var texels := buffer.size() / 2
	rows = maxi(ceili(float(texels) / TEX_WIDTH), 1)
	buffer.resize(rows * TEX_WIDTH * 2)


func _add_piece(key: Variant, entry: Array) -> int:
	var pts: PackedFloat32Array = entry[0]
	var pid := piece_offset.size()
	var n := pts.size() / 2
	piece_offset.append(buffer.size() / 2)
	piece_count.append(n)
	piece_length.append(float(entry[1]))
	var d_in := Vector2(pts[2] - pts[0], pts[3] - pts[1]).normalized()
	var d_out := Vector2(pts[n * 2 - 2] - pts[n * 2 - 4], pts[n * 2 - 1] - pts[n * 2 - 3]).normalized()
	piece_dir_in.append(d_in)
	piece_dir_out.append(d_out)
	piece_key.append(key)
	buffer.append_array(pts)
	return pid

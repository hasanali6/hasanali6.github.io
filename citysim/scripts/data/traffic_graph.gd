class_name TrafficGraph
extends RefCounted
## Compact, read-only copy of the road network for routing and traffic
## assignment. Nodes and directed edges live in flat packed arrays (CSR
## layout), so searches touch no Dictionaries and a copy can be handed to a
## worker thread while the player keeps editing the real RoadGraph.
##
## Directed edge e = segment index * 2 + dir; dir 0 runs from node a to b,
## dir 1 from b to a (not allowed on one-way roads).

var node_ids := PackedInt32Array()       # index -> RoadGraph node id
var node_index: Dictionary = {}          # node id -> index
var node_pos := PackedVector2Array()
var node_degree := PackedByteArray()
var node_lit := PackedByteArray()        # 1 = traffic lights
var seg_ids := PackedInt32Array()        # index -> RoadGraph segment id
var seg_index: Dictionary = {}           # segment id -> index
var seg_a := PackedInt32Array()          # node index at end a
var seg_b := PackedInt32Array()
var seg_len := PackedFloat32Array()
var seg_lanes := PackedInt32Array()      # lanes per travel direction
var seg_oneway := PackedByteArray()
var seg_speed := PackedFloat32Array()    # free-flow speed, m/s
var seg_capacity := PackedFloat32Array() # vehicles per hour per direction
var out_start := PackedInt32Array()      # node -> first slot in out_edge (size nodes + 1)
var out_edge := PackedInt32Array()
var in_start := PackedInt32Array()
var in_edge := PackedInt32Array()


func node_count() -> int:
	return node_ids.size()


func edge_count() -> int:
	return seg_ids.size() * 2


func edge_allowed(e: int) -> bool:
	return (e & 1) == 0 or seg_oneway[e >> 1] == 0


func edge_from(e: int) -> int:
	return seg_a[e >> 1] if (e & 1) == 0 else seg_b[e >> 1]


func edge_to(e: int) -> int:
	return seg_b[e >> 1] if (e & 1) == 0 else seg_a[e >> 1]


## Snapshot of a RoadGraph. `types` are the road types (data/roads.json) and
## `cfg` the traffic settings (data/traffic.json).
static func build(graph: RoadGraph, types: Dictionary, cfg: Dictionary) -> TrafficGraph:
	var g := TrafficGraph.new()
	var lights: Dictionary = cfg["lights"]
	var capacity: Dictionary = cfg["lane_capacity_per_hour"]
	var ids := graph.nodes.keys()
	ids.sort()
	for nid: int in ids:
		var node: RoadGraph.RoadNode = graph.nodes[nid]
		g.node_index[nid] = g.node_ids.size()
		g.node_ids.append(nid)
		g.node_pos.append(node.pos)
		var degree := node.segments.size()
		g.node_degree.append(mini(degree, 255))
		var major := false
		for sid in node.segments:
			if str((graph.segments[sid] as RoadGraph.RoadSegment).type) in lights["major_types"]:
				major = true
		var lit := degree >= int(lights["min_legs"]) and (major or degree >= int(lights["always_from_legs"]))
		g.node_lit.append(1 if lit else 0)
	var sids := graph.segments.keys()
	sids.sort()
	for sid: int in sids:
		var seg: RoadGraph.RoadSegment = graph.segments[sid]
		var t: Dictionary = types[seg.type]
		g.seg_index[sid] = g.seg_ids.size()
		g.seg_ids.append(sid)
		g.seg_a.append(g.node_index[seg.a])
		g.seg_b.append(g.node_index[seg.b])
		g.seg_len.append(maxf(seg.length, 1.0))
		g.seg_lanes.append(int(t["lanes_per_dir"]))
		g.seg_oneway.append(1 if bool(t["oneway"]) else 0)
		g.seg_speed.append(float(t["speed_kmh"]) / 3.6)
		g.seg_capacity.append(float(capacity.get(seg.type, 600.0)) * int(t["lanes_per_dir"]))
	g._build_adjacency()
	return g


func _build_adjacency() -> void:
	var n := node_count()
	var out_count := PackedInt32Array()
	var in_count := PackedInt32Array()
	out_count.resize(n)
	in_count.resize(n)
	for e in edge_count():
		if edge_allowed(e):
			out_count[edge_from(e)] += 1
			in_count[edge_to(e)] += 1
	out_start.resize(n + 1)
	in_start.resize(n + 1)
	out_start[0] = 0
	in_start[0] = 0
	for i in n:
		out_start[i + 1] = out_start[i] + out_count[i]
		in_start[i + 1] = in_start[i] + in_count[i]
	out_edge.resize(out_start[n])
	in_edge.resize(in_start[n])
	var out_fill := out_start.duplicate()
	var in_fill := in_start.duplicate()
	for e in edge_count():
		if not edge_allowed(e):
			continue
		var f := edge_from(e)
		var t := edge_to(e)
		out_edge[out_fill[f]] = e
		out_fill[f] += 1
		in_edge[in_fill[t]] = e
		in_fill[t] += 1

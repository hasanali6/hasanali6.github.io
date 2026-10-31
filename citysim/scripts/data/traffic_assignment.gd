class_name TrafficAssignment
extends RefCounted
## One round of traffic assignment: routes every trip of the day over the
## road network with travel times from the previous round's congestion,
## adds the trips onto the roads and smooths the result with the previous
## volumes (method of successive averages, so congestion settles instead of
## flipping between routes).
##
## Trips are grouped by an anchor segment (the workplace, shop, factory or
## service building's road): one shortest-time tree per anchor and direction
## routes all of them, and loads are pushed along the tree once instead of
## walking every path. The trees are kept for routing visible vehicles.
##
## Built on the main thread, then run() on a WorkerThreadPool thread (or
## directly in tests). It only touches its own data.

# --- Inputs -----------------------------------------------------------------
var graph: TrafficGraph
var cfg: Dictionary
var trip_origin := PackedInt32Array()   # segment index where the trip starts
var trip_dest := PackedInt32Array()     # segment index where it ends
var trip_count := PackedFloat32Array()  # trips per day
var trip_forward := PackedByteArray()   # 1: routed by a forward tree from the origin, 0: reverse tree into the destination
var previous := PackedFloat32Array()    # smoothed daily volumes per directed edge from the last round
# Optional bookkeeping done on the worker thread too (see summarize()).
var trip_seg_o := PackedInt32Array()    # segment ids, for the commute table
var trip_seg_d := PackedInt32Array()
var trip_group := PackedInt32Array()    # spawn group per trip
var trip_commute := PackedByteArray()   # 1 = home -> work trip

# --- Outputs ----------------------------------------------------------------
var volumes := PackedFloat32Array()     # daily vehicles per directed edge (smoothed)
var factors := PackedFloat32Array()     # speed factor per directed edge
var trip_time := PackedFloat32Array()   # seconds, TrafficRules.FAR when unreachable
var trip_node := PackedInt32Array()     # junction where the route leaves the non-anchor segment's tree side
var trip_exit := PackedInt32Array()     # directed edge used on the non-anchor segment
var fwd_trees: Dictionary = {}          # anchor segment index -> via
var rev_trees: Dictionary = {}          # anchor segment index -> via
var groups: Dictionary = {}             # spawn group -> [trip ids, cumulative counts, total]
var commute: Dictionary = {}            # Vector2i(home seg id, work seg id) -> minutes
var avg_commute: float = 0.0
var total_trips: float = 0.0
var jammed: int = 0
var elapsed_ms: int = 0
var done: bool = false


func run() -> void:
	var start := Time.get_ticks_msec()
	var n_trips := trip_origin.size()
	var ne := graph.edge_count()
	var costs := TrafficRules.edge_costs(graph, TrafficRules.factors_for(graph, previous, cfg), cfg)
	var fresh := PackedFloat32Array()
	fresh.resize(ne)
	trip_time.resize(n_trips)
	trip_time.fill(TrafficRules.FAR)
	trip_node.resize(n_trips)
	trip_node.fill(-1)
	trip_exit.resize(n_trips)
	trip_exit.fill(-1)
	var groups := {}
	for i in n_trips:
		var anchor := trip_origin[i] if trip_forward[i] == 1 else trip_dest[i]
		var key := anchor * 2 + trip_forward[i]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(i)
	var node_load := PackedFloat32Array()
	node_load.resize(graph.node_count())
	for key: int in groups:
		var anchor := key >> 1
		var forward := (key & 1) == 1
		var seeds := anchor_seeds(anchor, forward, costs)
		if (seeds[0] as PackedInt32Array).is_empty():
			continue
		var res := TrafficRules.dijkstra(graph, seeds[0], seeds[1], costs, forward)
		var dist: PackedFloat32Array = res["dist"]
		node_load.fill(0.0)
		for i in groups[key]:
			var other := trip_dest[i] if forward else trip_origin[i]
			if other == anchor:
				continue
			var pick := best_end(other, dist, forward, costs)
			if pick[0] < 0:
				continue
			trip_time[i] = pick[1]
			trip_node[i] = pick[0]
			trip_exit[i] = pick[2]
			node_load[pick[0]] += trip_count[i]
			fresh[pick[2]] += trip_count[i]
		TrafficRules.accumulate(graph, res["via"], res["order"], node_load, fresh, forward)
		if forward:
			fwd_trees[anchor] = res["via"]
		else:
			rev_trees[anchor] = res["via"]
	var smoothing := float(cfg["assignment"]["smoothing"]) if previous.size() == ne else 1.0
	volumes.resize(ne)
	for e in ne:
		var old := previous[e] if previous.size() == ne else 0.0
		volumes[e] = old + (fresh[e] - old) * smoothing
	factors = TrafficRules.factors_for(graph, volumes, cfg)
	summarize()
	elapsed_ms = Time.get_ticks_msec() - start
	done = true


## Spawn tables, commute times and jam count, so the main thread only has
## to swap results in.
func summarize() -> void:
	var lists := {}
	var commute_sum := 0.0
	var commute_n := 0.0
	total_trips = 0.0
	for i in trip_count.size():
		total_trips += trip_count[i]
		if trip_time[i] >= TrafficRules.FAR:
			continue
		if trip_commute.size() == trip_count.size() and trip_commute[i] == 1:
			var minutes := trip_time[i] / 60.0
			commute[Vector2i(trip_seg_o[i], trip_seg_d[i])] = minutes
			commute_sum += minutes * trip_count[i]
			commute_n += trip_count[i]
		if trip_group.size() == trip_count.size():
			var g := trip_group[i]
			if not lists.has(g):
				lists[g] = [[], [], 0.0]
			var entry: Array = lists[g]
			entry[2] = float(entry[2]) + trip_count[i]
			(entry[0] as Array).append(i)
			(entry[1] as Array).append(float(entry[2]))
	for g: int in lists:
		var entry: Array = lists[g]
		groups[g] = [PackedInt32Array(entry[0]), PackedFloat32Array(entry[1]), entry[2]]
	avg_commute = 0.0 if commute_n <= 0.0 else commute_sum / commute_n
	var peak := float(cfg["peak_hour_share"])
	var limit := float(cfg["jam"]["ratio"])
	jammed = 0
	for s in graph.seg_ids.size():
		var cap := maxf(graph.seg_capacity[s], 1.0)
		if maxf(volumes[s * 2], volumes[s * 2 + 1]) * peak / cap > limit:
			jammed += 1


## Seeds of the tree for trips anchored at segment s: a forward tree starts
## from the middle of s towards its ends, a reverse tree ends there (entered
## from either end). Returns [nodes, start costs].
func anchor_seeds(s: int, forward: bool, costs: PackedFloat32Array) -> Array:
	var nodes := PackedInt32Array()
	var start := PackedFloat32Array()
	var e0 := s * 2
	var e1 := e0 + 1
	if forward:
		nodes.append(graph.seg_b[s])
		start.append(costs[e0] * 0.5)
		if graph.edge_allowed(e1):
			nodes.append(graph.seg_a[s])
			start.append(costs[e1] * 0.5)
	else:
		nodes.append(graph.seg_a[s])
		start.append(costs[e0] * 0.5)
		if graph.edge_allowed(e1):
			nodes.append(graph.seg_b[s])
			start.append(costs[e1] * 0.5)
	return [nodes, start]


## Best way to connect segment o to a tree: forward trees enter o through
## one of its ends, reverse trees leave o through one of them.
## Returns [junction node, time, directed edge on o] or [-1, FAR, -1].
func best_end(o: int, dist: PackedFloat32Array, forward: bool, costs: PackedFloat32Array) -> Array:
	var best := [-1, TrafficRules.FAR, -1]
	var e0 := o * 2
	var e1 := e0 + 1
	var candidates := []
	if forward:
		candidates.append([graph.seg_a[o], e0])          # enter at a, drive a -> b
		if graph.edge_allowed(e1):
			candidates.append([graph.seg_b[o], e1])      # enter at b, drive b -> a
	else:
		candidates.append([graph.seg_b[o], e0])          # leave towards b
		if graph.edge_allowed(e1):
			candidates.append([graph.seg_a[o], e1])      # leave towards a
	for c: Array in candidates:
		var node: int = c[0]
		if dist[node] >= TrafficRules.FAR:
			continue
		var t := dist[node] + costs[c[1]] * 0.5
		if t < float(best[1]):
			best = [node, t, c[1]]
	return best

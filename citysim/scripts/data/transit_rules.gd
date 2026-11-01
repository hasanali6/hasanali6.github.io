class_name TransitRules
extends RefCounted
## Pure maths for public transport and districts, testable headless:
##  * the loop a line drives through its stops (shortest paths stop to stop,
##    never turning around at a stop, closing back onto the first one),
##  * distances along that loop,
##  * mode choice between car and transit (logit on generalised minutes),
##  * polygon helpers for districts.


## Loop route of a line through stops given as [segment index, t] in a
## TrafficGraph. Returns {ok, route (directed edges), stop_edge (route index
## per stop), length, error}. Both starting directions are tried and the
## shorter closed loop kept.
static func loop_route(g: TrafficGraph, stops: Array, costs: PackedFloat32Array) -> Dictionary:
	var best := {"ok": false, "error": "TRANSIT_ERR_ROUTE"}
	if stops.size() < 2:
		best["error"] = "TRANSIT_ERR_STOPS"
		return best
	var first: Array = stops[0]
	for d0 in 2:
		if not g.edge_allowed(int(first[0]) * 2 + d0):
			continue
		var res := _loop_from(g, stops, costs, d0)
		if res["ok"] and (not best["ok"] or float(res["cost"]) < float(best["cost"])):
			best = res
	return best


static func _loop_from(g: TrafficGraph, stops: Array, costs: PackedFloat32Array, d0: int) -> Dictionary:
	var n := stops.size()
	var route := PackedInt32Array()
	var stop_edge := PackedInt32Array()
	var first: Array = stops[0]
	route.append(int(first[0]) * 2 + d0)
	stop_edge.append(0)
	var dir := d0
	var cost := 0.0
	for i in n:
		var a: Array = stops[i]
		var b: Array = stops[(i + 1) % n]
		var leg := _leg(g, a, dir, b, d0 if i == n - 1 else -1, costs)
		if not leg["ok"]:
			return {"ok": false, "error": "TRANSIT_ERR_ROUTE"}
		cost += float(leg["cost"])
		if not leg["direct"]:
			route.append_array(leg["edges"])
			route.append(int(b[0]) * 2 + int(leg["arrive"]))
		if i < n - 1:
			stop_edge.append(route.size() - 1)
		dir = int(leg["arrive"])
	# The last entry is the first one again: close the cycle.
	if route.size() > 1 and route[route.size() - 1] == route[0]:
		var last := route.size() - 1
		route.remove_at(last)
		for k in stop_edge.size():
			if stop_edge[k] == last:
				stop_edge[k] = 0
	var length := 0.0
	for e in route:
		length += g.seg_len[e >> 1]
	return {"ok": true, "route": route, "stop_edge": stop_edge, "cost": cost, "length": length}


## One leg from stop a (driving in direction `dir` on its segment) to stop b.
## forced >= 0 requires arriving at b in that direction. Searched over
## directed edges so a bus never turns round on the spot (there are no
## U-turn lanes at junctions).
static func _leg(g: TrafficGraph, a: Array, dir: int, b: Array, forced: int, costs: PackedFloat32Array) -> Dictionary:
	var sa := int(a[0])
	var sb := int(b[0])
	var ta := float(a[1])
	var tb := float(b[1])
	if sa == sb and (forced < 0 or forced == dir):
		if (dir == 0 and tb > ta + 0.001) or (dir == 1 and tb < ta - 0.001):
			return {"ok": true, "direct": true, "edges": PackedInt32Array(), "arrive": dir,
				"cost": absf(tb - ta) * costs[sa * 2 + dir]}
	var e_start := sa * 2 + dir
	var init := costs[e_start] * ((1.0 - ta) if dir == 0 else ta)
	var res := edge_dijkstra(g, e_start, init, costs)
	var dist: PackedFloat32Array = res["dist"]
	var best_dir := -1
	var best_cost := TrafficRules.FAR
	for arrive in 2:
		if forced >= 0 and arrive != forced:
			continue
		var e_arr := sb * 2 + arrive
		if not g.edge_allowed(e_arr) or dist[e_arr] >= TrafficRules.FAR:
			continue
		var c := dist[e_arr] - costs[e_arr] * ((1.0 - tb) if arrive == 0 else tb)
		if c < best_cost:
			best_cost = c
			best_dir = arrive
	if best_dir < 0:
		return {"ok": false}
	var prev: PackedInt32Array = res["prev"]
	var path := PackedInt32Array()
	var cur := prev[sb * 2 + best_dir]
	var guard := g.edge_count()
	while cur >= 0 and guard > 0:
		path.append(cur)
		cur = prev[cur]
		guard -= 1
	path.reverse()
	return {"ok": true, "direct": false, "edges": path, "arrive": best_dir, "cost": best_cost}


## Shortest times over directed edges, leaving the end of e_start (reached
## at cost `init`) without U-turns. dist[e] is the time to reach the end of
## edge e; prev[e] the edge before it (-1 for the first one after e_start).
static func edge_dijkstra(g: TrafficGraph, e_start: int, init: float, costs: PackedFloat32Array) -> Dictionary:
	var ne := g.edge_count()
	var dist := PackedFloat32Array()
	dist.resize(ne)
	dist.fill(TrafficRules.FAR)
	var prev := PackedInt32Array()
	prev.resize(ne)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(ne)
	var heap_e := PackedInt32Array()
	var heap_k := PackedFloat32Array()
	var n0 := g.edge_to(e_start)
	for k in range(g.out_start[n0], g.out_start[n0 + 1]):
		var e2 := g.out_edge[k]
		if e2 == (e_start ^ 1):
			continue
		var c := init + costs[e2]
		if c < dist[e2]:
			dist[e2] = c
			TrafficRules._push(heap_e, heap_k, e2, c)
	while not heap_e.is_empty():
		var top := TrafficRules._pop(heap_e, heap_k)
		var e: int = top[0]
		if done[e] == 1 or float(top[1]) > dist[e]:
			continue
		done[e] = 1
		var n := g.edge_to(e)
		for k in range(g.out_start[n], g.out_start[n + 1]):
			var e2 := g.out_edge[k]
			if e2 == (e ^ 1):
				continue
			var nd := dist[e] + costs[e2]
			if nd < dist[e2]:
				dist[e2] = nd
				prev[e2] = e
				TrafficRules._push(heap_e, heap_k, e2, nd)
	return {"dist": dist, "prev": prev}


## Distance along the loop to each stop from the start of route[0].
static func stop_distances(g: TrafficGraph, route: PackedInt32Array, stop_edge: PackedInt32Array, stops: Array) -> PackedFloat32Array:
	var start := PackedFloat32Array()
	var acc := 0.0
	for e in route:
		start.append(acc)
		acc += g.seg_len[e >> 1]
	var out := PackedFloat32Array()
	for i in stops.size():
		var e := route[stop_edge[i]]
		var t := float((stops[i] as Array)[1])
		var frac := t if (e & 1) == 0 else 1.0 - t
		out.append(start[stop_edge[i]] + frac * g.seg_len[e >> 1])
	return out


## Forward distance along a loop of length `loop` from position a to b.
static func along(a: float, b: float, loop: float) -> float:
	var d := fposmod(b - a, loop)
	return loop if d < 0.01 else d


## Underground (metro) line: a smooth open tunnel through the stations in
## order, trains running there and back. Returns {pts: Array of Vector2 every
## <= `step` m, stop_dist: distance of each station from the first, length}.
static func tunnel_path(stations: Array, step: float) -> Dictionary:
	var pts: Array = []
	var stop_dist := PackedFloat32Array()
	var n := stations.size()
	if n < 2:
		return {"pts": pts, "stop_dist": stop_dist, "length": 0.0}
	var acc := 0.0
	var last: Vector2 = stations[0]
	pts.append(last)
	stop_dist.append(0.0)
	for i in n - 1:
		# Catmull-Rom between station i and i + 1, ends held straight.
		var p0: Vector2 = stations[maxi(i - 1, 0)]
		var p1: Vector2 = stations[i]
		var p2: Vector2 = stations[i + 1]
		var p3: Vector2 = stations[mini(i + 2, n - 1)]
		var parts := maxi(int(ceil(p1.distance_to(p2) * 1.5 / step)), 1)   # curve speed varies
		for k in range(1, parts + 1):
			var t := float(k) / parts
			var q := 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)
			if k == parts:
				q = p2
			acc += last.distance_to(q)
			last = q
			pts.append(q)
		stop_dist.append(acc)
	return {"pts": pts, "stop_dist": stop_dist, "length": acc}


## Ride between two stations of a there-and-back line.
static func shuttle(a: float, b: float) -> float:
	return absf(b - a)


## Share of trips taking transit: logit on generalised minutes, capped
## (some people always drive). transit_minutes < 0 means no transit option.
static func transit_share(car_minutes: float, transit_minutes: float, cfg: Dictionary) -> float:
	if transit_minutes < 0.0:
		return 0.0
	var x := clampf((transit_minutes - car_minutes) / float(cfg["scale_minutes"]), -30.0, 30.0)
	return float(cfg["max_share"]) / (1.0 + exp(x))


## A polygon is usable as a district if no two non-adjacent edges cross.
static func polygon_simple(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	for i in n:
		var a1 := poly[i]
		var a2 := poly[(i + 1) % n]
		for j in range(i + 1, n):
			if j == i or (j + 1) % n == i or j == (i + 1) % n:
				continue
			if Geometry2D.segment_intersects_segment(a1, a2, poly[j], poly[(j + 1) % n]) != null:
				return false
	return true


static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func polygon_centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)

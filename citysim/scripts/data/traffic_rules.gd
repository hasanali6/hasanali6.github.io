class_name TrafficRules
extends RefCounted
## Pure traffic maths, testable headless and safe to call from a worker
## thread: congestion (BPR), shortest-time trees over a TrafficGraph, flow
## accumulation along trees, signal groups, turn classification and the
## vehicle motion model shared with assets/materials/vehicle.gdshader.

const FAR := 1e30


## Bureau of Public Roads curve: speed factor (0..1] from peak-hour volume
## and capacity. 1 when empty, ~0.87 at capacity, falling fast beyond.
static func speed_factor(volume_per_hour: float, capacity: float, alpha: float, beta: float, min_factor: float) -> float:
	if capacity <= 0.0:
		return min_factor
	return maxf(1.0 / (1.0 + alpha * pow(maxf(volume_per_hour, 0.0) / capacity, beta)), min_factor)


## Speed factor per directed edge from daily volumes.
static func factors_for(g: TrafficGraph, volumes: PackedFloat32Array, cfg: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(g.edge_count())
	out.fill(1.0)
	if volumes.size() != g.edge_count():
		return out
	var peak := float(cfg["peak_hour_share"])
	var alpha := float(cfg["bpr_alpha"])
	var beta := float(cfg["bpr_beta"])
	var floor_factor := float(cfg["min_speed_factor"])
	for e in g.edge_count():
		out[e] = speed_factor(volumes[e] * peak, g.seg_capacity[e >> 1], alpha, beta, floor_factor)
	return out


## Travel time (s) per directed edge: driving time at the congested speed
## plus a delay at the junction it leads into (lights, or giving way).
static func edge_costs(g: TrafficGraph, factors: PackedFloat32Array, cfg: Dictionary) -> PackedFloat32Array:
	var delays: Dictionary = cfg["junction_delay_s"]
	var lit := float(delays["lit"])
	var plain := float(delays["plain"])
	var out := PackedFloat32Array()
	out.resize(g.edge_count())
	for e in g.edge_count():
		var s := e >> 1
		var to := g.edge_to(e)
		var delay := 0.0
		if g.node_lit[to] == 1:
			delay = lit
		elif g.node_degree[to] >= 3:
			delay = plain
		out[e] = g.seg_len[s] / maxf(g.seg_speed[s] * factors[e], 0.1) + delay
	return out


## Shortest travel times over directed edges from (forward) or to (reverse)
## a set of seed nodes with start costs. Returns {dist, via, order}:
## via[n] is the directed edge linking n to its parent in the tree (forward:
## the edge entering n; reverse: the edge leaving n towards the seeds), -1 at
## seeds and unreached nodes; order lists the nodes in settle order.
static func dijkstra(g: TrafficGraph, seed_nodes: PackedInt32Array, seed_costs: PackedFloat32Array,
		costs: PackedFloat32Array, forward: bool) -> Dictionary:
	var n := g.node_count()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(FAR)
	var via := PackedInt32Array()
	via.resize(n)
	via.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	var order := PackedInt32Array()
	var heap_nodes := PackedInt32Array()
	var heap_keys := PackedFloat32Array()
	for i in seed_nodes.size():
		var s := seed_nodes[i]
		if seed_costs[i] < dist[s]:
			dist[s] = seed_costs[i]
			_push(heap_nodes, heap_keys, s, seed_costs[i])
	while not heap_nodes.is_empty():
		var top := _pop(heap_nodes, heap_keys)
		var u: int = top[0]
		if done[u] == 1 or float(top[1]) > dist[u]:
			continue
		done[u] = 1
		order.append(u)
		var du := dist[u]
		if forward:
			for k in range(g.out_start[u], g.out_start[u + 1]):
				var e := g.out_edge[k]
				var w := g.edge_to(e)
				var nd := du + costs[e]
				if nd < dist[w]:
					dist[w] = nd
					via[w] = e
					_push(heap_nodes, heap_keys, w, nd)
		else:
			for k in range(g.in_start[u], g.in_start[u + 1]):
				var e := g.in_edge[k]
				var w := g.edge_from(e)
				var nd := du + costs[e]
				if nd < dist[w]:
					dist[w] = nd
					via[w] = e
					_push(heap_nodes, heap_keys, w, nd)
	return {"dist": dist, "via": via, "order": order}


## Directed edges from the seeds of a forward tree to node n, in travel order.
static func path_to(g: TrafficGraph, via: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cur := n
	var guard := g.node_count()
	while via[cur] >= 0 and guard > 0:
		var e := via[cur]
		out.append(e)
		cur = g.edge_from(e)
		guard -= 1
	out.reverse()
	return out


## Directed edges from node n to the seeds of a reverse tree, in travel order.
static func path_from(g: TrafficGraph, via: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cur := n
	var guard := g.node_count()
	while via[cur] >= 0 and guard > 0:
		var e := via[cur]
		out.append(e)
		cur = g.edge_to(e)
		guard -= 1
	return out


## Moves the loads placed on nodes along a tree to its seeds and adds them to
## the edge volumes. Walking the settle order backwards visits every node
## before its parent, so each edge is touched once.
static func accumulate(g: TrafficGraph, via: PackedInt32Array, order: PackedInt32Array,
		node_load: PackedFloat32Array, volumes: PackedFloat32Array, forward: bool) -> void:
	for k in range(order.size() - 1, -1, -1):
		var n := order[k]
		var load := node_load[n]
		if load == 0.0:
			continue
		var e := via[n]
		if e < 0:
			continue
		volumes[e] += load
		var parent := g.edge_from(e) if forward else g.edge_to(e)
		node_load[parent] += load


## Two signal groups for the legs of a junction (directions leaving it):
## the first leg and the legs roughly opposite it share phase 0.
static func signal_groups(dirs: Array) -> PackedInt32Array:
	var groups := PackedInt32Array()
	groups.resize(dirs.size())
	groups.fill(1)
	if dirs.is_empty():
		return groups
	groups[0] = 0
	var first: Vector2 = dirs[0]
	for i in range(1, dirs.size()):
		if (dirs[i] as Vector2).dot(first) < -0.6:
			groups[i] = 0
	if not 1 in groups and dirs.size() > 1:
		groups[dirs.size() - 1] = 1
	return groups


## -1 left, 0 straight, 1 right for heading d_in followed by d_out, in plan
## coordinates (x right, z towards the bottom of the map).
static func turn_of(d_in: Vector2, d_out: Vector2) -> int:
	if d_in.dot(d_out) > 0.82:
		return 0
	return 1 if d_in.x * d_out.y - d_in.y * d_out.x > 0.0 else -1


## Lane to take for the next turn: rightmost for a right turn, leftmost for
## a left turn, keep the lane (clamped) when going straight. Lane 0 is the
## one next to the centre line.
static func lane_for_turn(turn: int, current: int, lanes: int) -> int:
	if turn > 0:
		return lanes - 1
	if turn < 0:
		return 0
	return clampi(current, 0, lanes - 1)


## Distance along a lane piece at time t for a vehicle that was at s0 at
## time t0 cruising at v (accel = 1: starting from rest), easing to a stop
## at s_stop. Must match vehicle.gdshader.
static func position_at(t: float, s0: float, t0: float, v: float, s_stop: float, accel: float,
		accel_time: float, softness: float) -> float:
	var tau := maxf(t - t0, 0.0)
	var lin := s0 + v * (tau - accel * accel_time * (1.0 - exp(-tau / accel_time)))
	var x := (s_stop - lin) / softness
	if x > 20.0:
		return lin
	return s_stop - softness * log(1.0 + exp(x))


## Speed (m/s) at time t, ignoring the easing into a stop.
static func speed_at(t: float, t0: float, v: float, accel: float, accel_time: float) -> float:
	var tau := maxf(t - t0, 0.0)
	return v * (1.0 - accel * exp(-tau / accel_time))


## Time when a free-running vehicle reaches s_target.
static func time_to_reach(s_target: float, s0: float, t0: float, v: float, accel: float, accel_time: float) -> float:
	var d := s_target - s0
	if d <= 0.0:
		return t0
	var base := d / maxf(v, 0.01)
	var tau := base
	if absf(accel) > 0.01:
		for i in 3:
			tau = base + accel_time * (1.0 - exp(-tau / accel_time))
	return t0 + tau


## Happiness change from a commute of `minutes` (data/traffic.json "commute").
static func commute_happiness(minutes: float, cfg: Dictionary) -> float:
	return -clampf((minutes - float(cfg["free_minutes"])) * float(cfg["penalty_per_minute"]), 0.0, float(cfg["max_penalty"]))


## A 24-value profile sampled at a fractional hour.
static func hourly(profile: Array, hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var i := int(h)
	return lerpf(float(profile[i]), float(profile[(i + 1) % 24]), h - i)


static func _push(nodes: PackedInt32Array, keys: PackedFloat32Array, node: int, key: float) -> void:
	nodes.append(node)
	keys.append(key)
	var i := nodes.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if keys[p] <= keys[i]:
			break
		var tn := nodes[p]
		nodes[p] = nodes[i]
		nodes[i] = tn
		var tk := keys[p]
		keys[p] = keys[i]
		keys[i] = tk
		i = p


static func _pop(nodes: PackedInt32Array, keys: PackedFloat32Array) -> Array:
	var top := [nodes[0], keys[0]]
	var last := nodes.size() - 1
	nodes[0] = nodes[last]
	keys[0] = keys[last]
	nodes.remove_at(last)
	keys.remove_at(last)
	var n := nodes.size()
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var m := l
		if l + 1 < n and keys[l + 1] < keys[l]:
			m = l + 1
		if keys[m] >= keys[i]:
			break
		var tn := nodes[m]
		nodes[m] = nodes[i]
		nodes[i] = tn
		var tk := keys[m]
		keys[m] = keys[i]
		keys[i] = tk
		i = m
	return top

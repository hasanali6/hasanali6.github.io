class_name ServiceRules
extends RefCounted
## Pure maths for city services and utilities, testable headless:
##  * network distances from a point on a road (Dijkstra over junctions),
##  * coverage strength per road segment within a service radius,
##  * connected road networks (utilities flow through the roads),
##  * serving demands in order until the supply runs out,
##  * a coarse pollution grid that sources stamp their falloff into.


## Shortest road distance from a point on segment `seg_id` at parameter t to
## every junction within max_dist. Returns node id -> metres.
static func node_distances(graph: RoadGraph, seg_id: int, t: float, max_dist: float) -> Dictionary:
	var dist := {}
	if not graph.segments.has(seg_id):
		return dist
	var seg: RoadGraph.RoadSegment = graph.segments[seg_id]
	var heap_nodes := PackedInt32Array()
	var heap_keys := PackedFloat32Array()
	_push(heap_nodes, heap_keys, seg.a, seg.length * t)
	_push(heap_nodes, heap_keys, seg.b, seg.length * (1.0 - t))
	while not heap_nodes.is_empty():
		var top := _pop(heap_nodes, heap_keys)
		var nid: int = top[0]
		var d: float = top[1]
		if dist.has(nid) or d > max_dist:
			continue
		dist[nid] = d
		for sid in (graph.nodes[nid] as RoadGraph.RoadNode).segments:
			var other := graph.other_node(sid, nid)
			if not dist.has(other):
				_push(heap_nodes, heap_keys, other, d + (graph.segments[sid] as RoadGraph.RoadSegment).length)
	return dist


## Coverage 0..1 at each segment's midpoint from a service at (seg_id, t):
## 1 at the service, falling linearly to 0 at `radius` road metres. Only the
## segments around junctions the search reached are visited.
static func segment_coverage(graph: RoadGraph, seg_id: int, t: float, radius: float) -> Dictionary:
	var out := {}
	if radius <= 0.0 or not graph.segments.has(seg_id):
		return out
	var own: RoadGraph.RoadSegment = graph.segments[seg_id]
	var d_own := absf(t - 0.5) * own.length
	if d_own < radius:
		out[seg_id] = 1.0 - d_own / radius
	var dist := node_distances(graph, seg_id, t, radius)
	for nid: int in dist:
		var dn: float = dist[nid]
		for sid in (graph.nodes[nid] as RoadGraph.RoadNode).segments:
			if sid == seg_id:
				continue
			var d := dn + (graph.segments[sid] as RoadGraph.RoadSegment).length * 0.5
			if d < radius:
				var v := 1.0 - d / radius
				if v > float(out.get(sid, 0.0)):
					out[sid] = v
	return out


## Connected road networks: node id -> component id (smallest node id in it).
static func components(graph: RoadGraph) -> Dictionary:
	var parent := {}
	for nid: int in graph.nodes:
		parent[nid] = nid
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		var ra := _find(parent, seg.a)
		var rb := _find(parent, seg.b)
		if ra != rb:
			parent[maxi(ra, rb)] = mini(ra, rb)
	var out := {}
	for nid: int in parent:
		out[nid] = _find(parent, nid)
	return out


static func _find(parent: Dictionary, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


## Serves demands [[id, amount], ...] in the given order while supply lasts.
## Returns id -> true for every served demand.
static func distribute(supply: float, demands: Array) -> Dictionary:
	var served := {}
	var left := supply
	for entry: Array in demands:
		var amount := float(entry[1])
		if amount <= left + 1e-6:
			served[entry[0]] = true
			left -= amount
	return served


## Budget slider (0.5..1.5) to service efficiency with diminishing returns.
static func efficiency(budget: float, exponent: float) -> float:
	return pow(maxf(budget, 0.0), exponent)


## Coverage of one category from a building's coverage dictionary; education
## counts the best of its three school levels.
static func category_coverage(cov: Dictionary, category: String) -> float:
	if category == "education":
		return maxf(maxf(float(cov.get("education0", 0.0)), float(cov.get("education1", 0.0))), float(cov.get("education2", 0.0)))
	return float(cov.get(category, 0.0))


## Happiness from service coverage: a bonus for each service that covers a
## home, a penalty for each one missing, scaled by `maturity` (0..1) so a
## small town is not punished for lacking a hospital yet.
static func coverage_happiness(cov: Dictionary, categories: Dictionary, maturity: float) -> float:
	var h := 0.0
	for cat: String in categories:
		var c: Dictionary = categories[cat]
		if not c.has("happy_bonus"):
			continue
		var v := category_coverage(cov, cat)
		h += float(c["happy_bonus"]) * v - float(c["happy_penalty"]) * (1.0 - v) * maturity
	return h


## Happiness from utilities and pollution; `utilities` holds power / water /
## sewage / polluted_water flags (a building record works).
static func utility_happiness(utilities: Dictionary, pollution: float, fx: Dictionary) -> float:
	var h := 0.0
	if not utilities.get("power", true):
		h += float(fx["no_power_happiness"])
	if not utilities.get("water", true):
		h += float(fx["no_water_happiness"])
	elif utilities.get("polluted_water", false):
		h += float(fx["polluted_water_happiness"])
	if not utilities.get("sewage", true):
		h += float(fx["no_sewage_happiness"])
	return h + float(fx["pollution_happiness"]) * clampf(pollution, 0.0, 1.0)


## Total happiness change for living in a building.
static func happiness_delta(cov: Dictionary, utilities: Dictionary, pollution: float,
		categories: Dictionary, fx: Dictionary, maturity: float) -> float:
	return coverage_happiness(cov, categories, maturity) + utility_happiness(utilities, pollution, fx)


## Monthly death chance multiplier from health coverage (0..1).
static func death_multiplier(health: float, fx: Dictionary) -> float:
	return lerpf(float(fx["death_multiplier_uncovered"]), float(fx["death_multiplier_covered"]), clampf(health, 0.0, 1.0))


## Chances that a child growing up here finishes high school (x) and then
## university (y), from the school coverage of the home.
static func education_chances(cov: Dictionary, fx: Dictionary) -> Vector2:
	return Vector2(float(cov.get("education1", 0.0)) * float(fx["high_school_chance"]),
		float(cov.get("education2", 0.0)) * float(fx["university_chance"]))


static func _push(nodes: PackedInt32Array, keys: PackedFloat32Array, node: int, key: float) -> void:
	nodes.append(node)
	keys.append(key)
	var i := nodes.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if keys[p] <= keys[i]:
			break
		_swap(nodes, keys, i, p)
		i = p


static func _pop(nodes: PackedInt32Array, keys: PackedFloat32Array) -> Array:
	var top := [nodes[0], keys[0]]
	var last := nodes.size() - 1
	nodes[0] = nodes[last]
	keys[0] = keys[last]
	nodes.remove_at(last)
	keys.remove_at(last)
	var i := 0
	var n := nodes.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and keys[l] < keys[m]:
			m = l
		if r < n and keys[r] < keys[m]:
			m = r
		if m == i:
			break
		_swap(nodes, keys, i, m)
		i = m
	return top


static func _swap(nodes: PackedInt32Array, keys: PackedFloat32Array, a: int, b: int) -> void:
	var tn := nodes[a]
	nodes[a] = nodes[b]
	nodes[b] = tn
	var tk := keys[a]
	keys[a] = keys[b]
	keys[b] = tk


## Coarse square grid of pollution 0..1 over the map. Sources add a linear
## falloff (strength at the source, 0 at the radius); values saturate at 1.
class PollutionGrid:
	extends RefCounted
	var cell: float
	var half: float
	var size: int
	var values := PackedFloat32Array()

	func _init(cell_m: float, map_half: float) -> void:
		cell = cell_m
		half = map_half
		size = ceili(map_half * 2.0 / cell_m)
		values.resize(size * size)

	func clear() -> void:
		values.fill(0.0)

	func stamp(p: Vector2, radius: float, strength: float) -> void:
		var lo := _index(p - Vector2(radius, radius))
		var hi := _index(p + Vector2(radius, radius))
		for y in range(maxi(lo.y, 0), mini(hi.y, size - 1) + 1):
			for x in range(maxi(lo.x, 0), mini(hi.x, size - 1) + 1):
				var c := Vector2((x + 0.5) * cell - half, (y + 0.5) * cell - half)
				var d := c.distance_to(p)
				if d < radius:
					var i := y * size + x
					values[i] = minf(values[i] + strength * (1.0 - d / radius), 1.0)

	func sample(p: Vector2) -> float:
		var idx := _index(p)
		if idx.x < 0 or idx.y < 0 or idx.x >= size or idx.y >= size:
			return 0.0
		return values[idx.y * size + idx.x]

	func _index(p: Vector2) -> Vector2i:
		return Vector2i(floori((p.x + half) / cell), floori((p.y + half) / cell))

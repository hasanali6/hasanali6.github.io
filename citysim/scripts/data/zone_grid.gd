class_name ZoneGrid
extends RefCounted
## Zoning cells generated along road sides, Cities: Skylines style: every road
## segment side gets rows of 8 m cells up to `max_depth` deep, aligned to the
## road, so zoning follows curves and diagonals. A cell that would sit on
## another road or overlap a cell of an older block is dropped, and a row stops
## at its first blocked cell so every cell keeps road access.
##
## Data is stored as parallel packed arrays (one entry per cell) so the
## simulation can scan thousands of cells cheaply. Zone ids are indices into
## data/zones.json "order" plus one; 0 means unzoned. building is -1 when free.

const UNZONED := 0
const FREE := -1
const _ROAD_BUCKET := 32.0  # metres; bucket size of the road lookup grid

var cell_size: float
var max_depth: int
var road_clearance: float
var overlap: float
var restore_radius: float

var centers := PackedVector2Array()
var dirs := PackedVector2Array()      # unit vector along the road
var fronts := PackedVector2Array()    # unit vector from the cell towards its road
var segment := PackedInt32Array()
var side := PackedInt32Array()        # +1 = left of the segment, -1 = right
var along := PackedInt32Array()       # index along the row
var depth := PackedInt32Array()       # 0 = touching the road
var zone := PackedInt32Array()
var building := PackedInt32Array()

var _water: MapWater
var _lookup: Dictionary = {}   # Vector4i(segment, side, along, depth) -> cell index
var _buckets: Dictionary = {}  # Vector2i -> PackedInt32Array of cell indices


func _init(config: Dictionary) -> void:
	cell_size = float(config["size_m"])
	max_depth = int(config["depth"])
	road_clearance = float(config["road_clearance_m"])
	overlap = float(config["overlap_m"])
	restore_radius = float(config["restore_radius_m"])


func size() -> int:
	return centers.size()


func index_of(seg_id: int, row_side: int, along_index: int, depth_index: int) -> int:
	return _lookup.get(Vector4i(seg_id, row_side, along_index, depth_index), -1)


## Regenerates all cells for the current road network. Zoning and building
## ownership are carried over to new cells at (almost) the same position, so
## splitting a road by drawing across it keeps the zoning around it.
func rebuild(graph: RoadGraph, types: Dictionary, mesh_cfg: Dictionary, playable_half: float, water: MapWater = null) -> void:
	_water = water
	var old_centers := centers
	var old_zone := zone
	var old_building := building
	var old_buckets := _buckets
	_clear()

	var seg_index := _segment_buckets(graph)
	var ids := graph.segments.keys()
	ids.sort()  # older roads claim space first
	for sid: int in ids:
		_add_rows(graph, sid, types, mesh_cfg, playable_half, seg_index)

	for i in size():
		var best := -1
		var best_d := restore_radius
		for j in _near(old_buckets, centers[i], restore_radius):
			var d := old_centers[j].distance_to(centers[i])
			if d < best_d:
				best_d = d
				best = j
		if best >= 0:
			zone[i] = old_zone[best]
			building[i] = old_building[best]


func _clear() -> void:
	centers = PackedVector2Array()
	dirs = PackedVector2Array()
	fronts = PackedVector2Array()
	segment = PackedInt32Array()
	side = PackedInt32Array()
	along = PackedInt32Array()
	depth = PackedInt32Array()
	zone = PackedInt32Array()
	building = PackedInt32Array()
	_lookup = {}
	_buckets = {}


func _add_rows(graph: RoadGraph, sid: int, types: Dictionary, mesh_cfg: Dictionary,
		playable_half: float, seg_index: Dictionary) -> void:
	var seg: RoadGraph.RoadSegment = graph.segments[sid]
	# Highways have no frontage: nothing is zoned along them.
	if not bool((types[seg.type] as Dictionary).get("zoning", true)):
		return
	var hw := RoadTypes.half_width(types[seg.type])
	var trim_a := RoadMeshBuilder.junction_radius(graph, seg.a, types, mesh_cfg)
	var trim_b := RoadMeshBuilder.junction_radius(graph, seg.b, types, mesh_cfg)
	var c := graph.curve_of(seg)
	var table := RoadMeshBuilder.arc_table(c[0], c[1], c[2], graph.sample_step * 0.5)
	var length: float = table[table.size() - 1].y
	# Cells sit on a fixed 8 m phase from the segment start (not centred), so a
	# road split at a grid point keeps its cells in place and keeps the zoning.
	var start := ceilf(trim_a / cell_size - 0.001) * cell_size
	var count := floori((length - trim_b - start) / cell_size + 0.001)
	if count <= 0:
		return
	for row_side: int in [1, -1]:
		for k in count:
			var tt := RoadMeshBuilder.t_at(table, start + cell_size * (k + 0.5))
			var p := RoadGraph.bezier(c[0], c[1], c[2], tt)
			var d := RoadGraph.bezier_tangent(c[0], c[1], c[2], tt).normalized()
			var out := Vector2(-d.y, d.x) * float(row_side)
			for dep in max_depth:
				var centre := p + out * (hw + cell_size * (dep + 0.5))
				if not _cell_ok(centre, graph, types, playable_half, seg_index):
					break
				_append(centre, d, -out, sid, row_side, k, dep)


func _cell_ok(centre: Vector2, graph: RoadGraph, types: Dictionary, playable_half: float, seg_index: Dictionary) -> bool:
	var margin := cell_size * 0.5
	if absf(centre.x) > playable_half - margin or absf(centre.y) > playable_half - margin:
		return false
	if _water != null and _water.distance(centre) < margin:
		return false
	for j in _near(_buckets, centre, overlap):
		if centers[j].distance_to(centre) < overlap:
			return false
	# Keep clear of every road edge nearby, own road included.
	var key := _bucket_of(centre, _ROAD_BUCKET)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for sid: int in seg_index.get(key + Vector2i(dx, dy), PackedInt32Array()):
				var seg: RoadGraph.RoadSegment = graph.segments[sid]
				var cv := graph.curve_of(seg)
				var p := RoadGraph.bezier(cv[0], cv[1], cv[2], graph.closest_t(cv[0], cv[1], cv[2], centre))
				if p.distance_to(centre) - RoadTypes.half_width(types[seg.type]) < road_clearance:
					return false
	return true


func _append(centre: Vector2, dir: Vector2, front: Vector2, sid: int, row_side: int, k: int, dep: int) -> void:
	var idx := centers.size()
	centers.append(centre)
	dirs.append(dir)
	fronts.append(front)
	segment.append(sid)
	side.append(row_side)
	along.append(k)
	depth.append(dep)
	zone.append(UNZONED)
	building.append(FREE)
	_lookup[Vector4i(sid, row_side, k, dep)] = idx
	var key := _bucket_of(centre, cell_size)
	var list: PackedInt32Array = _buckets.get(key, PackedInt32Array())
	list.append(idx)
	_buckets[key] = list


## Segment ids bucketed by the grid squares their padded bounding box touches.
func _segment_buckets(graph: RoadGraph) -> Dictionary:
	var index := {}
	var pad := 24.0 + cell_size
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		var c := graph.curve_of(seg)
		var lo := _bucket_of(Vector2(minf(minf(c[0].x, c[1].x), c[2].x) - pad, minf(minf(c[0].y, c[1].y), c[2].y) - pad), _ROAD_BUCKET)
		var hi := _bucket_of(Vector2(maxf(maxf(c[0].x, c[1].x), c[2].x) + pad, maxf(maxf(c[0].y, c[1].y), c[2].y) + pad), _ROAD_BUCKET)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var key := Vector2i(x, y)
				var list: PackedInt32Array = index.get(key, PackedInt32Array())
				list.append(seg.id)
				index[key] = list
	return index


func _bucket_of(p: Vector2, bucket: float) -> Vector2i:
	return Vector2i(floori(p.x / bucket), floori(p.y / bucket))


func _near(buckets: Dictionary, p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := _bucket_of(p - Vector2(radius, radius), cell_size)
	var hi := _bucket_of(p + Vector2(radius, radius), cell_size)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			out.append_array(buckets.get(Vector2i(x, y), PackedInt32Array()))
	return out


# --- Queries -------------------------------------------------------------------

func cells_near(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _near(_buckets, p, radius):
		if centers[i].distance_to(p) <= radius:
			out.append(i)
	return out


## The cell whose square contains p (or -1).
func cell_at(p: Vector2) -> int:
	var half := cell_size * 0.5
	for i in _near(_buckets, p, cell_size):
		var rel := p - centers[i]
		if absf(rel.dot(dirs[i])) <= half and absf(rel.dot(fronts[i])) <= half:
			return i
	return -1


## Every cell in the same block side (segment + side) as cell i.
func row_cells(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for j in size():
		if segment[j] == segment[i] and side[j] == side[i]:
			out.append(j)
	return out


## Cells of a width x lot_depth lot starting at cell i (i must touch the road),
## all zoned `zone_id` and free; empty if the lot does not fit.
func find_lot(i: int, width: int, lot_depth: int, zone_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if depth[i] != 0:
		return out
	for k in range(along[i], along[i] + width):
		for dep in lot_depth:
			var j := index_of(segment[i], side[i], k, dep)
			if j < 0 or zone[j] != zone_id or building[j] != FREE:
				return PackedInt32Array()
			out.append(j)
	return out


## Cells of a width x lot_depth lot starting at road-touching cell i that are
## all free (any zone); used for hand-placed buildings and parks.
func find_free_lot(i: int, width: int, lot_depth: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if i < 0 or depth[i] != 0:
		return out
	for k in range(along[i], along[i] + width):
		for dep in lot_depth:
			var j := index_of(segment[i], side[i], k, dep)
			if j < 0 or building[j] != FREE:
				return PackedInt32Array()
			out.append(j)
	return out


## The road-touching cell nearest to p within radius, or -1.
func front_cell_near(p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in cells_near(p, radius):
		if depth[i] == 0:
			var d := centers[i].distance_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best

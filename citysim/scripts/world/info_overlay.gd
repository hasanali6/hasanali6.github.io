extends Node3D
## Info overlays ("Katmanlar"): heat maps of service coverage, electricity,
## water, pollution and happiness. Every zoning cell is tinted on a red →
## yellow → green ramp and buildings take the colour of their own value
## (providers of the shown service in blue), so the whole city reads at a
## glance. The ground and trees fade to grey (global shader parameter
## overlay_dim) so the colours stand out. Refreshes are throttled while the
## city keeps changing. The traffic layer colours the roads themselves by
## how full they are and homes by their commute time; the transit layer
## shows how near each street is to a bus or tram stop (lines show as
## ribbons, drawn by the TransitSystem).

const OVERLAY_SHADER := preload("res://assets/materials/info_overlay.gdshader")
const BAD := Color(0.9, 0.24, 0.2)
const MID := Color(0.98, 0.8, 0.22)
const GOOD := Color(0.26, 0.8, 0.36)
const NONE := Color(0.6, 0.62, 0.66)
const PROVIDER := Color(0.25, 0.5, 0.95)
const REFRESH_SECONDS := 1.0
const DIM_SPEED := 4.0
const CELL_ALPHA := 0.62
const COVERAGE_LAYERS := ["health", "education", "police", "fire", "garbage", "deathcare"]

@export var zone_system_path: NodePath
@export var building_system_path: NodePath
@export var service_system_path: NodePath
@export var traffic_system_path: NodePath
@export var transit_system_path: NodePath

var current: String = ""

var _zones: Node
var _buildings: Node
var _services: Node
var _cells: MultiMeshInstance3D
var _dirty: bool = false
var _since_refresh: float = 0.0
var _height: float
var _dim: float = 0.0
var _cells_dirty: bool = true   # cell transforms must be rebuilt
var _buffer := PackedFloat32Array()
var _traffic: Node
var _transit: Node
var _roads: MultiMeshInstance3D
var _road_seg := PackedInt32Array()
var _road_buffer := PackedFloat32Array()
var _roads_dirty: bool = true


func _ready() -> void:
	_zones = get_node(zone_system_path)
	_buildings = get_node(building_system_path)
	_services = get_node(service_system_path)
	_height = GameData.num("zones/overlay/height_m") + 0.06
	var mat := ShaderMaterial.new()
	mat.shader = OVERLAY_SHADER
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	_cells = MultiMeshInstance3D.new()
	_cells.name = "InfoCells"
	_cells.multimesh = mm
	_cells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cells)
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.use_colors = true
	rmm.mesh = quad
	_roads = MultiMeshInstance3D.new()
	_roads.name = "InfoRoads"
	_roads.multimesh = rmm
	_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_roads)
	if not traffic_system_path.is_empty():
		_traffic = get_node(traffic_system_path)
	if not transit_system_path.is_empty():
		_transit = get_node(transit_system_path)
	EventBus.transit_changed.connect(_queue)
	EventBus.lanes_rebuilt.connect(func() -> void:
		_roads_dirty = true
		_queue())
	EventBus.traffic_updated.connect(_queue)
	EventBus.overlay_selected.connect(func(key: String) -> void:
		current = key
		_refresh())
	EventBus.services_changed.connect(_queue)
	EventBus.zone_cells_rebuilt.connect(func() -> void:
		_cells_dirty = true
		_queue())


func _process(delta: float) -> void:
	var target := 0.0 if current == "" else 1.0
	if not is_equal_approx(_dim, target):
		_dim = move_toward(_dim, target, delta * DIM_SPEED)
		RenderingServer.global_shader_parameter_set("overlay_dim", _dim)
	_since_refresh += delta
	if _dirty and _since_refresh >= REFRESH_SECONDS:
		_refresh()


func _queue() -> void:
	if current != "":
		_dirty = true


## 0 = red (none), 0.5 = yellow, 1 = green (full).
static func ramp(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	return BAD.lerp(MID, v * 2.0) if v < 0.5 else MID.lerp(GOOD, (v - 0.5) * 2.0)


func _refresh() -> void:
	_dirty = false
	_since_refresh = 0.0
	var mm := _cells.multimesh
	if current != "traffic":
		_roads.multimesh.instance_count = 0
		_roads_dirty = true
	if current == "":
		mm.instance_count = 0
		_cells_dirty = true
		_buildings.set_overlay_tint({})
		return
	if current == "traffic":
		mm.instance_count = 0
		_cells_dirty = true
		_refresh_roads()
		var commute_tints := {}
		for id: int in _buildings.buildings:
			commute_tints[id] = _building_color(_buildings.buildings[id])
		_buildings.set_overlay_tint(commute_tints)
		return
	var grid: ZoneGrid = _zones.grid
	var records: Dictionary = _buildings.buildings
	var n := grid.size()
	if _cells_dirty or mm.instance_count != n:
		# Transforms only change with the cells; keep them in a buffer and
		# rewrite just the colours on later refreshes.
		var size := grid.cell_size * 0.94
		mm.instance_count = n
		for i in n:
			var d := grid.dirs[i]
			var f := grid.fronts[i]
			var c := grid.centers[i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3(d.x, 0, d.y) * size, Vector3.UP, Vector3(f.x, 0, f.y) * size),
				Vector3(c.x, _height, c.y)))
		_buffer = mm.buffer
		_cells_dirty = false
	var seg_colors := {}
	if _buffer.size() < n * 16:
		_cells_dirty = true   # headless renderers keep no buffer
		return
	for i in n:
		var col := _cell_color(i, grid, records, seg_colors)
		var o := i * 16 + 12
		_buffer[o] = col.r
		_buffer[o + 1] = col.g
		_buffer[o + 2] = col.b
		_buffer[o + 3] = col.a
	mm.buffer = _buffer
	var tints := {}
	for id: int in records:
		tints[id] = _building_color(records[id])
	_buildings.set_overlay_tint(tints)


## Road surfaces coloured by how full they are (peak volume / capacity).
func _refresh_roads() -> void:
	if _traffic == null:
		return
	var mm := _roads.multimesh
	if _roads_dirty or mm.instance_count != _road_seg.size():
		_build_road_quads()
	var colors := {}
	for i in _road_seg.size():
		var sid := _road_seg[i]
		if not colors.has(sid):
			var ratio: float = _traffic.segment_ratio(sid)
			colors[sid] = ramp(1.0 - clampf(ratio / 1.1, 0.0, 1.0))
		var col: Color = colors[sid]
		var o := i * 16 + 12
		_road_buffer[o] = col.r
		_road_buffer[o + 1] = col.g
		_road_buffer[o + 2] = col.b
		_road_buffer[o + 3] = 0.85
	if not _road_seg.is_empty():
		mm.buffer = _road_buffer


func _build_road_quads() -> void:
	_roads_dirty = false
	var rg: RoadGraph = _traffic.get_node(_traffic.road_network_path).graph
	var types := GameData.section("roads/types")
	var mesh_cfg := GameData.section("roads/mesh")
	var trims := {}
	var xforms := []
	_road_seg = PackedInt32Array()
	for seg: RoadGraph.RoadSegment in rg.segments.values():
		for nid in [seg.a, seg.b]:
			if not trims.has(nid):
				trims[nid] = RoadMeshBuilder.junction_radius(rg, nid, types, mesh_cfg)
		var c := rg.curve_of(seg)
		var table := RoadMeshBuilder.arc_table(c[0], c[1], c[2], 2.0)
		var total: float = table[table.size() - 1].y
		var s0 := minf(float(trims[seg.a]), total * 0.45)
		var s1 := maxf(total - float(trims[seg.b]), s0 + 0.5)
		var width := RoadTypes.carriageway_width(types[seg.type]) * 0.92
		var n := maxi(ceili((s1 - s0) / 8.0), 1)
		var step := (s1 - s0) / n
		for k in n:
			var t := RoadMeshBuilder.t_at(table, s0 + step * (k + 0.5))
			var p := RoadGraph.bezier(c[0], c[1], c[2], t)
			var d := RoadGraph.bezier_tangent(c[0], c[1], c[2], t).normalized()
			var fz := Vector3(d.x, 0.0, d.y)
			xforms.append(Transform3D(Basis(Vector3.UP.cross(fz) * width, Vector3.UP, fz * (step + 0.4)), Vector3(p.x, 0.22, p.y)))
			_road_seg.append(seg.id)
	var mm := _roads.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	_road_buffer = mm.buffer if not xforms.is_empty() else PackedFloat32Array()


func _cell_color(i: int, grid: ZoneGrid, records: Dictionary, seg_colors: Dictionary) -> Color:
	var sid := grid.segment[i]
	if current in COVERAGE_LAYERS:
		if not seg_colors.has(sid):
			seg_colors[sid] = Color(ramp(_services.segment_coverage(sid, current)), CELL_ALPHA)
		return seg_colors[sid]
	if current == "transit":
		if not seg_colors.has(sid):
			var access: float = 0.0 if _transit == null else _transit.segment_access(sid)
			seg_colors[sid] = Color(ramp(access), CELL_ALPHA) if access > 0.0 else Color(NONE, CELL_ALPHA * 0.4)
		return seg_colors[sid]
	var owner := grid.building[i]
	var b: Dictionary = records.get(owner, {}) if owner != ZoneGrid.FREE else {}
	match current:
		"power", "water":
			if not b.is_empty() and _services.is_consumer(b):
				return Color(GOOD if b.get(current, true) else BAD, CELL_ALPHA)
			# Free land: can a new building here be supplied?
			return Color(MID, CELL_ALPHA * 0.8) if _services.spare_on_segment(sid, current) > 0.0 else Color(BAD, CELL_ALPHA * 0.6)
		"pollution":
			return Color(ramp(1.0 - _services.pollution.sample(grid.centers[i])), CELL_ALPHA)
		"happiness":
			if not b.is_empty() and int(b.get("occupants", 0)) > 0:
				return Color(ramp(float(b.get("happiness", 0.0)) / 100.0), CELL_ALPHA)
	return Color(NONE, CELL_ALPHA * 0.4)


func _building_color(b: Dictionary) -> Color:
	var t: Dictionary = _services.type_of(b)
	if current in COVERAGE_LAYERS:
		if not t.is_empty() and str(t["category"]) == current:
			return PROVIDER
		if not _services.is_consumer(b):
			return NONE
		return ramp(_services.coverage_of(b, current))
	match current:
		"power", "water":
			if not t.is_empty() and str(t["category"]) == current:
				return PROVIDER
			if not _services.is_consumer(b):
				return NONE
			if current == "water" and b.get("polluted_water", false):
				return MID
			return GOOD if b.get(current, true) else BAD
		"pollution":
			return ramp(1.0 - float(b.get("pollution", 0.0)))
		"happiness":
			if int(b.get("occupants", 0)) > 0:
				return ramp(float(b.get("happiness", 0.0)) / 100.0)
		"transit":
			if _transit != null and _services.is_consumer(b):
				var access: float = _transit.segment_access(int(b.get("segment", -1)))
				return ramp(access) if access > 0.0 else NONE
		"traffic":
			var commute := float(b.get("commute", -1.0))
			if int(b.get("occupants", 0)) > 0 and commute >= 0.0:
				return ramp(1.0 - clampf((commute - 8.0) / 32.0, 0.0, 1.0))
	return NONE

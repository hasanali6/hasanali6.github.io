extends Node3D
## Trees: forests from the terrain's forest density map, street trees on
## avenues and boulevards (sidewalks and medians), and yard trees around
## houses and apartments. Low-poly pine and round trees in two MultiMeshes per
## 512 m chunk, so far chunks are culled and hidden by visibility range (from
## afar the terrain shader paints the forest canopy instead).
##
## Forest spots are generated once and indexed in a spatial hash. Roads and
## built lots block the trees under them: an edit only re-marks blocked trees
## by walking the roads / lots through the hash and rebuilds the chunks whose
## trees changed.

const TREE_SHADER := preload("res://assets/materials/tree_low.gdshader")
const KINDS: PackedStringArray = ["pine", "round"]

@export var terrain_path: NodePath
@export var road_network_path: NodePath
@export var zone_system_path: NodePath
@export var building_system_path: NodePath

var _terrain: Node
var _net: Node
var _zones: Node
var _buildings: Node
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _chunk_size: float
var _bucket: float

# Forest trees (static spots).
var _pos := PackedVector2Array()
var _kind := PackedByteArray()
var _scale := PackedFloat32Array()
var _color := PackedColorArray()
var _road_block := PackedByteArray()
var _lot_block := PackedByteArray()
var _hash: Dictionary = {}          # bucket -> PackedInt32Array of tree indices
var _chunk_trees: Dictionary = {}   # chunk -> PackedInt32Array of tree indices

# Trees that follow roads and buildings: chunk -> Array of [kind, pos, scale, color].
var _extras_roads: Dictionary = {}
var _extras_lots: Dictionary = {}

var _chunks: Dictionary = {}        # chunk -> {kind: MultiMeshInstance3D}
var _meshes: Dictionary = {}
var _dirty: Dictionary = {}
var _lots_pending: bool = false
var _rebuild_queued: bool = false


func _ready() -> void:
	_terrain = get_node(terrain_path)
	_net = get_node(road_network_path)
	_zones = get_node(zone_system_path)
	_buildings = get_node(building_system_path)
	_cfg = GameData.section("vegetation")
	_chunk_size = float(_cfg["chunk_size_m"])
	_bucket = float(_cfg["hash_bucket_m"])
	_rng.seed = int(_cfg["seed"])
	_build_meshes()
	_generate_forest()
	EventBus.roads_changed.connect(_on_roads_changed)
	EventBus.buildings_changed.connect(_on_buildings_changed)
	EventBus.graphics_preset_changed.connect(_apply_graphics)
	for chunk: Vector2i in _chunk_trees:
		_dirty[chunk] = true
	_queue_rebuild()


# --- Generation -------------------------------------------------------------------

## Dense tree clusters where the forest map says so. A coarse pass finds the
## forested squares first so the fine spacing is only generated there.
func _generate_forest() -> void:
	var fcfg := GameData.section("map/forest")
	var spacing := float(fcfg["spacing_m"])
	var coarse := float(fcfg["coarse_m"])
	var radius := float(fcfg["radius_m"])
	var jitter := float(fcfg["jitter"]) * spacing
	var pine_share := float(_cfg["pine_share"])
	var srange: Array = _cfg["scale_range"]
	var factor := float(fcfg["density_factor"])
	var per := maxi(roundi(coarse / spacing), 1)
	var steps := ceili(radius / coarse)
	for cy in range(-steps, steps + 1):
		for cx in range(-steps, steps + 1):
			var corner := Vector2(cx, cy) * coarse
			if (corner + Vector2(coarse, coarse) * 0.5).length() > radius:
				continue
			var centre_density: float = _terrain.forest_density(corner + Vector2(coarse, coarse) * 0.5)
			if centre_density <= 0.05:
				continue
			for fy in per:
				for fx in per:
					var p := corner + (Vector2(fx, fy) + Vector2(0.5, 0.5)) * spacing \
						+ Vector2(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter))
					var density: float = _terrain.forest_density(p)
					if _rng.randf() > density * factor:
						continue
					var kind := 0 if _rng.randf() < pine_share else 1
					_add_tree(p, kind, _rng.randf_range(float(srange[0]), float(srange[1])))


func _add_tree(p: Vector2, kind: int, s: float) -> void:
	var i := _pos.size()
	_pos.append(p)
	_kind.append(kind)
	_scale.append(s)
	_color.append(_random_color(kind))
	_road_block.append(0)
	_lot_block.append(0)
	var key := _bucket_of(p)
	var list: PackedInt32Array = _hash.get(key, PackedInt32Array())
	list.append(i)
	_hash[key] = list
	var chunk := _chunk_of(p)
	var trees: PackedInt32Array = _chunk_trees.get(chunk, PackedInt32Array())
	trees.append(i)
	_chunk_trees[chunk] = trees


func _random_color(kind: int) -> Color:
	var palette: Array = _cfg["pine_colors"] if kind == 0 else _cfg["round_colors"]
	return Color.html(palette[_rng.randi_range(0, palette.size() - 1)]) * _rng.randf_range(0.9, 1.08)


func _bucket_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _bucket), floori(p.y / _bucket))


func _chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _chunk_size), floori(p.y / _chunk_size))


## Visits forest trees within radius of p.
func _trees_near(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := _bucket_of(p - Vector2(radius, radius))
	var hi := _bucket_of(p + Vector2(radius, radius))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for i in _hash.get(Vector2i(x, y), PackedInt32Array()):
				if _pos[i].distance_to(p) <= radius:
					out.append(i)
	return out


# --- Reacting to roads and buildings ---------------------------------------------------

func _on_roads_changed() -> void:
	var graph: RoadGraph = _net.graph
	var blocked := PackedByteArray()
	blocked.resize(_pos.size())
	var clearance := float(_cfg["road_clearance_m"])
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		var c := graph.curve_of(seg)
		var hw := RoadTypes.half_width(_net.type_config(seg.type)) + clearance
		var n := RoadGraph.sample_count(c[0], c[1], c[2], hw)
		for k in n + 1:
			for i in _trees_near(RoadGraph.bezier(c[0], c[1], c[2], float(k) / n), hw):
				blocked[i] = 1
	_apply_block(_road_block, blocked)
	_road_block = blocked
	_set_extras(_extras_roads, _street_trees())
	_queue_rebuild()


## Buildings change a few times a second while a town grows; the trees on
## their lots are re-checked at most every half second.
func _on_buildings_changed() -> void:
	if _lots_pending:
		return
	_lots_pending = true
	get_tree().create_timer(0.5).timeout.connect(_refresh_lots)


func _refresh_lots() -> void:
	_lots_pending = false
	var grid: ZoneGrid = _zones.grid
	var blocked := PackedByteArray()
	blocked.resize(_pos.size())
	var clearance := float(_cfg["lot_clearance_m"])
	for b: Dictionary in _buildings.buildings.values():
		for c: int in b["cells"]:
			if c < grid.size():
				for i in _trees_near(grid.centers[c], clearance):
					blocked[i] = 1
		# An airport's runway strip behind its lot stays clear too.
		if b["style"] == "airport":
			var f: Vector2 = b["front"]
			var side := Vector2(-f.y, f.x)
			var back: Vector2 = (b["centre"] as Vector2) - f * (float(b["depth"]) * 0.5 + 6.0)
			var v := 0.0
			while v <= 330.0:
				for u in [-18.0, 0.0, 18.0]:
					for i in _trees_near(back - f * v + side * u, 16.0):
						blocked[i] = 1
				v += 12.0
	_apply_block(_lot_block, blocked)
	_lot_block = blocked
	_set_extras(_extras_lots, _yard_trees())
	_queue_rebuild()


## Marks the chunks of trees whose blocked state changed as dirty.
func _apply_block(old: PackedByteArray, new: PackedByteArray) -> void:
	for i in _pos.size():
		if old[i] != new[i]:
			_dirty[_chunk_of(_pos[i])] = true


func _set_extras(store: Dictionary, trees: Array) -> void:
	var fresh := {}
	for t: Array in trees:
		var chunk := _chunk_of(t[1])
		if not fresh.has(chunk):
			fresh[chunk] = []
		(fresh[chunk] as Array).append(t)
	for chunk: Vector2i in store:
		if not fresh.has(chunk) or fresh[chunk] != store[chunk]:
			_dirty[chunk] = true
	for chunk: Vector2i in fresh:
		if not store.has(chunk) or fresh[chunk] != store[chunk]:
			_dirty[chunk] = true
	store.clear()
	store.merge(fresh)


func _street_trees() -> Array:
	var out := []
	var graph: RoadGraph = _net.graph
	var spacing := float(_cfg["street_tree_spacing_m"])
	var median_spacing := float(_cfg["median_tree_spacing_m"])
	var s := float(_cfg["street_tree_scale"])
	var mesh_cfg: Dictionary = _net.mesh_cfg
	var palette: Array = _cfg["round_colors"]
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		var t: Dictionary = _net.type_config(seg.type)
		if not bool(t.get("street_trees", false)):
			continue
		var trim_a := RoadMeshBuilder.junction_radius(graph, seg.a, _net.types, mesh_cfg) + 4.0
		var trim_b := RoadMeshBuilder.junction_radius(graph, seg.b, _net.types, mesh_cfg) + 4.0
		var walk := RoadTypes.half_width(t) - float(t["sidewalk_width_m"]) * 0.5
		var d := trim_a + spacing * 0.5
		var k := 0
		while d < seg.length - trim_b:
			var tt := d / seg.length
			var p := graph.point_on(seg.id, tt)
			var dir := graph.tangent_on(seg.id, tt)
			var left := Vector2(-dir.y, dir.x)
			var color := Color.html(palette[(seg.id * 7 + k) % palette.size()])
			for side in [-1.0, 1.0]:
				out.append([1, p + left * walk * side, s, color])
			d += spacing
			k += 1
		if float(t["median_width_m"]) > 0.0:
			d = trim_a + median_spacing * 0.5
			while d < seg.length - trim_b:
				out.append([1, graph.point_on(seg.id, d / seg.length), s * 0.85, Color.html(palette[k % palette.size()])])
				d += median_spacing
				k += 1
	return out


func _yard_trees() -> Array:
	var out := []
	var s := float(_cfg["yard_tree_scale"])
	var palette: Array = _cfg["round_colors"]
	for b: Dictionary in _buildings.buildings.values():
		var count := 0
		match str(b["style"]):
			"house":
				count = int(_cfg["yard_trees_house"])
			"apartment", "kenney_b", "kenney_c":
				count = int(_cfg["yard_trees_apartment"])
		var spots: Array = (_cfg.get("service_trees", {}) as Dictionary).get(str(b["style"]), [])
		if not spots.is_empty() and not b.get("abandoned", false):
			# Service grounds: trees at fixed spots, fractions of the half lot size.
			var fr: Vector2 = b["front"]
			var across := Vector2(fr.y, -fr.x)
			for k in spots.size():
				var sp: Array = spots[k]
				var q: Vector2 = b["centre"] + across * float(sp[0]) * float(b["width"]) * 0.5 + fr * float(sp[1]) * float(b["depth"]) * 0.5
				out.append([1, q, s * (0.9 + 0.08 * (k % 3)), Color.html(palette[(int(b["id"]) + k) % palette.size()])])
		if count == 0 or b.get("abandoned", false):
			continue
		var f: Vector2 = b["front"]
		var dir: Vector2 = b["dir"]
		var back: Vector2 = b["centre"] - f * (float(b["depth"]) * 0.5 - 3.0)
		for k in count:
			var side := -1.0 if k % 2 == 0 else 1.0
			var p: Vector2 = back + dir * side * (float(b["width"]) * 0.5 - 2.5)
			out.append([1, p, s * (0.85 + 0.1 * k), Color.html(palette[(int(b["id"]) + k) % palette.size()])])
	return out


# --- Rendering ---------------------------------------------------------------------

func _queue_rebuild() -> void:
	if not _rebuild_queued:
		_rebuild_queued = true
		_rebuild_dirty.call_deferred()


func _rebuild_dirty() -> void:
	_rebuild_queued = false
	for chunk: Vector2i in _dirty:
		_rebuild_chunk(chunk)
	_dirty.clear()


func _rebuild_chunk(chunk: Vector2i) -> void:
	var lists := {0: [], 1: []}
	for i in _chunk_trees.get(chunk, PackedInt32Array()):
		if _road_block[i] == 0 and _lot_block[i] == 0:
			(lists[_kind[i]] as Array).append([_pos[i], _scale[i], _color[i]])
	for store: Dictionary in [_extras_roads, _extras_lots]:
		for t: Array in store.get(chunk, []):
			(lists[int(t[0])] as Array).append([t[1], t[2], t[3]])
	if not _chunks.has(chunk):
		var entry := {}
		for k in KINDS.size():
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees_%s_%d_%d" % [KINDS[k], chunk.x, chunk.y]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = _meshes[KINDS[k]]
			mmi.multimesh = mm
			add_child(mmi)
			entry[k] = mmi
		_chunks[chunk] = entry
		_apply_graphics_to(entry)
	var entry: Dictionary = _chunks[chunk]
	for k in KINDS.size():
		var list: Array = lists[k]
		var mm := (entry[k] as MultiMeshInstance3D).multimesh
		mm.instance_count = list.size()
		for n in list.size():
			var t: Array = list[n]
			var p: Vector2 = t[0]
			var s: float = t[1]
			var yaw := fposmod(p.x * 0.37 + p.y * 0.71, TAU)
			mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(p.x, 0.0, p.y)))
			mm.set_instance_color(n, t[2])


func _apply_graphics(_preset: String) -> void:
	for entry: Dictionary in _chunks.values():
		_apply_graphics_to(entry)


func _apply_graphics_to(entry: Dictionary) -> void:
	var dist := float(GraphicsSettings.get_value("tree_draw_distance_m"))
	var shadows := bool(GraphicsSettings.get_value("tree_shadows"))
	for mmi: MultiMeshInstance3D in entry.values():
		mmi.visibility_range_end = dist
		mmi.visibility_range_end_margin = dist * 0.1
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_meshes() -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color.html(_cfg["trunk_color"])
	trunk_mat.roughness = 0.9
	var foliage := ShaderMaterial.new()
	foliage.shader = TREE_SHADER
	foliage.set_shader_parameter("sway", float(_cfg["sway"]))

	var pine := ArrayMesh.new()
	_append_flat(pine, _cylinder(0.24, 0.16, 2.2, 6), Transform3D(Basis(), Vector3(0, 1.1, 0)))
	var cones := [[2.5, 3.4, 1.3], [2.0, 3.0, 3.4], [1.35, 2.6, 5.3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for c: Array in cones:
		st.append_from(_cylinder(float(c[0]), 0.0, float(c[1]), 7), 0, Transform3D(Basis(), Vector3(0, float(c[2]) + float(c[1]) * 0.5, 0)))
	st.generate_normals()
	st.commit(pine)
	pine.surface_set_material(0, trunk_mat)
	pine.surface_set_material(1, foliage)
	_meshes["pine"] = pine

	var round_tree := ArrayMesh.new()
	_append_flat(round_tree, _cylinder(0.26, 0.2, 2.6, 6), Transform3D(Basis(), Vector3(0, 1.3, 0)))
	var ball := SphereMesh.new()
	ball.radius = 2.6
	ball.height = 4.6
	ball.radial_segments = 8
	ball.rings = 5
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.append_from(ball, 0, Transform3D(Basis(), Vector3(0, 4.6, 0)))
	st.append_from(ball, 0, Transform3D(Basis().scaled(Vector3(0.62, 0.62, 0.62)), Vector3(1.2, 5.6, 0.5)))
	st.generate_normals()
	st.commit(round_tree)
	round_tree.surface_set_material(0, trunk_mat)
	round_tree.surface_set_material(1, foliage)
	_meshes["round"] = round_tree


func _cylinder(bottom: float, top: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


func _append_flat(mesh: ArrayMesh, src: Mesh, xf: Transform3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.append_from(src, 0, xf)
	st.generate_normals()
	st.commit(mesh)



extends Node3D
## Owns the city's RoadGraph and its visuals. Building and demolishing go
## through here so cost, refunds and mesh updates stay consistent.
##
## Rendering: every segment and junction is built once into a Parts bundle and
## cached; pieces are merged per square chunk into a single mesh (one draw call
## per material per chunk). An edit only rebuilds the pieces around it and the
## chunks they live in. Street lamps and their night light pools are two
## MultiMeshes for the whole city.
##
## Outside connections: highway stubs from the east and west map edges
## (data/roads.json "outside") exist from the start, free. Roads joined to
## them are "reachable": trade trucks and newcomers use them; an unlinked
## town exports little, imports dearly and grows slower.

const ASPHALT_SHADER := preload("res://assets/materials/road_asphalt.gdshader")
const SIDEWALK_SHADER := preload("res://assets/materials/road_sidewalk.gdshader")
const LAMP_SHADER := preload("res://assets/materials/lamp_light.gdshader")
const POOL_SHADER := preload("res://assets/materials/light_pool.gdshader")
const SURFACE_ORDER: PackedStringArray = [
	RoadMeshBuilder.ASPHALT, RoadMeshBuilder.SIDEWALK, RoadMeshBuilder.CURB, RoadMeshBuilder.MEDIAN,
]

var graph: RoadGraph
var types: Dictionary
var mesh_cfg: Dictionary

var _materials: Dictionary = {}
var _pieces: Dictionary = {}       # "s<id>" / "n<id>" -> RoadMeshBuilder.Parts
var _piece_chunk: Dictionary = {}  # piece key -> Vector2i
var _chunks: Dictionary = {}       # Vector2i -> MeshInstance3D
var _chunk_size: float
var _refund_ratio: float
var _node_signature: Dictionary = {}  # node id -> sorted segment ids at last build
var _lamps: MultiMeshInstance3D
var _pools: MultiMeshInstance3D
var _reach_dirty: bool = true
var _reachable: Dictionary = {}    # segment id -> true when linked to an outside connection
var _outside_nodes: Dictionary = {}  # node id -> true (map edge ends)
var _connected: bool = false


func _ready() -> void:
	types = GameData.section("roads/types")
	mesh_cfg = GameData.section("roads/mesh")
	graph = RoadGraph.new(GameData.section("roads/graph"))
	_chunk_size = float(mesh_cfg["chunk_size_m"])
	_refund_ratio = GameData.num("economy/road_refund_ratio")
	_build_materials()
	_build_lamp_nodes()
	EventBus.roads_changed.connect(func() -> void: _reach_dirty = true)
	EventBus.month_changed.connect(_on_month)
	ensure_outside.call_deferred()


func type_config(type: String) -> Dictionary:
	return types[type]


func cost_of(length: float, type: String) -> int:
	return ceili(length * float(types[type]["cost_per_m"]))


func refund_of(seg_id: int) -> int:
	var seg: RoadGraph.RoadSegment = graph.segments[seg_id]
	return roundi(seg.length * float(types[seg.type]["cost_per_m"]) * _refund_ratio)


## Price of a planned road: its length, plus the bridge premium over water.
func plan_cost(plan: Dictionary, type: String) -> int:
	var bridge := MapWater.shared().curve_water_length(plan["a"], plan["control"], plan["b"])
	return cost_of(plan["length"], type) + ceili(bridge * float(types[type]["cost_per_m"]) * (GameData.num("roads/bridge/cost_factor") - 1.0))


## Why a planned road cannot stand where it is ("" if fine): bridges need
## both ends and every junction on firm land.
func water_error(plan: Dictionary, type: String) -> String:
	var clear := RoadTypes.half_width(types[type]) + GameData.num("roads/bridge/land_clearance_m")
	var points: Array = [plan["a"], plan["b"]]
	for hit: Dictionary in plan.get("hits", []):
		points.append(hit["point"])
	for p: Vector2 in points:
		if MapWater.shared().distance(p) < clear:
			return "ROAD_ERR_WATER"
	return ""


## Plans and, if affordable, builds a road. Returns the plan with "cost" added.
func build_road(start: Vector2, end: Vector2, control: Variant, type: String) -> Dictionary:
	var plan := graph.plan_road(start, end, control)
	if not plan["ok"]:
		return plan
	var wet := water_error(plan, type)
	if wet != "":
		return {"ok": false, "error": wet}
	plan["cost"] = plan_cost(plan, type)
	if not EconomySystem.try_spend(plan["cost"]):
		return {"ok": false, "error": "ROAD_ERR_MONEY", "cost": plan["cost"]}
	var before := _snapshot()
	graph.commit_road(plan, type)
	_refresh_after_edit(before)
	return plan


## Cost of changing a road to another type: the new road minus what the old
## one gives back (never negative).
func upgrade_cost(seg_id: int, type: String) -> int:
	var seg: RoadGraph.RoadSegment = graph.segments[seg_id]
	var c := graph.curve_of(seg)
	var fresh := plan_cost({"a": c[0], "control": c[1], "b": c[2], "length": seg.length}, type)
	return maxi(fresh - refund_of(seg_id), 0)


## Rebuilds a road as another type in place (wider roads may take frontage
## from the lots beside them). Returns {ok, cost, error}.
func upgrade(seg_id: int, type: String) -> Dictionary:
	if not graph.segments.has(seg_id):
		return {"ok": false, "error": "ROAD_ERR_UPGRADE_NONE"}
	var seg: RoadGraph.RoadSegment = graph.segments[seg_id]
	if seg.type == type:
		return {"ok": false, "error": "ROAD_ERR_UPGRADE_SAME"}
	if is_outside_segment(seg_id):
		return {"ok": false, "error": "ROAD_ERR_OUTSIDE_LINK"}
	var c := graph.curve_of(seg)
	var wet := water_error({"a": c[0], "b": c[2]}, type)
	if wet != "":
		return {"ok": false, "error": wet}
	var cost := upgrade_cost(seg_id, type)
	if not EconomySystem.try_spend(cost):
		return {"ok": false, "error": "ROAD_ERR_MONEY", "cost": cost}
	var before := _snapshot()
	seg.type = type
	_refresh_after_edit(before, [seg_id])
	return {"ok": true, "cost": cost}


func upkeep_per_month() -> float:
	var factor := GameData.num("economy/budget/road_upkeep_per_m_per_cost")
	var total := 0.0
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		total += seg.length * float(types[seg.type]["cost_per_m"]) * factor
	return total


func save_state() -> Dictionary:
	return {"graph": graph.save_state()}


## Rebuilds the whole network from a save (visuals included).
func load_state(state: Dictionary) -> void:
	var before := _snapshot()
	graph.load_state(state.get("graph", {}))
	_refresh_after_edit(before)
	ensure_outside()


# --- Outside connections ---------------------------------------------------------

## Builds the highway stubs at the map edges if they are missing (new city,
## or a save from before outside connections).
func ensure_outside() -> void:
	var cfg: Dictionary = GameData.section("roads/outside")
	var before := _snapshot()
	var built := false
	for link: Dictionary in cfg["links"]:
		var from := Vector2(link["from"][0], link["from"][1])
		var to := Vector2(link["to"][0], link["to"][1])
		if graph.find_node_near(from, 3.0) >= 0:
			continue
		# Shorten towards the edge until it fits among roads already built.
		for k in 4:
			var end := from.lerp(to, 1.0 - k * 0.2)
			var plan := graph.plan_road(from, end, null)
			if plan["ok"]:
				graph.commit_road(plan, str(cfg["type"]))
				built = true
				break
	_outside_nodes = {}
	for link: Dictionary in cfg["links"]:
		var n := graph.find_node_near(Vector2(link["from"][0], link["from"][1]), 3.0)
		if n >= 0:
			_outside_nodes[n] = true
	if built:
		_refresh_after_edit(before)
	_reach_dirty = true


func is_outside_segment(seg_id: int) -> bool:
	var seg: RoadGraph.RoadSegment = graph.segments.get(seg_id)
	return seg != null and (_outside_nodes.has(seg.a) or _outside_nodes.has(seg.b))


## Segments at the map edge (where trade and newcomers enter).
func outside_segments() -> PackedInt32Array:
	var out := PackedInt32Array()
	for nid: int in _outside_nodes:
		if graph.nodes.has(nid):
			out.append_array((graph.nodes[nid] as RoadGraph.RoadNode).segments)
	return out


func is_reachable(seg_id: int) -> bool:
	_update_reach()
	return _reachable.has(seg_id)


## True once the player's roads join an outside connection.
func city_connected() -> bool:
	_update_reach()
	return _connected


func _update_reach() -> void:
	if not _reach_dirty:
		return
	_reach_dirty = false
	_reachable = {}
	var seen := {}
	var stack: Array = _outside_nodes.keys()
	while not stack.is_empty():
		var nid: int = stack.pop_back()
		if seen.has(nid) or not graph.nodes.has(nid):
			continue
		seen[nid] = true
		for sid in (graph.nodes[nid] as RoadGraph.RoadNode).segments:
			_reachable[sid] = true
			stack.append(graph.other_node(sid, nid))
	var stub_type := str(GameData.value("roads/outside/type"))
	_connected = false
	for sid: int in _reachable:
		if (graph.segments[sid] as RoadGraph.RoadSegment).type != stub_type:
			_connected = true
			break


func _on_month(_m: int) -> void:
	if graph.segments.size() > _outside_nodes.size() * 2 and not city_connected():
		EventBus.notification_posted.emit("roads", tr("NOTIFY_NO_CONNECTION"))


func demolish(seg_id: int) -> int:
	if not graph.segments.has(seg_id):
		return 0
	var refund := refund_of(seg_id)
	var before := _snapshot()
	graph.remove_segment(seg_id)
	EconomySystem.refund(refund)
	_refresh_after_edit(before)
	return refund


# --- Rendering -------------------------------------------------------------------

func _build_materials() -> void:
	var colors := GameData.section("roads/colors")
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.02
	noise.noise = fnl

	var asphalt := ShaderMaterial.new()
	asphalt.shader = ASPHALT_SHADER
	asphalt.set_shader_parameter("noise_tex", noise)
	asphalt.set_shader_parameter("asphalt_color", DataLoader.to_color(colors["asphalt"]))
	asphalt.set_shader_parameter("marking_color", DataLoader.to_color(colors["marking"]))
	asphalt.set_shader_parameter("center_color", DataLoader.to_color(colors["center_marking"]))
	asphalt.set_shader_parameter("marking_width", float(mesh_cfg["marking_width_m"]))
	asphalt.set_shader_parameter("dash_length", float(mesh_cfg["dash_length_m"]))
	asphalt.set_shader_parameter("dash_gap", float(mesh_cfg["dash_gap_m"]))
	asphalt.set_shader_parameter("crosswalk_length", float(mesh_cfg["crosswalk_length_m"]))
	asphalt.set_shader_parameter("crosswalk_stripe", float(mesh_cfg["crosswalk_stripe_m"]))
	asphalt.set_shader_parameter("detail_tex", load("res://assets/textures/asphalt_detail.png"))
	asphalt.set_shader_parameter("detail_normal", load("res://assets/textures/asphalt_normal.png"))

	var sidewalk := ShaderMaterial.new()
	sidewalk.shader = SIDEWALK_SHADER
	sidewalk.set_shader_parameter("noise_tex", noise)
	sidewalk.set_shader_parameter("base_color", DataLoader.to_color(colors["sidewalk"]))
	sidewalk.set_shader_parameter("tile", float(mesh_cfg["sidewalk_tile_m"]))
	sidewalk.set_shader_parameter("detail_tex", load("res://assets/textures/concrete_detail.png"))
	sidewalk.set_shader_parameter("detail_normal", load("res://assets/textures/concrete_normal.png"))

	var curb := StandardMaterial3D.new()
	curb.albedo_color = DataLoader.to_color(colors["curb"])
	curb.roughness = 0.85
	curb.cull_mode = BaseMaterial3D.CULL_DISABLED
	var median := StandardMaterial3D.new()
	median.albedo_color = DataLoader.to_color(colors["median"])
	median.roughness = 0.95
	median.cull_mode = BaseMaterial3D.CULL_DISABLED

	_materials = {
		RoadMeshBuilder.ASPHALT: asphalt, RoadMeshBuilder.SIDEWALK: sidewalk,
		RoadMeshBuilder.CURB: curb, RoadMeshBuilder.MEDIAN: median,
	}


func get_materials() -> Dictionary:
	return _materials


func _snapshot() -> Dictionary:
	return {"segments": graph.segments.keys(), "nodes": graph.nodes.keys()}


## Rebuilds pieces affected by an edit: new segments, nodes whose set of
## roads changed, and every segment touching such a node (junction trims and
## mitres depend on all roads meeting there).
func _refresh_after_edit(before: Dictionary, forced: Array = []) -> void:
	var dirty_chunks := {}
	for sid: int in before["segments"]:
		if not graph.segments.has(sid):
			_drop_piece("s%d" % sid, dirty_chunks)
	for nid: int in before["nodes"]:
		if not graph.nodes.has(nid):
			_drop_piece("n%d" % nid, dirty_chunks)
			_node_signature.erase(nid)

	var dirty_nodes := {}
	for nid: int in graph.nodes:
		var signature := (graph.nodes[nid] as RoadGraph.RoadNode).segments.duplicate()
		signature.sort()
		if _node_signature.get(nid, PackedInt32Array()) != signature:
			_node_signature[nid] = signature
			dirty_nodes[nid] = true
	var dirty_segments := {}
	for sid: int in graph.segments:
		if not (before["segments"] as Array).has(sid):
			dirty_segments[sid] = true
	# Roads changed in place (upgrades): their ends and neighbours redraw too.
	for sid: int in forced:
		var fs: RoadGraph.RoadSegment = graph.segments.get(sid)
		if fs != null:
			dirty_nodes[fs.a] = true
			dirty_nodes[fs.b] = true
	for nid: int in dirty_nodes:
		for sid in (graph.nodes[nid] as RoadGraph.RoadNode).segments:
			dirty_segments[sid] = true

	for nid: int in dirty_nodes:
		_update_piece("n%d" % nid, RoadMeshBuilder.build_junction(graph, nid, types, mesh_cfg),
			_chunk_of((graph.nodes[nid] as RoadGraph.RoadNode).pos), dirty_chunks)
	for sid: int in dirty_segments:
		_update_piece("s%d" % sid, RoadMeshBuilder.build_segment(graph, sid, types, mesh_cfg),
			_chunk_of(graph.point_on(sid, 0.5)), dirty_chunks)
	for chunk: Vector2i in dirty_chunks:
		_rebuild_chunk(chunk)
	_rebuild_lamps()
	EventBus.road_upkeep_changed.emit(upkeep_per_month())
	EventBus.roads_changed.emit()


func _drop_piece(key: String, dirty_chunks: Dictionary) -> void:
	if _piece_chunk.has(key):
		dirty_chunks[_piece_chunk[key]] = true
	_pieces.erase(key)
	_piece_chunk.erase(key)


func _update_piece(key: String, parts: RoadMeshBuilder.Parts, chunk: Vector2i, dirty_chunks: Dictionary) -> void:
	if _piece_chunk.has(key):
		dirty_chunks[_piece_chunk[key]] = true
	_pieces[key] = parts
	_piece_chunk[key] = chunk
	dirty_chunks[chunk] = true


func _chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _chunk_size), floori(p.y / _chunk_size))


func _rebuild_chunk(chunk: Vector2i) -> void:
	var merged := RoadMeshBuilder.Parts.new()
	for key: String in _piece_chunk:
		if _piece_chunk[key] == chunk:
			merged.append(_pieces[key])
	if merged.is_empty():
		if _chunks.has(chunk):
			(_chunks[chunk] as MeshInstance3D).queue_free()
			_chunks.erase(chunk)
		return
	var mi: MeshInstance3D = _chunks.get(chunk)
	if mi == null:
		mi = MeshInstance3D.new()
		# Roads are flat; 18 cm curbs only produce shimmering shadow aliasing.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "RoadChunk_%d_%d" % [chunk.x, chunk.y]
		add_child(mi)
		_chunks[chunk] = mi
	mi.mesh = merged.to_mesh(SURFACE_ORDER, _materials)


# --- Street lamps -------------------------------------------------------------------

func _build_lamp_nodes() -> void:
	var cfg := GameData.section("roads/lamps")
	var light := DataLoader.to_color(cfg["light_color"])
	_lamps = MultiMeshInstance3D.new()
	# Thin poles are thinner than a shadow-map texel; their shadows flicker as the sun moves.
	_lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamps.name = "StreetLamps"
	_lamps.multimesh = _new_multimesh(_build_lamp_mesh(cfg, light))
	add_child(_lamps)

	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = POOL_SHADER
	pool_mat.set_shader_parameter("light_color", light)
	pool_mat.set_shader_parameter("strength", float(cfg["pool_strength"]))
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * float(cfg["pool_radius_m"]) * 2.0
	quad.material = pool_mat
	_pools = MultiMeshInstance3D.new()
	_pools.name = "LampPools"
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pools.multimesh = _new_multimesh(quad)
	add_child(_pools)


func _new_multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	return mm


## Pole + arm + lamp head, local +X points over the road.
func _build_lamp_mesh(cfg: Dictionary, light: Color) -> ArrayMesh:
	var h := float(cfg["pole_height_m"])
	var mesh := ArrayMesh.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = h
	pole.radial_segments = 6
	pole.rings = 1
	var arm := BoxMesh.new()
	arm.size = Vector3(1.6, 0.1, 0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(pole, 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))
	st.append_from(arm, 0, Transform3D(Basis(), Vector3(0.75, h - 0.05, 0)))
	st.commit(mesh)
	var head := BoxMesh.new()
	head.size = Vector3(0.7, 0.16, 0.32)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(head, 0, Transform3D(Basis(), Vector3(1.45, h - 0.14, 0)))
	st.commit(mesh)
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.55, 0.58, 0.63)
	body.roughness = 0.55
	body.metallic = 0.4
	var head_mat := ShaderMaterial.new()
	head_mat.shader = LAMP_SHADER
	head_mat.set_shader_parameter("light_color", light)
	head_mat.set_shader_parameter("light_energy", float(cfg["light_energy"]))
	mesh.surface_set_material(0, body)
	mesh.surface_set_material(1, head_mat)
	return mesh


func _rebuild_lamps() -> void:
	var cfg := GameData.section("roads/lamps")
	var inset := float(cfg["inset_m"])
	var transforms: Array[Transform3D] = []
	var pools: Array[Transform3D] = []
	var curb_h := float(mesh_cfg["curb_height_m"])
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		var t: Dictionary = types[seg.type]
		var spacing := float(t["lamp_spacing_m"])
		var trim_a := RoadMeshBuilder.junction_radius(graph, seg.a, types, mesh_cfg)
		var trim_b := RoadMeshBuilder.junction_radius(graph, seg.b, types, mesh_cfg)
		var usable := seg.length - trim_a - trim_b
		if usable < spacing * 0.5:
			continue
		var count := maxi(floori(usable / spacing), 1)
		var hw := RoadTypes.half_width(t) - inset
		var sides: Array[float] = [-1.0]
		if bool(t["lamps_both_sides"]):
			sides.append(1.0)
		for i in count:
			var s := trim_a + (i + 0.5) * usable / count
			var tt := s / seg.length
			var p := graph.point_on(seg.id, tt)
			var d := graph.tangent_on(seg.id, tt)
			var left := Vector2(-d.y, d.x)
			for side in sides:
				var base := p + left * hw * side
				# Lamp arm (+X) points towards the road centre.
				var inward := -left * side
				var basis := Basis(Vector3(inward.x, 0, inward.y), Vector3.UP, Vector3(-inward.y, 0, inward.x))
				transforms.append(Transform3D(basis, Vector3(base.x, curb_h, base.y)))
				var pool := base + inward * 2.2
				pools.append(Transform3D(Basis(), Vector3(pool.x, curb_h + 0.03, pool.y)))
	_fill(_lamps.multimesh, transforms)
	_fill(_pools.multimesh, pools)


func _fill(mm: MultiMesh, transforms: Array[Transform3D]) -> void:
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

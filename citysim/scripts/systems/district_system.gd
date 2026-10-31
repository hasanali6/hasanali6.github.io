extends Node3D
## Districts: named areas the player outlines on the map, each with its own
## policies (data/districts.json):
##   heavy_ban     : trucks drive around it when they can; quieter streets
##   high_rise_ban : new and growing buildings stay low
##   recycling     : less garbage from its homes, paid per resident
##   paid_parking  : drivers pay to park there (city income), so more of
##                   them take the bus or tram
##
## Drawing: with the district tool open each tap adds a corner; tapping the
## first corner again (or "Bitir") closes the outline, tapping the last one
## removes it. Outlines may not cross themselves. Where districts overlap,
## the newer one counts. Names show on the map; outlines are always drawn
## faintly and filled while the tool is open.
##
## Lookups are cached: buildings remember their district flags until the
## districts change (version), roads per segment until roads or districts
## change.

const OUTLINE_HEIGHT := 0.5
const FILL_HEIGHT := 0.32
const OUTLINE_WIDTH := 2.4
const CLOSE_RADIUS := 22.0
const TAP_PIXELS := 28.0

@export var building_system_path: NodePath
@export var road_network_path: NodePath

var districts: Array = []          # {id, number, name, color, points: PackedVector2Array, flags, rect: Rect2}
var version: int = 1
var last_report: Dictionary = {"recycling": 0.0}
var stats: Dictionary = {}         # district id -> {residents, buildings}

var _buildings: Node
var _net: Node
var _cfg: Dictionary
var _policies: Dictionary
var _colors: Array = []
var _next_id: int = 1
var _seg_flags: Dictionary = {}    # segment id -> flags
var _seg_version: int = -1
var _flag_of: Dictionary = {}      # policy key -> bit
# Tool.
var _active: bool = false
var _draft := PackedVector2Array()
var _down_pos := Vector2.INF
# Visuals.
var _root: Node3D
var _fills: Array = []
var _draft_mesh: MeshInstance3D
var _line_mat: StandardMaterial3D


func _ready() -> void:
	_buildings = get_node(building_system_path)
	_net = get_node(road_network_path)
	_cfg = GameData.section("districts")
	_policies = _cfg["policies"]
	for key: String in _policies:
		_flag_of[key] = int(_policies[key]["flag"])
	for c: String in _cfg["colors"]:
		_colors.append(DataLoader.to_color(c))
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_root = Node3D.new()
	_root.name = "Districts"
	add_child(_root)
	_draft_mesh = MeshInstance3D.new()
	_draft_mesh.name = "DistrictDraft"
	_draft_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_draft_mesh)
	EventBus.build_tool_selected.connect(_on_tool_selected)
	EventBus.tool_pointer.connect(_on_pointer)
	EventBus.roads_changed.connect(func() -> void: _seg_version = -1)
	EventBus.month_changed.connect(_on_month)


# --- Lookups ------------------------------------------------------------------------

func flag(key: String) -> int:
	return int(_flag_of.get(key, 0))


## The district a point lies in (the newest when several overlap), or {}.
func district_at(p: Vector2) -> Dictionary:
	for i in range(districts.size() - 1, -1, -1):
		var d: Dictionary = districts[i]
		if (d["rect"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, d["points"]):
			return d
	return {}


func flags_at(p: Vector2) -> int:
	var d := district_at(p)
	return 0 if d.is_empty() else int(d["flags"])


## Policy flags of a building, cached on the record until districts change.
func flags_of(b: Dictionary) -> int:
	if int(b.get("policy_version", 0)) != version:
		var d := district_at(b["centre"])
		b["district"] = -1 if d.is_empty() else int(d["id"])
		b["policy_flags"] = 0 if d.is_empty() else int(d["flags"])
		b["policy_version"] = version
	return int(b["policy_flags"])


## Policy flags of a road (at its middle).
func segment_flags(seg_id: int) -> int:
	if _seg_version != version:
		_rebuild_segment_flags()
	return int(_seg_flags.get(seg_id, 0))


func _rebuild_segment_flags() -> void:
	_seg_version = version
	_seg_flags = {}
	if districts.is_empty():
		return
	var rg: RoadGraph = _net.graph
	for seg: RoadGraph.RoadSegment in rg.segments.values():
		var f := flags_at(rg.point_on(seg.id, 0.5))
		if f != 0:
			_seg_flags[seg.id] = f


## Parking fee for driving to a road inside a paid-parking district.
func parking_fee(seg_id: int) -> float:
	if segment_flags(seg_id) & flag("paid_parking"):
		return float(_policies["paid_parking"]["fee"])
	return 0.0


## Cost multiplier per directed edge of a TrafficGraph for trucks (empty when
## no district bans heavy traffic).
func heavy_penalty(g: TrafficGraph) -> PackedFloat32Array:
	var bit := flag("heavy_ban")
	var any := false
	for d: Dictionary in districts:
		if int(d["flags"]) & bit:
			any = true
	if not any:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(g.edge_count())
	out.fill(1.0)
	var penalty := float(_policies["heavy_ban"]["route_penalty"])
	for s in g.seg_ids.size():
		if segment_flags(g.seg_ids[s]) & bit:
			out[s * 2] = penalty
			out[s * 2 + 1] = penalty
	return out


## Traffic noise multiplier along a road.
func noise_factor(seg_id: int) -> float:
	if segment_flags(seg_id) & flag("heavy_ban"):
		return float(_policies["heavy_ban"]["noise_factor"])
	return 1.0


## Highest floor count allowed for a building at p (0 = no limit).
func floor_cap(p: Vector2) -> int:
	if flags_at(p) & flag("high_rise_ban"):
		return int(_policies["high_rise_ban"]["max_floors"])
	return 0


func garbage_factor(b: Dictionary) -> float:
	if flags_of(b) & flag("recycling"):
		return float(_policies["recycling"]["garbage_factor"])
	return 1.0


## Happiness from the policies of a home's district.
func happiness_of(b: Dictionary) -> float:
	var f := flags_of(b)
	if f == 0:
		return 0.0
	var h := 0.0
	for key: String in _policies:
		if f & int(_policies[key]["flag"]):
			h += float(_policies[key]["happiness"])
	return h


# --- Editing ---------------------------------------------------------------------------

func district_by_id(id: int) -> Dictionary:
	for d: Dictionary in districts:
		if int(d["id"]) == id:
			return d
	return {}


func set_policy(id: int, key: String, on: bool) -> void:
	var d := district_by_id(id)
	if d.is_empty() or not _flag_of.has(key):
		return
	var bit := int(_flag_of[key])
	d["flags"] = (int(d["flags"]) | bit) if on else (int(d["flags"]) & ~bit)
	_changed()


func rename(id: int, name: String) -> void:
	var d := district_by_id(id)
	var clean := name.strip_edges().left(24)
	if d.is_empty() or clean == "":
		return
	d["name"] = clean
	_rebuild_visuals()
	EventBus.districts_changed.emit()


func delete_district(id: int) -> void:
	var d := district_by_id(id)
	if d.is_empty():
		return
	districts.erase(d)
	stats.erase(id)
	_changed()


func _changed() -> void:
	version += 1
	_rebuild_visuals()
	EventBus.districts_changed.emit()


func draft_points() -> int:
	return _draft.size()


## Error key for the outline being drawn, "" if it can become a district.
func draft_error() -> String:
	if _draft.size() < 3:
		return "DISTRICT_ERR_POINTS"
	if not TransitRules.polygon_simple(_draft):
		return "DISTRICT_ERR_CROSSING"
	if TransitRules.polygon_area(_draft) < float(_cfg["min_area_m2"]):
		return "DISTRICT_ERR_SMALL"
	if districts.size() >= int(_cfg["max_districts"]):
		return "DISTRICT_ERR_MAX"
	return ""


func finish_draft() -> bool:
	var error := draft_error()
	if error != "":
		EventBus.district_draft_changed.emit({"points": _draft.size(), "error": error})
		return false
	var number := 1
	var used := {}
	for d: Dictionary in districts:
		used[int(d["number"])] = true
	while used.has(number):
		number += 1
	var d := _make_district(_next_id, number, tr("DISTRICT_NAME") % number, _free_color(), _draft, 0)
	_next_id += 1
	districts.append(d)
	_draft = PackedVector2Array()
	_update_draft()
	_changed()
	EventBus.notification_posted.emit("districts", tr("NOTIFY_DISTRICT_CREATED") % d["name"])
	return true


func cancel_draft() -> void:
	_draft = PackedVector2Array()
	_update_draft()


func _make_district(id: int, number: int, name: String, color: int, points: PackedVector2Array, flags: int) -> Dictionary:
	var pts := points.duplicate()
	# Counter-clockwise outlines keep the fill facing up.
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	return {"id": id, "number": number, "name": name, "color": color, "points": pts, "flags": flags, "rect": rect}


func _free_color() -> int:
	var used := {}
	for d: Dictionary in districts:
		used[int(d["color"])] = true
	for i in _colors.size():
		if not used.has(i):
			return i
	return districts.size() % _colors.size()


func _on_tool_selected(tool: String, _options: Dictionary) -> void:
	var was := _active
	_active = tool == "district"
	if was and not _active:
		_draft = PackedVector2Array()
	for f: Node3D in _fills:
		f.visible = _active
	_update_draft()


func _on_pointer(phase: int, screen_pos: Vector2) -> void:
	if not _active:
		return
	if phase == GestureTracker.Pointer.DOWN:
		_down_pos = screen_pos
	elif phase == GestureTracker.Pointer.UP:
		if _down_pos != Vector2.INF and _down_pos.distance_to(screen_pos) <= TAP_PIXELS:
			var g: Variant = _ground(screen_pos)
			if g != null:
				add_point(g)
		_down_pos = Vector2.INF
	elif phase == GestureTracker.Pointer.CANCEL:
		_down_pos = Vector2.INF


## Adds a corner; the first corner closes the outline, the last one undoes.
func add_point(p: Vector2) -> void:
	if _draft.size() >= 3 and p.distance_to(_draft[0]) < CLOSE_RADIUS:
		finish_draft()
		return
	if not _draft.is_empty() and p.distance_to(_draft[_draft.size() - 1]) < CLOSE_RADIUS:
		_draft.remove_at(_draft.size() - 1)
		_update_draft()
		return
	if _draft.size() >= int(_cfg["max_points"]):
		EventBus.district_draft_changed.emit({"points": _draft.size(), "error": "DISTRICT_ERR_MAX_POINTS"})
		return
	_draft.append(p)
	_update_draft()


func _update_draft() -> void:
	var error := draft_error() if _draft.size() >= 3 else ""
	EventBus.district_draft_changed.emit({"points": _draft.size(), "error": error})
	if not _active or _draft.is_empty():
		_draft_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col: Color = _colors[_free_color()]
	var line := Array(_draft)
	_outline(st, line, false, OUTLINE_HEIGHT + 0.05, OUTLINE_WIDTH, Color(col, 0.95))
	for p in _draft:
		_disc(st, p, 5.0, OUTLINE_HEIGHT + 0.1, Color(1, 1, 1, 0.95), Color(col, 0.95))
	var m := st.commit()
	m.surface_set_material(0, _line_mat)
	_draft_mesh.mesh = m


# --- Monthly ---------------------------------------------------------------------------

func _on_month(_m: int) -> void:
	var recycling := 0.0
	var per_resident := float(_policies["recycling"]["cost_per_resident"])
	var bit := flag("recycling")
	var out := {}
	if not districts.is_empty():
		for b: Dictionary in _buildings.buildings.values():
			var f := flags_of(b)
			var id := int(b.get("district", -1))
			if id < 0:
				continue
			var residents := int(b.get("residents", 0))
			if not out.has(id):
				out[id] = {"residents": 0, "buildings": 0}
			out[id]["residents"] += residents
			out[id]["buildings"] += 1
			if f & bit:
				recycling += residents * per_resident
	stats = out
	last_report = {"recycling": recycling}
	EventBus.district_reported.emit(last_report.duplicate())


# --- Visuals ---------------------------------------------------------------------------

func _rebuild_visuals() -> void:
	for child in _root.get_children():
		child.queue_free()
	_fills = []
	for d: Dictionary in districts:
		var col: Color = _colors[int(d["color"]) % _colors.size()]
		var pts: PackedVector2Array = d["points"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_outline(st, Array(pts), true, OUTLINE_HEIGHT, OUTLINE_WIDTH, Color(col, 0.75))
		var outline := MeshInstance3D.new()
		var om := st.commit()
		om.surface_set_material(0, _line_mat)
		outline.mesh = om
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(outline)
		var tris := Geometry2D.triangulate_polygon(pts)
		if not tris.is_empty():
			var fs := SurfaceTool.new()
			fs.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in tris:
				var p := pts[k]
				fs.set_color(Color(col, 0.2))
				fs.add_vertex(Vector3(p.x, FILL_HEIGHT, p.y))
			var fill := MeshInstance3D.new()
			var fm := fs.commit()
			fm.surface_set_material(0, _line_mat)
			fill.mesh = fm
			fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fill.visible = _active
			_root.add_child(fill)
			_fills.append(fill)
		var label := Label3D.new()
		label.text = str(d["name"])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.0011
		label.font_size = 44
		label.outline_size = 14
		label.modulate = Color(1, 1, 1, 0.95)
		label.outline_modulate = Color(col.darkened(0.55), 0.9)
		label.no_depth_test = true
		label.font = UiStyle.font(800)
		var c := TransitRules.polygon_centroid(pts)
		label.position = Vector3(c.x, 30.0, c.y)
		_root.add_child(label)


func _outline(st: SurfaceTool, pts: Array, closed: bool, y: float, width: float, color: Color) -> void:
	var n := pts.size()
	if n < 2:
		return
	var count := n if closed else n - 1
	for i in count:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var d := (b - a).normalized()
		var side := Vector2(d.y, -d.x) * width * 0.5
		var quad := [Vector3(a.x + side.x, y, a.y + side.y), Vector3(a.x - side.x, y, a.y - side.y),
			Vector3(b.x - side.x, y, b.y - side.y), Vector3(b.x + side.x, y, b.y + side.y)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.add_vertex(quad[k])
		_disc(st, b, width * 0.5, y, color, color)


func _disc(st: SurfaceTool, p: Vector2, r: float, y: float, inner: Color, outer: Color) -> void:
	var n := 12
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		st.set_color(inner)
		st.add_vertex(Vector3(p.x, y, p.y))
		st.set_color(outer)
		st.add_vertex(Vector3(p.x + cos(a1) * r, y, p.y + sin(a1) * r))
		st.set_color(outer)
		st.add_vertex(Vector3(p.x + cos(a0) * r, y, p.y + sin(a0) * r))


func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return null if hit == null else Vector2((hit as Vector3).x, (hit as Vector3).z)


# --- Saving ---------------------------------------------------------------------------

func save_state() -> Dictionary:
	var out := []
	for d: Dictionary in districts:
		out.append({"id": d["id"], "number": d["number"], "name": d["name"], "color": d["color"],
			"points": d["points"], "flags": d["flags"]})
	return {"districts": out, "next_id": _next_id}


func load_state(state: Dictionary) -> void:
	districts = []
	_next_id = int(state.get("next_id", 1))
	for rec: Dictionary in state.get("districts", []):
		var pts := PackedVector2Array(rec.get("points", PackedVector2Array()))
		if pts.size() < 3:
			continue
		districts.append(_make_district(int(rec["id"]), int(rec.get("number", 1)), str(rec.get("name", "")),
			int(rec.get("color", 0)), pts, int(rec.get("flags", 0))))
	_changed()

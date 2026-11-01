extends Node3D
## Road drawing tool. Active while the HUD's road panel is open; receives
## single-finger strokes as EventBus.tool_pointer (two fingers keep moving the
## camera). Modes:
##   straight : press = start, drag = end, release = build
##   curve    : first stroke start -> bend point, second stroke drags the end
##   bulldoze : touch a building or a road to select it, release to demolish
##              (hand-built buildings and roads give part of their price back)
## Straight roads always follow 15° steps measured from the road they start
## on (so continuing or crossing at right angles is exact) with 8 m length
## steps; the end only jumps onto a nearby junction or road when that keeps
## the drawn direction. Start points snap to junctions, roads or the 8 m grid.

@export var road_network_path: NodePath
@export var building_system_path: NodePath

var _net: Node
var _buildings: Node
var _target_building: int = -1
var _ref_angle: float = 0.0
var _max_turn: float
var _active: bool = false
var _type: String = ""
var _mode: String = "straight"
var _start: Variant = null
var _control: Variant = null
var _end: Variant = null
var _curve_stage: int = 0
var _highlight: int = -1
var _last_screen: Vector2 = Vector2.ZERO

var _grid: float
var _angle_step: float
var _angle_tolerance: float
var _node_radius_px: float
var _segment_radius_px: float
var _playable_half: float
var _preview: MeshInstance3D
var _marker: MeshInstance3D
var _valid_mat: StandardMaterial3D
var _invalid_mat: StandardMaterial3D


func _ready() -> void:
	_net = get_node(road_network_path)
	if not building_system_path.is_empty():
		_buildings = get_node(building_system_path)
	var snap := GameData.section("roads/snap")
	_grid = float(snap["grid_m"])
	_angle_step = deg_to_rad(float(snap["angle_step_deg"]))
	_angle_tolerance = deg_to_rad(float(snap["angle_snap_tolerance_deg"]))
	_node_radius_px = float(snap["node_radius_px"])
	_max_turn = deg_to_rad(float(snap.get("end_snap_max_turn_deg", 7.0)))
	_segment_radius_px = float(snap["segment_radius_px"])
	_playable_half = GameData.num("map/playable_size_m") * 0.5
	_type = str((GameData.value("roads/order") as Array)[0])

	var prev := GameData.section("roads/preview")
	_valid_mat = _preview_material(DataLoader.to_color(prev["valid_color"]), float(prev["alpha"]))
	_invalid_mat = _preview_material(DataLoader.to_color(prev["invalid_color"]), float(prev["alpha"]))
	_preview = MeshInstance3D.new()
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview)
	_marker = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 1.4
	ring.bottom_radius = 1.4
	ring.height = 0.06
	ring.radial_segments = 20
	ring.rings = 1
	_marker.mesh = ring
	_marker.material_override = _valid_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	_reset()

	EventBus.build_tool_selected.connect(_on_tool_selected)
	EventBus.tool_pointer.connect(_on_pointer)


func _preview_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat


func _on_tool_selected(tool: String, options: Dictionary) -> void:
	_active = tool == "road"
	if _active:
		_type = str(options.get("type", _type))
		_mode = str(options.get("mode", _mode))
	_reset()


func _on_pointer(phase: int, screen_pos: Vector2) -> void:
	if not _active:
		return
	_last_screen = screen_pos
	match phase:
		GestureTracker.Pointer.CANCEL:
			_reset()
		GestureTracker.Pointer.DOWN:
			_on_down(screen_pos)
		GestureTracker.Pointer.MOVE:
			_on_move(screen_pos)
		GestureTracker.Pointer.UP:
			_on_up(screen_pos)


func _on_down(screen_pos: Vector2) -> void:
	match _mode:
		"bulldoze":
			_pick_target(screen_pos)
		"upgrade":
			_highlight = _segment_at(screen_pos)
		"curve":
			if _curve_stage == 0:
				_start = _snap(screen_pos, null)
				_control = _start
				_ref_angle = _reference_angle(_start)
			else:
				_end = _snap(screen_pos, null)
		_:
			_start = _snap(screen_pos, null)
			_end = _start
			_ref_angle = _reference_angle(_start)
	_refresh()


func _on_move(screen_pos: Vector2) -> void:
	match _mode:
		"bulldoze":
			_pick_target(screen_pos)
		"upgrade":
			_highlight = _segment_at(screen_pos)
		"curve":
			if _curve_stage == 0:
				_control = _snap(screen_pos, _start)
			else:
				_end = _snap(screen_pos, null)
		_:
			if _start != null:
				_end = _snap(screen_pos, _start)
	_refresh()


func _on_up(screen_pos: Vector2) -> void:
	match _mode:
		"upgrade":
			_highlight = _segment_at(screen_pos)
			if _highlight >= 0:
				var res: Dictionary = _net.upgrade(_highlight, _type)
				if res["ok"]:
					EventBus.sfx_requested.emit("build_road")
					EventBus.notification_posted.emit("roads", tr("ROAD_UPGRADED") % [tr(_net.type_config(_type)["name_key"]), UiStyle.format_int(int(res["cost"]))])
				else:
					EventBus.sfx_requested.emit("error")
					EventBus.notification_posted.emit("roads", tr(res["error"]))
			_reset()
		"bulldoze":
			_pick_target(screen_pos)
			if _target_building >= 0:
				var back: int = _buildings.refund_of(_target_building)
				_buildings.demolish(_target_building, true)
				EventBus.zones_changed.emit()
				if back > 0:
					EconomySystem.refund(back)
				EventBus.sfx_requested.emit("bulldoze")
				EventBus.notification_posted.emit("roads", tr("BUILDING_DEMOLISHED") % UiStyle.format_int(back))
			elif _highlight >= 0 and _net.is_outside_segment(_highlight):
				EventBus.sfx_requested.emit("error")
				EventBus.notification_posted.emit("roads", tr("ROAD_ERR_OUTSIDE_LINK"))
			elif _highlight >= 0:
				var refund: int = _net.demolish(_highlight)
				EventBus.sfx_requested.emit("bulldoze")
				EventBus.notification_posted.emit("roads", tr("ROAD_REFUND") % UiStyle.format_int(refund))
			_reset()
		"curve":
			if _curve_stage == 0:
				if _start != null and _control != null and (_start as Vector2).distance_to(_control) >= _grid:
					_curve_stage = 1
					_end = _control
					_refresh()
				else:
					_reset()
			else:
				_end = _snap(screen_pos, null)
				_try_build(_start, _end, _control)
		_:
			if _start != null:
				_end = _snap(screen_pos, _start)
				_try_build(_start, _end, null)


func _try_build(a: Vector2, b: Vector2, control: Variant) -> void:
	var check := _evaluate(a, b, control)
	if check["valid"]:
		var result: Dictionary = _net.build_road(a, b, control, _type)
		if not result["ok"]:
			EventBus.sfx_requested.emit("error")
			EventBus.notification_posted.emit("roads", tr(result["error"]))
		else:
			EventBus.sfx_requested.emit("build_road")
	elif a.distance_to(b) > 0.5:
		EventBus.sfx_requested.emit("error")
		EventBus.notification_posted.emit("roads", tr(check["error"]))
	_reset()


func _reset() -> void:
	_start = null
	_control = null
	_end = null
	_curve_stage = 0
	_highlight = -1
	_target_building = -1
	_preview.visible = false
	_marker.visible = false
	EventBus.road_preview_changed.emit({"active": false})


# --- Evaluation and preview ------------------------------------------------------

func _evaluate(a: Vector2, b: Vector2, control: Variant) -> Dictionary:
	var pts: Array[Vector2] = [a, b]
	if control != null:
		pts.append(control)
	var open_half := ProgressionSystem.area_half()
	for p in pts:
		if not MapGrid.is_inside(Vector3(p.x, 0, p.y), _playable_half):
			return {"valid": false, "error": "ROAD_ERR_OUTSIDE", "cost": 0, "length": 0.0}
		if not MapGrid.is_inside(Vector3(p.x, 0, p.y), open_half):
			return {"valid": false, "error": "ROAD_ERR_LOCKED_AREA", "cost": 0, "length": 0.0}
	var plan: Dictionary = (_net.graph as RoadGraph).plan_road(a, b, control, (_net.graph as RoadGraph).elevated_types.has(_type))
	if not plan["ok"]:
		return {"valid": false, "error": plan["error"], "cost": 0, "length": 0.0}
	# Over water the road becomes a bridge; its ends must stand on land.
	var wet: String = _net.water_error(plan, _type)
	if wet != "":
		return {"valid": false, "error": wet, "cost": 0, "length": plan["length"]}
	var cost: int = _net.plan_cost(plan, _type)
	if not EconomySystem.can_afford(cost):
		return {"valid": false, "error": "ROAD_ERR_MONEY", "cost": cost, "length": plan["length"]}
	return {"valid": true, "error": "", "cost": cost, "length": plan["length"]}


func _refresh() -> void:
	if _mode == "bulldoze":
		_show_bulldoze()
		return
	if _mode == "upgrade":
		_show_upgrade()
		return
	var a: Variant = _start
	var b: Variant = _end
	var control: Variant = null
	if _mode == "curve":
		if _curve_stage == 0:
			b = _control
		else:
			control = _control
	if a == null or b == null:
		return
	_marker.visible = true
	_marker.position = Vector3((b as Vector2).x, 0.25, (b as Vector2).y)
	if (a as Vector2).distance_to(b) < 0.5:
		_preview.visible = false
		EventBus.road_preview_changed.emit({"active": false})
		return
	var check := _evaluate(a, b, control)
	var ctrl: Vector2 = control if control != null else ((a as Vector2) + (b as Vector2)) * 0.5
	var width := RoadTypes.total_width(_net.type_config(_type))
	_preview.transform = Transform3D.IDENTITY
	_preview.mesh = _ribbon(a, ctrl, b, width)
	_preview.material_override = _valid_mat if check["valid"] else _invalid_mat
	_marker.material_override = _preview.material_override
	_preview.visible = true
	check["active"] = true
	check["screen_pos"] = _last_screen
	if _mode == "curve" and _curve_stage == 0:
		check["hint"] = "ROAD_HINT_CURVE"
	EventBus.road_preview_changed.emit(check)


func _show_upgrade() -> void:
	var graph: RoadGraph = _net.graph
	if _highlight < 0 or not graph.segments.has(_highlight):
		_preview.visible = false
		EventBus.road_preview_changed.emit({"active": false})
		return
	var seg: RoadGraph.RoadSegment = graph.segments[_highlight]
	var c := graph.curve_of(seg)
	var same := seg.type == _type
	var cost: int = 0 if same else _net.upgrade_cost(_highlight, _type)
	var ok: bool = not same and not _net.is_outside_segment(_highlight) and EconomySystem.can_afford(cost)
	_preview.transform = Transform3D.IDENTITY
	_preview.mesh = _ribbon(c[0], c[1], c[2], RoadTypes.total_width(_net.type_config(_type)) + 0.6)
	_preview.material_override = _valid_mat if ok else _invalid_mat
	_preview.visible = true
	var error := ""
	if same:
		error = "ROAD_ERR_UPGRADE_SAME"
	elif _net.is_outside_segment(_highlight):
		error = "ROAD_ERR_OUTSIDE_LINK"
	elif not ok:
		error = "ROAD_ERR_MONEY"
	EventBus.road_preview_changed.emit({"active": true, "valid": ok, "error": error, "cost": cost,
		"length": seg.length, "screen_pos": _last_screen, "hint": "ROAD_HINT_UPGRADE"})


func _show_bulldoze() -> void:
	if _target_building >= 0 and _buildings.buildings.has(_target_building):
		var b: Dictionary = _buildings.buildings[_target_building]
		var f: Vector2 = b["front"]
		var fz := Vector3(f.x, 0, f.y)
		var dx := Vector3.UP.cross(fz)
		var h := maxf(int(b["floors"]) * 3.4 + 2.0, 5.0)
		var box := BoxMesh.new()
		box.size = Vector3(float(b["width"]) + 0.6, h, float(b["depth"]) + 0.6)
		_preview.mesh = box
		var c: Vector2 = b["centre"]
		_preview.transform = Transform3D(Basis(dx, Vector3.UP, fz), Vector3(c.x, h * 0.5, c.y))
		_preview.material_override = _invalid_mat
		_preview.visible = true
		EventBus.road_preview_changed.emit({"active": true, "valid": true, "refund": _buildings.refund_of(_target_building),
			"length": 0.0, "screen_pos": _last_screen})
		return
	_preview.transform = Transform3D.IDENTITY
	if _highlight < 0 or not (_net.graph as RoadGraph).segments.has(_highlight):
		_preview.visible = false
		EventBus.road_preview_changed.emit({"active": false})
		return
	var graph: RoadGraph = _net.graph
	var seg: RoadGraph.RoadSegment = graph.segments[_highlight]
	var c := graph.curve_of(seg)
	_preview.mesh = _ribbon(c[0], c[1], c[2], RoadTypes.total_width(_net.type_config(seg.type)) + 1.0)
	_preview.material_override = _invalid_mat
	_preview.visible = true
	EventBus.road_preview_changed.emit({"active": true, "valid": true, "refund": _net.refund_of(_highlight),
		"length": seg.length, "screen_pos": _last_screen})


func _ribbon(a: Vector2, c: Vector2, b: Vector2, width: float) -> ArrayMesh:
	var n := clampi(ceili((a.distance_to(c) + c.distance_to(b)) / 3.0), 1, 256)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	st.set_normal(Vector3.UP)
	for i in n + 1:
		var t := float(i) / n
		var p := RoadGraph.bezier(a, c, b, t)
		var d := RoadGraph.bezier_tangent(a, c, b, t).normalized()
		var l := Vector2(-d.y, d.x) * width * 0.5
		st.add_vertex(Vector3(p.x + l.x, 0.3, p.y + l.y))
		st.add_vertex(Vector3(p.x - l.x, 0.3, p.y - l.y))
	return st.commit()


# --- Snapping ------------------------------------------------------------------------

func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if hit == null:
		return null
	return Vector2((hit as Vector3).x, (hit as Vector3).z)


func _metres_per_pixel(at: Vector2) -> float:
	var cam := get_viewport().get_camera_3d()
	var p0 := cam.unproject_position(Vector3(at.x, 0, at.y))
	var p1 := cam.unproject_position(Vector3(at.x + 1.0, 0, at.y))
	return 1.0 / maxf(p0.distance_to(p1), 0.001)


func _snap(screen_pos: Vector2, anchor: Variant) -> Variant:
	var g: Variant = _ground(screen_pos)
	if g == null:
		return anchor
	var p: Vector2 = g
	var graph: RoadGraph = _net.graph
	var cam := get_viewport().get_camera_3d()
	# Where an existing junction or road would take the point (if anywhere).
	var target: Variant = null
	var target_px := INF
	var best_px := _node_radius_px
	for node: RoadGraph.RoadNode in graph.nodes.values():
		var sp := cam.unproject_position(Vector3(node.pos.x, 0, node.pos.y))
		var dpx := sp.distance_to(screen_pos)
		if dpx < best_px:
			best_px = dpx
			target = node.pos
			target_px = dpx
	if target == null:
		var hit := graph.find_segment_near(p, _segment_radius_px * _metres_per_pixel(p))
		if not hit.is_empty():
			target = hit["point"]
			target_px = cam.unproject_position(Vector3(target.x, 0, target.y)).distance_to(screen_pos)
	if anchor == null:
		if target != null:
			return target
		return Vector2(roundf(p.x / _grid) * _grid, roundf(p.y / _grid) * _grid)
	# Drawing from a start point: fixed angle steps from the reference
	# direction and length steps, unless a junction or road lies (almost)
	# straight ahead.
	var a: Vector2 = anchor
	var v := p - a
	if v.length() < 0.01:
		return a
	var rel := angle_difference(_ref_angle, v.angle())
	var ang := _ref_angle + roundf(rel / _angle_step) * _angle_step
	if absf(angle_difference(ang, v.angle())) > _angle_tolerance:
		ang = v.angle()
	var length := maxf(roundf(v.length() / _grid) * _grid, _grid)
	var stepped := a + Vector2.from_angle(ang) * length
	if target != null:
		var tv: Vector2 = (target as Vector2) - a
		if tv.length() > 1.0 and (absf(angle_difference(tv.angle(), ang)) <= _max_turn or target_px < _node_radius_px * 0.35):
			return target
	return stepped


## Direction to measure angle steps from: the road the start point sits on
## (or the first road at a junction), else the map axes.
func _reference_angle(start: Variant) -> float:
	if start == null:
		return 0.0
	var graph: RoadGraph = _net.graph
	var p: Vector2 = start
	var node := graph.find_node_near(p, 0.5)
	if node >= 0:
		var segs: PackedInt32Array = (graph.nodes[node] as RoadGraph.RoadNode).segments
		if not segs.is_empty():
			return graph.leaving_direction(segs[0], node).angle()
	var hit := graph.find_segment_near(p, 0.5)
	if not hit.is_empty():
		return graph.tangent_on(int(hit["segment"]), float(hit["t"])).angle()
	return 0.0


## Bulldoze target under the finger: a building first, else a road.
func _pick_target(screen_pos: Vector2) -> void:
	_target_building = -1
	_highlight = -1
	var g: Variant = _ground(screen_pos)
	if g != null and _buildings != null:
		_target_building = _buildings.building_at(g)
	if _target_building < 0:
		_highlight = _segment_at(screen_pos)


func _segment_at(screen_pos: Vector2) -> int:
	var g: Variant = _ground(screen_pos)
	if g == null:
		return -1
	var hit := (_net.graph as RoadGraph).find_segment_near(g, _segment_radius_px * 1.5 * _metres_per_pixel(g))
	return hit.get("segment", -1)

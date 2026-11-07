extends Node3D
## Hand placement of buildings and parks from data/catalog.json. While a
## catalogue item is selected, dragging a finger previews the lot on the
## exact squares it will take (green = fits and affordable, red = not);
## releasing leaves the preview standing and asks ✓ / ✗ (confirm_pending).
## Placed buildings join the economy like grown ones.
## Pumps, sewage outlets and treatment plants must stand next to water.

@export var building_system_path: NodePath
@export var zone_system_path: NodePath

var _buildings: Node
var _zones: Node
var _active: bool = false
var _item: Dictionary = {}
var _cell: int = -1
var _snap_radius: float
var _water_reach: float
var _valid: bool = false
var _pending_cell: int = -1   # a placement waiting for ✓ / ✗
var _preview: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D


func _ready() -> void:
	_buildings = get_node(building_system_path)
	_zones = get_node(zone_system_path)
	_snap_radius = GameData.num("catalog/snap_radius_m")
	_water_reach = GameData.num("services/effects/water_reach_m")
	var prev := GameData.section("roads/preview")
	_ok_mat = _material(DataLoader.to_color(prev["valid_color"]), float(prev["alpha"]))
	_bad_mat = _material(DataLoader.to_color(prev["invalid_color"]), float(prev["alpha"]))
	_preview = MeshInstance3D.new()
	_preview.mesh = BoxMesh.new()
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.visible = false
	add_child(_preview)
	EventBus.build_tool_selected.connect(_on_tool_selected)
	EventBus.tool_pointer.connect(_on_pointer)


func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _on_tool_selected(tool: String, options: Dictionary) -> void:
	if _pending_cell >= 0:
		cancel_pending()
	_active = tool == "place"
	_item = options.get("item", {}) if _active else {}
	_preview.visible = false


func _on_pointer(phase: int, screen_pos: Vector2) -> void:
	if not _active or _item.is_empty():
		return
	match phase:
		GestureTracker.Pointer.CANCEL:
			_preview.visible = false
		GestureTracker.Pointer.DOWN, GestureTracker.Pointer.MOVE:
			if phase == GestureTracker.Pointer.DOWN and _pending_cell >= 0:
				cancel_pending()
			_preview_at(screen_pos)
		GestureTracker.Pointer.UP:
			_preview_at(screen_pos)
			if _cell >= 0 and _valid:
				# Ask first: the preview stays where it is.
				_pending_cell = _cell
				EventBus.road_preview_changed.emit({"active": false})
				EventBus.road_proposal_changed.emit({"active": true, "node": "BuildTool", "label": _item["name_key"],
					"cost": int(_item["cost"])})
			else:
				_build()
				_preview.visible = false


func confirm_pending() -> void:
	if _pending_cell < 0:
		return
	_cell = _pending_cell
	_valid = not _buildings.lot_for(_item, _cell).is_empty() and EconomySystem.can_afford(int(_item["cost"]))
	_pending_cell = -1
	_build()
	_preview.visible = false
	EventBus.road_proposal_changed.emit({"active": false})


func cancel_pending() -> void:
	_pending_cell = -1
	_preview.visible = false
	EventBus.road_proposal_changed.emit({"active": false})


## Water-side buildings need their lot within reach of a river or lake.
func _water_ok(centre: Vector2, w: float, d: float) -> bool:
	if not _item.get("needs_water", false):
		return true
	return MapWater.shared().distance(centre) <= maxf(w, d) * 0.5 + _water_reach


## Sea-front buildings need their lot by the sea shore.
func _coast_ok(centre: Vector2, w: float, d: float) -> bool:
	if not _item.get("near_coast", false):
		return true
	var cd := MapWater.shared().coast_distance(centre)
	return cd <= maxf(w, d) * 0.5 + float(GameData.value("catalog/coast_reach_m"))


## An airport needs a clear strip behind its lot for the runway: no roads,
## buildings or water, inside the open map.
func _runway_ok(centre: Vector2, f: Vector2, d: float) -> bool:
	if not _item.has("runway"):
		return true
	var rw := float(_item["runway"][0])
	var rl := float(_item["runway"][1])
	var side := Vector2(-f.y, f.x)
	var rg: RoadGraph = get_parent().get_node("RoadNetwork").graph
	var half: float = ProgressionSystem.area_half()
	var v := d * 0.5 + 6.0
	while v <= d * 0.5 + 6.0 + rl:
		for u in [-rw * 0.5, 0.0, rw * 0.5]:
			var p: Vector2 = centre - f * v + side * u
			if maxf(absf(p.x), absf(p.y)) > half or MapWater.shared().is_water(p, 2.0):
				return false
			if not rg.find_segment_near(p, 10.0).is_empty() or int(_buildings.building_at(p)) >= 0:
				return false
		v += 12.0
	return true


## Where the selected item goes for a finger at g: its footprint covers the
## square under the finger. Of all footprints (any square nearby, either
## road) that contain g, a free one whose middle is closest to the finger
## wins. If none fits, a free lot at most ~6 m from the finger (finger on the
## kerb) takes over; otherwise the lot under the finger is shown red with the
## reason, and -1 means there are no squares there at all. It never jumps
## to a far-away spot.
func _best_cell(g: Vector2) -> int:
	var grid: ZoneGrid = _zones.grid
	var w := int(_item["lot"][0]) * grid.cell_size
	var d := int(_item["lot"][1]) * grid.cell_size
	var reach := _snap_radius + maxf(w, d) + grid.cell_size
	var best_in := -1
	var best_in_d := INF
	var bad_in := -1
	var bad_in_d := INF
	var best_near := -1
	var best_near_d := INF
	var near: Array[int] = []
	# Any square may be the lot's first square (the lot only has to touch a
	# road somewhere); far away only road-facing squares are tried.
	var inner := (w + d) * 0.75 + grid.cell_size
	for i in grid.cells_near(g, reach):
		if grid.depth[i] != 0:
			if grid.centers[i].distance_to(g) > inner:
				continue
			# Cheap test first: would this square's lot cover the finger at all?
			var c0 := grid.centers[i] - grid.dirs[i] * grid.cell_size * 0.5 + grid.fronts[i] * grid.cell_size * 0.5 \
				+ grid.dirs[i] * w * 0.5 - grid.fronts[i] * d * 0.5
			var r0 := g - c0
			if absf(r0.dot(grid.dirs[i])) > w * 0.5 or absf(r0.dot(grid.fronts[i])) > d * 0.5:
				continue
		var fp: Dictionary = _buildings.footprint(_item, i, false)
		var rel := g - (fp["centre"] as Vector2)
		var inside := absf(rel.dot(grid.dirs[i])) <= w * 0.5 and absf(rel.dot(grid.fronts[i])) <= d * 0.5
		if not inside:
			# Only a fallback (finger on the road or beside the lots).
			if fp["ok"] and grid.depth[i] == 0:
				near.append(i)
			continue
		if fp["ok"]:
			# The road test is the slow part: only for lots under the finger.
			fp = _buildings.footprint(_item, i)
		var dist := rel.length()
		if fp["ok"] and dist < best_in_d:
			best_in_d = dist
			best_in = i
		elif not fp["ok"] and dist < bad_in_d:
			bad_in_d = dist
			bad_in = i
	# Nothing fits under the finger: only a lot right next to it (the finger
	# on the kerb or a step into the plot) may take its place. Anything
	# farther would put the building somewhere the player did not point.
	if best_in < 0:
		var tolerance := grid.cell_size * 0.75
		for i: int in near:
			var c0 := grid.centers[i] - grid.dirs[i] * grid.cell_size * 0.5 + grid.fronts[i] * grid.cell_size * 0.5 \
				+ grid.dirs[i] * w * 0.5 - grid.fronts[i] * d * 0.5
			var r0 := g - c0
			var gap := Vector2(maxf(absf(r0.dot(grid.dirs[i])) - w * 0.5, 0.0), maxf(absf(r0.dot(grid.fronts[i])) - d * 0.5, 0.0)).length()
			if gap > tolerance or gap >= best_near_d:
				continue
			if _buildings.footprint(_item, i)["ok"]:
				best_near_d = gap
				best_near = i
	if best_in >= 0:
		return best_in
	if best_near >= 0:
		return best_near
	return bad_in


func _preview_at(screen_pos: Vector2) -> void:
	var g: Variant = _ground(screen_pos)
	_cell = -1
	_valid = false
	if g == null:
		_preview.visible = false
		return
	var grid: ZoneGrid = _zones.grid
	_cell = _best_cell(g)
	if _cell < 0:
		# No squares here at all (far from roads): show the lot red right
		# under the finger instead of jumping somewhere else.
		_draw_squares(_phantom(g), false)
		EventBus.road_preview_changed.emit({"active": true, "valid": false, "error": "BUILD_ERR_ROAD", "screen_pos": screen_pos,
			"hint": tr(_item["name_key"]) + " · " + tr("BUILD_SQUARES") % [int(_item["lot"][0]), int(_item["lot"][1])]})
		return
	var fp: Dictionary = _buildings.footprint(_item, _cell)
	var w := int(fp["w"]) * grid.cell_size
	var d := int(fp["d"]) * grid.cell_size
	var f: Vector2 = fp["front"]
	var centre: Vector2 = fp["centre"]
	var cost := int(_item["cost"])
	var water_ok := _water_ok(centre, w, d)
	var coast_ok := _coast_ok(centre, w, d)
	var runway_ok := _runway_ok(centre, f, d)
	# Farms, camps, mines and wells need their resource under the lot.
	var richness := 1.0
	if _item.has("extractor"):
		var field := str(GameData.value("resources/types/%s/field" % _item["extractor"]))
		richness = ResourceMap.shared().lot_richness(field, centre, w, d)
	var rich_ok := richness >= GameData.num("resources/min_richness")
	var valid: bool = fp["ok"] and EconomySystem.can_afford(cost) and water_ok and rich_ok and coast_ok and runway_ok
	_valid = valid
	_draw_squares(fp, valid)
	var error := ""
	if not fp["ok"]:
		error = str(fp["error"])
	elif not water_ok:
		error = "BUILD_ERR_WATER"
	elif not coast_ok:
		error = "BUILD_ERR_COAST"
	elif not runway_ok:
		error = "BUILD_ERR_RUNWAY"
	elif not rich_ok:
		error = "BUILD_ERR_RESOURCE"
	elif not EconomySystem.can_afford(cost):
		error = "ROAD_ERR_MONEY"
	var hint: String = tr(_item["name_key"]) + " · " + tr("BUILD_SQUARES") % [int(_item["lot"][0]), int(_item["lot"][1])]
	if _item.has("extractor"):
		hint += " · " + tr("BUILD_RICHNESS") % roundi(richness * 100.0)
	EventBus.road_preview_changed.emit({"active": true, "valid": valid, "error": error, "cost": cost,
		"length": 0.0, "screen_pos": screen_pos, "hint": hint})


## A footprint-shaped outline centred on g, lined up with the nearest road
## squares (or the map), for spots where nothing can be built.
func _phantom(g: Vector2) -> Dictionary:
	var grid: ZoneGrid = _zones.grid
	var cs := grid.cell_size
	var f := Vector2.UP
	var dir := Vector2.RIGHT
	var near := grid.cells_near(g, 80.0)
	var best := INF
	for i in near:
		var dd := grid.centers[i].distance_squared_to(g)
		if dd < best:
			best = dd
			f = grid.fronts[i]
			dir = grid.dirs[i]
	var w := int(_item["lot"][0])
	var d := int(_item["lot"][1])
	var corner := g - dir * w * cs * 0.5 + f * d * cs * 0.5
	var squares := PackedVector2Array()
	for b in d:
		for a in w:
			squares.append(corner + dir * (a + 0.5) * cs - f * (b + 0.5) * cs)
	return {"ok": false, "squares": squares, "centre": g, "front": f, "dir": dir, "w": w, "d": d}


## The footprint drawn square by square (w x d tiles with a thin gap) and a
## faint box around the whole lot, so the exact size reads at a glance.
func _draw_squares(fp: Dictionary, valid: bool) -> void:
	var grid: ZoneGrid = _zones.grid
	var cs := grid.cell_size
	var f: Vector2 = fp["front"]
	var dir: Vector2 = fp["dir"]
	var tile := cs * 0.44
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector2 in fp["squares"]:
		var a := p + dir * tile + f * tile
		var b := p - dir * tile + f * tile
		var c := p - dir * tile - f * tile
		var e := p + dir * tile - f * tile
		for v: Vector2 in [a, b, c, a, c, e]:
			im.surface_add_vertex(Vector3(v.x, 0.35, v.y))
	# Walls of the lot: a low translucent box edge on the outline.
	var w := int(fp["w"]) * cs * 0.5
	var d := int(fp["d"]) * cs * 0.5
	var centre: Vector2 = fp["centre"]
	var corners := [centre + dir * w + f * d, centre - dir * w + f * d, centre - dir * w - f * d, centre + dir * w - f * d]
	for k in 4:
		var p0: Vector2 = corners[k]
		var p1: Vector2 = corners[(k + 1) % 4]
		for v: Vector3 in [Vector3(p0.x, 0.0, p0.y), Vector3(p1.x, 0.0, p1.y), Vector3(p1.x, 3.0, p1.y),
				Vector3(p0.x, 0.0, p0.y), Vector3(p1.x, 3.0, p1.y), Vector3(p0.x, 3.0, p0.y)]:
			im.surface_add_vertex(v)
	im.surface_end()
	_preview.mesh = im
	_preview.transform = Transform3D.IDENTITY
	_preview.material_override = _ok_mat if valid else _bad_mat
	_preview.visible = true


func _build() -> void:
	if _cell < 0 or not _valid:
		if _cell >= 0:
			EventBus.sfx_requested.emit("error")
		EventBus.road_preview_changed.emit({"active": false})
		return
	var cost := int(_item["cost"])
	if not _buildings.lot_for(_item, _cell).is_empty() and EconomySystem.try_spend(cost):
		var bid: int = _buildings.place(_item, _cell)
		EventBus.sfx_requested.emit("build_place")
		var rt: Node = get_parent().get_node_or_null("RoadTool")
		if rt != null and bid >= 0:
			rt.remember({"kind": "placed", "id": bid, "cost": cost})
	EventBus.road_preview_changed.emit({"active": false})


func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return null if hit == null else Vector2((hit as Vector3).x, (hit as Vector3).z)

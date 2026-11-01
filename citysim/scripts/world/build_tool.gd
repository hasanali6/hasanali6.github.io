extends Node3D
## Hand placement of buildings and parks from data/catalog.json. While a
## catalogue item is selected, dragging a finger previews the lot on the
## nearest road-facing cell (green = fits and affordable, red = not) and
## releasing builds it. Placed buildings join the economy like grown ones.
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
	return mat


func _on_tool_selected(tool: String, options: Dictionary) -> void:
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
			_preview_at(screen_pos)
		GestureTracker.Pointer.UP:
			_preview_at(screen_pos)
			_build()
			_preview.visible = false


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


func _preview_at(screen_pos: Vector2) -> void:
	var g: Variant = _ground(screen_pos)
	_cell = -1
	_valid = false
	if g == null:
		_preview.visible = false
		return
	var grid: ZoneGrid = _zones.grid
	_cell = grid.front_cell_near(g, _snap_radius)
	if _cell < 0:
		_preview.visible = false
		EventBus.road_preview_changed.emit({"active": true, "valid": false, "error": "BUILD_ERR_ROAD", "screen_pos": screen_pos})
		return
	var lot: PackedInt32Array = _buildings.lot_for(_item, _cell)
	var w := int(_item["lot"][0]) * grid.cell_size
	var d := int(_item["lot"][1]) * grid.cell_size
	var f := grid.fronts[_cell]
	var dir := grid.dirs[_cell]
	var corner := grid.centers[_cell] - dir * grid.cell_size * 0.5 + f * grid.cell_size * 0.5
	var centre := corner + dir * w * 0.5 - f * d * 0.5
	var fz := Vector3(f.x, 0, f.y)
	var dx := Vector3.UP.cross(fz)
	_preview.transform = Transform3D(Basis(dx * w, Vector3.UP * 3.0, fz * d), Vector3(centre.x, 1.5, centre.y))
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
	var valid: bool = not lot.is_empty() and EconomySystem.can_afford(cost) and water_ok and rich_ok and coast_ok and runway_ok
	_valid = valid
	_preview.material_override = _ok_mat if valid else _bad_mat
	_preview.visible = true
	var error := ""
	if lot.is_empty():
		error = "BUILD_ERR_SPACE"
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
	var hint: String = tr(_item["name_key"])
	if _item.has("extractor"):
		hint += " · " + tr("BUILD_RICHNESS") % roundi(richness * 100.0)
	EventBus.road_preview_changed.emit({"active": true, "valid": valid, "error": error, "cost": cost,
		"length": 0.0, "screen_pos": screen_pos, "hint": hint})


func _build() -> void:
	if _cell < 0 or not _valid:
		if _cell >= 0:
			EventBus.sfx_requested.emit("error")
		EventBus.road_preview_changed.emit({"active": false})
		return
	var cost := int(_item["cost"])
	if not _buildings.lot_for(_item, _cell).is_empty() and EconomySystem.try_spend(cost):
		_buildings.place(_item, _cell)
		EventBus.sfx_requested.emit("build_place")
	EventBus.road_preview_changed.emit({"active": false})


func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return null if hit == null else Vector2((hit as Vector3).x, (hit as Vector3).z)

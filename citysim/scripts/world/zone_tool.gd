extends Node3D
## Zoning tool. While open, single-finger strokes paint zoning cells:
##   brush : paints cells under a circular brush while dragging
##   fill  : one touch zones the whole block side (road segment side)
##   erase : clears zoning; buildings on erased cells are demolished
## Zoning is free; only free cells change zone.

@export var zone_system_path: NodePath
@export var building_system_path: NodePath

var _zones: Node
var _buildings: Node
var _active: bool = false
var _zone_key: String = ""
var _mode: String = "brush"
var _radius: float
var _marker: MeshInstance3D
var _painted: bool = false   # this stroke zoned something (for the no-demand hint)


func _ready() -> void:
	_zones = get_node(zone_system_path)
	_buildings = get_node(building_system_path)
	_radius = GameData.num("zones/tool/brush_radius_m")
	_zone_key = str((GameData.value("zones/order") as Array)[0])
	_marker = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = _radius
	ring.bottom_radius = _radius
	ring.height = 0.05
	ring.radial_segments = 32
	ring.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.25)
	ring.material = mat
	_marker.mesh = ring
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)
	EventBus.build_tool_selected.connect(_on_tool_selected)
	EventBus.tool_pointer.connect(_on_pointer)


func _on_tool_selected(tool: String, options: Dictionary) -> void:
	_active = tool == "zone"
	if _active:
		_zone_key = str(options.get("zone", _zone_key))
		_mode = str(options.get("mode", _mode))
	_marker.visible = false


func _on_pointer(phase: int, screen_pos: Vector2) -> void:
	if not _active:
		return
	if phase == GestureTracker.Pointer.UP or phase == GestureTracker.Pointer.CANCEL:
		_marker.visible = false
		if _painted:
			_painted = false
			_warn_no_demand()
		return
	var g: Variant = _ground(screen_pos)
	if g == null:
		return
	var p: Vector2 = g
	var grid: ZoneGrid = _zones.grid
	var cells: PackedInt32Array
	if _mode == "fill":
		if phase != GestureTracker.Pointer.DOWN:
			return
		var c := grid.cell_at(p)
		if c < 0:
			return
		cells = grid.row_cells(c)
	else:
		_marker.visible = true
		_marker.position = Vector3(p.x, 0.12, p.y)
		cells = grid.cells_near(p, _radius)
	if _mode == "erase":
		var doomed := {}
		for c in cells:
			if grid.building[c] != ZoneGrid.FREE:
				doomed[grid.building[c]] = true
		for id: int in doomed:
			_buildings.demolish(id)
		if not doomed.is_empty():
			EventBus.sfx_requested.emit("bulldoze")
		if _zones.set_zone(cells, ZoneGrid.UNZONED) > 0:
			EventBus.sfx_requested.emit("zone_paint")
	elif _zones.set_zone(cells, _zones.zone_id(_zone_key)) > 0:
		EventBus.sfx_requested.emit("zone_paint")
		_painted = true
	if _mode == "fill" and _painted:
		_painted = false
		_warn_no_demand()


## After painting a zone nobody wants yet, say why nothing will grow there
## and what brings the demand (the matching K/T/O/S bar is empty).
func _warn_no_demand() -> void:
	var group := str(_zones.zone_types[_zone_key]["group"])
	if _buildings.group_demand(_zone_key) > 0.02:
		return
	var population: int = get_node("../CitizenSystem").population
	var cfg := GameData.section("economy/demand")
	var text := ""
	match group:
		"residential", "mixed":
			text = tr("ZONE_NO_DEMAND_RES")
		"commercial":
			var need := int(cfg["min_commercial_customers"])
			text = tr("ZONE_NO_DEMAND_COM_POP") % need if population < need else tr("ZONE_NO_DEMAND_COM")
		"industrial":
			var need_i := int(cfg["min_industry_population"])
			text = tr("ZONE_NO_DEMAND_IND_POP") % need_i if population < need_i else tr("ZONE_NO_DEMAND_IND")
		"office":
			var need_o := int(cfg["min_office_population"])
			text = tr("ZONE_NO_DEMAND_OFF_POP") % need_o if population < need_o else tr("ZONE_NO_DEMAND_OFF")
	if text != "":
		EventBus.notification_posted.emit("zones", text)


func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return null if hit == null else Vector2((hit as Vector3).x, (hit as Vector3).z)

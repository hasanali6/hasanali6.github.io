extends Node3D
## Hand placement of buildings and parks from data/catalog.json. While a
## catalogue item is selected, dragging a finger previews the lot on the
## nearest road-facing cell (green = fits and affordable, red = not) and
## releasing builds it. Placed buildings join the economy like grown ones.

@export var building_system_path: NodePath
@export var zone_system_path: NodePath

var _buildings: Node
var _zones: Node
var _active: bool = false
var _item: Dictionary = {}
var _cell: int = -1
var _snap_radius: float
var _preview: MeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D


func _ready() -> void:
	_buildings = get_node(building_system_path)
	_zones = get_node(zone_system_path)
	_snap_radius = GameData.num("catalog/snap_radius_m")
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


func _preview_at(screen_pos: Vector2) -> void:
	var g: Variant = _ground(screen_pos)
	_cell = -1
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
	var valid: bool = not lot.is_empty() and EconomySystem.can_afford(cost)
	_preview.material_override = _ok_mat if valid else _bad_mat
	_preview.visible = true
	var error := ""
	if lot.is_empty():
		error = "BUILD_ERR_SPACE"
	elif not EconomySystem.can_afford(cost):
		error = "ROAD_ERR_MONEY"
	EventBus.road_preview_changed.emit({"active": true, "valid": valid, "error": error, "cost": cost,
		"length": 0.0, "screen_pos": screen_pos, "hint": _item["name_key"]})


func _build() -> void:
	if _cell < 0:
		EventBus.road_preview_changed.emit({"active": false})
		return
	var cost := int(_item["cost"])
	if not _buildings.lot_for(_item, _cell).is_empty() and EconomySystem.try_spend(cost):
		_buildings.place(_item, _cell)
	EventBus.road_preview_changed.emit({"active": false})


func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return null if hit == null else Vector2((hit as Vector3).x, (hit as Vector3).z)

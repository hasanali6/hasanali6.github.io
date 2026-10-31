extends Node3D
## Owns the zoning cells (ZoneGrid). Regenerates them when roads change and
## draws the zone overlay: zoned free cells are always tinted faintly; while
## the zoning tool is open every cell is shown, unzoned ones in white.

const OVERLAY_SHADER := preload("res://assets/materials/zone_overlay.gdshader")

@export var road_network_path: NodePath

var grid: ZoneGrid
var zone_keys: PackedStringArray  # zone id - 1 -> type key
var zone_types: Dictionary

var _net: Node
var _colors: Array[Color] = []
var _overlay: MultiMeshInstance3D
var _overlay_cfg: Dictionary
var _show_all: bool = false
var _playable_half: float


func _ready() -> void:
	_net = get_node(road_network_path)
	grid = ZoneGrid.new(GameData.section("zones/cells"))
	zone_keys = PackedStringArray(GameData.value("zones/order"))
	zone_types = GameData.section("zones/types")
	_overlay_cfg = GameData.section("zones/overlay")
	_playable_half = GameData.num("map/playable_size_m") * 0.5
	_colors.append(DataLoader.to_color(_overlay_cfg["empty_color"]))
	for key in zone_keys:
		_colors.append(DataLoader.to_color(zone_types[key]["color"]))

	var mat := ShaderMaterial.new()
	mat.shader = OVERLAY_SHADER
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	_overlay = MultiMeshInstance3D.new()
	_overlay.name = "ZoneOverlay"
	_overlay.multimesh = mm
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_overlay)

	EventBus.roads_changed.connect(_on_roads_changed)
	EventBus.zones_changed.connect(_refresh_overlay)
	EventBus.buildings_changed.connect(_refresh_overlay)
	EventBus.build_tool_selected.connect(func(tool: String, _o: Dictionary) -> void:
		_show_all = tool == "zone"
		_refresh_overlay())


func zone_id(key: String) -> int:
	return zone_keys.find(key) + 1


func zone_key(id: int) -> String:
	return zone_keys[id - 1] if id > 0 else ""


func zone_config(id: int) -> Dictionary:
	return zone_types[zone_key(id)]


## Applies a zone (0 clears) to free cells; returns how many changed.
func set_zone(cells: PackedInt32Array, id: int) -> int:
	var changed := 0
	for c in cells:
		if grid.building[c] == ZoneGrid.FREE and grid.zone[c] != id:
			grid.zone[c] = id
			changed += 1
	if changed > 0:
		EventBus.zones_changed.emit()
	return changed


func _on_roads_changed() -> void:
	grid.rebuild(_net.graph, _net.types, _net.mesh_cfg, _playable_half)
	EventBus.zone_cells_rebuilt.emit()
	_refresh_overlay()


func _refresh_overlay() -> void:
	var size := grid.cell_size * float(_overlay_cfg["inset"])
	var h := float(_overlay_cfg["height_m"])
	var alpha_zone := float(_overlay_cfg["alpha_tool"] if _show_all else _overlay_cfg["alpha_idle"])
	var alpha_empty := float(_overlay_cfg["empty_alpha"])
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in grid.size():
		if grid.building[i] != ZoneGrid.FREE:
			continue
		var z := grid.zone[i]
		if z == ZoneGrid.UNZONED and not _show_all:
			continue
		var d := grid.dirs[i]
		var f := grid.fronts[i]
		var basis := Basis(Vector3(d.x, 0, d.y) * size, Vector3.UP, Vector3(f.x, 0, f.y) * size)
		var c := grid.centers[i]
		transforms.append(Transform3D(basis, Vector3(c.x, h, c.y)))
		colors.append(Color(_colors[z], alpha_zone if z != ZoneGrid.UNZONED else alpha_empty))
	var mm := _overlay.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

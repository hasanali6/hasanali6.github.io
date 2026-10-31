extends Node3D
## Grows buildings on zoned cells, keeps their economic capacity and draws them.
##
## Growth runs on simulation ticks: every few ticks some zoned, free,
## road-touching cells are tried as the front of a lot (width x depth cells
## from data/zones.json). The chance follows the RCI demand of the zone's
## group, so nothing grows without demand. Each building gets capacity from
## its zone, floors and lot size: households for homes, job slots by
## education for companies (EconomyRules).
##
## Monthly: buildings level up when they deserve it (full and happy homes,
## companies profitable for a while); homes left empty while demand is
## negative and companies that went bankrupt are abandoned (darkened) and
## collapse after a few months, freeing the lot for something new.
## Players can also place buildings and parks by hand (BuildTool).
##
## Rendering: one MultiMesh per mesh kind (Kenney models, procedural house
## bodies and roofs, facade boxes per style, factory parts, rooftop boxes).
## Any structural change rebuilds the instance lists; new buildings animate
## upwards by updating only their own instances each frame.

const FACADE_SHADER := preload("res://assets/materials/building_placeholder.gdshader")
const KENNEY_DIR := "res://assets/models/kenney/"
const KENNEY_MODELS := {
	"kenney_a": "building-small-a", "kenney_b": "building-small-b", "kenney_c": "building-small-c",
	"kenney_d": "building-small-d", "kenney_garage": "building-garage",
	"park_fountain": "pavement-fountain", "park_trees": "grass-trees", "park_trees_tall": "grass-trees-tall",
}
const ABANDONED_TINT := Color(0.4, 0.38, 0.36)

@export var zone_system_path: NodePath

var buildings: Dictionary = {}  # id -> Dictionary record
var demand: Dictionary = {"residential": 0.0, "commercial": 0.0, "office": 0.0, "industrial": 0.0}

var _zones: Node
var _rng := RandomNumberGenerator.new()
var _growth: Dictionary
var _vis: Dictionary
var _hh_cfg: Dictionary
var _co_cfg: Dictionary
var _rules: Dictionary
var _next_id: int = 1
var _tick: int = 0
var _meshes: Dictionary = {}      # mesh key -> MultiMeshInstance3D
var _instances: Dictionary = {}   # building id -> Array of [mesh key, instance index]
var _rising: Dictionary = {}      # building id -> progress 0..1
var _rise_seconds: float
var _wall_palette: Array[Color] = []
var _roof_palette: Array[Color] = []
var _office_palette: Array[Color] = []
var _industry_palette: Array[Color] = []


func _ready() -> void:
	_zones = get_node(zone_system_path)
	_growth = GameData.section("zones/growth")
	_vis = GameData.section("zones/visuals")
	_hh_cfg = GameData.section("economy/households")
	_co_cfg = GameData.section("economy/companies")
	_rules = GameData.section("economy/buildings")
	_rise_seconds = float(_growth["rise_seconds"])
	_rng.randomize()
	for c: String in _vis["wall_palette"]:
		_wall_palette.append(Color.html(c))
	for c: String in _vis["roof_palette"]:
		_roof_palette.append(Color.html(c))
	for c: String in _vis["office_wall_palette"]:
		_office_palette.append(Color.html(c))
	for c: String in _vis["industry_wall_palette"]:
		_industry_palette.append(Color.html(c))
	_build_meshes()
	EventBus.sim_tick.connect(_on_tick)
	EventBus.month_changed.connect(_on_month)
	EventBus.zone_cells_rebuilt.connect(_on_cells_rebuilt)
	EventBus.ground_long_pressed.connect(_on_long_press)
	EventBus.demand_changed.connect(func(d: Dictionary) -> void: demand = d)
	EventBus.company_bankrupt.connect(_abandon)


func _process(delta: float) -> void:
	if _rising.is_empty():
		return
	for id: int in _rising.keys():
		var p: float = minf(_rising[id] + delta / _rise_seconds, 1.0)
		if p >= 1.0 or not buildings.has(id):
			_rising.erase(id)
			p = 1.0
		else:
			_rising[id] = p
		if buildings.has(id):
			_update_instances(id, p)


# --- Growth ------------------------------------------------------------------------

func _group_demand(zone_key: String) -> float:
	var group := str(_zones.zone_types[zone_key]["group"])
	if group == "mixed":
		return (float(demand["residential"]) + float(demand["commercial"])) * 0.5
	return float(demand.get(group, 0.0))


func _on_tick(_t: int) -> void:
	_tick += 1
	if _tick % int(_growth["interval_ticks"]) != 0:
		return
	var grid: ZoneGrid = _zones.grid
	var candidates := PackedInt32Array()
	for i in grid.size():
		if grid.depth[i] == 0 and grid.zone[i] != ZoneGrid.UNZONED and grid.building[i] == ZoneGrid.FREE:
			candidates.append(i)
	if candidates.is_empty():
		return
	var grew := false
	for attempt in int(_growth["attempts_per_interval"]):
		var cell := candidates[_rng.randi_range(0, candidates.size() - 1)]
		if grid.building[cell] != ZoneGrid.FREE:
			continue
		var chance := float(_growth["base_chance"]) * clampf(_group_demand(_zones.zone_key(grid.zone[cell])), 0.0, 1.0)
		if _rng.randf() >= chance:
			continue
		if _try_grow(cell):
			grew = true
	if grew:
		_render_all()
		EventBus.buildings_changed.emit()


func _try_grow(cell: int) -> bool:
	var grid: ZoneGrid = _zones.grid
	var zid := grid.zone[cell]
	var cfg: Dictionary = _zones.zone_config(zid)
	var widths: Array = cfg["lot_widths"]
	var depths: Array = cfg["lot_depths"]
	var w := _rng.randi_range(int(widths[0]), int(widths[1]))
	var d := _rng.randi_range(int(depths[0]), int(depths[1]))
	var lot := grid.find_lot(cell, w, d, zid)
	if lot.is_empty():
		w = int(widths[0])
		d = int(depths[0])
		lot = grid.find_lot(cell, w, d, zid)
	if lot.is_empty():
		return false
	var styles: Array = cfg["styles"]
	_create(zid, lot, cell, w, d, str(styles[_rng.randi_range(0, styles.size() - 1)]), _floors_for(cfg, 1), false)
	return true


func _create(zid: int, lot: PackedInt32Array, front_cell: int, w: int, d: int, style: String, floors: int, manual: bool) -> int:
	var grid: ZoneGrid = _zones.grid
	var id := _next_id
	_next_id += 1
	var centre := Vector2.ZERO
	for c in lot:
		centre += grid.centers[c]
		grid.building[c] = id
	centre /= lot.size()
	var b := {
		"id": id, "zone": zid, "zone_key": _zones.zone_key(zid), "level": 1, "cells": lot,
		"centre": centre, "front": grid.fronts[front_cell], "dir": grid.dirs[front_cell],
		"width": w * grid.cell_size, "depth": d * grid.cell_size, "lot": Vector2i(w, d),
		"style": style, "floors": floors, "manual": manual,
		"seed": _rng.randf() * 100.0, "palette": _rng.randi(),
		"occupants": 0, "employees": 0, "abandoned": false, "empty_months": 0, "abandoned_months": 0,
		"happiness": 0.0, "profit": 0.0, "profit_months": 0,
	}
	_apply_capacity(b)
	buildings[id] = b
	_rising[id] = 0.0
	return id


func _apply_capacity(b: Dictionary) -> void:
	var key: String = b["zone_key"]
	var group := "" if key == "" else str(_zones.zone_types[key]["group"])
	var cells := (b["cells"] as PackedInt32Array).size()
	b["households_cap"] = EconomyRules.households_capacity(key, b["floors"], cells, _hh_cfg) if group in ["residential", "mixed"] else 0
	b["job_slots"] = EconomyRules.job_slots(key, group, b["floors"], cells, _co_cfg) if group in ["commercial", "office", "industrial", "mixed"] else PackedInt32Array([0, 0, 0])
	b["company_kind"] = EconomyRules.company_kind(key, group)


func _floors_for(cfg: Dictionary, level: int) -> int:
	var r: Array = (cfg["floors_by_level"] as Array)[level - 1]
	return _rng.randi_range(int(r[0]), int(r[1]))


# --- Monthly life of buildings ---------------------------------------------------------

func _on_month(_m: int) -> void:
	var changed := false
	var max_level := int(_growth["max_level"])
	var grid: ZoneGrid = _zones.grid
	for id: int in buildings.keys():
		var b: Dictionary = buildings[id]
		if b["zone_key"] == "":
			continue
		if b["abandoned"]:
			b["abandoned_months"] += 1
			if b["abandoned_months"] >= int(_rules["collapse_months"]):
				for c: int in b["cells"]:
					grid.building[c] = ZoneGrid.FREE
				buildings.erase(id)
				changed = true
			continue
		if int(b["households_cap"]) > 0 and int(b["occupants"]) == 0 and float(demand["residential"]) < 0.0:
			b["empty_months"] += 1
			if b["empty_months"] >= int(_rules["abandon_empty_months"]):
				b["abandoned"] = true
				b["abandoned_months"] = 0
				changed = true
				continue
		else:
			b["empty_months"] = 0
		if b["level"] < max_level and _rng.randf() < float(_growth["level_up_chance_per_month"]) and _deserves_level(b):
			b["level"] += 1
			b["floors"] = maxi(b["floors"], _floors_for(_zones.zone_config(b["zone"]), b["level"]))
			# A fixed-size Kenney model is replaced once the building outgrows it.
			if not b["manual"] and KENNEY_MODELS.has(b["style"]) and b["floors"] > int(_vis["kenney_max_floors"]):
				b["style"] = str(_vis["kenney_upgrade_style"])
			_apply_capacity(b)
			changed = true
	if changed:
		_render_all()
		EventBus.buildings_changed.emit()


func _deserves_level(b: Dictionary) -> bool:
	if int(b["households_cap"]) > 0:
		return int(b["occupants"]) >= int(b["households_cap"]) and float(b["happiness"]) >= float(_rules["level_up_happiness"])
	return int(b["profit_months"]) >= int(_rules["level_up_profit_months"])


func _abandon(id: int) -> void:
	if not buildings.has(id) or buildings[id]["abandoned"]:
		return
	buildings[id]["abandoned"] = true
	buildings[id]["abandoned_months"] = 0
	_render_all()
	EventBus.buildings_changed.emit()


## After roads change the cells are regenerated; a building keeps standing
## only if all of its lot cells still exist.
func _on_cells_rebuilt() -> void:
	var grid: ZoneGrid = _zones.grid
	var owned := {}
	for i in grid.size():
		var id := grid.building[i]
		if id != ZoneGrid.FREE:
			if not owned.has(id):
				owned[id] = PackedInt32Array()
			(owned[id] as PackedInt32Array).append(i)
	var changed := false
	for id: int in buildings.keys():
		var b: Dictionary = buildings[id]
		var cells: PackedInt32Array = owned.get(id, PackedInt32Array())
		if cells.size() != (b["cells"] as PackedInt32Array).size():
			for c in cells:
				grid.building[c] = ZoneGrid.FREE
			buildings.erase(id)
			_rising.erase(id)
			changed = true
		else:
			b["cells"] = cells
	# Cells inherited from a building that no longer exists are freed.
	for i in grid.size():
		if grid.building[i] != ZoneGrid.FREE and not buildings.has(grid.building[i]):
			grid.building[i] = ZoneGrid.FREE
	_render_all()
	if changed:
		EventBus.buildings_changed.emit()


func demolish(id: int) -> void:
	if not buildings.has(id):
		return
	var grid: ZoneGrid = _zones.grid
	for c: int in buildings[id]["cells"]:
		grid.building[c] = ZoneGrid.FREE
	buildings.erase(id)
	_rising.erase(id)
	_render_all()
	EventBus.buildings_changed.emit()


func building_at(p: Vector2) -> int:
	var grid: ZoneGrid = _zones.grid
	var cell := grid.cell_at(p)
	return grid.building[cell] if cell >= 0 else -1


# --- Manual placement ----------------------------------------------------------------------

## Lot for a catalogue item fronting the road at cell, or empty if it does not fit.
func lot_for(item: Dictionary, cell: int) -> PackedInt32Array:
	return (_zones.grid as ZoneGrid).find_free_lot(cell, int(item["lot"][0]), int(item["lot"][1]))


func place(item: Dictionary, cell: int) -> int:
	var lot := lot_for(item, cell)
	if lot.is_empty():
		return -1
	var grid: ZoneGrid = _zones.grid
	var key := str(item.get("zone", ""))
	var zid: int = _zones.zone_id(key) if key != "" else ZoneGrid.UNZONED
	for c in lot:
		grid.zone[c] = zid
	var floors := int(item.get("floors", 1))
	if key != "":
		floors = maxi(floors, _floors_for(_zones.zone_config(zid), 1))
	var id := _create(zid, lot, cell, int(item["lot"][0]), int(item["lot"][1]), str(item["style"]), floors, true)
	_render_all()
	EventBus.zones_changed.emit()
	EventBus.buildings_changed.emit()
	return id


func _on_long_press(world_pos: Vector3) -> void:
	var id := building_at(Vector2(world_pos.x, world_pos.z))
	if id < 0:
		return
	var b: Dictionary = buildings[id]
	var slots: PackedInt32Array = b["job_slots"]
	EventBus.building_inspected.emit({
		"zone_key": _zones.zone_config(b["zone"])["name_key"] if b["zone_key"] != "" else "BUILD_PARK",
		"level": b["level"], "floors": b["floors"], "width": b["width"], "depth": b["depth"],
		"households": b["occupants"], "households_cap": b["households_cap"],
		"employees": b["employees"], "jobs": slots[0] + slots[1] + slots[2],
		"abandoned": b["abandoned"], "profit": b["profit"],
	})


# --- Save / load -------------------------------------------------------------------------------

func save_state() -> Dictionary:
	var grid: ZoneGrid = _zones.grid
	var list := []
	for b: Dictionary in buildings.values():
		var keys := []
		for c: int in b["cells"]:
			keys.append([grid.segment[c], grid.side[c], grid.along[c], grid.depth[c]])
		var front_cell: int = b["cells"][0]
		list.append({
			"id": b["id"], "zone_key": b["zone_key"], "level": b["level"], "style": b["style"], "floors": b["floors"],
			"manual": b["manual"], "seed": b["seed"], "palette": b["palette"], "lot": [b["lot"].x, b["lot"].y],
			"abandoned": b["abandoned"], "empty_months": b["empty_months"], "abandoned_months": b["abandoned_months"],
			"cells": keys, "front": [grid.segment[front_cell], grid.side[front_cell], grid.along[front_cell], grid.depth[front_cell]],
		})
	return {"buildings": list, "next_id": _next_id}


func load_state(state: Dictionary) -> void:
	var grid: ZoneGrid = _zones.grid
	buildings.clear()
	for i in grid.size():
		grid.building[i] = ZoneGrid.FREE
	for rec: Dictionary in state.get("buildings", []):
		var lot := PackedInt32Array()
		var ok := true
		for k: Array in rec["cells"]:
			var idx := grid.index_of(int(k[0]), int(k[1]), int(k[2]), int(k[3]))
			if idx < 0 or grid.building[idx] != ZoneGrid.FREE:
				ok = false
				break
			lot.append(idx)
		if not ok or lot.is_empty():
			continue
		var f: Array = rec["front"]
		var front := grid.index_of(int(f[0]), int(f[1]), int(f[2]), int(f[3]))
		if front < 0:
			front = lot[0]
		var key := str(rec["zone_key"])
		var zid: int = _zones.zone_id(key) if key != "" else ZoneGrid.UNZONED
		_next_id = int(rec["id"])
		var id := _create(zid, lot, front, int(rec["lot"][0]), int(rec["lot"][1]), str(rec["style"]), int(rec["floors"]), bool(rec["manual"]))
		var b: Dictionary = buildings[id]
		for field: String in ["level", "seed", "palette", "abandoned", "empty_months", "abandoned_months"]:
			b[field] = rec[field]
		_apply_capacity(b)
		_rising.erase(id)
	_next_id = maxi(int(state.get("next_id", 1)), _next_id + 1)
	_render_all()
	EventBus.buildings_changed.emit()


# --- Rendering -------------------------------------------------------------------

func _build_meshes() -> void:
	for key: String in KENNEY_MODELS:
		var scene: PackedScene = load(KENNEY_DIR + KENNEY_MODELS[key] + ".glb")
		var root := scene.instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		# Let the instance colour tint the model (white = as authored, grey = abandoned).
		var mesh: Mesh = mi.mesh.duplicate()
		for sidx in mesh.get_surface_count():
			var mat := mesh.surface_get_material(sidx)
			if mat is BaseMaterial3D:
				var tinted := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				tinted.vertex_color_use_as_albedo = true
				mesh.surface_set_material(sidx, tinted)
		_add_multimesh(key, mesh, true, false)
		root.free()

	var unit_box := BoxMesh.new()
	unit_box.material = _facade_material(0.0, 3.0)
	_add_multimesh("apartment", unit_box, true, true)
	var tower_box := BoxMesh.new()
	tower_box.material = _facade_material(float(_vis["ground_floor_height_m"]), float(_vis["floor_height_m"]))
	_add_multimesh("tower", tower_box, true, true)
	var office_box := BoxMesh.new()
	office_box.material = _facade_material(float(_vis["ground_floor_height_m"]), float(_vis["floor_height_m"]))
	_add_multimesh("office", office_box, true, true)
	var house_box := BoxMesh.new()
	house_box.material = _facade_material(0.0, float(_vis["house_floor_height_m"]))
	_add_multimesh("house", house_box, true, true)
	var factory_box := BoxMesh.new()
	factory_box.material = _facade_material(0.0, 5.0)
	_add_multimesh("factory", factory_box, true, true)

	var roof_mat := StandardMaterial3D.new()
	roof_mat.vertex_color_use_as_albedo = true
	roof_mat.roughness = 0.85
	var roof := _gable_mesh()
	roof.surface_set_material(0, roof_mat)
	_add_multimesh("house_roof", roof, true, false)

	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.roughness = 0.8
	var top_box := BoxMesh.new()
	top_box.material = plain
	_add_multimesh("roof_box", top_box, true, false)
	var chimney := CylinderMesh.new()
	chimney.top_radius = 0.42
	chimney.bottom_radius = 0.5
	chimney.height = 1.0
	chimney.radial_segments = 8
	chimney.rings = 1
	chimney.material = plain
	_add_multimesh("chimney", chimney, true, false)


func _facade_material(ground_floor: float, floor_height: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	mat.set_shader_parameter("glass_color", Color.html(_vis["glass_color"]))
	mat.set_shader_parameter("light_color", Color.html(_vis["window_light_color"]))
	mat.set_shader_parameter("light_energy", float(_vis["window_light_energy"]))
	mat.set_shader_parameter("lit_ratio", float(_vis["lit_window_ratio"]))
	mat.set_shader_parameter("floor_height", floor_height)
	mat.set_shader_parameter("ground_floor_height", ground_floor)
	return mat


func _add_multimesh(key: String, mesh: Mesh, colors: bool, custom: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Buildings_" + key
	mmi.multimesh = mm
	add_child(mmi)
	_meshes[key] = mmi


## Gable roof prism on a unit footprint (x, z in -0.5..0.5), ridge along x at
## height 1. Faces are wound outwards for Godot (clockwise front faces).
func _gable_mesh() -> ArrayMesh:
	var a := Vector3(-0.5, 0, -0.5)
	var b := Vector3(0.5, 0, -0.5)
	var c := Vector3(0.5, 0, 0.5)
	var d := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(-0.5, 1, 0)
	var r1 := Vector3(0.5, 1, 0)
	var tris := [[a, b, r1], [a, r1, r0], [c, d, r0], [c, r0, r1], [b, c, r1], [d, a, r0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, 0.3, 0)
	for t: Array in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var n := (p1 - p0).cross(p2 - p0).normalized()
		var outward := ((p0 + p1 + p2) / 3.0 - centre).normalized()
		if n.dot(outward) > 0.0:
			# Counter-clockwise from outside: flip to clockwise.
			var tmp := p1
			p1 = p2
			p2 = tmp
			n = -n
		st.set_normal(-n)
		for p in [p0, p1, p2]:
			st.add_vertex(p)
	return st.commit()


## The pieces a building is drawn with: [{key, xf, color, custom}] at a given
## rise (0 = just started, 1 = complete).
func _parts_for(b: Dictionary, rise: float) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var f: Vector2 = b["front"]
	var dir2: Vector2 = b["dir"]
	var fz := Vector3(f.x, 0, f.y)
	var dx := Vector3.UP.cross(fz)  # right-handed: x = y cross z
	var margin := float(_growth["lot_margin_m"])
	var setback := float(_growth["front_setback_m"])
	var lot_w: float = b["width"]
	var lot_d: float = b["depth"]
	var centre: Vector2 = b["centre"]
	var front_edge := centre + f * (lot_d * 0.5 - setback)
	var style: String = b["style"]
	var floors: int = b["floors"]
	var e := maxf(ease(rise, 0.4), 0.02)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b["palette"])
	var wall := _wall_palette[rng.randi_range(0, _wall_palette.size() - 1)]

	if style.begins_with("park"):
		# Park tiles cover the whole lot.
		var ps := minf(lot_w, lot_d)
		parts.append(_part(style, Basis(dx * ps, Vector3.UP * ps * e, fz * ps), centre, 0.0, Color.WHITE, Color()))
		return parts
	if KENNEY_MODELS.has(style):
		# Kenney models are scaled uniformly; stretching them looks wrong.
		var s := minf(lot_w, lot_d) - float(_vis["kenney_margin_m"]) * 2.0
		var pos := front_edge - f * (s * 0.5)
		parts.append(_part(style, Basis(dx * s, Vector3.UP * s * e, fz * s), pos, 0.0, _tint(b, Color.WHITE), Color()))
		return parts

	match style:
		"house":
			var w := minf(lot_w - margin * 2.0, 12.0)
			var d := minf(lot_d * 0.55, 10.0)
			var h := floors * float(_vis["house_floor_height_m"])
			var pos := front_edge - f * (d * 0.5 + 2.0)
			parts.append(_part("house", Basis(dx * w, Vector3.UP * h * e, fz * d), pos, h * e * 0.5, wall,
				Color(b["seed"], 0.45, 2.2, 0.0)))
			var roof := _roof_palette[rng.randi_range(0, _roof_palette.size() - 1)]
			var rh := minf(w, d) * 0.4
			parts.append(_part("house_roof", Basis(dx * (w + 0.6), Vector3.UP * rh * e, fz * (d + 0.6)), pos, h * e, roof, Color()))
		"apartment", "tower", "office":
			var w := lot_w - margin * 2.0
			var d := lot_d - margin * 2.0
			var h := float(_vis["ground_floor_height_m"]) + (floors - 1) * float(_vis["floor_height_m"])
			var curtain := 0.0
			var ratio := rng.randf_range(0.4, 0.7)
			if style == "office":
				wall = _office_palette[rng.randi_range(0, _office_palette.size() - 1)]
				curtain = 1.0 if rng.randf() < 0.7 else 0.0
			elif style == "tower":
				w *= 0.85
				d *= 0.85
				curtain = 1.0 if rng.randf() < 0.25 else 0.0
			if style == "apartment":
				h = floors * 3.0
			var pos := centre + f * (lot_d * 0.5 - setback - d * 0.5)
			parts.append(_part(style, Basis(dx * w, Vector3.UP * h * e, fz * d), pos, h * e * 0.5, wall,
				Color(b["seed"], ratio, rng.randf_range(2.2, 3.2), curtain)))
			var top := Color(0.78, 0.8, 0.83)
			parts.append(_part("roof_box", Basis(dx * w * 0.35, Vector3.UP * 2.6 * e, fz * d * 0.3),
				pos - f * d * 0.15, h * e + 1.3 * e, top, Color()))
		"factory":
			var w := lot_w - margin * 2.0
			var d := lot_d * 0.7
			var h := 6.0 + floors * 3.0
			wall = _industry_palette[rng.randi_range(0, _industry_palette.size() - 1)]
			var pos := front_edge - f * (d * 0.5)
			parts.append(_part("factory", Basis(dx * w, Vector3.UP * h * e, fz * d), pos, h * e * 0.5, wall,
				Color(b["seed"], 0.3, 6.0, 0.0)))
			var stack := pos - f * (d * 0.3) + Vector2(dx.x, dx.z) * (w * 0.3)
			var ch := h + 8.0
			parts.append(_part("chimney", Basis(Vector3.RIGHT * 1.6, Vector3.UP * ch * e, Vector3.BACK * 1.6), stack, ch * e * 0.5,
				Color(0.72, 0.36, 0.3), Color()))
	if b["abandoned"]:
		for part in parts:
			part["color"] = _tint(b, part["color"])
	return parts


func _tint(b: Dictionary, color: Color) -> Color:
	return color * ABANDONED_TINT if b["abandoned"] else color


func _part(key: String, basis: Basis, pos: Vector2, y: float, color: Color, custom: Color) -> Dictionary:
	return {"key": key, "xf": Transform3D(basis, Vector3(pos.x, y, pos.y)), "color": color, "custom": custom}


func _render_all() -> void:
	var per_key: Dictionary = {}
	_instances.clear()
	for id: int in buildings:
		var entries := []
		for part in _parts_for(buildings[id], _rising.get(id, 1.0)):
			var key: String = part["key"]
			if not per_key.has(key):
				per_key[key] = []
			entries.append([key, (per_key[key] as Array).size()])
			(per_key[key] as Array).append(part)
		_instances[id] = entries
	for key: String in _meshes:
		var mm := (_meshes[key] as MultiMeshInstance3D).multimesh
		var list: Array = per_key.get(key, [])
		mm.instance_count = list.size()
		for i in list.size():
			var part: Dictionary = list[i]
			mm.set_instance_transform(i, part["xf"])
			if mm.use_colors:
				mm.set_instance_color(i, part["color"])
			if mm.use_custom_data:
				mm.set_instance_custom_data(i, part["custom"])


func _update_instances(id: int, rise: float) -> void:
	var parts := _parts_for(buildings[id], rise)
	var entries: Array = _instances.get(id, [])
	for i in mini(parts.size(), entries.size()):
		var mm := (_meshes[entries[i][0]] as MultiMeshInstance3D).multimesh
		if entries[i][1] < mm.instance_count:
			mm.set_instance_transform(entries[i][1], parts[i]["xf"])

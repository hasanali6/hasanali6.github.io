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
## Players can also place buildings, parks and city services by hand
## (BuildTool). Homes and companies left without electricity or water for
## too long are abandoned as well; a fire turns a building into a ruin.
##
## Rendering: one MultiMesh per mesh kind (Kenney models, procedural house
## bodies and roofs, facade boxes per style, factory parts, rooftop boxes,
## service pieces from ServiceModels). While an info overlay is shown the
## buildings are tinted with its colours.
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
const PARKED_COLORS: Array[Color] = [Color(0.8, 0.12, 0.12), Color(0.15, 0.3, 0.65), Color(0.85, 0.85, 0.86), Color(0.12, 0.12, 0.13), Color(0.55, 0.57, 0.6), Color(0.9, 0.7, 0.15), Color(0.2, 0.45, 0.3)]
const LOT_SHADER := preload("res://assets/materials/lot_ground.gdshader")
const CONTACT_SHADER := preload("res://assets/materials/contact_shadow.gdshader")
const ROOF_SHADER := preload("res://assets/materials/roof.gdshader")
const BEACON_SHADER := preload("res://assets/materials/beacon.gdshader")
const LOT_GARDEN := 0
const LOT_PLAZA := 1
const LOT_PARKING := 2
const LOT_YARD := 3

@export var zone_system_path: NodePath
@export var district_system_path: NodePath

var buildings: Dictionary = {}  # id -> Dictionary record
var demand: Dictionary = {"residential": 0.0, "commercial": 0.0, "office": 0.0, "industrial": 0.0}

var _zones: Node
var _rng := RandomNumberGenerator.new()
var _districts: Node
var _part_cache: Dictionary = {}   # building id -> [signature, parts at full height]
var _render_queued: bool = false
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
var _overlay_tint: Dictionary = {}   # building id -> Color while an info overlay is shown
var _utility_abandon_months: int
var _leisure: Dictionary = {}          # style -> catalog leisure item
var last_leisure: Dictionary = {"upkeep": 0.0, "tourism": 0.0}
var _style_counts: Dictionary = {}     # style -> working buildings (rebuilt when dirty)
var _counts_dirty: bool = true
var _service_names: Dictionary = {}  # service id -> name key


func _ready() -> void:
	_zones = get_node(zone_system_path)
	if not district_system_path.is_empty():
		_districts = get_node(district_system_path)
	_growth = GameData.section("zones/growth")
	_vis = GameData.section("zones/visuals")
	_hh_cfg = GameData.section("economy/households")
	_co_cfg = GameData.section("economy/companies")
	_rules = GameData.section("economy/buildings")
	_rise_seconds = float(_growth["rise_seconds"])
	_utility_abandon_months = GameData.integer("services/effects/abandon_without_utility_months")
	for t: Dictionary in GameData.value("services/types"):
		_service_names[str(t["id"])] = str(t["name_key"])
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
		# A full redraw is coming this frame and will place it anyway.
		if buildings.has(id) and not _render_queued:
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
		var chance := float(_growth["base_chance"]) * clampf(_group_demand(_zones.zone_key(grid.zone[cell])), 0.0, 1.0) * Cheats.growth_factor()
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
	var floors := _floors_for(cfg, 1)
	var cap := _floor_cap(grid.centers[cell])
	if cap > 0:
		floors = mini(floors, cap)
	_create(zid, lot, cell, w, d, str(styles[_rng.randi_range(0, styles.size() - 1)]), floors, false)
	return true


## Floor limit of a high-rise ban district at p (0 = none).
func _floor_cap(p: Vector2) -> int:
	return 0 if _districts == null else int(_districts.floor_cap(p))


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
		"happiness": 0.0, "profit": 0.0, "profit_months": 0, "service": "", "no_utility_months": 0,
	}
	_apply_capacity(b)
	buildings[id] = b
	_rising[id] = 0.0
	return id


func _apply_capacity(b: Dictionary) -> void:
	if b.has("extractor"):
		# Farms, lumber camps, mines and oil wells: jobs from data/resources.json.
		b["households_cap"] = 0
		b["job_slots"] = PackedInt32Array(GameData.value("resources/types/%s/jobs" % b["extractor"]))
		b["company_kind"] = "extractor"
		return
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

## How many working (not abandoned) buildings of a style stand, e.g. "port".
func count_style(style: String) -> int:
	if _counts_dirty:
		_style_counts = {}
		for b: Dictionary in buildings.values():
			if not b["abandoned"]:
				_style_counts[b["style"]] = int(_style_counts.get(b["style"], 0)) + 1
		_counts_dirty = false
	return int(_style_counts.get(style, 0))


## Monthly upkeep and visitor income of parks and the sea front (catalog
## "leisure" items, by style). Visitors come by the highway: an unlinked
## city earns a part of it.
func _report_leisure() -> void:
	if _leisure.is_empty():
		for item: Dictionary in GameData.value("catalog/leisure"):
			_leisure[str(item["style"])] = item
	var upkeep := 0.0
	var tourism := 0.0
	for b: Dictionary in buildings.values():
		var item: Dictionary = _leisure.get(b["style"], {})
		if item.is_empty() or b["abandoned"]:
			continue
		upkeep += float(item.get("upkeep", 0.0))
		tourism += float(item.get("tourism", 0.0))
	var net: Node = get_tree().current_scene.get_node_or_null("RoadNetwork") if get_tree().current_scene != null else null
	var transit: Node = get_parent().get_node_or_null("TransitSystem")
	var by_rail: bool = transit != null and transit.has_intercity()
	if net != null and net.has_method("city_connected") and not net.city_connected() and not by_rail and count_style("airport") == 0:
		tourism *= float(GameData.value("economy/tourism_isolated_factor"))
	last_leisure = {"upkeep": upkeep, "tourism": tourism}
	EventBus.leisure_reported.emit(last_leisure.duplicate())


func _on_month(_m: int) -> void:
	_report_leisure()
	var changed := false
	var abandoned_for_utilities := 0
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
		# Homes and companies without electricity or water are given up in time.
		var used := int(b["occupants"]) + int(b["employees"]) > 0
		if used and not (b.get("power", true) and b.get("water", true)):
			b["no_utility_months"] = int(b.get("no_utility_months", 0)) + 1
			if b["no_utility_months"] >= _utility_abandon_months:
				b["abandoned"] = true
				b["abandoned_months"] = 0
				changed = true
				abandoned_for_utilities += 1
				continue
		else:
			b["no_utility_months"] = 0
		if b["level"] < max_level and _rng.randf() < float(_growth["level_up_chance_per_month"]) * Cheats.growth_factor() and _deserves_level(b):
			b["level"] += 1
			var floors := maxi(b["floors"], _floors_for(_zones.zone_config(b["zone"]), b["level"]))
			var cap := _floor_cap(b["centre"])
			if cap > 0:
				floors = mini(floors, maxi(cap, b["floors"]))
			b["floors"] = floors
			# A fixed-size Kenney model is replaced once the building outgrows it.
			if not b["manual"] and KENNEY_MODELS.has(b["style"]) and b["floors"] > int(_vis["kenney_max_floors"]):
				b["style"] = str(_vis["kenney_upgrade_style"])
			_apply_capacity(b)
			changed = true
	if abandoned_for_utilities > 0:
		EventBus.notification_posted.emit("services", tr("NOTIFY_ABANDONED_UTILITIES") % abandoned_for_utilities)
	if Cheats.densify and _densify() > 0:
		changed = true
	if changed:
		_render_all()
		EventBus.buildings_changed.emit()


## A lot of w x d cells for rebuilding b: a run of cells along its street
## that b covers, made only of b, free cells of the same zone and other grown
## buildings of the same zone. Returns {cells, ids} or {}.
func _redevelop_site(b: Dictionary, w: int, d: int) -> Dictionary:
	var grid: ZoneGrid = _zones.grid
	var cells: PackedInt32Array = b["cells"]
	var front := cells[0]
	for c in cells:
		if grid.depth[c] == 0 and (grid.depth[front] != 0 or grid.along[c] < grid.along[front]):
			front = c
	if grid.depth[front] != 0:
		return {}
	var seg := grid.segment[front]
	var side := grid.side[front]
	var zid := grid.zone[front]
	var first := grid.along[front]
	for start in range(first - w + 1, first + 1):
		var lot := PackedInt32Array()
		var ids := {}
		var ok := true
		for k in range(start, start + w):
			for dep in d:
				var j := grid.index_of(seg, side, k, dep)
				if j < 0:
					ok = false
					break
				var owner := grid.building[j]
				if owner == ZoneGrid.FREE:
					if grid.zone[j] != zid:
						ok = false
						break
				elif owner != int(b["id"]):
					var o: Dictionary = buildings.get(owner, {})
					if o.is_empty() or o["manual"] or o["zone"] != b["zone"]:
						ok = false
						break
					ids[owner] = true
				lot.append(j)
			if not ok:
				break
		if not ok:
			continue
		# Every building touched must fit wholly inside the new lot.
		ids[int(b["id"])] = true
		var inside := {}
		for j in lot:
			inside[j] = true
		for id: int in ids:
			for c: int in buildings[id]["cells"]:
				if not inside.has(c):
					ok = false
		if ok:
			return {"cells": lot, "ids": ids.keys()}
	return {}


## Redevelopment: thriving high-level houses and shops in a busy city are
## rebuilt at the next density (house -> apartment block -> tower), the way
## neighbourhoods grow denser. Only where the bigger lot fits and the
## district allows tall buildings. Returns how many were rebuilt.
func _densify() -> int:
	var cfg: Dictionary = _growth["densify"]
	var chain: Dictionary = cfg["chain"]
	var grid: ZoneGrid = _zones.grid
	var done := 0
	for id: int in buildings.keys():
		if done >= int(cfg["max_per_month"]):
			break
		var b: Dictionary = buildings.get(id, {})
		if b.is_empty() or b["manual"] or b["abandoned"] or not chain.has(b["zone_key"]):
			continue
		if int(b["level"]) < int(cfg["min_level"]) or not _deserves_level(b):
			continue
		var need := -1.0 if Cheats.fast_growth else float(cfg["min_demand"])
		if _group_demand(b["zone_key"]) < need or _rng.randf() > float(cfg["chance_per_month"]) * Cheats.growth_factor():
			continue
		if _floor_cap(b["centre"]) > 0:
			continue
		var new_key := str(chain[b["zone_key"]])
		var new_zid: int = _zones.zone_id(new_key)
		var zcfg: Dictionary = _zones.zone_config(new_zid)
		var w := int((zcfg["lot_widths"] as Array)[0])
		var dd := int((zcfg["lot_depths"] as Array)[0])
		var site := _redevelop_site(b, w, dd)
		if site.is_empty():
			continue
		var lot: PackedInt32Array = site["cells"]
		# Neighbours merged into the bigger lot go too (their people move).
		for other: int in site["ids"]:
			for c: int in buildings[other]["cells"]:
				grid.building[c] = ZoneGrid.FREE
			buildings.erase(other)
			_rising.erase(other)
		for c in lot:
			grid.zone[c] = new_zid
		var styles: Array = zcfg["styles"]
		var nid := _create(new_zid, lot, lot[0], w, dd, str(styles[_rng.randi_range(0, styles.size() - 1)]), _floors_for(zcfg, 1), false)
		buildings[nid]["level"] = 1
		done += 1
	if done > 0:
		EventBus.notification_posted.emit("zones", tr("NOTIFY_DENSIFIED") % done)
	return done


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
	# Plain Arrays: appending to a packed array taken out of a Dictionary
	# would only change a copy.
	var owned := {}
	for i in grid.size():
		var id := grid.building[i]
		if id != ZoneGrid.FREE:
			if not owned.has(id):
				owned[id] = []
			(owned[id] as Array).append(i)
	var changed := false
	for id: int in buildings.keys():
		var b: Dictionary = buildings[id]
		var cells := PackedInt32Array(owned.get(id, []))
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


## A fire leaves a ruin that collapses like an abandoned building.
func burn(id: int) -> void:
	if not buildings.has(id) or buildings[id]["abandoned"]:
		return
	buildings[id]["burned"] = true
	_abandon(id)


func demolish(id: int, clear_zone: bool = false) -> void:
	if not buildings.has(id):
		return
	var grid: ZoneGrid = _zones.grid
	for c: int in buildings[id]["cells"]:
		grid.building[c] = ZoneGrid.FREE
		# Bulldozed on purpose: the lot is left empty instead of regrowing.
		if clear_zone:
			grid.zone[c] = ZoneGrid.UNZONED
	buildings.erase(id)
	_rising.erase(id)
	_render_all()
	EventBus.buildings_changed.emit()


## Money back for demolishing a building: part of its price if it was built
## by hand (catalogue or service); grown buildings return nothing.
func refund_of(id: int) -> int:
	if not buildings.has(id):
		return 0
	var b: Dictionary = buildings[id]
	var ratio := GameData.num("economy/building_refund_ratio")
	var service := str(b.get("service", ""))
	if service != "":
		for t: Dictionary in GameData.value("services/types"):
			if t["id"] == service:
				return roundi(float(t["cost"]) * ratio)
	if b["manual"]:
		for item: Dictionary in GameData.value("catalog/items"):
			if item["style"] == b["style"] and str(item["zone"]) == str(b["zone_key"]):
				return roundi(float(item["cost"]) * ratio)
	return 0


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
	buildings[id]["service"] = str(item.get("service", ""))
	if item.has("extractor"):
		_init_extractor(buildings[id], str(item["extractor"]))
	_render_all()
	EventBus.zones_changed.emit()
	EventBus.buildings_changed.emit()
	return id


## Resource richness under the lot and, for ore and oil, the deposit that
## will run out.
func _init_extractor(b: Dictionary, type: String) -> void:
	var t: Dictionary = GameData.value("resources/types/" + type)
	b["extractor"] = type
	b["richness"] = ResourceMap.shared().lot_richness(str(t["field"]), b["centre"], float(b["width"]), float(b["depth"]))
	if not bool(t["renewable"]):
		var deposit := float(b["richness"]) * float(t["deposit_per_cell"]) * (b["cells"] as PackedInt32Array).size()
		b["deposit"] = deposit
		b["deposit_max"] = deposit
	_apply_capacity(b)


func _on_long_press(world_pos: Vector3) -> void:
	var id := building_at(Vector2(world_pos.x, world_pos.z))
	if id < 0:
		return
	var b: Dictionary = buildings[id]
	var slots: PackedInt32Array = b["job_slots"]
	var name_key := "BUILD_PARK"
	if b["zone_key"] != "":
		name_key = _zones.zone_config(b["zone"])["name_key"]
	elif str(b.get("service", "")) != "":
		name_key = str(_service_names.get(b["service"], name_key))
	elif b.has("extractor"):
		for item: Dictionary in GameData.value("catalog/production"):
			if item["style"] == b["style"]:
				name_key = str(item["name_key"])
	EventBus.building_inspected.emit({
		"id": id, "zone_key": name_key, "service": b.get("service", ""),
		"level": b["level"], "floors": b["floors"], "width": b["width"], "depth": b["depth"],
		"households": b["occupants"], "households_cap": b["households_cap"],
		"employees": b["employees"], "jobs": slots[0] + slots[1] + slots[2],
		"abandoned": b["abandoned"], "burned": b.get("burned", false), "profit": b["profit"],
		"power": b.get("power", true), "water": b.get("water", true), "sewage": b.get("sewage", true),
		"polluted_water": b.get("polluted_water", false), "pollution": b.get("pollution", 0.0),
		"coverage": b.get("coverage", {}), "happiness": b.get("happiness", 0.0),
		"residents": b.get("residents", 0), "no_utility_months": b.get("no_utility_months", 0),
		"commute": b.get("commute", -1.0), "extractor": b.get("extractor", ""), "richness": b.get("richness", 0.0),
		"deposit": b.get("deposit", -1.0), "deposit_max": b.get("deposit_max", -1.0),
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
			"service": b.get("service", ""), "no_utility_months": b.get("no_utility_months", 0), "burned": b.get("burned", false),
			"extractor": b.get("extractor", ""), "richness": b.get("richness", 0.0), "deposit": b.get("deposit", -1.0),
			"deposit_max": b.get("deposit_max", -1.0),
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
		for field: String in ["service", "no_utility_months", "burned"]:
			if rec.has(field):
				b[field] = rec[field]
		if str(rec.get("extractor", "")) != "":
			b["extractor"] = str(rec["extractor"])
			b["richness"] = float(rec.get("richness", 0.5))
			if float(rec.get("deposit", -1.0)) >= 0.0:
				b["deposit"] = float(rec["deposit"])
				b["deposit_max"] = float(rec.get("deposit_max", rec["deposit"]))
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
	# Upper parts of stepped towers: no shop floor at their base.
	var tower_upper := BoxMesh.new()
	tower_upper.material = _facade_material(0.0, float(_vis["floor_height_m"]))
	_add_multimesh("tower_upper", tower_upper, true, true)
	var office_upper := BoxMesh.new()
	office_upper.material = _facade_material(0.0, float(_vis["floor_height_m"]))
	_add_multimesh("office_upper", office_upper, true, true)

	var lot_mat := ShaderMaterial.new()
	lot_mat.shader = LOT_SHADER
	lot_mat.set_shader_parameter("noise_tex", _noise_texture())
	var lot := PlaneMesh.new()
	lot.size = Vector2.ONE
	lot.material = lot_mat
	_add_multimesh("lot", lot, false, true)
	(_meshes["lot"] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var contact_mat := ShaderMaterial.new()
	contact_mat.shader = CONTACT_SHADER
	contact_mat.set_shader_parameter("spread", float(_vis["contact_spread_m"]))
	contact_mat.set_shader_parameter("strength", float(_vis["contact_strength"]))
	var contact := PlaneMesh.new()
	contact.size = Vector2.ONE
	contact.material = contact_mat
	_add_multimesh("contact", contact, false, true)
	(_meshes["contact"] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var roof_mat := ShaderMaterial.new()
	roof_mat.shader = ROOF_SHADER
	roof_mat.set_shader_parameter("tiles", true)
	roof_mat.set_shader_parameter("tile_tex", load("res://assets/textures/rooftile_detail.png"))
	roof_mat.set_shader_parameter("tile_normal", load("res://assets/textures/rooftile_normal.png"))
	var roof := _gable_mesh()
	roof.surface_set_material(0, roof_mat)
	_add_multimesh("house_roof", roof, true, false)

	var plain := ShaderMaterial.new()
	plain.shader = ROOF_SHADER
	plain.set_shader_parameter("roughness", 0.8)
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

	var beacon_mat := ShaderMaterial.new()
	beacon_mat.shader = BEACON_SHADER
	var beacon := SphereMesh.new()
	beacon.radius = 0.35
	beacon.height = 0.7
	beacon.radial_segments = 8
	beacon.rings = 4
	beacon.material = beacon_mat
	_add_multimesh("beacon", beacon, false, true)
	(_meshes["beacon"] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	LeisureModels.build_meshes(_add_multimesh)
	for key in ServiceModels.build_meshes(_add_multimesh):
		(_meshes[key] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Plumes and rotors move in their shaders, beyond their mesh bounds.
	(_meshes["smoke"] as MultiMeshInstance3D).extra_cull_margin = 40.0
	(_meshes["rotor"] as MultiMeshInstance3D).extra_cull_margin = 4.0


func _noise_texture() -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.05
	tex.noise = fnl
	return tex


func _facade_material(ground_floor: float, floor_height: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	mat.set_shader_parameter("glass_color", Color.html(_vis["glass_color"]))
	mat.set_shader_parameter("light_color", Color.html(_vis["window_light_color"]))
	mat.set_shader_parameter("light_energy", float(_vis["window_light_energy"]))
	mat.set_shader_parameter("lit_ratio", float(_vis["lit_window_ratio"]))
	mat.set_shader_parameter("floor_height", floor_height)
	mat.set_shader_parameter("ground_floor_height", ground_floor)
	mat.set_shader_parameter("brick_tex", load("res://assets/textures/brick_detail.png"))
	mat.set_shader_parameter("brick_normal", load("res://assets/textures/brick_normal.png"))
	mat.set_shader_parameter("plaster_tex", load("res://assets/textures/plaster_detail.png"))
	mat.set_shader_parameter("plaster_normal", load("res://assets/textures/plaster_normal.png"))
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
## rise (0 = just started, 1 = complete). Every building also gets a lot
## ground quad and a soft contact shadow under its main body.
func _parts_for(b: Dictionary, rise: float) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var ctx := _context(b, rise)
	var style: String = b["style"]
	if LeisureModels.has_style(style):
		LeisureModels.parts(b, ctx, parts)
		parts.append(_part("lot", _basis(ctx, ctx["lot_w"], 1.0, ctx["lot_d"]), ctx["centre"], 0.04, Color.WHITE,
			Color(LeisureModels.lot_kind(style), float(b["seed"]), 0.0, 0.0)))
		if b["abandoned"]:
			for part in parts:
				part["color"] = _tint(b, part["color"])
		return parts
	if style.begins_with("park"):
		# Park tiles cover the whole lot.
		var ps := minf(ctx["lot_w"], ctx["lot_d"])
		parts.append(_part(style, _basis(ctx, ps, ps * ctx["e"], ps), ctx["centre"], 0.0, Color.WHITE, Color()))
		return parts
	if KENNEY_MODELS.has(style):
		_parts_kenney(b, ctx, parts)
	else:
		match style:
			"house":
				_parts_house(b, ctx, parts)
			"apartment":
				_parts_apartment(b, ctx, parts)
			"tower", "office":
				_parts_tower(b, ctx, parts)
			"factory":
				_parts_factory(b, ctx, parts)
			"farm", "lumber", "mine", "oil_well":
				_parts_extractor(b, ctx, parts)
			_:
				if style.begins_with("svc_"):
					ServiceModels.parts(b, ctx, parts)
					_service_sign(b, ctx, parts)
	parts.append(_part("lot", _basis(ctx, ctx["lot_w"], 1.0, ctx["lot_d"]), ctx["centre"], 0.04, Color.WHITE,
		Color(_lot_kind(b), float(b["seed"]), 0.0, 0.0)))
	if b["abandoned"]:
		for part in parts:
			if part["key"] == "smoke":
				part["color"] = Color(0, 0, 0, 0)
			else:
				part["color"] = _tint(b, part["color"])
	return parts


func _context(b: Dictionary, rise: float) -> Dictionary:
	var f: Vector2 = b["front"]
	var fz := Vector3(f.x, 0, f.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b["palette"])
	var lot_d: float = b["depth"]
	return {
		"f": f, "fz": fz, "dx": Vector3.UP.cross(fz),  # right-handed: x = y cross z
		"side": Vector2(Vector3.UP.cross(fz).x, Vector3.UP.cross(fz).z),
		"lot_w": float(b["width"]), "lot_d": lot_d, "centre": b["centre"],
		"front_edge": (b["centre"] as Vector2) + f * (lot_d * 0.5 - float(_growth["front_setback_m"])),
		"margin": float(_growth["lot_margin_m"]), "e": maxf(ease(rise, 0.4), 0.02), "rng": rng,
		"spread": float(_vis["contact_spread_m"]),
		"wall": _wall_palette[rng.randi_range(0, _wall_palette.size() - 1)],
	}


func _basis(ctx: Dictionary, w: float, h: float, d: float) -> Basis:
	return Basis(ctx["dx"] * w, Vector3.UP * h, ctx["fz"] * d)


func _lot_kind(b: Dictionary) -> int:
	if str(b["style"]).begins_with("svc_"):
		return ServiceModels.lot_kind(b["style"])
	match str(b["style"]):
		"house":
			return LOT_GARDEN
		"farm", "lumber":
			return 5
		"mine", "oil_well":
			return 7
		"factory", "kenney_garage":
			return LOT_PARKING
	if str(b["zone_key"]) == "industry":
		return LOT_YARD
	return LOT_PLAZA


func _contact(parts: Array[Dictionary], ctx: Dictionary, pos: Vector2, w: float, d: float) -> void:
	var spread := float(_vis["contact_spread_m"])
	parts.append(_part("contact", _basis(ctx, w + spread * 2.0, 1.0, d + spread * 2.0), pos, 0.07, Color.WHITE, Color(w, d, 0.0, 0.0)))


func _parts_kenney(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	# Kenney models are scaled uniformly; stretching them looks wrong.
	var s: float = minf(ctx["lot_w"], ctx["lot_d"]) - float(_vis["kenney_margin_m"]) * 2.0
	var pos: Vector2 = ctx["front_edge"] - ctx["f"] * (s * 0.5)
	parts.append(_part(b["style"], _basis(ctx, s, s * ctx["e"], s), pos, 0.0, _tint(b, Color.WHITE), Color()))
	_contact(parts, ctx, pos, s * 0.9, s * 0.9)


func _parts_house(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var w := minf(ctx["lot_w"] - ctx["margin"] * 2.0, 12.0)
	var d := minf(ctx["lot_d"] * 0.55, 10.0)
	var e: float = ctx["e"]
	var h := int(b["floors"]) * float(_vis["house_floor_height_m"])
	var pos: Vector2 = ctx["front_edge"] - ctx["f"] * (d * 0.5 + 2.0)
	parts.append(_part("house", _basis(ctx, w, h * e, d), pos, h * e * 0.5, ctx["wall"], Color(b["seed"], 0.45, 2.2, 0.0)))
	var roof := _roof_palette[rng.randi_range(0, _roof_palette.size() - 1)]
	var rh := minf(w, d) * 0.4
	parts.append(_part("house_roof", _basis(ctx, w + 0.6, rh * e, d + 0.6), pos, h * e, roof, Color()))
	var chimney_pos: Vector2 = pos + ctx["side"] * (w * 0.28) - ctx["f"] * (d * 0.18)
	parts.append(_part("roof_box", _basis(ctx, 0.7, (rh + 0.8) * e, 0.7), chimney_pos, h * e + (rh + 0.8) * e * 0.5, Color(0.62, 0.36, 0.3), Color()))
	_contact(parts, ctx, pos, w, d)
	# Most lived-in houses have a car parked in the front yard, along the street.
	if int(b["occupants"]) > 0 and fposmod(float(b["seed"]) * 7.13, 1.0) < 0.8:
		var cu := clampf(w * 0.22, 0.0, 3.0)
		var cv: float = float(ctx["lot_d"]) * 0.5 - float(_growth["front_setback_m"]) - 1.0
		var paint: Color = PARKED_COLORS[int(float(b["seed"]) * 13.0) % PARKED_COLORS.size()]
		ServiceModels._put(parts, ctx, "roof_box", cu, cv, 1.8, 0.9, 4.2, paint, 0.3, Color(), true)
		ServiceModels._put(parts, ctx, "roof_box", cu - 0.25, cv, 1.55, 0.6, 2.1, Color(0.2, 0.24, 0.3), 1.2, Color(), true)


func _parts_apartment(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var w: float = ctx["lot_w"] - ctx["margin"] * 2.0
	var d: float = ctx["lot_d"] - ctx["margin"] * 2.0
	var e: float = ctx["e"]
	var h := int(b["floors"]) * 3.0
	var pos: Vector2 = ctx["centre"] + ctx["f"] * (ctx["lot_d"] * 0.5 - float(_growth["front_setback_m"]) - d * 0.5)
	parts.append(_part("apartment", _basis(ctx, w, h * e, d), pos, h * e * 0.5, ctx["wall"],
		Color(b["seed"], rng.randf_range(0.4, 0.7), rng.randf_range(2.2, 3.2), 0.0)))
	_roof_kit(ctx, parts, pos, w, d, h, true)
	if str(b["zone_key"]) == "mixed":
		_awning(ctx, parts, pos, w, d)
	_contact(parts, ctx, pos, w, d)


## Stepped high-rise: shop podium, setback tower, crown on the tallest.
func _parts_tower(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var office: bool = b["style"] == "office"
	var w: float = ctx["lot_w"] - ctx["margin"] * 2.0
	var d: float = ctx["lot_d"] - ctx["margin"] * 2.0
	var e: float = ctx["e"]
	var floors := int(b["floors"])
	var ground := float(_vis["ground_floor_height_m"])
	var floor_h := float(_vis["floor_height_m"])
	var h := ground + (floors - 1) * floor_h
	var wall: Color = ctx["wall"]
	var curtain := 0.0
	if office:
		wall = _office_palette[rng.randi_range(0, _office_palette.size() - 1)]
		curtain = 1.0 if rng.randf() < 0.7 else 0.0
	else:
		curtain = 1.0 if rng.randf() < 0.25 else 0.0
	var ratio := rng.randf_range(0.4, 0.7)
	var spacing := rng.randf_range(2.2, 3.2)
	var pos: Vector2 = ctx["centre"] + ctx["f"] * (ctx["lot_d"] * 0.5 - float(_growth["front_setback_m"]) - d * 0.5)
	var key := "office" if office else "tower"
	var upper_key := "office_upper" if office else "tower_upper"
	if floors < 6:
		parts.append(_part(key, _basis(ctx, w, h * e, d), pos, h * e * 0.5, wall, Color(b["seed"], ratio, spacing, curtain)))
		_roof_kit(ctx, parts, pos, w, d, h, false)
		_contact(parts, ctx, pos, w, d)
		return
	var podium := ground + floor_h
	parts.append(_part(key, _basis(ctx, w, podium * e, d), pos, podium * e * 0.5, wall.darkened(0.08), Color(b["seed"], 0.7, 3.0, 0.0)))
	var tw := w * 0.72
	var td := d * 0.72
	var tpos: Vector2 = pos - ctx["f"] * (d - td) * 0.3
	var th := h - podium
	parts.append(_part(upper_key, _basis(ctx, tw, th * e, td), tpos, (podium + th * 0.5) * e, wall,
		Color(b["seed"] + 7.0, ratio, spacing, curtain)))
	if floors >= 12:
		var crown := wall.darkened(0.25)
		parts.append(_part("roof_box", _basis(ctx, tw * 0.55, 4.0 * e, td * 0.55), tpos, (h + 2.0) * e, crown, Color()))
		if office:
			parts.append(_part("chimney", _basis(ctx, 0.35, 10.0 * e, 0.35), tpos, (h + 4.0 + 5.0) * e, Color(0.82, 0.82, 0.84), Color()))
			parts.append(_part("beacon", _basis(ctx, 1.0, e, 1.0), tpos, (h + 14.3) * e, Color.WHITE, Color(float(b["seed"]) * 0.137, 0, 0, 0)))
	else:
		_roof_kit(ctx, parts, tpos, tw, td, h, false)
	if floors >= 10:
		# Aircraft warning lights on two opposite corners of the roof.
		var side: Vector2 = ctx["side"]
		var fwd: Vector2 = ctx["f"]
		for k in [-1.0, 1.0]:
			var corner: Vector2 = tpos + side * (tw * 0.5 - 0.5) * k + fwd * (td * 0.5 - 0.5) * k
			parts.append(_part("beacon", _basis(ctx, 1.0, e, 1.0), corner, (h + 0.5) * e, Color.WHITE, Color(float(b["seed"]) * 0.137, 0, 0, 0)))
	if not office and str(b["zone_key"]) in ["com_high", "mixed"]:
		_awning(ctx, parts, pos, w, d)
	_contact(parts, ctx, pos, w, d)


func _parts_factory(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var w: float = ctx["lot_w"] - ctx["margin"] * 2.0
	var d: float = ctx["lot_d"] * 0.62
	var e: float = ctx["e"]
	var h := 6.0 + int(b["floors"]) * 3.0
	var wall := _industry_palette[rng.randi_range(0, _industry_palette.size() - 1)]
	var pos: Vector2 = ctx["centre"] - ctx["f"] * (ctx["lot_d"] * 0.5 - d * 0.5 - ctx["margin"])
	parts.append(_part("factory", _basis(ctx, w, h * e, d), pos, h * e * 0.5, wall, Color(b["seed"], 0.3, 6.0, 0.0)))
	var stack: Vector2 = pos - ctx["f"] * (d * 0.3) + ctx["side"] * (w * 0.3)
	var ch := h + 8.0
	parts.append(_part("chimney", _basis(ctx, 1.6, ch * e, 1.6), stack, ch * e * 0.5, Color(0.72, 0.36, 0.3), Color()))
	var he := maxf(26.0 * e * e * e, 0.01)
	parts.append(_part("smoke", Basis(Vector3.RIGHT * 6.0, Vector3.UP * he, Vector3.BACK), stack, ch * e + he * 0.5,
		Color(0.6, 0.6, 0.62, 0.55), Color(fposmod(float(b["seed"]) * 0.29, 1.0), 0.0, 0.0, 0.0)))
	var annex: Vector2 = pos + ctx["f"] * (d * 0.5 + 2.6) - ctx["side"] * (w * 0.3)
	parts.append(_part("house", _basis(ctx, w * 0.3, 4.0 * e, 5.0), annex, 2.0 * e, wall.lightened(0.1), Color(b["seed"], 0.5, 2.4, 0.0)))
	_contact(parts, ctx, pos, w, d)


## A sign by the street in the service's colour (power yellow, water blue,
## health red...), so public buildings stand apart from homes and shops.
func _service_sign(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	var t: Dictionary = {}
	for entry: Dictionary in GameData.value("services/types"):
		if entry["id"] == str(b.get("service", "")):
			t = entry
	if t.is_empty():
		return
	var color := DataLoader.to_color(GameData.value("services/categories/%s/color" % t["category"]))
	var e: float = ctx["e"]
	var f: Vector2 = ctx["f"]
	var side: Vector2 = ctx["side"]
	var spot: Vector2 = (ctx["centre"] as Vector2) + f * (float(ctx["lot_d"]) * 0.5 - 1.2) + side * (float(ctx["lot_w"]) * 0.5 - 2.0)
	for k in [-1.0, 1.0]:
		parts.append(_part("chimney", _basis(ctx, 0.25, 4.6 * e, 0.25), spot + side * k * 1.8, 2.3 * e, Color(0.3, 0.32, 0.35), Color()))
	parts.append(_part("roof_box", _basis(ctx, 4.2, 2.0 * e, 0.22), spot, 4.6 * e, color, Color()))
	parts.append(_part("roof_box", _basis(ctx, 4.4, 0.18 * e, 0.28), spot, 5.69 * e, Color(0.95, 0.95, 0.95), Color()))


## Farms, lumber camps, mines and oil wells from boxes, cylinders and gables.
func _parts_extractor(b: Dictionary, ctx: Dictionary, parts: Array[Dictionary]) -> void:
	var e: float = ctx["e"]
	var c: Vector2 = ctx["centre"]
	var f: Vector2 = ctx["f"]
	var side: Vector2 = ctx["side"]
	var w: float = ctx["lot_w"]
	var d: float = ctx["lot_d"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var up := Vector3.UP
	match str(b["style"]):
		"farm":
			# Red barn with a grey roof, two silos.
			var barn: Vector2 = c + f * (d * 0.32) - side * (w * 0.25)
			parts.append(_part("roof_box", _basis(ctx, 7.0, 4.0 * e, 10.0), barn, 2.0 * e, Color(0.62, 0.2, 0.16), Color()))
			parts.append(_part("house_roof", _basis(ctx, 7.6, 2.6 * e, 10.6), barn, 4.0 * e, Color(0.42, 0.42, 0.44), Color()))
			for k in 2:
				var silo: Vector2 = barn + side * (6.0 + k * 3.6)
				parts.append(_part("chimney", _basis(ctx, 3.0, 9.0 * e, 3.0), silo, 4.5 * e, Color(0.78, 0.8, 0.82), Color()))
		"lumber":
			# Shed and stacks of logs lying along the lot.
			var shed: Vector2 = c + f * (d * 0.3)
			parts.append(_part("roof_box", _basis(ctx, 9.0, 3.6 * e, 6.0), shed, 1.8 * e, Color(0.48, 0.36, 0.24), Color()))
			parts.append(_part("house_roof", _basis(ctx, 9.6, 1.6 * e, 6.6), shed, 3.6 * e, Color(0.3, 0.34, 0.3), Color()))
			for row in 3:
				for k in 4:
					var p: Vector2 = c - f * (d * 0.12 + row * 2.4) + side * (k - 1.5) * 0.9
					var lie := Basis(ctx["dx"] * 0.8, Vector3(ctx["fz"]) * 6.0 * e, -up * 0.8)
					parts.append(_part("chimney", lie, p, 0.45 + row * 0.0, Color(0.5, 0.34, 0.2).lerp(Color(0.62, 0.45, 0.3), rng.randf()), Color()))
		"mine":
			# Headframe tower, winding house and a spoil heap.
			var head: Vector2 = c + f * (d * 0.2) + side * (w * 0.2)
			for k in 4:
				var leg: Vector2 = head + side * (1.6 if k % 2 == 0 else -1.6) + f * (1.6 if k < 2 else -1.6)
				parts.append(_part("roof_box", _basis(ctx, 0.4, 16.0 * e, 0.4), leg, 8.0 * e, Color(0.36, 0.3, 0.26), Color()))
			parts.append(_part("roof_box", _basis(ctx, 4.0, 1.2 * e, 4.0), head, 16.0 * e, Color(0.36, 0.3, 0.26), Color()))
			parts.append(_part("chimney", Basis(ctx["dx"] * 2.4, up * 0.5, ctx["fz"] * 2.4), head, 17.0 * e, Color(0.2, 0.2, 0.22), Color()))
			var house: Vector2 = head - side * (w * 0.42)
			parts.append(_part("roof_box", _basis(ctx, 6.0, 5.0 * e, 7.0), house, 2.5 * e, Color(0.55, 0.5, 0.45), Color()))
			var heap: Vector2 = c - f * (d * 0.22) - side * (w * 0.05)
			parts.append(_part("house_roof", _basis(ctx, w * 0.6, 7.0 * e, d * 0.4), heap, 0.0, Color(0.35, 0.32, 0.3), Color()))
		"oil_well":
			# Two pump jacks and storage tanks.
			for k in 2:
				var jack: Vector2 = c - f * (d * 0.15) + side * (k - 0.5) * (w * 0.45)
				parts.append(_part("roof_box", _basis(ctx, 1.0, 4.0 * e, 1.0), jack, 2.0 * e, Color(0.24, 0.24, 0.26), Color()))
				parts.append(_part("roof_box", Basis(ctx["dx"] * 0.6, up * 0.6 * e, ctx["fz"] * 7.0).rotated(ctx["dx"].normalized(), 0.25), jack, 4.2 * e, Color(0.86, 0.6, 0.12), Color()))
				parts.append(_part("roof_box", _basis(ctx, 1.4, 1.4 * e, 1.4), jack - f * 3.2, 0.7 * e, Color(0.3, 0.3, 0.32), Color()))
			for k in 2:
				var tank: Vector2 = c + f * (d * 0.3) + side * (k - 0.5) * 7.0
				parts.append(_part("chimney", _basis(ctx, 5.5, 5.0 * e, 5.5), tank, 2.5 * e, Color(0.82, 0.83, 0.84), Color()))
	_contact(parts, ctx, c, w * 0.6, d * 0.6)


## Rooftop clutter: AC units, and a water tank on residential blocks.
func _roof_kit(ctx: Dictionary, parts: Array[Dictionary], pos: Vector2, w: float, d: float, h: float, tank: bool) -> void:
	var e: float = ctx["e"]
	var grey := Color(0.78, 0.8, 0.83)
	parts.append(_part("roof_box", _basis(ctx, w * 0.3, 2.4 * e, d * 0.28), pos - ctx["f"] * d * 0.18 + ctx["side"] * w * 0.15,
		(h + 1.2) * e, grey, Color()))
	parts.append(_part("roof_box", _basis(ctx, 1.4, 1.1 * e, 1.4), pos + ctx["f"] * d * 0.22 - ctx["side"] * w * 0.25,
		(h + 0.55) * e, grey.darkened(0.1), Color()))
	if tank:
		parts.append(_part("chimney", _basis(ctx, 2.2, 2.6 * e, 2.2), pos + ctx["side"] * w * 0.28 + ctx["f"] * d * 0.2,
			(h + 1.3) * e, Color(0.55, 0.42, 0.32), Color()))


const AWNING_COLORS: Array[Color] = [Color(0.85, 0.25, 0.22), Color(0.2, 0.52, 0.85), Color(0.95, 0.62, 0.18), Color(0.22, 0.65, 0.4)]


func _awning(ctx: Dictionary, parts: Array[Dictionary], pos: Vector2, w: float, d: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var color := AWNING_COLORS[rng.randi_range(0, AWNING_COLORS.size() - 1)]
	var e: float = ctx["e"]
	parts.append(_part("roof_box", _basis(ctx, w * 0.92, 0.25, 1.5), pos + ctx["f"] * (d * 0.5 + 0.75), 3.6 * e, color, Color()))


func _tint(b: Dictionary, color: Color) -> Color:
	return color * ABANDONED_TINT if b["abandoned"] else color


func _part(key: String, basis: Basis, pos: Vector2, y: float, color: Color, custom: Color) -> Dictionary:
	return {"key": key, "xf": Transform3D(basis, Vector3(pos.x, y, pos.y)), "color": color, "custom": custom}


## Info overlay colours per building id (empty = normal look).
func set_overlay_tint(tints: Dictionary) -> void:
	if tints == _overlay_tint:
		return
	_overlay_tint = tints
	_render_all()


const UNTINTED := ["lot", "contact", "smoke", "solar", "basin", "beacon"]


## Redraws every building once this frame (calls in between are merged).
func _render_all() -> void:
	_counts_dirty = true
	if not _render_queued:
		_render_queued = true
		_render_now.call_deferred()


func _render_now() -> void:
	_render_queued = false
	# Parts of finished buildings are cached (they only change when a building
	# levels up, changes style or is abandoned) and each MultiMesh is filled
	# with one buffer write, so a growing city stays cheap to redraw.
	var per_key: Dictionary = {}
	_instances.clear()
	for id: int in buildings:
		var b: Dictionary = buildings[id]
		var rise: float = _rising.get(id, 1.0)
		var parts: Array
		if rise >= 1.0:
			var sig := "%s|%d|%d|%s" % [b["style"], int(b["floors"]), int(b["level"]), b["abandoned"]]
			var cached: Array = _part_cache.get(id, [])
			if cached.size() == 2 and cached[0] == sig:
				parts = cached[1]
			else:
				parts = _parts_for(b, 1.0)
				_part_cache[id] = [sig, parts]
		else:
			parts = _parts_for(b, rise)
		var tinted := _overlay_tint.has(id)
		var entries := []
		for part: Dictionary in parts:
			var key: String = part["key"]
			if not per_key.has(key):
				per_key[key] = []
			var list: Array = per_key[key]
			entries.append([key, list.size()])
			if tinted and not key in UNTINTED:
				var copy := part.duplicate()
				copy["color"] = _overlay_tint[id]
				list.append(copy)
			else:
				list.append(part)
		_instances[id] = entries
	if _part_cache.size() > buildings.size():
		for id: int in _part_cache.keys():
			if not buildings.has(id):
				_part_cache.erase(id)
	for key: String in _meshes:
		var mm := (_meshes[key] as MultiMeshInstance3D).multimesh
		var list: Array = per_key.get(key, [])
		mm.instance_count = list.size()
		if list.is_empty():
			continue
		var colors := mm.use_colors
		var custom := mm.use_custom_data
		var stride := 12 + (4 if colors else 0) + (4 if custom else 0)
		var buf := PackedFloat32Array()
		buf.resize(list.size() * stride)
		var k := 0
		for part: Dictionary in list:
			var xf: Transform3D = part["xf"]
			var bs := xf.basis
			buf[k] = bs.x.x
			buf[k + 1] = bs.y.x
			buf[k + 2] = bs.z.x
			buf[k + 3] = xf.origin.x
			buf[k + 4] = bs.x.y
			buf[k + 5] = bs.y.y
			buf[k + 6] = bs.z.y
			buf[k + 7] = xf.origin.y
			buf[k + 8] = bs.x.z
			buf[k + 9] = bs.y.z
			buf[k + 10] = bs.z.z
			buf[k + 11] = xf.origin.z
			var o := k + 12
			if colors:
				var c: Color = part["color"]
				buf[o] = c.r
				buf[o + 1] = c.g
				buf[o + 2] = c.b
				buf[o + 3] = c.a
				o += 4
			if custom:
				var d: Color = part["custom"]
				buf[o] = d.r
				buf[o + 1] = d.g
				buf[o + 2] = d.b
				buf[o + 3] = d.a
			k += stride
		mm.buffer = buf


func _update_instances(id: int, rise: float) -> void:
	var parts := _parts_for(buildings[id], rise)
	var entries: Array = _instances.get(id, [])
	for i in mini(parts.size(), entries.size()):
		var mm := (_meshes[entries[i][0]] as MultiMeshInstance3D).multimesh
		if entries[i][1] < mm.instance_count:
			mm.set_instance_transform(entries[i][1], parts[i]["xf"])

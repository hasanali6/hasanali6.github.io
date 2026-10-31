extends Node3D
## City services and utilities.
##
## Coverage: every service building (clinic, school, police...) covers the
## road segments within its radius, measured along the roads (ServiceRules).
## A building gets the coverage of the segment its lot fronts, scaled by the
## service's budget efficiency and by how overloaded the serving building is
## (people served vs capacity, re-evaluated monthly).
##
## Utilities: electricity, water and sewage flow through connected road
## networks (cables and pipes follow the roads). Plants, pumps and outlets add
## supply to their network; consumers are served oldest first until it runs
## out. A pump near an untreated sewage outlet delivers polluted water.
##
## Pollution: plants, incinerators, sewage outlets and industry stamp a coarse
## grid. Results are written onto the building records (power, water, sewage,
## coverage, pollution and the derived service_happiness, death_mult and
## edu_chance) where the citizen, company and building systems read them.
## Monthly it reports upkeep and utility fees, fills landfills and cemeteries
## and may start a fire where there is no fire cover. Buildings without power
## or water get a floating warning icon.
##
## Cost per frame stays flat: coverage is rebuilt one service at a time within
## a small time budget, and the utility pass walks the buildings in chunks,
## at most once per PASS_INTERVAL while the city keeps changing.

const ICON_SHADER := preload("res://assets/materials/icon_billboard.gdshader")
const ICON_DIR := "res://assets/ui/icons/"
const PASS_INTERVAL := 1.0
const PASS_CHUNK := 200
const COVERAGE_BUDGET_US := 1500

@export var road_network_path: NodePath
@export var zone_system_path: NodePath
@export var building_system_path: NodePath

var types: Dictionary = {}               # service id -> type entry
var categories: Dictionary
var coverage: Dictionary = {}            # coverage key -> {segment id -> 0..1}
var network_of_segment: Dictionary = {}  # segment id -> network id
var pollution: ServiceRules.PollutionGrid
var last_report: Dictionary = {}

var _net: Node
var _zones: Node
var _buildings: Node
var _cons: Dictionary
var _fx: Dictionary
var _budget_cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _best: Dictionary = {}               # coverage key -> {segment id -> serving building id}
var _load: Dictionary = {}               # service building id -> efficiency from load (0..1)
var _served: Dictionary = {}             # service building id -> people served last month
var _storage: Dictionary = {}            # service building id -> stored amount
var _services: Array = []                # [record, type, segment, t] per service building
var _spots: Dictionary = {}              # service building id -> [segment, t]
var _seg_fx: Dictionary = {}             # segment id -> {cov, cov_h, death, edu}
var _no_fx: Dictionary = {}              # effects where nothing covers
var _service_signature: String = ""
var _dirty: bool = true
var _urgent: bool = true
var _roads_dirty: bool = true
var _coverage_dirty: bool = true
var _since_pass: float = 0.0
# Coverage being rebuilt over several frames.
var _cov_queue: Array = []
var _cov_next: Dictionary = {}
var _best_next: Dictionary = {}
# Utility pass in progress.
var _supply: Dictionary = {}             # network id -> {power, water, sewage, polluted, *_used}
var _supply_done: Dictionary = {}        # the last finished pass's _supply
var _pass_ids := PackedInt32Array()
var _pass_pos: int = -1
var _pass_icons: Dictionary = {}
var _pollution_next: ServiceRules.PollutionGrid
var _power_fee: float = 1.0
var _water_fee: float = 1.0
var _fee_h: float = 0.0
var _fees: Dictionary = {"power": 0.0, "water": 0.0}
var _icons: Dictionary = {}              # "power" / "water" -> MultiMeshInstance3D
var _population: int = 0
var _deaths: int = 0


func _ready() -> void:
	_net = get_node(road_network_path)
	_zones = get_node(zone_system_path)
	_buildings = get_node(building_system_path)
	categories = GameData.section("services/categories")
	for t: Dictionary in GameData.value("services/types"):
		types[str(t["id"])] = t
	_cons = GameData.section("services/consumption")
	_fx = GameData.section("services/effects")
	_budget_cfg = GameData.section("services/budget")
	var half := GameData.num("map/playable_size_m") * 0.5
	pollution = ServiceRules.PollutionGrid.new(float(_fx["pollution_cell_m"]), half)
	_pollution_next = ServiceRules.PollutionGrid.new(float(_fx["pollution_cell_m"]), half)
	_no_fx = _effects_for({})
	_rng.randomize()
	_build_icons()
	EventBus.roads_changed.connect(func() -> void:
		_roads_dirty = true
		_coverage_dirty = true
		_cov_queue.clear()
		_mark_dirty(true))
	EventBus.buildings_changed.connect(_mark_dirty.bind(false))
	EventBus.service_budgets_changed.connect(func() -> void:
		_coverage_dirty = true
		_mark_dirty(true))
	EventBus.month_changed.connect(_on_month)
	EventBus.citizens_reported.connect(func(r: Dictionary) -> void:
		_deaths = int(r.get("deaths", 0))
		_population = int(r.get("population", 0)))


func _mark_dirty(urgent: bool) -> void:
	_dirty = true
	if urgent:
		_urgent = true


func _process(delta: float) -> void:
	_since_pass += delta
	if not _cov_queue.is_empty():
		_step_coverage(COVERAGE_BUDGET_US)
	if _pass_pos >= 0:
		_step_pass(PASS_CHUNK)
	elif _dirty and (_urgent or _since_pass >= PASS_INTERVAL):
		_begin_pass()


## Runs everything to completion in one go (loading, tests, captures).
func recompute_now() -> void:
	for i in 2:
		if _pass_pos < 0:
			_dirty = true
			_begin_pass()
		while not _cov_queue.is_empty():
			_step_coverage(1 << 30)
		if _pass_pos >= 0:
			_step_pass(1 << 30)


## Service type entry of a building record, or {} for ordinary buildings.
func type_of(b: Dictionary) -> Dictionary:
	return types.get(str(b.get("service", "")), {})


## Catalogue entries (BuildTool items) of one group: "services" or "utilities".
func catalog_items(group: String) -> Array:
	var items := []
	for t: Dictionary in GameData.value("services/types"):
		if str(categories[t["category"]]["group"]) == group:
			var item := t.duplicate()
			item["zone"] = ""
			item["service"] = t["id"]
			items.append(item)
	return items


func budget_efficiency(category: String) -> float:
	return ServiceRules.efficiency(EconomySystem.service_budget(category), float(_budget_cfg["efficiency_exponent"]))


func _coverage_key(t: Dictionary) -> String:
	return "education%d" % int(t["level"]) if t["category"] == "education" else str(t["category"])


## Missing services only start to hurt as the town grows.
func maturity() -> float:
	return clampf(float(_population) / float(_fx["service_expectation_population"]), 0.0, 1.0)


## Ordinary buildings use utilities; services, parks and ruins do not.
func is_consumer(b: Dictionary) -> bool:
	return type_of(b).is_empty() and not str(b["style"]).begins_with("park") and not b.get("abandoned", false)


func _segment_of(b: Dictionary, grid: ZoneGrid) -> int:
	var cells: PackedInt32Array = b["cells"]
	if cells.is_empty() or cells[0] >= grid.size():
		return -1
	return grid.segment[cells[0]]


func _fee_factor(kind: String) -> float:
	return 1.0 + (1.0 - EconomySystem.utility_fee(kind)) * float(_cons["fee_consumption_effect"])


# --- Coverage (rebuilt one service at a time) ------------------------------------------

func _collect_services(graph: RoadGraph) -> void:
	_services.clear()
	var grid: ZoneGrid = _zones.grid
	var signature := PackedStringArray()
	var records: Dictionary = _buildings.buildings
	for id: int in records:
		var b: Dictionary = records[id]
		var t := type_of(b)
		if t.is_empty():
			continue
		var spot: Array = _spots.get(id, [])
		if spot.is_empty():
			var sid := _segment_of(b, grid)
			if sid < 0 or not graph.segments.has(sid):
				continue
			var c := graph.curve_of(graph.segments[sid])
			spot = [sid, graph.closest_t(c[0], c[1], c[2], b["centre"])]
			_spots[id] = spot
		_services.append([b, t, spot[0], spot[1]])
		signature.append("%d:%d" % [id, spot[0]])
	signature.sort()
	var sig := ",".join(signature)
	if sig != _service_signature:
		_service_signature = sig
		_coverage_dirty = true


func _start_coverage() -> void:
	_coverage_dirty = false
	_cov_queue.clear()
	for entry: Array in _services:
		if (entry[1] as Dictionary).has("radius"):
			_cov_queue.append(entry)
	_cov_next = {}
	_best_next = {}
	if _cov_queue.is_empty():
		_finish_coverage()


func _step_coverage(budget_us: int) -> void:
	var start := Time.get_ticks_usec()
	var graph: RoadGraph = _net.graph
	while not _cov_queue.is_empty():
		_cover(graph, _cov_queue.pop_back())
		if Time.get_ticks_usec() - start > budget_us:
			break
	if _cov_queue.is_empty():
		_finish_coverage()


func _cover(graph: RoadGraph, entry: Array) -> void:
	var b: Dictionary = entry[0]
	var t: Dictionary = entry[1]
	var eff := budget_efficiency(str(t["category"])) * float(_load.get(b["id"], 1.0))
	if eff <= 0.0:
		return
	var key := _coverage_key(t)
	var cov := ServiceRules.segment_coverage(graph, entry[2], entry[3], float(t["radius"]) * sqrt(eff))
	if not _cov_next.has(key):
		_cov_next[key] = {}
		_best_next[key] = {}
	var cmap: Dictionary = _cov_next[key]
	var bmap: Dictionary = _best_next[key]
	var strength := minf(eff, 1.0)
	for sid: int in cov:
		var v := float(cov[sid]) * strength
		if v > float(cmap.get(sid, 0.0)):
			cmap[sid] = v
			bmap[sid] = b["id"]


func _finish_coverage() -> void:
	coverage = _cov_next
	_best = _best_next
	_cov_next = {}
	_best_next = {}
	_rebuild_segment_effects()
	_mark_dirty(true)


## Coverage-derived effects are the same for every building on a segment.
func _rebuild_segment_effects() -> void:
	_seg_fx.clear()
	_no_fx = _effects_for({})
	var segs := {}
	for key: String in coverage:
		for sid: int in coverage[key]:
			segs[sid] = true
	for sid: int in segs:
		var cov := {}
		for key: String in coverage:
			var v: Variant = (coverage[key] as Dictionary).get(sid)
			if v != null:
				cov[key] = v
		_seg_fx[sid] = _effects_for(cov)


func _effects_for(cov: Dictionary) -> Dictionary:
	return {
		"cov": cov, "cov_h": ServiceRules.coverage_happiness(cov, categories, maturity()),
		"death": ServiceRules.death_multiplier(float(cov.get("health", 0.0)), _fx),
		"edu": ServiceRules.education_chances(cov, _fx),
	}


# --- Utility pass (buildings in chunks) ---------------------------------------------------

func _begin_pass() -> void:
	_dirty = false
	_urgent = false
	_since_pass = 0.0
	var graph: RoadGraph = _net.graph
	if _roads_dirty:
		_roads_dirty = false
		_spots.clear()
		var comps := ServiceRules.components(graph)
		network_of_segment.clear()
		for seg: RoadGraph.RoadSegment in graph.segments.values():
			network_of_segment[seg.id] = comps.get(seg.a, -1)
	_collect_services(graph)
	if _coverage_dirty:
		_start_coverage()
	_compute_supply()
	_power_fee = _fee_factor("power")
	_water_fee = _fee_factor("water")
	_fee_h = ((1.0 - EconomySystem.utility_fee("power")) + (1.0 - EconomySystem.utility_fee("water"))) \
		* float(_cons["fee_happiness_effect"]) * 0.5
	_pass_ids = PackedInt32Array(_buildings.buildings.keys())
	_pass_ids.sort()
	_pass_pos = 0
	_pass_icons = {"power": [], "water": []}
	_pollution_next.clear()
	for entry: Array in _services:
		var t: Dictionary = entry[1]
		if t.has("pollution"):
			var pol: Array = t["pollution"]
			_pollution_next.stamp((entry[0] as Dictionary)["centre"], float(pol[0]), float(pol[1]))


func _network(net_id: int) -> Dictionary:
	if not _supply.has(net_id):
		_supply[net_id] = {"power": 0.0, "water": 0.0, "sewage": 0.0, "polluted": false,
			"power_used": 0.0, "water_used": 0.0, "sewage_used": 0.0}
	return _supply[net_id]


func _compute_supply() -> void:
	_supply = {}
	var outlets := []
	for entry: Array in _services:
		var t: Dictionary = entry[1]
		var s := _network(network_of_segment.get(entry[2], -1))
		var eff := budget_efficiency(str(t["category"]))
		s["power"] += float(t.get("power", 0.0)) * eff
		s["water"] += float(t.get("water", 0.0)) * eff
		s["sewage"] += float(t.get("sewage", 0.0)) * eff
		if bool(t.get("water_pollution", false)):
			outlets.append([(entry[0] as Dictionary)["centre"], float((t["pollution"] as Array)[0])])
	# A pump within reach of an untreated sewage outlet pumps polluted water.
	for entry: Array in _services:
		if float((entry[1] as Dictionary).get("water", 0.0)) <= 0.0:
			continue
		for o: Array in outlets:
			if ((entry[0] as Dictionary)["centre"] as Vector2).distance_to(o[0]) < float(o[1]):
				_network(network_of_segment.get(entry[2], -1))["polluted"] = true


func _step_pass(chunk: int) -> void:
	var records: Dictionary = _buildings.buildings
	var grid: ZoneGrid = _zones.grid
	var ind: Array = _fx["industry_pollution"]
	var end := mini(_pass_pos + chunk, _pass_ids.size())
	for k in range(_pass_pos, end):
		var b: Dictionary = records.get(_pass_ids[k], {})
		if b.is_empty():
			continue
		var sid := _segment_of(b, grid)
		var fx: Dictionary = _seg_fx.get(sid, _no_fx)
		b["coverage"] = fx["cov"]
		b["death_mult"] = fx["death"]
		b["edu_chance"] = fx["edu"]
		var pol := pollution.sample(b["centre"])
		b["pollution"] = pol
		if str(b["zone_key"]) == "industry" and not b.get("abandoned", false):
			_pollution_next.stamp(b["centre"], float(ind[0]), float(ind[1]))
		if is_consumer(b):
			_serve(b, sid)
		else:
			b["power"] = true
			b["water"] = true
			b["sewage"] = true
			b["polluted_water"] = false
		b["service_happiness"] = float(fx["cov_h"]) + ServiceRules.utility_happiness(b, pol, _fx) + _fee_h
	_pass_pos = end
	if _pass_pos >= _pass_ids.size():
		_finish_pass()


## Electricity, water and sewage for one consumer from its network's supply.
func _serve(b: Dictionary, sid: int) -> void:
	var s := _network(network_of_segment.get(sid, -1))
	var households := int(b.get("occupants", 0))
	var jobs := int(b.get("employees", 0))
	var p := (float(_cons["power_per_building"]) + households * float(_cons["power_per_household"])
		+ jobs * float(_cons["power_per_job"])) * _power_fee
	var w := (float(_cons["water_per_building"]) + households * float(_cons["water_per_household"])
		+ jobs * float(_cons["water_per_job"])) * _water_fee
	var powered := p <= float(s["power"]) - float(s["power_used"]) + 1e-6
	if powered:
		s["power_used"] += p
	var watered := w <= float(s["water"]) - float(s["water_used"]) + 1e-6
	if watered:
		s["water_used"] += w
	var drained := w <= float(s["sewage"]) - float(s["sewage_used"]) + 1e-6
	if drained:
		s["sewage_used"] += w
	b["power"] = powered
	b["water"] = watered
	b["sewage"] = drained
	b["polluted_water"] = watered and bool(s["polluted"])
	if households + jobs > 0 and not (powered and watered):
		var c: Vector2 = b["centre"]
		var top := Vector3(c.x, int(b["floors"]) * 3.4 + 10.0, c.y)
		(_pass_icons["power" if not powered else "water"] as Array).append(top)


func _finish_pass() -> void:
	_pass_pos = -1
	var swap := pollution
	pollution = _pollution_next
	_pollution_next = swap
	_supply_done = _supply
	var used_power := 0.0
	var used_water := 0.0
	for s: Dictionary in _supply_done.values():
		used_power += float(s["power_used"])
		used_water += float(s["water_used"])
	_fees = {
		"power": used_power * float(_cons["power_price"]) * EconomySystem.utility_fee("power"),
		"water": used_water * float(_cons["water_price"]) * EconomySystem.utility_fee("water"),
	}
	for key: String in _pass_icons:
		var mm := (_icons[key] as MultiMeshInstance3D).multimesh
		var list: Array = _pass_icons[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(Basis(), list[i]))
	EventBus.services_changed.emit()


# --- Queries for the UI ------------------------------------------------------------

func coverage_of(b: Dictionary, category: String) -> float:
	return ServiceRules.category_coverage(b.get("coverage", {}), category)


## Coverage 0..1 of a road segment for an overlay key ("education" = best level).
func segment_coverage(sid: int, category: String) -> float:
	if category == "education":
		var best := 0.0
		for level in 3:
			best = maxf(best, float((coverage.get("education%d" % level, {}) as Dictionary).get(sid, 0.0)))
		return best
	return float((coverage.get(category, {}) as Dictionary).get(sid, 0.0))


## Spare supply on the network of a segment for "power" or "water".
func spare_on_segment(sid: int, kind: String) -> float:
	var s: Dictionary = _supply_done.get(network_of_segment.get(sid, -1), {})
	return 0.0 if s.is_empty() else float(s[kind]) - float(s[kind + "_used"])


## City-wide supply and use: {power: [used, supply], water: [...], sewage: [...]}.
func utility_totals() -> Dictionary:
	var out := {"power": [0.0, 0.0], "water": [0.0, 0.0], "sewage": [0.0, 0.0]}
	for s: Dictionary in _supply_done.values():
		for kind: String in out:
			(out[kind] as Array)[0] += float(s[kind + "_used"])
			(out[kind] as Array)[1] += float(s[kind])
	return out


## Details of one service building for the info card.
func building_details(id: int) -> Dictionary:
	var records: Dictionary = _buildings.buildings
	if not records.has(id):
		return {}
	var t := type_of(records[id])
	if t.is_empty():
		return {}
	var cat := str(t["category"])
	var eff := budget_efficiency(cat)
	return {
		"category": cat, "name_key": t["name_key"], "upkeep": float(t["upkeep"]) * EconomySystem.service_budget(cat),
		"capacity": float(t.get("capacity", 0)) * eff, "served": int(_served.get(id, 0)),
		"radius": float(t.get("radius", 0.0)) * sqrt(eff * float(_load.get(id, 1.0))),
		"storage": float(_storage.get(id, 0.0)), "storage_max": float(t.get("storage", 0.0)),
		"power": float(t.get("power", 0.0)) * eff, "water": float(t.get("water", 0.0)) * eff,
		"sewage": float(t.get("sewage", 0.0)) * eff, "load": float(_load.get(id, 1.0)),
	}


# --- Monthly ---------------------------------------------------------------------------

func _on_month(_m: int) -> void:
	var records: Dictionary = _buildings.buildings
	var grid: ZoneGrid = _zones.grid
	# People each service building served -> its efficiency next month.
	var served := {}
	var uni_share := float(_fx["education_share_university"])
	for b: Dictionary in records.values():
		var residents := int(b.get("residents", 0))
		if residents <= 0:
			continue
		var sid := _segment_of(b, grid)
		for key: String in _best:
			var by: int = (_best[key] as Dictionary).get(sid, -1)
			if by < 0:
				continue
			var people := residents
			if key == "education2":
				people = roundi(residents * uni_share)
			elif key.begins_with("education"):
				people = int(b.get("children", 0))
			served[by] = int(served.get(by, 0)) + people
	_served = served
	_load.clear()
	var upkeep := {}
	var full := []
	var total := maxf(float(_population), 1.0)
	for b: Dictionary in records.values():
		var t := type_of(b)
		if t.is_empty():
			continue
		var id: int = b["id"]
		var cat := str(t["category"])
		upkeep[cat] = float(upkeep.get(cat, 0.0)) + float(t["upkeep"]) * EconomySystem.service_budget(cat)
		var load := 1.0
		if t.has("capacity"):
			load = minf(1.0, float(t["capacity"]) * budget_efficiency(cat) / maxf(float(served.get(id, 0)), 1.0))
		if t.has("storage"):
			var amount := float(served.get(id, 0)) * float(_cons["garbage_per_citizen"])
			if cat == "deathcare":
				amount = float(_deaths) * minf(float(served.get(id, 0)) / total, 1.0)
			var stored := minf(float(_storage.get(id, 0.0)) + amount, float(t["storage"]))
			_storage[id] = stored
			if stored >= float(t["storage"]):
				load = 0.0
				full.append(t["name_key"])
		_load[id] = load
	for name_key: String in full:
		EventBus.notification_posted.emit("services", tr("NOTIFY_STORAGE_FULL") % tr(name_key))
	_start_fire(records)
	last_report = {"upkeep": upkeep, "fees": _fees.duplicate()}
	EventBus.services_reported.emit(last_report.duplicate(true))
	_warn_missing_utilities(records)
	# Loads and the town's size changed: coverage and expectations follow.
	_coverage_dirty = true
	_mark_dirty(true)


func _start_fire(records: Dictionary) -> void:
	if _population < int(_fx["fire_min_population"]):
		return
	for id: int in records.keys():
		var b: Dictionary = records[id]
		if not is_consumer(b):
			continue
		if _rng.randf() < float(_fx["fire_chance_uncovered"]) * (1.0 - coverage_of(b, "fire")):
			_buildings.burn(id)
			EventBus.notification_posted.emit("fire", tr("NOTIFY_FIRE"))
			return


func _warn_missing_utilities(records: Dictionary) -> void:
	var no_power := 0
	var no_water := 0
	for b: Dictionary in records.values():
		if not is_consumer(b) or int(b.get("occupants", 0)) + int(b.get("employees", 0)) == 0:
			continue
		if not b.get("power", true):
			no_power += 1
		if not b.get("water", true):
			no_water += 1
	if no_power > 0:
		EventBus.notification_posted.emit("power", tr("NOTIFY_NO_POWER") % no_power)
	elif no_water > 0:
		EventBus.notification_posted.emit("water", tr("NOTIFY_NO_WATER") % no_water)


# --- Warning icons -----------------------------------------------------------------------

func _build_icons() -> void:
	for entry: Array in [["power", "zap", Color(0.95, 0.6, 0.08)], ["water", "droplet", Color(0.16, 0.5, 0.92)]]:
		var mat := ShaderMaterial.new()
		mat.shader = ICON_SHADER
		mat.set_shader_parameter("icon", load(ICON_DIR + str(entry[1]) + ".svg"))
		mat.set_shader_parameter("badge_color", entry[2])
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Icons_" + str(entry[0])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Icons are scaled up in the shader; keep them from being culled early.
		mmi.extra_cull_margin = 40.0
		add_child(mmi)
		_icons[entry[0]] = mmi


# --- Save / load ---------------------------------------------------------------------------

func save_state() -> Dictionary:
	var store := {}
	for id: int in _storage:
		store[str(id)] = _storage[id]
	return {"storage": store}


func load_state(state: Dictionary) -> void:
	_storage.clear()
	var store: Dictionary = state.get("storage", {})
	for key: String in store:
		_storage[int(key)] = float(store[key])
	_roads_dirty = true
	_coverage_dirty = true
	_mark_dirty(true)

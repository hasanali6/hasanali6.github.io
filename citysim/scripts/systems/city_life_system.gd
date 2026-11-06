extends Node3D
## The city's day-to-day life on top of the economy (data/life.json):
##  * Land value per building and per spot: parks, the shore, transit stops
##    and services raise it; pollution, traffic noise, crime, the port and
##    the airport lower it. Valuable land grows faster, pays more tax, draws
##    new residents first and is needed for the top building levels.
##  * Crime per building: dense, unhappy, jobless or run-down places breed
##    it, police coverage keeps it down. It costs happiness (people move out).
##  * Fires burn for a while: a fire station in reach puts them out, else
##    the building burns down and the fire may jump to its neighbours.
##  * Disasters (can be switched off in Settings): rare earthquakes damage
##    buildings around an epicentre and start fires; heavy rain floods
##    homes close to the river and lakes.
##  * Missions: three short-term goals at a time, paid on completion.
##  * Tutorial: first steps for a new city, one at a time.

const FIRE_SHADER := preload("res://assets/materials/fire.gdshader")
const ICON_SHADER := preload("res://assets/materials/icon_billboard.gdshader")
const MISSION_KINDS: Array[String] = ["population", "happiness", "parks", "services", "budget", "transit", "crime", "land_value"]

var disasters_enabled: bool = true
var missions: Array = []                 # [{kind, target, reward, start?}]
var tutorial_step: int = -1              # index into life/tutorial, -1 = off
var last_stats: Dictionary = {}

var _lv: Dictionary
var _crime: Dictionary
var _fire: Dictionary
var _dis: Dictionary
var _mis: Dictionary
var _steps: Array
var _buildings: Node
var _services: Node
var _citizens: Node
var _zones: Node
var _roads: Node
var _rng := RandomNumberGenerator.new()
var _cache: Dictionary = {}              # Vector2i -> spot value without segment parts
var _parks: Array = []                   # [Vector3(x, y, radius)]
var _nuisances: Array = []               # [Vector4(x, y, radius, weight)]
var _water_d: Dictionary = {}            # building id -> distance to water
var _fires: Dictionary = {}              # building id -> {"t", "spread"}
var _flame_mm: MultiMeshInstance3D
var _icon_mm: MultiMeshInstance3D
var _fires_dirty: bool = false
var _shake_left: float = 0.0
var _layer_seen: bool = false
var _missions_seen: bool = false
var _roads_at_start: int = -1


func _ready() -> void:
	var cfg := GameData.section("life")
	_lv = cfg["land_value"]
	_crime = cfg["crime"]
	_fire = cfg["fire"]
	_dis = cfg["disasters"]
	_mis = cfg["missions"]
	_steps = cfg["tutorial"]
	_rng.randomize()
	_buildings = get_node("../BuildingSystem")
	_services = get_node("../ServiceSystem")
	_citizens = get_node("../CitizenSystem")
	_zones = get_node("../ZoneSystem")
	_roads = get_node("../RoadNetwork")
	_build_visuals()
	EventBus.month_changed.connect(_on_month)
	EventBus.buildings_changed.connect(func() -> void: _cache.clear())
	EventBus.overlay_selected.connect(func(key: String) -> void:
		if key != "":
			_layer_seen = true
			_check_tutorial())
	EventBus.zones_changed.connect(_check_tutorial)
	EventBus.services_changed.connect(_check_tutorial)
	EventBus.roads_changed.connect(_check_tutorial)
	# A brand-new city starts with the tutorial; a loaded one sets its own state.
	_start_new.call_deferred()


func _start_new() -> void:
	if _roads_at_start < 0:
		_roads_at_start = _road_count()
	if last_stats.is_empty() and int(_citizens.population) == 0 and _buildings.buildings.is_empty() and tutorial_step < 0 and missions.is_empty():
		tutorial_step = 0
		EventBus.life_changed.emit()
	_refill_missions(_stats())


# --- Land value ------------------------------------------------------------------------

## Land value 0..1 at p on road segment sid (-1 = unknown), ignoring the
## spot's own crime unless given.
func value_at(p: Vector2, sid: int = -1, crime: float = -1.0) -> float:
	var key := Vector2i(floori(p.x / float(_lv["cache_cell_m"])), floori(p.y / float(_lv["cache_cell_m"])))
	var spot: Dictionary
	if _cache.has(key):
		spot = _cache[key]
	else:
		spot = _spot(p)
		_cache[key] = spot
	var f := spot.duplicate()
	if sid >= 0:
		var traffic: Node = get_node_or_null("../TrafficSystem")
		var transit: Node = get_node_or_null("../TransitSystem")
		if transit != null:
			f["transit"] = float(transit.segment_access(sid))
		if traffic != null:
			f["noise"] = float(traffic.noise(sid))
		var cov := 0.0
		var cats: Array = _lv["service_categories"]
		for cat: String in cats:
			cov += float(_services.segment_coverage(sid, cat))
		f["services"] = cov / maxf(cats.size(), 1.0)
	if _services.get("pollution") != null:
		f["pollution"] = float(_services.pollution.sample(p))
	f["crime"] = maxf(crime, 0.0) if crime >= 0.0 else _crime_near(p)
	return CityLifeRules.land_value(f, _lv)


## Position-only parts of the land value (cached per 32 m square).
func _spot(p: Vector2) -> Dictionary:
	var park := 0.0
	for q: Vector3 in _parks:
		park = maxf(park, CityLifeRules.closeness(Vector2(q.x, q.y).distance_to(p), q.z))
	var nuisance := 0.0
	for n: Vector4 in _nuisances:
		nuisance = maxf(nuisance, n.w * CityLifeRules.closeness(Vector2(n.x, n.y).distance_to(p), n.z))
	var water := CityLifeRules.closeness(maxf(MapWater.shared().distance(p), 0.0), float(_lv["water_radius_m"]))
	return {"park": park, "water": water, "nuisance": nuisance}


func _crime_near(p: Vector2) -> float:
	var best := INF
	var crime := 0.0
	var b: Dictionary = {}
	var bid: int = _buildings.building_at(p)
	if bid >= 0:
		b = _buildings.buildings.get(bid, {})
		return float(b.get("crime", 0.0))
	# Empty land takes the crime of the closest building around.
	for other: Dictionary in _buildings.buildings.values():
		var d := (other["centre"] as Vector2).distance_squared_to(p)
		if d < best and d < 3600.0:
			best = d
			crime = float(other.get("crime", 0.0))
	return crime


## Growth chance multiplier for a new building at p.
func growth_factor(p: Vector2, sid: int) -> float:
	return CityLifeRules.scale(value_at(p, sid), float(_lv["growth_min"]), float(_lv["growth_max"]))


## Tax multiplier of the households of a building.
func tax_factor(b: Dictionary) -> float:
	return CityLifeRules.scale(float(b.get("land_value", 0.35)), float(_lv["tax_min"]), float(_lv["tax_max"]))


## Extra score for picking a home in this building (valuable land first).
func home_score(b: Dictionary) -> float:
	return float(_lv["home_choice_weight"]) * float(b.get("land_value", 0.35))


## False while the land is not worth the building's next level.
func allows_level(b: Dictionary, next_level: int) -> bool:
	if str(b.get("zone_key", "")) == "industry" or b.get("manual", false):
		return true
	return float(b.get("land_value", 1.0)) >= CityLifeRules.level_requirement(next_level, _lv)


func _collect_places() -> void:
	_parks.clear()
	_nuisances.clear()
	var radius_by_style := {}
	for item: Dictionary in GameData.value("catalog/leisure"):
		radius_by_style[str(item["style"])] = float(item.get("park_radius_m", 0.0))
	var nuis: Dictionary = _lv["nuisances"]
	for b: Dictionary in _buildings.buildings.values():
		var style := str(b["style"])
		var c: Vector2 = b["centre"]
		if nuis.has(style):
			var n: Array = nuis[style]
			_nuisances.append(Vector4(c.x, c.y, float(n[0]), float(n[1])))
		elif style.begins_with("park") or float(radius_by_style.get(style, 0.0)) > 0.0:
			var r := float(radius_by_style.get(style, 0.0))
			_parks.append(Vector3(c.x, c.y, r if r > 0.0 else float(_lv["park_radius_default_m"])))


# --- Monthly ---------------------------------------------------------------------------

func _on_month(_m: int) -> void:
	_collect_places()
	_cache.clear()
	_update_buildings()
	_floods()
	_earthquake_roll()
	var s := _stats()
	_update_missions(s)
	_check_tutorial()
	EventBus.life_changed.emit()


func _update_buildings() -> void:
	var records: Dictionary = _buildings.buildings
	var stats: Dictionary = _citizens.stats()
	var unemployment := float(stats.get("unemployed", 0)) / maxf(float(stats.get("workers", 0)), 1.0)
	# Empty (abandoned) buildings on a coarse grid, for "run-down nearby".
	var cell := float(_crime["abandoned_radius_m"])
	var empty := {}
	var all := {}
	for b: Dictionary in records.values():
		var k := Vector2i(floori((b["centre"] as Vector2).x / cell), floori((b["centre"] as Vector2).y / cell))
		all[k] = int(all.get(k, 0)) + 1
		if b["abandoned"]:
			empty[k] = int(empty.get(k, 0)) + 1
	var high := 0
	var high_unpoliced := 0
	for b: Dictionary in records.values():
		if b["abandoned"] or not _services.is_consumer(b):
			b["crime"] = 0.0
			continue
		var k := Vector2i(floori((b["centre"] as Vector2).x / cell), floori((b["centre"] as Vector2).y / cell))
		var happy := float(b.get("happiness", 0.0)) if int(b.get("occupants", 0)) > 0 else -1.0
		var police := float(_services.coverage_of(b, "police"))
		var target := CityLifeRules.crime({
			"floors": int(b["floors"]), "happiness": happy, "unemployment": unemployment,
			"abandoned": float(empty.get(k, 0)) / maxf(float(all.get(k, 1)), 1.0), "police": police,
		}, _crime)
		var crime := CityLifeRules.smooth(float(b.get("crime", target)), target, float(_crime["smoothing"]))
		b["crime"] = crime
		if crime >= float(_crime["high"]):
			high += 1
			if police < 0.2:
				high_unpoliced += 1
	for b: Dictionary in records.values():
		var id: int = b["id"]
		b["land_value"] = value_at(b["centre"], int(b.get("segment", -1)), float(b.get("crime", 0.0)))
		var flood := int(b.get("flooded", 0))
		if flood > 0:
			b["flooded"] = flood - 1
		var penalty := float(b.get("crime", 0.0)) * float(_crime["happiness_penalty"])
		if flood > 0:
			penalty += float(_dis["flood_happiness_penalty"])
		b["life_happiness"] = -penalty
		if not _water_d.has(id):
			_water_d[id] = MapWater.shared().distance(b["centre"])
	if high_unpoliced >= int(_crime["warn_count"]):
		EventBus.notification_posted.emit("crime", tr("NOTIFY_CRIME_HIGH") % high_unpoliced)


# --- Fires -----------------------------------------------------------------------------

## Starts a fire in a building (no-op if it is already burning or empty).
func ignite(id: int) -> bool:
	var b: Dictionary = _buildings.buildings.get(id, {})
	if b.is_empty() or b["abandoned"] or _fires.has(id) or _fires.size() >= int(_fire["max_fires"]):
		return false
	_fires[id] = {"t": 0.0, "spread": 0.0}
	_fires_dirty = true
	EventBus.notification_posted.emit("fire", tr("NOTIFY_FIRE_STARTED"))
	EventBus.sfx_requested.emit("error")
	return true


## Sets a random lived-in building on fire (Cheats).
func ignite_random() -> bool:
	var ids: Array = []
	for b: Dictionary in _buildings.buildings.values():
		if not b["abandoned"] and _services.is_consumer(b) and int(b.get("occupants", 0)) + int(b.get("employees", 0)) > 0:
			ids.append(int(b["id"]))
	if ids.is_empty():
		return false
	return ignite(int(ids[_rng.randi_range(0, ids.size() - 1)]))


func burning_count() -> int:
	return _fires.size()


func is_burning(id: int) -> bool:
	return _fires.has(id)


func _process(delta: float) -> void:
	if _shake_left > 0.0:
		_shake_left -= delta
	if _fires_dirty:
		_draw_fires()
	if _fires.is_empty():
		return
	var clock: SimClock = TimeSystem.clock
	var game_delta := delta * clock.speed_multipliers[clock.speed_index]
	if game_delta <= 0.0:
		return
	var records: Dictionary = _buildings.buildings
	for id: int in _fires.keys():
		var f: Dictionary = _fires[id]
		if not records.has(id) or records[id]["abandoned"]:
			_fires.erase(id)
			_fires_dirty = true
			continue
		f["t"] = float(f["t"]) + game_delta
		f["spread"] = float(f["spread"]) + game_delta
		var cover := float(_services.coverage_of(records[id], "fire"))
		match CityLifeRules.fire_state(float(f["t"]), cover, _fire):
			"out":
				_fires.erase(id)
				_fires_dirty = true
				EventBus.notification_posted.emit("fire", tr("NOTIFY_FIRE_OUT"))
				continue
			"down":
				_fires.erase(id)
				_fires_dirty = true
				_buildings.burn(id)
				EventBus.notification_posted.emit("fire", tr("NOTIFY_FIRE_DOWN"))
				continue
		if float(f["spread"]) >= float(_fire["spread_interval_seconds"]):
			f["spread"] = 0.0
			if _rng.randf() < float(_fire["spread_chance"]) * (1.0 - cover):
				var near := _neighbour(records[id])
				if near >= 0:
					ignite(near)
	if _fires_dirty:
		_draw_fires()


func _neighbour(b: Dictionary) -> int:
	var c: Vector2 = b["centre"]
	var reach := float(_fire["spread_radius_m"]) + maxf(float(b["width"]), float(b["depth"])) * 0.5
	var best := -1
	var best_d := INF
	for other: Dictionary in _buildings.buildings.values():
		var id: int = other["id"]
		if id == b["id"] or other["abandoned"] or _fires.has(id):
			continue
		var d := (other["centre"] as Vector2).distance_to(c)
		if d < reach and d < best_d:
			best_d = d
			best = id
	return best


func _build_visuals() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FIRE_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	_flame_mm = MultiMeshInstance3D.new()
	_flame_mm.name = "Fires"
	_flame_mm.multimesh = mm
	_flame_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_mm.extra_cull_margin = 200.0
	add_child(_flame_mm)
	var imat := ShaderMaterial.new()
	imat.shader = ICON_SHADER
	imat.set_shader_parameter("icon", load("res://assets/ui/icons/flame.svg"))
	imat.set_shader_parameter("badge_color", Color(0.9, 0.2, 0.1))
	var iquad := QuadMesh.new()
	iquad.size = Vector2.ONE
	iquad.material = imat
	var imm := MultiMesh.new()
	imm.transform_format = MultiMesh.TRANSFORM_3D
	imm.mesh = iquad
	_icon_mm = MultiMeshInstance3D.new()
	_icon_mm.name = "FireIcons"
	_icon_mm.multimesh = imm
	_icon_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_icon_mm.extra_cull_margin = 40.0
	add_child(_icon_mm)


## Three flames and three smoke puffs on each burning roof, plus a badge.
func _draw_fires() -> void:
	_fires_dirty = false
	var records: Dictionary = _buildings.buildings
	var ids: Array = []
	for id: int in _fires:
		if records.has(id):
			ids.append(id)
	var mm := _flame_mm.multimesh
	mm.instance_count = ids.size() * 6
	_icon_mm.multimesh.instance_count = ids.size()
	for n in ids.size():
		var b: Dictionary = records[ids[n]]
		var c: Vector2 = b["centre"]
		var f: Vector2 = b["front"]
		var side := Vector2(-f.y, f.x)
		var top := float(b["floors"]) * 3.2 + 1.0
		if str(b["style"]) == "factory":
			top = 6.0 + float(b["floors"]) * 3.0
		var size := clampf(minf(float(b["width"]), float(b["depth"])) * 0.75, 6.0, 15.0)
		_icon_mm.multimesh.set_instance_transform(n, Transform3D(Basis(), Vector3(c.x, top + size * 2.0 + 8.0, c.y)))
		for k in 3:
			var off := side * (float(k) - 1.0) * size * 0.45 + f * (float(k % 2) - 0.5) * size * 0.3
			var seed := fposmod(float(b["seed"]) * 0.37 + k * 0.29, 1.0)
			mm.set_instance_transform(n * 6 + k, Transform3D(Basis(), Vector3(c.x + off.x, top - size * 0.2, c.y + off.y)))
			mm.set_instance_custom_data(n * 6 + k, Color(seed, size * (1.0 - 0.2 * k), 0.0, 0.0))
			mm.set_instance_transform(n * 6 + 3 + k, Transform3D(Basis(), Vector3(c.x + off.x * 0.6, top + size * 0.6, c.y + off.y * 0.6)))
			mm.set_instance_custom_data(n * 6 + 3 + k, Color(fposmod(seed + 0.33, 1.0), size * 1.1, 1.0, 0.0))


# --- Disasters -------------------------------------------------------------------------

func set_disasters(on: bool) -> void:
	disasters_enabled = on
	EventBus.life_changed.emit()


func _earthquake_roll() -> void:
	if not disasters_enabled or int(_citizens.population) < int(_dis["min_population"]):
		return
	if _rng.randf() < float(_dis["earthquake_chance_per_month"]):
		earthquake()


## Shakes the ground around a random part of the city: buildings nearby may
## be damaged (left as ruins) and a few fires break out.
func earthquake() -> int:
	var list: Array = _buildings.buildings.values()
	if list.is_empty():
		return 0
	var centre: Vector2 = (list[_rng.randi_range(0, list.size() - 1)] as Dictionary)["centre"]
	var radius := float(_dis["earthquake_radius_m"])
	var damaged := 0
	var standing: Array = []
	for b: Dictionary in list:
		if b["abandoned"] or not _services.is_consumer(b):
			continue
		var d := (b["centre"] as Vector2).distance_to(centre)
		if d > radius:
			continue
		# Older, lower buildings suffer more; well-built towers less.
		var chance := float(_dis["earthquake_damage"]) * (1.0 - d / radius) * (1.2 - 0.15 * int(b["level"]))
		if _rng.randf() < chance:
			_buildings.burn(int(b["id"]))
			damaged += 1
		else:
			standing.append(int(b["id"]))
	standing.shuffle()
	for i in mini(int(_dis["earthquake_fires"]), standing.size()):
		ignite(int(standing[i]))
	var shake: Array = _dis["earthquake_shake"]
	_shake_left = float(shake[1])
	EventBus.camera_shake_requested.emit(float(shake[0]), float(shake[1]))
	EventBus.notification_posted.emit("disaster", tr("NOTIFY_EARTHQUAKE") % damaged)
	EventBus.sfx_requested.emit("bulldoze")
	return damaged


## Heavy rain floods homes near the river and lakes for a couple of months.
func _floods() -> void:
	if not disasters_enabled or WeatherSystem.rain < float(_dis["flood_rain"]):
		return
	if _rng.randf() >= float(_dis["flood_chance_per_month"]):
		return
	flood()


func flood() -> int:
	var hit := 0
	for b: Dictionary in _buildings.buildings.values():
		if b["abandoned"] or not _services.is_consumer(b):
			continue
		var id: int = b["id"]
		if not _water_d.has(id):
			_water_d[id] = MapWater.shared().distance(b["centre"])
		var d := float(_water_d[id])
		# The sea coast has a beach; rivers and lakes flood.
		if d > float(_dis["flood_distance_m"]) or MapWater.shared().coast_distance(b["centre"]) <= d + 1.0:
			continue
		b["flooded"] = int(_dis["flood_months"])
		hit += 1
		if _rng.randf() < float(_dis["flood_abandon_chance"]):
			_buildings.burn(id)
	if hit > 0:
		EventBus.notification_posted.emit("disaster", tr("NOTIFY_FLOOD") % hit)
	return hit


# --- Stats, missions and tutorial ------------------------------------------------------

func _road_count() -> int:
	return (_roads.graph as RoadGraph).segments.size()


func _stats() -> Dictionary:
	var records: Dictionary = _buildings.buildings
	var crime := 0.0
	var crime_n := 0
	var value := 0.0
	var value_n := 0
	var parks := 0
	var cov := 0.0
	var cov_n := 0
	var cats: Array = _lv["service_categories"]
	for b: Dictionary in records.values():
		var style := str(b["style"])
		if style.begins_with("park"):
			parks += 1
		if b["abandoned"] or not _services.is_consumer(b):
			continue
		crime += float(b.get("crime", 0.0))
		crime_n += 1
		if b.has("land_value"):
			value += float(b["land_value"])
			value_n += 1
		if int(b.get("occupants", 0)) > 0:
			var c := 0.0
			for cat: String in cats:
				c += float(_services.coverage_of(b, cat))
			cov += c / maxf(cats.size(), 1.0)
			cov_n += 1
	var transit: Node = get_node_or_null("../TransitSystem")
	var s := {
		"population": int(_citizens.population),
		"happiness": float(_citizens.stats().get("happiness", 50.0)),
		"crime": crime / maxf(crime_n, 1.0),
		"land_value": value / maxf(value_n, 1.0),
		"parks": parks,
		"transit_lines": 0 if transit == null else (transit.lines as Array).size(),
		"net": float(EconomySystem.last_ledger.get("net", 0.0)),
		"coverage": cov / maxf(cov_n, 1.0),
		"fires": _fires.size(),
	}
	last_stats = s
	return s


func _refill_missions(s: Dictionary) -> void:
	var kinds: Array = MISSION_KINDS.duplicate()
	kinds.shuffle()
	var have := {}
	for m: Dictionary in missions:
		have[m["kind"]] = true
	for kind: String in kinds:
		if missions.size() >= int(_mis["active"]):
			break
		if have.has(kind):
			continue
		var m := CityLifeRules.make_mission(kind, s, _mis)
		if m.is_empty():
			continue
		# Not already done the moment it is offered.
		if CityLifeRules.mission_progress(m, s) >= 1.0:
			continue
		missions.append(m)
		have[kind] = true


func _update_missions(s: Dictionary) -> void:
	var done: Array = []
	for m: Dictionary in missions:
		if CityLifeRules.mission_progress(m, s) >= 1.0:
			done.append(m)
	for m: Dictionary in done:
		missions.erase(m)
		EconomySystem.add_bonus(int(m["reward"]))
		EventBus.notification_posted.emit("mission", tr("NOTIFY_MISSION_DONE") % [mission_text(m), UiStyle.format_int(int(m["reward"]))])
		EventBus.sfx_requested.emit("milestone")
	_refill_missions(s)


## Missions with their progress for the UI: [{text, progress, reward}].
func mission_rows() -> Array:
	var s := _stats()
	_missions_seen = true
	_check_tutorial()
	var out := []
	for m: Dictionary in missions:
		out.append({"text": mission_text(m), "progress": CityLifeRules.mission_progress(m, s), "reward": int(m["reward"])})
	return out


func mission_text(m: Dictionary) -> String:
	var t: Variant = m["target"]
	match str(m["kind"]):
		"crime", "land_value", "services":
			return tr("MISSION_" + str(m["kind"]).to_upper()) % roundi(float(t) * 100.0)
		"budget":
			return tr("MISSION_BUDGET") % UiStyle.format_int(int(t))
		"happiness":
			return tr("MISSION_HAPPINESS") % roundi(float(t))
	return tr("MISSION_" + str(m["kind"]).to_upper()) % int(t)


func tutorial_text() -> String:
	if tutorial_step < 0 or tutorial_step >= _steps.size():
		return ""
	return tr(str((_steps[tutorial_step] as Dictionary)["text"]))


func tutorial_progress() -> Vector2i:
	return Vector2i(tutorial_step + 1, _steps.size())


func start_tutorial() -> void:
	tutorial_step = 0
	_roads_at_start = _road_count()
	_layer_seen = false
	_missions_seen = false
	_check_tutorial()
	EventBus.life_changed.emit()


func skip_tutorial() -> void:
	tutorial_step = -1
	EventBus.life_changed.emit()


func _tutorial_stats() -> Dictionary:
	var grid: ZoneGrid = _zones.grid
	var counts := {"residential": 0, "commercial": 0, "industrial": 0, "office": 0, "mixed": 0}
	for i in grid.size():
		var z := grid.zone[i]
		if z == ZoneGrid.UNZONED:
			continue
		var group := str(_zones.zone_types[_zones.zone_key(z)]["group"])
		counts[group] = int(counts.get(group, 0)) + 1
	var cats := {}
	for b: Dictionary in _buildings.buildings.values():
		var t: Dictionary = _services.type_of(b)
		if not t.is_empty():
			cats[str(t["category"])] = true
	return {
		"roads_built": _road_count() - maxi(_roads_at_start, 0),
		"res_cells": int(counts["residential"]) + int(counts["mixed"]),
		"com_cells": int(counts["commercial"]) + int(counts["office"]) + int(counts["mixed"]),
		"ind_cells": int(counts["industrial"]),
		"power": 1 if cats.has("power") else 0, "water": 1 if cats.has("water") else 0,
		"safety": 1 if cats.has("police") or cats.has("fire") or cats.has("health") else 0,
		"population": int(_citizens.population), "layer_seen": _layer_seen, "missions_seen": _missions_seen,
	}


func _check_tutorial() -> void:
	if tutorial_step < 0:
		return
	var s := _tutorial_stats()
	var moved := false
	while tutorial_step >= 0 and tutorial_step < _steps.size() and CityLifeRules.tutorial_done(str((_steps[tutorial_step] as Dictionary)["id"]), s):
		tutorial_step += 1
		moved = true
	if tutorial_step >= _steps.size():
		tutorial_step = -1
		EventBus.notification_posted.emit("tutorial", tr("TUT_FINISHED"))
		moved = true
	if moved:
		EventBus.sfx_requested.emit("ui_click")
		EventBus.life_changed.emit()


## Small screen shake offset while an earthquake lasts (for the camera).
func shake_left() -> float:
	return _shake_left


# --- Save / load -----------------------------------------------------------------------

func save_state() -> Dictionary:
	var fires := {}
	for id: int in _fires:
		fires[str(id)] = float((_fires[id] as Dictionary)["t"])
	return {"missions": missions.duplicate(true), "tutorial": tutorial_step, "disasters": disasters_enabled,
		"fires": fires, "roads_at_start": _roads_at_start}


func load_state(state: Dictionary) -> void:
	missions = (state.get("missions", []) as Array).duplicate(true)
	# Cities from before the tutorial existed are past their first steps.
	tutorial_step = int(state.get("tutorial", -1))
	disasters_enabled = bool(state.get("disasters", true))
	_roads_at_start = int(state.get("roads_at_start", _road_count()))
	_fires.clear()
	var fires: Dictionary = state.get("fires", {})
	for key: String in fires:
		_fires[int(key)] = {"t": float(fires[key]), "spread": 0.0}
	_fires_dirty = true
	last_stats = {"loaded": true}
	_collect_places()
	_cache.clear()
	_after_load.call_deferred()


func _after_load() -> void:
	_refill_missions(_stats())
	EventBus.life_changed.emit()

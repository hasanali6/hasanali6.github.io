extends Node
## City traffic: the statistical layer and the routing service.
##
## Demand: every day each worker drives home -> work -> home, households go
## shopping, shops get deliveries from local industry and service buildings
## send vehicles (garbage, police, ambulances...) to the homes they cover.
## Trips are counted per pair of road segments, gathered a few thousand
## households per frame.
##
## Assignment: TrafficAssignment routes all trips with congestion-aware
## travel times on a WorkerThreadPool thread and loads them onto the roads;
## successive rounds smooth out, so busy roads slow down and some drivers
## pick other routes. Results: daily volume and speed per road direction,
## commute time per home/work pair, road noise, and the shortest-time trees
## the visible vehicles use as their cached routes.
##
## Also owns the driving-lane geometry (LaneGeometry), answers long presses
## on roads and warns about traffic jams.

const KIND_COMMUTE_OUT := 0
const KIND_COMMUTE_BACK := 1
const KIND_SHOP_OUT := 2
const KIND_SHOP_BACK := 3
const KIND_FREIGHT := 4
const KIND_SERVICE_OUT := 5
const KIND_SERVICE_BACK := 6
## Spawn groups (data/traffic.json "kind_by_hour") per trip kind.
const GROUP_NAMES: Array[String] = ["commute_out", "commute_back", "shopping", "freight", "service"]
const GROUP_OF_KIND: Array[int] = [0, 1, 2, 2, 3, 4, 4]
const SERVICE_CATEGORIES: Array[String] = ["garbage", "police", "health", "fire", "deathcare"]
const NO_CATEGORY := 15

@export var road_network_path: NodePath
@export var zone_system_path: NodePath
@export var building_system_path: NodePath
@export var citizen_system_path: NodePath
@export var company_system_path: NodePath
@export var service_system_path: NodePath

var graph: TrafficGraph                  # matches the current roads
var lanes := LaneGeometry.new()
var last_stats: Dictionary = {"avg_commute": 0.0, "jammed": 0, "trips": 0.0, "ms": 0}

var _net: Node
var _zones: Node
var _buildings: Node
var _citizens: Node
var _companies: Node
var _services: Node
var _cfg: Dictionary
var _types: Dictionary
var _mesh_cfg: Dictionary
var _rng := RandomNumberGenerator.new()
# Demand being gathered over several frames.
var _demand: Dictionary = {}             # Vector3i(origin seg id, dest seg id, kind * 16 + category) -> trips per day
var _demand_stage: int = 0               # 0 idle, 1 commuters, 2 homes, 3 freight, 4 ready
var _demand_cursor: int = 0
var _demand_list: Array = []
var _seg_of: Dictionary = {}             # building id -> segment id (snapshot)
# Assignment in flight / adopted.
var _job: TrafficAssignment
var _task_id: int = -1
var _since_run: float = 0.0
var _wanted: bool = true                 # a new round should start when possible
var _result_graph: TrafficGraph          # graph the adopted results belong to
var _volumes := PackedFloat32Array()
var _factors := PackedFloat32Array()
var _fwd_trees: Dictionary = {}
var _rev_trees: Dictionary = {}
var _trip_o := PackedInt32Array()        # segment ids
var _trip_d := PackedInt32Array()
var _trip_code := PackedInt32Array()     # kind * 16 + category
var _trip_count := PackedFloat32Array()
var _trip_forward := PackedByteArray()
var _trip_time := PackedFloat32Array()
var _trip_node := PackedInt32Array()
var _trip_exit := PackedInt32Array()
var _commute: Dictionary = {}            # Vector2i(home seg id, job seg id) -> minutes
var _groups: Dictionary = {}             # spawn group -> [trip indices PackedInt32Array, cumulative PackedFloat32Array]
var _jam_month: int = -1


func _ready() -> void:
	_net = get_node(road_network_path)
	_zones = get_node(zone_system_path)
	_buildings = get_node(building_system_path)
	_citizens = get_node(citizen_system_path)
	_companies = get_node(company_system_path)
	_services = get_node(service_system_path)
	_cfg = GameData.section("traffic")
	_types = GameData.section("roads/types")
	_mesh_cfg = GameData.section("roads/mesh")
	_rng.randomize()
	_rebuild_graph()
	EventBus.roads_changed.connect(_rebuild_graph)
	EventBus.ground_long_pressed.connect(_on_long_press)
	EventBus.month_changed.connect(func(_m: int) -> void: _wanted = true)


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _process(delta: float) -> void:
	if TimeSystem.get_speed_index() > 0:
		_since_run += delta
	if _task_id >= 0:
		if WorkerThreadPool.is_task_completed(_task_id):
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = -1
			_adopt(_job)
		return
	if _demand_stage > 0 and _demand_stage < 4:
		_step_demand(int(_cfg["assignment"]["demand_households_per_frame"]))
	elif _demand_stage == 4:
		_start_job(true)
	elif _wanted or _since_run >= float(_cfg["assignment"]["rerun_seconds"]):
		_wanted = false
		_since_run = 0.0
		_start_demand()


## Everything at once, without threads (tests, captures, loading screens).
func run_now() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_adopt(_job)
	_start_demand()
	while _demand_stage < 4:
		_step_demand(1 << 30)
	_start_job(false)


func _rebuild_graph() -> void:
	graph = TrafficGraph.build(_net.graph, _types, _cfg)
	lanes.rebuild(_net.graph, _types, _mesh_cfg)
	EventBus.lanes_rebuilt.emit()
	_wanted = true


# --- Demand -----------------------------------------------------------------------

func _start_demand() -> void:
	_demand = {}
	_seg_of = {}
	var grid: ZoneGrid = _zones.grid
	for id: int in _buildings.buildings:
		var cells: PackedInt32Array = _buildings.buildings[id]["cells"]
		if not cells.is_empty() and cells[0] < grid.size():
			_seg_of[id] = grid.segment[cells[0]]
	_demand_stage = 1
	_demand_cursor = 0


func _add_trip(o: int, d: int, kind: int, category: int, count: float) -> void:
	if o < 0 or d < 0 or o == d or count <= 0.0:
		return
	var key := Vector3i(o, d, kind * 16 + category)
	_demand[key] = float(_demand.get(key, 0.0)) + count


func _step_demand(budget: int) -> void:
	match _demand_stage:
		1:
			var data: HouseholdData = _citizens.data
			var per_worker := float(_cfg["trips"]["commute_per_worker"])
			var end := mini(_demand_cursor + budget, data.capacity())
			for i in range(_demand_cursor, end):
				if data.alive[i] == 0:
					continue
				var home: int = _seg_of.get(data.home[i], -1)
				if home < 0:
					continue
				for k in data.adults[i]:
					var code := data.job[i * HouseholdData.MAX_ADULTS + k]
					if code == HouseholdData.NO_JOB:
						continue
					var work: int = _seg_of.get(HouseholdData.job_company(code), -1)
					_add_trip(home, work, KIND_COMMUTE_OUT, NO_CATEGORY, per_worker)
					_add_trip(work, home, KIND_COMMUTE_BACK, NO_CATEGORY, per_worker)
			_demand_cursor = end
			if end >= data.capacity():
				_demand_stage = 2
				_demand_cursor = 0
				_demand_list = _citizens._homes.keys()
		2:
			var homes: Dictionary = _citizens._homes
			var records: Dictionary = _buildings.buildings
			var shop_rate := float(_cfg["trips"]["shopping_per_household"])
			var rates: Dictionary = _cfg["trips"]["service_per_resident"]
			var end := mini(_demand_cursor + maxi(budget / 4, 1), _demand_list.size())
			for k in range(_demand_cursor, end):
				var bid: int = _demand_list[k]
				if not homes.has(bid) or not records.has(bid):
					continue
				var home_seg: int = _seg_of.get(bid, -1)
				if home_seg < 0:
					continue
				var households := (homes[bid]["residents"] as PackedInt32Array).size()
				if households == 0:
					continue
				var shop: int = _seg_of.get(int(homes[bid]["shop"]), -1)
				_add_trip(home_seg, shop, KIND_SHOP_OUT, NO_CATEGORY, households * shop_rate)
				_add_trip(shop, home_seg, KIND_SHOP_BACK, NO_CATEGORY, households * shop_rate)
				var people := float(records[bid].get("residents", households * 2))
				for c in SERVICE_CATEGORIES.size():
					var cat := SERVICE_CATEGORIES[c]
					var by: int = _services.serving_building(cat, home_seg)
					if by < 0:
						continue
					var station: int = _seg_of.get(by, -1)
					var n := people * float(rates.get(cat, 0.0))
					_add_trip(station, home_seg, KIND_SERVICE_OUT, c, n)
					_add_trip(home_seg, station, KIND_SERVICE_BACK, c, n)
			_demand_cursor = end
			if end >= _demand_list.size():
				_demand_stage = 3
		3:
			var shops := []
			var factories := []
			for bid: int in _companies.companies:
				var kind: String = _companies.companies[bid]["kind"]
				if kind == "commercial":
					shops.append(bid)
				elif kind == "industrial":
					factories.append(bid)
			if not factories.is_empty():
				var per_shop := float(_cfg["trips"]["freight_per_shop"])
				for k in shops.size():
					var from: int = _seg_of.get(factories[k % factories.size()], -1)
					_add_trip(from, _seg_of.get(shops[k], -1), KIND_FREIGHT, NO_CATEGORY, per_shop)
			_demand_stage = 4


# --- Assignment rounds ------------------------------------------------------------

func _start_job(threaded: bool) -> void:
	_demand_stage = 0
	var job := TrafficAssignment.new()
	job.graph = graph
	job.cfg = _cfg.duplicate(true)
	var origins := PackedInt32Array()
	var dests := PackedInt32Array()
	var counts := PackedFloat32Array()
	var forwards := PackedByteArray()
	var groups := PackedInt32Array()
	var commute := PackedByteArray()
	var meta_o := PackedInt32Array()
	var meta_d := PackedInt32Array()
	var meta_code := PackedInt32Array()
	for key: Vector3i in _demand:
		if not graph.seg_index.has(key.x) or not graph.seg_index.has(key.y):
			continue
		var kind := key.z >> 4
		var forward := kind in [KIND_COMMUTE_BACK, KIND_SHOP_BACK, KIND_FREIGHT, KIND_SERVICE_OUT]
		origins.append(graph.seg_index[key.x])
		dests.append(graph.seg_index[key.y])
		counts.append(float(_demand[key]))
		forwards.append(1 if forward else 0)
		groups.append(GROUP_OF_KIND[kind])
		commute.append(1 if kind == KIND_COMMUTE_OUT else 0)
		meta_o.append(key.x)
		meta_d.append(key.y)
		meta_code.append(key.z)
	job.trip_origin = origins
	job.trip_dest = dests
	job.trip_count = counts
	job.trip_forward = forwards
	job.trip_group = groups
	job.trip_commute = commute
	job.trip_seg_o = meta_o
	job.trip_seg_d = meta_d
	job.set_meta("o", meta_o)
	job.set_meta("d", meta_d)
	job.set_meta("code", meta_code)
	if _result_graph == graph and _volumes.size() == graph.edge_count():
		job.previous = _volumes
	_job = job
	if threaded:
		_task_id = WorkerThreadPool.add_task(job.run, false, "Traffic assignment")
	else:
		job.run()
		_adopt(job)


func _adopt(job: TrafficAssignment) -> void:
	if job == null or not job.done:
		return
	if job.graph != graph:
		# Roads changed while it ran: start over on the new network.
		_wanted = true
		return
	_result_graph = job.graph
	_volumes = job.volumes
	_factors = job.factors
	_fwd_trees = job.fwd_trees
	_rev_trees = job.rev_trees
	_trip_o = job.get_meta("o")
	_trip_d = job.get_meta("d")
	_trip_code = job.get_meta("code")
	_trip_count = job.trip_count
	_trip_forward = job.trip_forward
	_trip_time = job.trip_time
	_trip_node = job.trip_node
	_trip_exit = job.trip_exit
	_commute = job.commute
	_groups = job.groups
	var jam: Dictionary = _cfg["jam"]
	last_stats = {"avg_commute": job.avg_commute, "jammed": job.jammed, "trips": job.total_trips, "ms": job.elapsed_ms}
	if job.jammed >= int(jam["min_roads"]) and TimeSystem.clock.month_index != _jam_month:
		_jam_month = TimeSystem.clock.month_index
		EventBus.notification_posted.emit("traffic", tr("NOTIFY_TRAFFIC_JAM") % job.jammed)
	EventBus.traffic_updated.emit()


# --- Queries ------------------------------------------------------------------------

func results_current() -> bool:
	return _result_graph != null and _result_graph == graph and _volumes.size() == graph.edge_count()


func _edge_ratio(e: int) -> float:
	if not results_current():
		return 0.0
	return _volumes[e] * float(_cfg["peak_hour_share"]) / maxf(graph.seg_capacity[e >> 1], 1.0)


## Peak-hour volume over capacity of the busier direction of a road.
func segment_ratio(seg_id: int) -> float:
	var s: int = graph.seg_index.get(seg_id, -1)
	if s < 0:
		return 0.0
	return maxf(_edge_ratio(s * 2), _edge_ratio(s * 2 + 1))


## Vehicles per day in both directions.
func segment_daily(seg_id: int) -> float:
	var s: int = graph.seg_index.get(seg_id, -1)
	if s < 0 or not results_current():
		return 0.0
	return _volumes[s * 2] + _volumes[s * 2 + 1]


## Current driving speed (m/s) of a road direction.
func lane_speed(seg_id: int, dir: int) -> float:
	var s: int = graph.seg_index.get(seg_id, -1)
	if s < 0:
		return 10.0
	var f := _factors[s * 2 + dir] if results_current() else 1.0
	return graph.seg_speed[s] * f


## 0..1 traffic noise along a road.
func noise(seg_id: int) -> float:
	return clampf(segment_daily(seg_id) / float(_cfg["noise"]["daily_volume_full"]), 0.0, 1.0)


## Minutes from a home's road to a workplace's road, or -1 if not known yet.
func commute_minutes(home_seg: int, job_seg: int) -> float:
	return float(_commute.get(Vector2i(home_seg, job_seg), -1.0))


func trips_ready() -> bool:
	return results_current() and not _groups.is_empty()


func trip_kind(i: int) -> int:
	return _trip_code[i] >> 4


## Service category index (SERVICE_CATEGORIES) of a trip, or -1.
func trip_category(i: int) -> int:
	var c := _trip_code[i] & 15
	return -1 if c == NO_CATEGORY else c


func _segment_mid(seg_id: int) -> Vector2:
	var s: int = graph.seg_index.get(seg_id, -1)
	if s < 0:
		return Vector2.INF
	return (graph.node_pos[graph.seg_a[s]] + graph.node_pos[graph.seg_b[s]]) * 0.5


## A trip to show as a vehicle now: a spawn group is chosen by its share of
## the day's trips and the hour, then a trip by its count. Trips that start
## or end near `focus` are preferred so the area on screen looks busy.
func pick_trip(hour: float, focus: Vector2, near_radius: float, far_accept: float) -> int:
	if _groups.is_empty():
		return -1
	var profiles: Dictionary = _cfg["kind_by_hour"]
	var weights := {}
	var total := 0.0
	for group: int in _groups:
		var w := float((_groups[group] as Array)[2]) * TrafficRules.hourly(profiles[GROUP_NAMES[group]], hour)
		weights[group] = w
		total += w
	if total <= 0.0:
		return -1
	for attempt in 6:
		var r := _rng.randf() * total
		var chosen: int = weights.keys()[0]
		for group: int in weights:
			r -= float(weights[group])
			if r <= 0.0:
				chosen = group
				break
		var entry: Array = _groups[chosen]
		var cumulative: PackedFloat32Array = entry[1]
		var target := _rng.randf() * float(entry[2])
		var idx := cumulative.bsearch(target)
		var trip: int = (entry[0] as PackedInt32Array)[mini(idx, cumulative.size() - 1)]
		var near := _segment_mid(_trip_o[trip]).distance_to(focus) < near_radius \
			or _segment_mid(_trip_d[trip]).distance_to(focus) < near_radius
		if near or _rng.randf() < far_accept:
			return trip
	return -1


## Route of a trip as directed road entries ((segment id << 1) | dir), from
## the cached shortest-time trees. Empty if routes are not ready.
func route(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not results_current() or i < 0 or i >= _trip_o.size() or _trip_node[i] < 0:
		return out
	var g := _result_graph
	var node := _trip_node[i]
	var edges := PackedInt32Array()
	if _trip_forward[i] == 1:
		var anchor: int = g.seg_index[_trip_o[i]]
		var via: PackedInt32Array = _fwd_trees.get(anchor, PackedInt32Array())
		if via.is_empty():
			return out
		var path := TrafficRules.path_to(g, via, node)
		var seed := node if path.is_empty() else g.edge_from(path[0])
		edges.append(anchor * 2 if g.seg_b[anchor] == seed else anchor * 2 + 1)
		edges.append_array(path)
		edges.append(_trip_exit[i])
	else:
		var anchor: int = g.seg_index[_trip_d[i]]
		var via: PackedInt32Array = _rev_trees.get(anchor, PackedInt32Array())
		if via.is_empty():
			return out
		var path := TrafficRules.path_from(g, via, node)
		var seed := node if path.is_empty() else g.edge_to(path[path.size() - 1])
		edges.append(_trip_exit[i])
		edges.append_array(path)
		edges.append(anchor * 2 if g.seg_a[anchor] == seed else anchor * 2 + 1)
	for e in edges:
		out.append((g.seg_ids[e >> 1] << 1) | (e & 1))
	return out


# --- Road info ------------------------------------------------------------------------

func _on_long_press(world_pos: Vector3) -> void:
	var p := Vector2(world_pos.x, world_pos.z)
	if _buildings.building_at(p) >= 0:
		return
	var hit: Dictionary = (_net.graph as RoadGraph).find_segment_near(p, 14.0)
	if hit.is_empty():
		return
	var seg: RoadGraph.RoadSegment = _net.graph.segments[hit["segment"]]
	var t: Dictionary = _types[seg.type]
	if float(hit["distance"]) > RoadTypes.half_width(t) + 1.0:
		return
	var s: int = graph.seg_index.get(seg.id, -1)
	var speed := 0.0
	if s >= 0:
		speed = minf(lane_speed(seg.id, 0), lane_speed(seg.id, 1) if graph.seg_oneway[s] == 0 else INF) * 3.6
	EventBus.road_inspected.emit({
		"type_key": t["name_key"], "lanes": RoadTypes.lane_count(t), "daily": segment_daily(seg.id),
		"ratio": segment_ratio(seg.id), "speed_kmh": speed, "limit_kmh": float(t["speed_kmh"]),
		"length": seg.length,
	})

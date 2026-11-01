extends Node3D
## Public transport: bus and tram lines the player draws (data/transit.json).
##
## Drawing: with the transit tool open, each tap on a road adds a stop
## (tapping a stop again removes it); "Bitir" closes the line into a loop
## through its stops in order, driving the shortest way between them and
## never turning round on the spot. Trams only run on avenues and
## boulevards. A line has a colour, a number of vehicles and shares one
## ticket price with every other line.
##
## Service: homes and workplaces within walking distance of a stop can ride.
## TrafficSystem asks transit_minutes() for each trip (walk + wait + ride +
## ticket in minutes) and sends some people by transit instead of by car;
## when a line has more riders than its vehicles can carry, crowding() turns
## the rest back to their cars on the next round.
##
## Vehicles: each line keeps its buses or trams driving its loop through
## VehicleSystem, spread over its stops; lost ones (road edits, quality
## changes) come back on their own. Stops have shelters, tram lines rails,
## and the lines show as coloured ribbons while drawing or on the transit
## overlay. Books: tickets in and vehicle upkeep out every month.
##
## Metro ("underground" types): stations are tapped next to any road (the
## entrance sits on the sidewalk) and the tunnel runs smoothly under
## everything, rivers included, from the first station to the last. Trains
## run there and back, so a ride is the plain distance between two
## stations. Trains stay underground (not drawn); the tunnels show on the
## transit overlay. Building costs a fee per station plus per tunnel metre.

const STOP_SHADER := preload("res://assets/materials/transit_stop.gdshader")
const CHECK_SECONDS := 0.5
const RIBBON_HEIGHT := 0.45
const RAIL_HEIGHT := 0.085
const RAIL_GAUGE := 1.435
const SPEED_FACTOR := 0.8          # average speed on the loop vs the speed limit
const WALK_DETOUR := 1.15
const TAP_PIXELS := 28.0
const MAP_AABB := AABB(Vector3(-2600, -20, -2600), Vector3(5200, 80, 5200))
const RIBBON_WIDTH := 3.2
const TUNNEL_STEP := 12.0

@export var traffic_system_path: NodePath
@export var vehicle_system_path: NodePath
@export var road_network_path: NodePath

var lines: Array = []              # see _make_line()
var ticket_price: float = 2.0
var last_report: Dictionary = {"tickets": 0.0, "upkeep": 0.0}

var _traffic: Node
var _vehicles: Node
var _net: Node
var _cfg: Dictionary
var _types: Dictionary
var _road_types: Dictionary
var _colors: Array = []
var _by_id: Dictionary = {}        # line id -> line
var _next_id: int = 1
var _cover: Dictionary = {}        # segment id -> {line id: Vector2(stop index, walk m)}
var _riders: Dictionary = {}       # line id -> rides per day (latest round)
var _raw: Dictionary = {}          # line id -> rides wanted before crowding
var _check_timer: float = 0.0
# Tool.
var _active: bool = false
var _draft_type: String = "bus"
var _draft: Array = []             # stop points (Vector2, on the road centre line)
var _draft_info: Dictionary = {}
var _down_pos := Vector2.INF
var _overlay_on: bool = false
# Visuals.
var _stop_mm: Dictionary = {}      # type -> MultiMeshInstance3D
var _rails: MeshInstance3D
var _ribbons: MeshInstance3D
var _draft_mesh: MeshInstance3D
var _ribbon_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _viaduct: MeshInstance3D
var _viaduct_mat: StandardMaterial3D
var _pillar_mm: MultiMeshInstance3D
var _platform_mm: MultiMeshInstance3D
var _trains: MultiMeshInstance3D
var _train_time: float = 0.0


func _ready() -> void:
	_traffic = get_node(traffic_system_path)
	_vehicles = get_node(vehicle_system_path)
	_net = get_node(road_network_path)
	_cfg = GameData.section("transit")
	_types = _cfg["types"]
	_road_types = GameData.section("roads/types")
	for c: String in _cfg["colors"]:
		_colors.append(DataLoader.to_color(c))
	ticket_price = float(_cfg["ticket"]["default"])
	_build_visuals()
	EventBus.lanes_rebuilt.connect(_on_lanes_rebuilt)
	EventBus.build_tool_selected.connect(_on_tool_selected)
	EventBus.tool_pointer.connect(_on_pointer)
	EventBus.mobility_reported.connect(_on_mobility)
	EventBus.month_changed.connect(_on_month)
	EventBus.overlay_selected.connect(func(key: String) -> void:
		_overlay_on = key == "transit"
		_ribbons.visible = _active or _overlay_on)


func _process(delta: float) -> void:
	_move_trains(delta)
	_check_timer += delta
	if _check_timer < CHECK_SECONDS:
		return
	_check_timer = 0.0
	# Keep every line's vehicles on the road (one more per line per check).
	for line: Dictionary in lines:
		if not line["ok"] or _open_line(line["type"]):
			continue
		var want := int(line["vehicles"])
		var have: int = _vehicles.line_vehicles(line["id"])
		if have < want:
			_spawn_on(line, int(line["spawned"]) % (line["stop_lane"] as PackedVector2Array).size())
			line["spawned"] = int(line["spawned"]) + 1
		elif have > want:
			_vehicles.despawn_line(line["id"])
			_respawn(line)


# --- Lines ------------------------------------------------------------------------

func _make_line(type: String, points: Array, color: int, number: int) -> Dictionary:
	return {
		"id": _next_id, "type": type, "number": number, "color": color, "points": points.duplicate(),
		"vehicles": int(_types[type]["default_vehicles"]), "spawned": 0,
		# Derived from the roads (not saved).
		"ok": false, "error": "", "route": PackedInt32Array(), "stop_lane": PackedVector2Array(),
		"stop_dist": PackedFloat32Array(), "stop_seg": PackedInt32Array(), "length": 0.0, "path": [],
	}


## Metro (tunnel) and train (viaduct) lines: open lines run there and back.
func _open_line(type: String) -> bool:
	var t: Dictionary = _types[type]
	return bool(t.get("underground", false)) or bool(t.get("elevated", false))


func _elevated(type: String) -> bool:
	return bool((_types[type] as Dictionary).get("elevated", false))


func is_underground(line: Dictionary) -> bool:
	return bool((_types[line["type"]] as Dictionary).get("underground", false))


## True when a train line reaches the edge of the map: the city is linked to
## the outside by rail (newcomers and tourists come even without a highway).
func has_intercity() -> bool:
	for line: Dictionary in lines:
		if line["ok"] and bool(line.get("intercity", false)) and int(line["vehicles"]) > 0:
			return true
	return false


func line_name(line: Dictionary) -> String:
	return "%s %d" % [tr(_types[line["type"]]["name_key"]), int(line["number"])]


func line_color(line: Dictionary) -> Color:
	return _colors[int(line["color"]) % _colors.size()]


func line_by_id(id: int) -> Dictionary:
	return _by_id.get(id, {})


## Rides per day on a line in the latest traffic round.
func riders(id: int) -> float:
	return float(_riders.get(id, 0.0))


## How many rides a day a line's vehicles can carry.
func capacity(line: Dictionary) -> float:
	return float(line["vehicles"]) * float(_types[line["type"]]["daily_capacity_per_vehicle"])


## Share (0..1] of would-be riders a line can take; the rest drive.
func crowding(id: int) -> float:
	var line: Dictionary = _by_id.get(id, {})
	if line.is_empty():
		return 0.0
	var raw := float(_raw.get(id, 0.0))
	return 1.0 if raw <= 0.0 else clampf(capacity(line) / raw, 0.0, 1.0)


func has_service() -> bool:
	for line: Dictionary in lines:
		if line["ok"] and int(line["vehicles"]) > 0:
			return true
	return false


func total_riders() -> float:
	var n := 0.0
	for v: float in _riders.values():
		n += v
	return n


## Seconds between two vehicles at a stop.
func headway_s(line: Dictionary) -> float:
	var t: Dictionary = _types[line["type"]]
	var cycle := float(line["length"]) / (float(t["speed_ms"]) * SPEED_FACTOR) \
		+ (line["points"] as Array).size() * float(t["dwell_s"])
	if _open_line(line["type"]):
		cycle *= 2.0   # there and back
	return cycle / maxf(float(line["vehicles"]), 1.0)


## Re-snaps the stops of every line to the current roads and re-routes them.
func _rebuild_lines() -> void:
	var g: TrafficGraph = _traffic.graph
	var rg: RoadGraph = _net.graph
	var lanes: LaneGeometry = _traffic.lanes
	for line: Dictionary in lines:
		var old: PackedInt32Array = line["route"]
		var old_stops: PackedVector2Array = line["stop_lane"]
		_route_line(line, g, rg, lanes)
		if _open_line(line["type"]):
			continue
		if line["route"] != old or line["stop_lane"] != old_stops or not line["ok"]:
			_vehicles.despawn_line(line["id"])
			if line["ok"]:
				_respawn(line)
	_rebuild_cover()
	_rebuild_visuals()


## Edge costs for a type: free-flow driving time, roads it may not use made
## very dear (a route through them is refused).
func _costs_for(type: String, g: TrafficGraph) -> PackedFloat32Array:
	var cfg := GameData.section("traffic")
	var ones := PackedFloat32Array()
	ones.resize(g.edge_count())
	ones.fill(1.0)
	var costs := TrafficRules.edge_costs(g, ones, cfg)
	var allowed: Array = _types[type]["road_types"]
	if not allowed.is_empty():
		var rg: RoadGraph = _net.graph
		var penalty := float(_cfg["off_street_penalty"])
		for s in g.seg_ids.size():
			var seg: RoadGraph.RoadSegment = rg.segments.get(g.seg_ids[s])
			if seg != null and not seg.type in allowed:
				costs[s * 2] += penalty
				costs[s * 2 + 1] += penalty
	return costs


## Snap: [segment index, t] in the TrafficGraph for a stop point, or [].
func _snap(p: Vector2, type: String, g: TrafficGraph, rg: RoadGraph) -> Array:
	var hit: Dictionary = rg.find_segment_near(p, float(_cfg["snap_radius_m"]))
	if hit.is_empty() or not g.seg_index.has(int(hit["segment"])):
		return []
	var seg: RoadGraph.RoadSegment = rg.segments[int(hit["segment"])]
	var allowed: Array = _types[type]["road_types"]
	if not allowed.is_empty() and not seg.type in allowed:
		return []
	return [int(g.seg_index[seg.id]), float(hit["t"])]


## Loop, lane positions and distances of a line on the current roads.
func _route_line(line: Dictionary, g: TrafficGraph, rg: RoadGraph, lanes: LaneGeometry) -> void:
	line["ok"] = false
	line["route"] = PackedInt32Array()
	line["stop_lane"] = PackedVector2Array()
	var stops := []
	for p: Vector2 in line["points"]:
		var snap := _snap(p, line["type"], g, rg)
		if snap.is_empty():
			line["error"] = "TRANSIT_ERR_STOP_LOST"
			return
		stops.append(snap)
	if _open_line(line["type"]):
		var path := TransitRules.tunnel_path(line["points"], TUNNEL_STEP)
		var segs := PackedInt32Array()
		for snap: Array in stops:
			segs.append(g.seg_ids[int(snap[0])])
		line["stop_seg"] = segs
		line["stop_dist"] = path["stop_dist"]
		line["length"] = float(path["length"])
		line["path"] = path["pts"]
		line["cum"] = RailVisuals.cumulative(path["pts"])
		line["ext"] = []
		line["intercity"] = false
		if _elevated(line["type"]):
			_link_outside(line)
		line["error"] = ""
		line["ok"] = true
		return
	var res := _loop(line["type"], stops, g)
	if not res["ok"]:
		line["error"] = res["error"]
		return
	var route: PackedInt32Array = res["route"]
	var stop_edge: PackedInt32Array = res["stop_edge"]
	var ids := PackedInt32Array()
	for e in route:
		ids.append((g.seg_ids[e >> 1] << 1) | (e & 1))
	var half := float(GameData.value("traffic/vehicle/half_length_m/" + str(_types[line["type"]]["model"])))
	var stop_lane := PackedVector2Array()
	var stop_seg := PackedInt32Array()
	for i in stops.size():
		var entry := ids[stop_edge[i]]
		var seg_id := entry >> 1
		var per_dir := int(_road_types[(rg.segments[seg_id] as RoadGraph.RoadSegment).type]["lanes_per_dir"])
		var pid: int = lanes.lane_pieces.get(LaneGeometry.lane_key(seg_id, entry & 1, per_dir - 1), -1)
		if pid < 0:
			line["error"] = "TRANSIT_ERR_ROUTE"
			return
		var length := lanes.piece_length[pid]
		var s := lanes.project(pid, rg.point_on(seg_id, float((stops[i] as Array)[1])))
		stop_lane.append(Vector2(stop_edge[i], clampf(s, minf(half + 1.0, length), maxf(length - 1.0, 0.0))))
		stop_seg.append(seg_id)
	line["route"] = ids
	line["stop_lane"] = stop_lane
	line["stop_seg"] = stop_seg
	line["stop_dist"] = TransitRules.stop_distances(g, route, stop_edge, stops)
	line["length"] = float(res["length"])
	line["error"] = ""
	line["ok"] = true


func _loop(type: String, stops: Array, g: TrafficGraph) -> Dictionary:
	var res := TransitRules.loop_route(g, stops, _costs_for(type, g))
	if res["ok"] and float(res["cost"]) >= float(_cfg["off_street_penalty"]):
		return {"ok": false, "error": "TRANSIT_ERR_TRAM_ROAD"}
	return res


## A train line whose first or last station is near the edge of the open
## map runs on out of it: an extra viaduct to the horizon (drawn only).
func _link_outside(line: Dictionary) -> void:
	var pts: Array = line["path"]
	if pts.size() < 2:
		return
	var half: float = ProgressionSystem.area_half()
	var reach := float(_cfg.get("intercity_reach_m", 260.0))
	for end in [0, pts.size() - 1]:
		var p: Vector2 = pts[end]
		var gap := half - maxf(absf(p.x), absf(p.y))
		if gap > reach:
			continue
		var out := Vector2(signf(p.x), 0.0) if absf(p.x) > absf(p.y) else Vector2(0.0, signf(p.y))
		var ext: Array = [p]
		var k := 30.0
		while k <= gap + 1500.0:
			ext.append(p + out * k)
			k += 30.0
		(line["ext"] as Array).append(ext)
		line["intercity"] = true


func _respawn(line: Dictionary) -> void:
	var n := (line["stop_lane"] as PackedVector2Array).size()
	if n == 0 or _open_line(line["type"]):
		line["spawned"] = int(line["vehicles"])
		return
	var want := int(line["vehicles"])
	for k in want:
		_spawn_on(line, int(float(k) * n / maxf(want, 1)) % n)
	line["spawned"] = want


func _spawn_on(line: Dictionary, stop: int) -> void:
	var t: Dictionary = _types[line["type"]]
	_vehicles.spawn_line_vehicle(line["id"], line["route"], line["stop_lane"], stop, str(t["model"]),
		line_color(line), Color(0.93, 0.94, 0.95), float(t["dwell_s"]))


## Walking distance from every road near a stop to the nearest stop of each line.
func _rebuild_cover() -> void:
	_cover = {}
	var g: TrafficGraph = _traffic.graph
	var radius := float(_cfg["walk_radius_m"])
	var mids := PackedVector2Array()
	for s in g.seg_ids.size():
		mids.append((g.node_pos[g.seg_a[s]] + g.node_pos[g.seg_b[s]]) * 0.5)
	for line: Dictionary in lines:
		if not line["ok"]:
			continue
		var id: int = line["id"]
		var points: Array = line["points"]
		var reach := float((_types[line["type"]] as Dictionary).get("walk_radius_m", radius))
		for i in points.size():
			var p: Vector2 = points[i]
			for s in mids.size():
				var d := mids[s].distance_to(p) * WALK_DETOUR
				if d > reach:
					continue
				var sid := g.seg_ids[s]
				if not _cover.has(sid):
					_cover[sid] = {}
				var entry: Dictionary = _cover[sid]
				if not entry.has(id) or d < (entry[id] as Vector2).y:
					entry[id] = Vector2(i, d)


## Best transit trip between two roads: Vector3(generalised minutes incl. the
## ticket, line id, travel minutes), or x = -1 when no line serves both.
func transit_minutes(o: int, d: int) -> Vector3:
	var best := Vector3(-1.0, -1.0, -1.0)
	var co: Dictionary = _cover.get(o, {})
	if co.is_empty():
		return best
	var cd: Dictionary = _cover.get(d, {})
	var walk_speed := float(_cfg["walk_speed_ms"])
	var money := ticket_price / float(_cfg["mode_choice"]["money_per_minute"])
	for id: int in co:
		if not cd.has(id):
			continue
		var a: Vector2 = co[id]
		var b: Vector2 = cd[id]
		if int(a.x) == int(b.x):
			continue
		var line: Dictionary = _by_id[id]
		if int(line["vehicles"]) <= 0:
			continue
		var t: Dictionary = _types[line["type"]]
		var dist: PackedFloat32Array = line["stop_dist"]
		var n := dist.size()
		var ride := TransitRules.along(dist[int(a.x)], dist[int(b.x)], float(line["length"]))
		var hops := posmod(int(b.x) - int(a.x), n)
		if _open_line(line["type"]):
			ride = TransitRules.shuttle(dist[int(a.x)], dist[int(b.x)])
			hops = absi(int(b.x) - int(a.x))
		var seconds := (a.y + b.y) / walk_speed + headway_s(line) * 0.5 \
			+ ride / (float(t["speed_ms"]) * SPEED_FACTOR) + maxi(hops - 1, 0) * float(t["dwell_s"])
		var minutes := seconds / 60.0
		if best.x < 0.0 or minutes + money < best.x:
			best = Vector3(minutes + money, id, minutes)
	return best


## 0..1: how close a road is to a stop (transit overlay).
func segment_access(sid: int) -> float:
	var best := 0.0
	var radius := float(_cfg["walk_radius_m"])
	for v: Vector2 in (_cover.get(sid, {}) as Dictionary).values():
		best = maxf(best, 1.0 - v.y / radius)
	return best


# --- Editing ---------------------------------------------------------------------------

func set_vehicles(id: int, count: int) -> void:
	var line: Dictionary = _by_id.get(id, {})
	if line.is_empty():
		return
	var n := clampi(count, 1, int(_types[line["type"]]["max_vehicles"]))
	if n == int(line["vehicles"]):
		return
	line["vehicles"] = n
	if line["ok"] and not _open_line(line["type"]):
		_vehicles.despawn_line(id)
		_respawn(line)
	EventBus.transit_changed.emit()


func set_ticket(price: float) -> void:
	var t: Dictionary = _cfg["ticket"]
	ticket_price = clampf(snappedf(price, float(t["step"])), float(t["min"]), float(t["max"]))
	EventBus.transit_changed.emit()


func delete_line(id: int) -> void:
	var line: Dictionary = _by_id.get(id, {})
	if line.is_empty():
		return
	_vehicles.despawn_line(id)
	lines.erase(line)
	_by_id.erase(id)
	_riders.erase(id)
	_raw.erase(id)
	_rebuild_cover()
	_rebuild_visuals()
	EventBus.transit_changed.emit()


func draft_cost(type: String, stops: int, length: float = 0.0) -> int:
	var t: Dictionary = _types[type]
	return int(t["line_cost"]) + stops * int(t["stop_cost"]) + int(length * float(t.get("track_cost_per_m", t.get("tunnel_cost_per_m", 0.0))))


## Opens the line being drawn as a real line. Returns false (and posts the
## reason in the draft info) if it cannot be built.
func finish_draft() -> bool:
	_update_draft()
	if not bool(_draft_info.get("ok", false)):
		if str(_draft_info.get("error", "")) == "":
			_draft_info["error"] = "TRANSIT_ERR_STOPS"
		EventBus.transit_draft_changed.emit(_draft_info)
		return false
	if lines.size() >= int(_cfg["max_lines"]):
		_draft_info["error"] = "TRANSIT_ERR_MAX_LINES"
		EventBus.transit_draft_changed.emit(_draft_info)
		return false
	var cost := draft_cost(_draft_type, _draft.size(), float(_draft_info.get("length", 0.0)))
	if not EconomySystem.try_spend(cost):
		_draft_info["error"] = "ROAD_ERR_MONEY"
		EventBus.transit_draft_changed.emit(_draft_info)
		return false
	var line := _make_line(_draft_type, _draft, _free_color(), _free_number(_draft_type))
	_next_id += 1
	lines.append(line)
	_by_id[line["id"]] = line
	_route_line(line, _traffic.graph, _net.graph, _traffic.lanes)
	if line["ok"]:
		_respawn(line)
	_draft = []
	_update_draft()
	_rebuild_cover()
	_rebuild_visuals()
	EventBus.transit_changed.emit()
	EventBus.sfx_requested.emit("build_place")
	EventBus.notification_posted.emit("transit", tr("NOTIFY_LINE_OPENED") % line_name(line))
	return true


func cancel_draft() -> void:
	_draft = []
	_update_draft()


func _free_color() -> int:
	var used := {}
	for line: Dictionary in lines:
		used[int(line["color"])] = true
	for i in _colors.size():
		if not used.has(i):
			return i
	return lines.size() % _colors.size()


func _free_number(type: String) -> int:
	var used := {}
	for line: Dictionary in lines:
		if line["type"] == type:
			used[int(line["number"])] = true
	var n := 1
	while used.has(n):
		n += 1
	return n


func _on_tool_selected(tool: String, options: Dictionary) -> void:
	var was := _active
	_active = tool == "transit"
	if _active:
		var type := str(options.get("type", _draft_type))
		if type != _draft_type:
			_draft_type = type
			_draft = []
		_update_draft()
	elif was:
		_draft = []
		_update_draft()
	_ribbons.visible = _active or _overlay_on


func _on_pointer(phase: int, screen_pos: Vector2) -> void:
	if not _active:
		return
	if phase == GestureTracker.Pointer.DOWN:
		_down_pos = screen_pos
	elif phase == GestureTracker.Pointer.UP:
		if _down_pos != Vector2.INF and _down_pos.distance_to(screen_pos) <= TAP_PIXELS:
			var g: Variant = _ground(screen_pos)
			if g != null:
				toggle_stop(g)
		_down_pos = Vector2.INF
	elif phase == GestureTracker.Pointer.CANCEL:
		_down_pos = Vector2.INF


## Adds a stop at the road nearest to p, or removes the draft stop there.
func toggle_stop(p: Vector2) -> void:
	var spacing := float((_types[_draft_type] as Dictionary).get("min_stop_spacing_m", _cfg["min_stop_spacing_m"]))
	for i in _draft.size():
		if (_draft[i] as Vector2).distance_to(p) < spacing * 0.5:
			_draft.remove_at(i)
			_update_draft()
			return
	var rg: RoadGraph = _net.graph
	var hit: Dictionary = rg.find_segment_near(p, float(_cfg["snap_radius_m"]))
	var error := ""
	if hit.is_empty():
		error = "TRANSIT_ERR_ROAD"
	elif _draft.size() >= int(_cfg["max_stops"]):
		error = "TRANSIT_ERR_MAX_STOPS"
	else:
		var allowed: Array = _types[_draft_type]["road_types"]
		var seg: RoadGraph.RoadSegment = rg.segments[int(hit["segment"])]
		if not allowed.is_empty() and not seg.type in allowed:
			error = "TRANSIT_ERR_TRAM_ROAD"
		else:
			for q: Vector2 in _draft:
				if q.distance_to(hit["point"]) < spacing:
					error = "TRANSIT_ERR_SPACING"
	if error != "":
		_update_draft()
		_draft_info["error"] = error
		EventBus.sfx_requested.emit("error")
		EventBus.transit_draft_changed.emit(_draft_info)
		return
	_draft.append(hit["point"])
	EventBus.sfx_requested.emit("ui_click")
	_update_draft()


func _update_draft() -> void:
	var info := {"type": _draft_type, "stops": _draft.size(), "cost": draft_cost(_draft_type, _draft.size()),
		"ok": false, "error": "", "length": 0.0}
	var route_pts: Array = []
	if _open_line(_draft_type):
		var all_snapped := true
		for p: Vector2 in _draft:
			if _snap(p, _draft_type, _traffic.graph, _net.graph).is_empty():
				all_snapped = false
		if _draft.size() >= 2:
			var path := TransitRules.tunnel_path(_draft, TUNNEL_STEP)
			route_pts = path["pts"]
			info["length"] = float(path["length"])
			info["cost"] = draft_cost(_draft_type, _draft.size(), float(path["length"]))
			info["ok"] = all_snapped
			if not all_snapped:
				info["error"] = "TRANSIT_ERR_STOP_LOST"
	elif _draft.size() >= 2:
		var g: TrafficGraph = _traffic.graph
		var rg: RoadGraph = _net.graph
		var stops := []
		for p: Vector2 in _draft:
			var snap := _snap(p, _draft_type, g, rg)
			if not snap.is_empty():
				stops.append(snap)
		var res := _loop(_draft_type, stops, g)
		if res["ok"] and stops.size() == _draft.size():
			info["ok"] = true
			info["length"] = float(res["length"])
			var ids := PackedInt32Array()
			for e in res["route"]:
				ids.append((g.seg_ids[e >> 1] << 1) | (e & 1))
			route_pts = _route_polyline(ids)
		else:
			info["error"] = res.get("error", "TRANSIT_ERR_ROUTE")
	_draft_info = info
	_rebuild_draft_mesh(route_pts)
	EventBus.transit_draft_changed.emit(info)


# --- Ridership and books ------------------------------------------------------------

func _on_mobility(report: Dictionary) -> void:
	_riders = (report.get("riders", {}) as Dictionary).duplicate()
	_raw = (report.get("raw", {}) as Dictionary).duplicate()


func _on_month(_m: int) -> void:
	var upkeep := 0.0
	for line: Dictionary in lines:
		upkeep += float(line["vehicles"]) * float(_types[line["type"]]["upkeep_per_vehicle"])
	# One game day is one month: the day's rides are the month's tickets.
	last_report = {"tickets": total_riders() * ticket_price, "upkeep": upkeep}
	EventBus.transit_reported.emit(last_report.duplicate())


# --- Visuals ----------------------------------------------------------------------------

func _build_visuals() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = STOP_SHADER
	for type: String in ["bus", "tram", "metro"]:
		var mesh: ArrayMesh = VehicleModels.bus_stop() if type == "bus" else (VehicleModels.tram_stop() if type == "tram" else VehicleModels.metro_entrance())
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		# The bounds of an instance created empty are not refreshed when stops
		# are added later, so it would be culled.
		mm.custom_aabb = MAP_AABB
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Stops_" + type
		mmi.multimesh = mm
		add_child(mmi)
		_stop_mm[type] = mmi
	_rail_mat = StandardMaterial3D.new()
	_rail_mat.vertex_color_use_as_albedo = true
	_rail_mat.metallic = 0.6
	_rail_mat.roughness = 0.4
	_rails = MeshInstance3D.new()
	_rails.name = "TramRails"
	_rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rails)
	_ribbon_mat = StandardMaterial3D.new()
	_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_mat.vertex_color_use_as_albedo = true
	# Opaque: see-through ribbons get sorted under the overlay tints.
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbons = MeshInstance3D.new()
	_ribbons.name = "LineRibbons"
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbons.visible = false
	add_child(_ribbons)
	_viaduct_mat = RailVisuals.material()
	_viaduct = MeshInstance3D.new()
	_viaduct.name = "Viaducts"
	add_child(_viaduct)
	_pillar_mm = _instances("ViaductPillars", RailVisuals.pillar_mesh(), false)
	_platform_mm = _instances("TrainPlatforms", RailVisuals.platform_mesh(), false)
	_trains = _instances("Trains", RailVisuals.car_mesh(), true)
	_trains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draft_mesh = MeshInstance3D.new()
	_draft_mesh.name = "DraftLine"
	_draft_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_draft_mesh)


func _instances(node_name: String, mesh: Mesh, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.custom_aabb = MAP_AABB
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


## World polyline (Vector2) a vehicle follows along a route of entries.
func _route_polyline(ids: PackedInt32Array) -> Array:
	var lanes: LaneGeometry = _traffic.lanes
	var rg: RoadGraph = _net.graph
	var pts: Array = []
	for k in ids.size():
		var entry := ids[k]
		var seg: RoadGraph.RoadSegment = rg.segments.get(entry >> 1)
		if seg == null:
			continue
		var per_dir := int(_road_types[seg.type]["lanes_per_dir"])
		var key := LaneGeometry.lane_key(entry >> 1, entry & 1, per_dir - 1)
		var pid: int = lanes.lane_pieces.get(key, -1)
		if pid >= 0:
			pts.append_array(lanes.points(pid))
		var nxt := ids[(k + 1) % ids.size()]
		var nseg: RoadGraph.RoadSegment = rg.segments.get(nxt >> 1)
		if nseg == null:
			continue
		var node := seg.b if (entry & 1) == 0 else seg.a
		var nkey := LaneGeometry.lane_key(nxt >> 1, nxt & 1, int(_road_types[nseg.type]["lanes_per_dir"]) - 1)
		var cpid: int = lanes.conn_pieces.get(Vector3i(node, key, nkey), -1)
		if cpid >= 0:
			pts.append_array(lanes.points(cpid))
	return pts


func _on_lanes_rebuilt() -> void:
	_rebuild_lines()
	if _active:
		_update_draft()


func _rebuild_visuals() -> void:
	var rg: RoadGraph = _net.graph
	var per_type := {"bus": [], "tram": [], "metro": []}
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_ribbon := false
	var any_rail := false
	var any_viaduct := false
	var viaduct := SurfaceTool.new()
	viaduct.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pillars: Array = []
	var platforms: Array = []
	for line: Dictionary in lines:
		if not line["ok"]:
			continue
		var route: PackedInt32Array = line["route"]
		var stop_lane: PackedVector2Array = line["stop_lane"]
		var points: Array = line["points"]
		var color := line_color(line)
		if _open_line(line["type"]):
			if _elevated(line["type"]):
				_train_visuals(line, color, viaduct, pillars, platforms, ribbon)
				any_viaduct = true
			else:
				_metro_visuals(line, color, per_type["metro"], ribbon)
			any_ribbon = true
			continue
		for i in stop_lane.size():
			var entry := route[int(stop_lane[i].x)]
			var seg: RoadGraph.RoadSegment = rg.segments.get(entry >> 1)
			if seg == null:
				continue
			var t: float = rg.closest_t(rg.nodes[seg.a].pos, seg.control, rg.nodes[seg.b].pos, points[i])
			var p := rg.point_on(seg.id, t)
			var d := rg.tangent_on(seg.id, t)
			if (entry & 1) == 1:
				d = -d
			var right := Vector2(-d.y, d.x)
			var rt: Dictionary = _road_types[seg.type]
			# On the sidewalk to the right of the driving direction, facing the road.
			var c := p + right * (RoadTypes.carriageway_width(rt) * 0.5 + float(rt["sidewalk_width_m"]) * 0.5)
			var z := Vector3(-right.x, 0.0, -right.y)
			var x := Vector3.UP.cross(z)
			var depth := clampf(float(rt["sidewalk_width_m"]) / 2.0, 0.45, 1.0)
			(per_type[line["type"]] as Array).append([Transform3D(Basis(x, Vector3.UP, z * depth), Vector3(c.x, 0.0, c.y)), color])
		var pts := _route_polyline(route)
		if pts.size() >= 2:
			_strip(ribbon, pts, 0.0, RIBBON_WIDTH, RIBBON_HEIGHT, Color(color, 0.95), true)
			any_ribbon = true
			if line["type"] == "tram":
				# Grooved rails: a dark channel in the asphalt with a bright steel head.
				for side in [-0.5, 0.5]:
					_strip(rails, pts, side * RAIL_GAUGE, 0.34, RAIL_HEIGHT, Color(0.13, 0.13, 0.14), true)
					_strip(rails, pts, side * RAIL_GAUGE, 0.1, RAIL_HEIGHT + 0.006, Color(0.78, 0.79, 0.82), true)
				any_rail = true
	for type: String in per_type:
		var mm := (_stop_mm[type] as MultiMeshInstance3D).multimesh
		var list: Array = per_type[type]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
	_viaduct.mesh = viaduct.commit() if any_viaduct else null
	if any_viaduct:
		_viaduct.mesh.surface_set_material(0, _viaduct_mat)
	for pair: Array in [[_pillar_mm, pillars], [_platform_mm, platforms]]:
		var mm := (pair[0] as MultiMeshInstance3D).multimesh
		var list: Array = pair[1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
	if any_ribbon:
		var m := ribbon.commit()
		m.surface_set_material(0, _ribbon_mat)
		_ribbons.mesh = m
	else:
		_ribbons.mesh = null
	if any_rail:
		rails.generate_normals()
		var m := rails.commit()
		m.surface_set_material(0, _rail_mat)
		_rails.mesh = m
	else:
		_rails.mesh = null


## Viaduct (stations section and any outside link), pillars where the
## ground is free (not on roads or buildings) and a platform per station.
func _train_visuals(line: Dictionary, color: Color, viaduct: SurfaceTool, pillars: Array, platforms: Array, ribbon: SurfaceTool) -> void:
	var rg: RoadGraph = _net.graph
	var bsys: Node = get_parent().get_node_or_null("BuildingSystem")
	var runs: Array = [line["path"]]
	runs.append_array(line["ext"])
	for pts: Array in runs:
		if pts.size() < 2:
			continue
		RailVisuals.add_viaduct(viaduct, pts)
		var cum := RailVisuals.cumulative(pts)
		var s := 6.0
		while s < cum[cum.size() - 1]:
			var at: Array = RailVisuals.sample(pts, cum, s)
			var p: Vector2 = at[0]
			var d: Vector2 = at[1]
			var free := rg.find_segment_near(p, 9.0).is_empty() and not MapWater.shared().is_water(p, -2.0)
			if free and bsys != null and int(bsys.call("building_at", p)) >= 0:
				free = false
			if free:
				var z := Vector3(d.x, 0, d.y)
				pillars.append(Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP * (RailVisuals.DECK_Y - RailVisuals.DECK_THICK), z), Vector3(p.x, 0, p.y)))
			s += 32.0
	var stop_dist: PackedFloat32Array = line["stop_dist"]
	for i in stop_dist.size():
		var at: Array = RailVisuals.sample(line["path"], line["cum"], stop_dist[i])
		var p: Vector2 = at[0]
		var d: Vector2 = at[1]
		var z := Vector3(d.x, 0, d.y)
		platforms.append(Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), Vector3(p.x, 0, p.y)))
	var path: Array = line["path"]
	if path.size() >= 2:
		_strip(ribbon, path, 0.0, RIBBON_WIDTH * 2.0 + 3.0, RIBBON_HEIGHT, color.darkened(0.6), true)
		_strip(ribbon, path, 0.0, RIBBON_WIDTH * 2.0, RIBBON_HEIGHT + 0.08, color, true)


## Moves every train along its viaduct, there and back (cars follow the path).
func _move_trains(delta: float) -> void:
	var mult := float((GameData.value("time/speed_multipliers") as Array)[TimeSystem.get_speed_index()])
	_train_time += delta * mult
	var xforms: Array = []
	var colors: Array = []
	for line: Dictionary in lines:
		if not line["ok"] or not _elevated(line["type"]):
			continue
		var pts: Array = line["path"]
		var cum: PackedFloat32Array = line["cum"]
		var length := float(line["length"])
		if length < 1.0:
			continue
		var speed := float(_types[line["type"]]["speed_ms"]) * SPEED_FACTOR
		var n := int(line["vehicles"])
		var cars := int(_types[line["type"]].get("cars", 3))
		var tint := line_color(line).lightened(0.35)
		for k in n:
			var s := fposmod(_train_time * speed + k * 2.0 * length / maxf(n, 1), 2.0 * length)
			var forward := s < length
			var head := s if forward else 2.0 * length - s
			for c in cars:
				var along := head - (c * (RailVisuals.CAR_LENGTH + RailVisuals.CAR_GAP) + RailVisuals.CAR_LENGTH * 0.5) * (1.0 if forward else -1.0)
				var at: Array = RailVisuals.sample(pts, cum, along)
				var p: Vector2 = at[0]
				var d: Vector2 = at[1] if forward else -(at[1] as Vector2)
				var right := Vector2(-d.y, d.x)
				p += right * 1.6
				var z := Vector3(d.x, 0, d.y)
				xforms.append(Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), Vector3(p.x, RailVisuals.DECK_Y + 0.15, p.y)))
				colors.append(tint)
	var mm := _trains.multimesh
	if mm.instance_count != xforms.size():
		mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])


## Station entrances on the sidewalk and the tunnel drawn as a dark-edged
## ribbon (seen only on the transit overlay).
func _metro_visuals(line: Dictionary, color: Color, out: Array, ribbon: SurfaceTool) -> void:
	var rg: RoadGraph = _net.graph
	for p: Vector2 in line["points"]:
		var hit: Dictionary = rg.find_segment_near(p, float(_cfg["snap_radius_m"]))
		if hit.is_empty():
			continue
		var seg: RoadGraph.RoadSegment = rg.segments[int(hit["segment"])]
		# Keep the entrance off the junction and its crossings.
		var keep := minf(16.0 / maxf(seg.length, 1.0), 0.5)
		var t := clampf(float(hit["t"]), keep, 1.0 - keep)
		var at := rg.point_on(seg.id, t)
		var d := rg.tangent_on(seg.id, t)
		var right := Vector2(-d.y, d.x)
		var rt: Dictionary = _road_types[seg.type]
		var c := at + right * (RoadTypes.carriageway_width(rt) * 0.5 + float(rt["sidewalk_width_m"]) * 0.5)
		var z := Vector3(-right.x, 0.0, -right.y)
		var x := Vector3.UP.cross(z)
		var depth := clampf(float(rt["sidewalk_width_m"]) / 2.4, 0.5, 1.0)
		out.append([Transform3D(Basis(x, Vector3.UP, z * depth), Vector3(c.x, 0.0, c.y)), color])
	var pts: Array = line["path"]
	if pts.size() >= 2:
		_strip(ribbon, pts, 0.0, RIBBON_WIDTH * 2.0 + 3.0, RIBBON_HEIGHT, color.darkened(0.6), true)
		_strip(ribbon, pts, 0.0, RIBBON_WIDTH * 2.0, RIBBON_HEIGHT + 0.08, color, true)


func _rebuild_draft_mesh(route_pts: Array) -> void:
	if not _active or _draft.is_empty():
		_draft_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col: Color = _colors[_free_color()]
	if route_pts.size() >= 2:
		_strip(st, route_pts, 0.0, RIBBON_WIDTH, RIBBON_HEIGHT + 0.05, Color(col, 0.85), true)
	# A marker disc per stop.
	for p: Vector2 in _draft:
		var n := 16
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var y := RIBBON_HEIGHT + 0.1
			st.set_color(Color(1, 1, 1, 0.95))
			st.add_vertex(Vector3(p.x, y, p.y))
			st.set_color(Color(col, 0.95))
			st.add_vertex(Vector3(p.x + cos(a1) * 4.5, y, p.y + sin(a1) * 4.5))
			st.set_color(Color(col, 0.95))
			st.add_vertex(Vector3(p.x + cos(a0) * 4.5, y, p.y + sin(a0) * 4.5))
	var m := st.commit()
	m.surface_set_material(0, _ribbon_mat)
	_draft_mesh.mesh = m


## Flat strip of `width` along a polyline, shifted sideways by `offset`.
func _strip(st: SurfaceTool, pts: Array, offset: float, width: float, y: float, color: Color, use_color: bool) -> void:
	var n := pts.size()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for k in n:
		var p: Vector2 = pts[k]
		var a: Vector2 = pts[maxi(k - 1, 0)]
		var b: Vector2 = pts[mini(k + 1, n - 1)]
		var d := (b - a).normalized()
		if d == Vector2.ZERO:
			continue
		var left := Vector2(d.y, -d.x)
		var c := p + left * offset
		var l := Vector3(c.x + left.x * width * 0.5, y, c.y + left.y * width * 0.5)
		var r := Vector3(c.x - left.x * width * 0.5, y, c.y - left.y * width * 0.5)
		if k > 0 and prev_l.distance_to(l) < 20.0:
			# Clockwise seen from above (Godot's front face).
			for v: Vector3 in [prev_l, r, prev_r, prev_l, l, r]:
				if use_color:
					st.set_color(color)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)
		prev_l = l
		prev_r = r


func _ground(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	return null if hit == null else Vector2((hit as Vector3).x, (hit as Vector3).z)


# --- Saving ---------------------------------------------------------------------------

func save_state() -> Dictionary:
	var out := []
	for line: Dictionary in lines:
		out.append({"id": line["id"], "type": line["type"], "number": line["number"], "color": line["color"],
			"points": line["points"], "vehicles": line["vehicles"]})
	return {"lines": out, "next_id": _next_id, "ticket": ticket_price}


func load_state(state: Dictionary) -> void:
	for line: Dictionary in lines:
		_vehicles.despawn_line(line["id"])
	lines = []
	_by_id = {}
	_next_id = int(state.get("next_id", 1))
	ticket_price = float(state.get("ticket", _cfg["ticket"]["default"]))
	for rec: Dictionary in state.get("lines", []):
		var type := str(rec.get("type", "bus"))
		if not _types.has(type):
			continue
		var saved_next := _next_id
		_next_id = int(rec["id"])
		var line := _make_line(type, rec.get("points", []), int(rec.get("color", 0)), int(rec.get("number", 1)))
		_next_id = saved_next
		line["vehicles"] = int(rec.get("vehicles", line["vehicles"]))
		lines.append(line)
		_by_id[line["id"]] = line
	_rebuild_lines()
	EventBus.transit_changed.emit()

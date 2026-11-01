extends Node3D
## Visible traffic: a sample of the day's trips driven along their cached
## routes, lane by lane, stopping at red lights, in queues and at their
## destination.
##
## Simulation LOD (three tiers):
##  * near: vehicles within the draw distance of the camera are drawn, one
##    MultiMesh per model, moved entirely in vehicle.gdshader;
##  * far: vehicles further away still drive as data (their events run) but
##    the shader collapses them, so they cost nothing to draw;
##  * statistical: every trip of the day, shown or not, is counted by the
##    TrafficSystem assignment that sets road speeds and commute times.
## The number of vehicles follows the time of day up to the cap of the
## graphics preset, and trips near the camera are preferred.
##
## Movement is event driven: the CPU acts only when a vehicle reaches the end
## of a lane piece, a light changes or a queue moves, and then rewrites that
## one instance (start position, start time, speed, stop position). Lights:
## junctions flagged lit by the TrafficGraph cycle two signal groups.
##
## Buses and trams (TransitSystem) are the same kind of vehicle on a looping
## route: they keep to the curb lane, stop at each of their stops for a while
## and never despawn on their own.

const SHADER := preload("res://assets/materials/vehicle.gdshader")
const LIGHT_SHADER := preload("res://assets/materials/traffic_light.gdshader")
const FREE := 1e6
const REBASE_AFTER := 3000.0
const MAP_AABB := AABB(Vector3(-2600, -20, -2600), Vector3(5200, 80, 5200))

@export var traffic_system_path: NodePath

var active: int = 0
var line_active: int = 0     # of which buses and trams
var _line_count: Dictionary = {}   # line id -> vehicles serving it
var trips_done: int = 0      # vehicles that reached their destination
var trips_lost: int = 0      # vehicles removed because their route broke

var _traffic: Node
var _cfg: Dictionary
var _veh: Dictionary
var _lights_cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _cap: int = 0
var _material: ShaderMaterial
var _lane_tex: ImageTexture
var _height_tex: ImageTexture
var _models: Array[String] = VehicleModels.NAMES
var _model_index: Dictionary = {}
var _mm: Array = []                # per model: MultiMeshInstance3D
var _slot_free: Array = []         # per model: Array of free slots (kept sorted, smallest last)
var _slot_used: Array = []         # per model: PackedByteArray
var _slot_high := PackedInt32Array()
var _speed_mult: Array
var _accel_time: float
var _softness: float
var _gap: float
var _half_by_model := PackedFloat32Array()
var _margin: float
var _reaction: float
var _paint: Array = []
var _paint_total: float = 0.0
var _blocked_timer: float = 0.0
var _focus := Vector2.ZERO
var _near: float = 450.0
var _lights: MultiMeshInstance3D
# Vehicles, struct of arrays (id = index; ids are reused).
var _alive := PackedByteArray()
var _model := PackedInt32Array()
var _slot := PackedInt32Array()
var _route: Array = []             # PackedInt32Array of (segment id << 1) | dir
var _leg := PackedInt32Array()
var _piece := PackedInt32Array()
var _pkey: Array = []              # stable key of the current piece
var _on_conn := PackedByteArray()
var _lane := PackedInt32Array()
var _npiece := PackedInt32Array()  # on a lane: the connector ahead; on a connector: the lane ahead
var _nlane := PackedInt32Array()
var _s0 := PackedFloat32Array()
var _t0 := PackedFloat32Array()
var _v := PackedFloat32Array()
var _stop := PackedFloat32Array()
var _accel := PackedFloat32Array()
var _end_s := PackedFloat32Array()
var _wait := PackedByteArray()
var _line := PackedInt32Array()    # transit line id, -1 for ordinary traffic
var _stops: Array = []             # line vehicles: PackedVector2Array of (route index, lane distance)
var _next_stop := PackedInt32Array()
var _dwell := PackedFloat32Array()
var _dwell_s := PackedFloat32Array()  # lane distance of the stop ahead on this road, -1 if none
var _half := PackedFloat32Array()  # half the vehicle length
var _ver := PackedInt32Array()
var _color := PackedColorArray()
var _second := PackedColorArray()
var _beacon := PackedByteArray()
var _seed := PackedFloat32Array()
var _free_ids: Array = []
# Event heap: time, vehicle id, version.
var _ev_t := PackedFloat32Array()
var _ev_id := PackedInt32Array()
var _ev_ver := PackedInt32Array()
# Lanes and junctions.
var _fifo: Dictionary = {}         # lane piece id -> Array of vehicle ids, head first
var _blocked: Dictionary = {}      # vehicle id -> true while the lane ahead is full
var _seg_lanes: Dictionary = {}    # segment id -> lanes per direction
var _seg_end: Dictionary = {}      # segment id -> Vector2i(node a, node b)
var _junctions: Array = []         # {legs, groups, phase, state, next, slots}
var _junction_of: Dictionary = {}  # incoming lane piece id -> Vector2i(junction, leg)


func _ready() -> void:
	_traffic = get_node(traffic_system_path)
	_cfg = GameData.section("traffic")
	_veh = _cfg["vehicle"]
	_lights_cfg = _cfg["lights"]
	_speed_mult = GameData.value("time/speed_multipliers")
	_accel_time = float(_veh["accel_time_s"])
	_softness = float(_veh["stop_softness_m"])
	_gap = float(_veh["gap_m"])
	_margin = float(_veh["stop_margin_m"])
	_reaction = float(_veh["reaction_s"])
	_rng.randomize()
	for i in _models.size():
		_model_index[_models[i]] = i
		_half_by_model.append(float(_veh["half_length_m"].get(_models[i], 2.3)))
	var acc := 0.0
	for entry: Array in _cfg["paint"]:
		acc += float(entry[1])
		_paint.append([DataLoader.to_color(entry[0]), acc])
	_paint_total = acc
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("accel_time", _accel_time)
	_material.set_shader_parameter("stop_softness", _softness)
	_material.set_shader_parameter("road_height", float(_veh["road_height_m"]))
	var light_mat := ShaderMaterial.new()
	light_mat.shader = LIGHT_SHADER
	var light_mesh := VehicleModels.traffic_light()
	light_mesh.surface_set_material(0, light_mat)
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.use_custom_data = true
	lmm.mesh = light_mesh
	_lights = MultiMeshInstance3D.new()
	_lights.name = "TrafficLights"
	_lights.multimesh = lmm
	add_child(_lights)
	_apply_preset(GraphicsSettings.current_preset)
	EventBus.lanes_rebuilt.connect(_on_lanes_rebuilt)
	EventBus.graphics_preset_changed.connect(_apply_preset)
	_on_lanes_rebuilt()


func _process(delta: float) -> void:
	var mult := float(_speed_mult[TimeSystem.get_speed_index()])
	_time += delta * mult
	RenderingServer.global_shader_parameter_set("traffic_time", _time)
	if mult <= 0.0:
		return
	_update_focus()
	_update_lights()
	_process_events()
	_blocked_timer += delta
	if _blocked_timer > 0.3:
		_blocked_timer = 0.0
		_retry_blocked()
	_spawn_some()
	if _time > REBASE_AFTER:
		_rebase_time()


## Runs the traffic forward by `seconds` of traffic time in steps (captures).
func advance(seconds: float, step: float = 0.1) -> void:
	var t := 0.0
	while t < seconds:
		t += step
		_time += step
		_update_lights()
		_process_events()
		_retry_blocked()
		_spawn_some()
	RenderingServer.global_shader_parameter_set("traffic_time", _time)


# --- Setup ----------------------------------------------------------------------

func _apply_preset(_preset: String) -> void:
	var cap := int(GraphicsSettings.get_value("vehicle_cap"))
	_material.set_shader_parameter("hide_distance", float(GraphicsSettings.get_value("vehicle_draw_distance_m")))
	if cap == _cap:
		return
	_cap = cap
	for v in _alive.size():
		if _alive[v] == 1:
			_despawn(v, false)
	_fifo.clear()
	_blocked.clear()
	for mmi: MultiMeshInstance3D in _mm:
		mmi.queue_free()
	_mm.clear()
	_slot_free.clear()
	_slot_used.clear()
	_slot_high = PackedInt32Array()
	var shares: Dictionary = _cfg["models"]["capacity_share"]
	for name in _models:
		var minimum: Dictionary = _cfg["models"].get("capacity_min", {})
		var capacity := maxi(maxi(ceili(_cap * float(shares.get(name, 0.1))), int(minimum.get(name, 4))), 4)
		var mesh := VehicleModels.build(name)
		mesh.surface_set_material(0, _material)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = capacity
		mm.visible_instance_count = 0
		mm.custom_aabb = MAP_AABB
		for i in capacity:
			mm.set_instance_transform(i, _hidden_transform())
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Vehicles_" + name
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mm.append(mmi)
		var free := []
		for i in range(capacity - 1, -1, -1):
			free.append(i)
		_slot_free.append(free)
		var used := PackedByteArray()
		used.resize(capacity)
		_slot_used.append(used)
		_slot_high.append(0)


func _hidden_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(FREE, 0, 0))


func _on_lanes_rebuilt() -> void:
	var lg: LaneGeometry = _traffic.lanes
	var img := lg.image()
	if _lane_tex == null or _lane_tex.get_height() != img.get_height():
		_lane_tex = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("lanes", _lane_tex)
	else:
		_lane_tex.update(img)
	var himg := lg.height_image()
	if _height_tex == null or _height_tex.get_height() != himg.get_height():
		_height_tex = ImageTexture.create_from_image(himg)
		_material.set_shader_parameter("lane_heights", _height_tex)
	else:
		_height_tex.update(himg)
	_seg_lanes.clear()
	_seg_end.clear()
	var rg: RoadGraph = _traffic.get_node(_traffic.road_network_path).graph
	var types := GameData.section("roads/types")
	for seg: RoadGraph.RoadSegment in rg.segments.values():
		_seg_lanes[seg.id] = int(types[seg.type]["lanes_per_dir"])
		_seg_end[seg.id] = Vector2i(seg.a, seg.b)
	# Keep the vehicles whose roads still exist, on the rebuilt pieces.
	_fifo.clear()
	_blocked.clear()
	var by_lane := {}
	for v in _alive.size():
		if _alive[v] == 0:
			continue
		var key: Variant = _pkey[v]
		var pid: int = lg.lane_pieces.get(key, -1) if key is int else lg.conn_pieces.get(key, -1)
		if pid < 0 or not _route_valid(v):
			_despawn(v, false)
			continue
		_piece[v] = pid
		_wait[v] = 0
		if _on_conn[v] == 0:
			if not by_lane.has(pid):
				by_lane[pid] = []
			(by_lane[pid] as Array).append(v)
		_plan_next(v)
		if _on_conn[v] == 1:
			var nk := _next_index(v)
			_npiece[v] = _lane_piece(_route[v][nk], _nlane[v]) if nk >= 0 else -1
	for pid: int in by_lane:
		var list: Array = by_lane[pid]
		list.sort_custom(func(a: int, b: int) -> bool: return _pos(a) > _pos(b))
		_fifo[pid] = list
	_build_junctions()
	for pid: int in _fifo.keys():
		_resolve(pid)
	for v in _alive.size():
		if _alive[v] == 1:
			_schedule(v)
			_write(v)


func _route_valid(v: int) -> bool:
	var route: PackedInt32Array = _route[v]
	var looping := _line[v] >= 0
	for k in range(0 if looping else _leg[v], route.size()):
		var seg := route[k] >> 1
		if not _seg_lanes.has(seg):
			return false
		var nk := (k + 1) % route.size() if looping else k + 1
		if nk < route.size():
			var nxt := route[nk]
			if not _seg_lanes.has(nxt >> 1) or _end_node(route[k]) != _start_node(nxt):
				return false
	return true


## Index of the road after the current one (wrapping for transit loops), or -1.
func _next_index(v: int) -> int:
	var size := (_route[v] as PackedInt32Array).size()
	if _line[v] >= 0:
		return (_leg[v] + 1) % size
	return _leg[v] + 1 if _leg[v] + 1 < size else -1


func _is_last(v: int) -> bool:
	return _line[v] < 0 and _leg[v] == (_route[v] as PackedInt32Array).size() - 1


## Lane distance of a transit vehicle's next stop if it is on the current road.
func _stop_on_leg(v: int) -> float:
	var stops: PackedVector2Array = _stops[v]
	if stops.is_empty():
		return -1.0
	var next := stops[_next_stop[v]]
	return next.y if int(next.x) == _leg[v] else -1.0


func _build_junctions() -> void:
	_junctions.clear()
	_junction_of.clear()
	var g: TrafficGraph = _traffic.graph
	var lg: LaneGeometry = _traffic.lanes
	var rg: RoadGraph = _traffic.get_node(_traffic.road_network_path).graph
	var transforms := []
	var green := float(_lights_cfg["green_s"])
	for n in g.node_count():
		if g.node_lit[n] == 0:
			continue
		var nid := g.node_ids[n]
		var node: RoadGraph.RoadNode = rg.nodes[nid]
		var legs := []
		var dirs := []
		for sid in node.segments:
			var seg: RoadGraph.RoadSegment = rg.segments[sid]
			var arriving := 0 if seg.b == nid else 1
			var pieces := PackedInt32Array()
			for lane in int(_seg_lanes.get(sid, 0)):
				var pid: int = lg.lane_pieces.get(LaneGeometry.lane_key(sid, arriving, lane), -1)
				if pid >= 0:
					pieces.append(pid)
			if pieces.is_empty():
				continue
			legs.append(pieces)
			dirs.append(rg.leaving_direction(sid, nid))
		if legs.size() < 2:
			continue
		var ji := _junctions.size()
		var slots := []
		for li in legs.size():
			var pieces: PackedInt32Array = legs[li]
			for pid in pieces:
				_junction_of[pid] = Vector2i(ji, li)
			var right_lane := pieces[pieces.size() - 1]
			var pts := lg.points(right_lane)
			var end := pts[pts.size() - 1]
			var d := lg.piece_dir_out[right_lane]
			var pos := end + Vector2(-d.y, d.x) * 2.6 - d * 0.6
			var fz := Vector3(-d.x, 0.0, -d.y)
			slots.append(transforms.size())
			transforms.append(Transform3D(Basis(Vector3.UP.cross(fz), Vector3.UP, fz), Vector3(pos.x, 0.0, pos.y)))
		_junctions.append({"legs": legs, "groups": TrafficRules.signal_groups(dirs), "phase": _rng.randi_range(0, 1),
			"state": 0, "next": _time + _rng.randf() * green, "slots": slots})
	var mm := _lights.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	for ji in _junctions.size():
		_show_lights(ji)


# --- Lights ---------------------------------------------------------------------

## 0 red, 1 amber, 2 green for leg `li` of junction `ji`.
func _leg_state(ji: int, li: int) -> int:
	var j: Dictionary = _junctions[ji]
	if (j["groups"] as PackedInt32Array)[li] != int(j["phase"]):
		return 0
	return [2, 1, 0][int(j["state"])]


func _show_lights(ji: int) -> void:
	var j: Dictionary = _junctions[ji]
	var mm := _lights.multimesh
	var slots: Array = j["slots"]
	for li in slots.size():
		mm.set_instance_custom_data(slots[li], Color(_leg_state(ji, li), 0, 0, 0))


func _update_lights() -> void:
	var green := float(_lights_cfg["green_s"])
	var amber := float(_lights_cfg["yellow_s"])
	var clear := float(_lights_cfg["all_red_s"])
	for ji in _junctions.size():
		var j: Dictionary = _junctions[ji]
		if float(j["next"]) > _time:
			continue
		var guard := 0
		while float(j["next"]) <= _time and guard < 8:
			guard += 1
			match int(j["state"]):
				0:
					j["state"] = 1
					j["next"] = float(j["next"]) + amber
				1:
					j["state"] = 2
					j["next"] = float(j["next"]) + clear
				_:
					j["state"] = 0
					j["phase"] = 1 - int(j["phase"])
					j["next"] = float(j["next"]) + green
		_show_lights(ji)
		for pieces: PackedInt32Array in j["legs"]:
			for pid in pieces:
				_resolve(pid)


func _lane_red(pid: int) -> bool:
	var jl: Variant = _junction_of.get(pid)
	if jl == null:
		return false
	return _leg_state(jl.x, jl.y) != 2


# --- Motion helpers ---------------------------------------------------------------

func _pos(v: int) -> float:
	return TrafficRules.position_at(_time, _s0[v], _t0[v], _v[v], _stop[v], _accel[v], _accel_time, _softness)


func _lin(v: int) -> float:
	return TrafficRules.position_at(_time, _s0[v], _t0[v], _v[v], FREE, _accel[v], _accel_time, _softness)


func _speed_now(v: int) -> float:
	var a := _pos(v)
	var b := TrafficRules.position_at(_time + 0.05, _s0[v], _t0[v], _v[v], _stop[v], _accel[v], _accel_time, _softness)
	return maxf((b - a) / 0.05, 0.0)


## Restarts the motion from where the vehicle is now, at speed `speed`,
## blending from its current speed (accel < 0 eases down, > 0 speeds up).
func _rebase(v: int, s_start: float, speed: float, delay: float) -> void:
	var v_now := _speed_now(v)
	_s0[v] = s_start
	_t0[v] = _time + (delay if v_now < 0.5 else 0.0)
	_v[v] = maxf(speed, 0.5)
	_accel[v] = clampf(1.0 - v_now / _v[v], -1.5, 1.0)


func _brake_distance(v: int) -> float:
	var s := _speed_now(v)
	return s * s / (2.0 * float(_veh["brake_decel"])) + 1.0


# --- Lane queues ------------------------------------------------------------------

## Re-evaluates where every vehicle on a lane has to stop: before a red
## stop line, behind the vehicle ahead if that one stops, at its destination,
## or nowhere. Positions are vehicle centres, so lengths and a gap are kept.
## Vehicles that are let go start one after another (reaction time).
func _resolve(pid: int) -> void:
	var fifo: Array = _fifo.get(pid, [])
	if fifo.is_empty():
		return
	var lg: LaneGeometry = _traffic.lanes
	var line := lg.piece_length[pid] - _margin
	var red := _lane_red(pid)
	var prev_stop := FREE
	var prev_half := 0.0
	var released := 0
	for v: int in fifo:
		var last := _is_last(v)
		var half := _half[v]
		var want := FREE
		if last:
			want = _end_s[v]
		elif _wait[v] == 1:
			want = line - half
		elif _line[v] >= 0 and _dwell_s[v] >= 0.0:
			want = _dwell_s[v]
		var s_now := _pos(v)
		var limit := FREE
		var at_line := false
		if prev_stop < FREE:
			limit = prev_stop - prev_half - half - _gap
		elif red:
			limit = line - half
			at_line = true
		if limit < FREE:
			var passing := at_line and _stop[v] >= FREE and not last and _wait[v] == 0 \
				and s_now + half + _brake_distance(v) > line
			if not passing:
				want = minf(want, limit)
		if want < FREE:
			want = maxf(want, s_now)
		released += _set_stop(v, want, released)
		if want < FREE:
			prev_stop = want
			prev_half = half
		else:
			prev_stop = FREE


## Applies a new stop position; returns 1 if a held vehicle was let go.
func _set_stop(v: int, want: float, rank: int) -> int:
	var old := _stop[v]
	if absf(want - old) < 0.05:
		return 0
	var released := 0
	if want > old and old < FREE and _lin(v) > old + 0.25:
		_rebase(v, _pos(v), _v[v], rank * _reaction)
		released = 1
	_stop[v] = want
	_schedule(v)
	_write(v)
	return released


func _lane_full(pid: int) -> bool:
	var fifo: Array = _fifo.get(pid, [])
	if fifo.is_empty():
		return false
	var tail: int = fifo[fifo.size() - 1]
	return _stop[tail] < FREE and _pos(tail) - _half[tail] < 4.0


func _fifo_remove(v: int, pid: int) -> void:
	var fifo: Array = _fifo.get(pid, [])
	fifo.erase(v)


func _retry_blocked() -> void:
	for v: int in _blocked.keys():
		if _alive[v] == 0 or _on_conn[v] == 1:
			_blocked.erase(v)
			continue
		var nk := _next_index(v)
		var ahead := _lane_piece(_route[v][nk], _nlane[v]) if nk >= 0 else -1
		if ahead < 0 or not _lane_full(ahead):
			_blocked.erase(v)
			_wait[v] = 0
			_resolve(_piece[v])


# --- Routes and lanes ---------------------------------------------------------------

func _end_node(entry: int) -> int:
	var ends: Vector2i = _seg_end.get(entry >> 1, Vector2i(-1, -1))
	return ends.y if (entry & 1) == 0 else ends.x


func _start_node(entry: int) -> int:
	var ends: Vector2i = _seg_end.get(entry >> 1, Vector2i(-1, -1))
	return ends.x if (entry & 1) == 0 else ends.y


func _lane_piece(entry: int, lane: int) -> int:
	return (_traffic.lanes as LaneGeometry).lane_pieces.get(LaneGeometry.lane_key(entry >> 1, entry & 1, lane), -1)


func _turn(e1: int, e2: int) -> int:
	var lg: LaneGeometry = _traffic.lanes
	var p1 := _lane_piece(e1, 0)
	var p2 := _lane_piece(e2, 0)
	if p1 < 0 or p2 < 0:
		return 0
	return TrafficRules.turn_of(lg.piece_dir_out[p1], lg.piece_dir_in[p2])


## Lane on road k of a route, ready for the turn at its end (curb lane on
## the destination road).
func _choose_lane(route: PackedInt32Array, k: int, current: int, lanes: int, transit: bool = false) -> int:
	if transit or k == route.size() - 1:
		return lanes - 1
	var turn := _turn(route[k], route[k + 1])
	if turn == 0:
		return clampi(current, 0, lanes - 1)
	return TrafficRules.lane_for_turn(turn, current, lanes)


## Picks the next road's lane and the junction connector leading there.
func _plan_next(v: int) -> void:
	var route: PackedInt32Array = _route[v]
	_npiece[v] = -1
	var nk := _next_index(v)
	if _on_conn[v] == 1 or nk < 0:
		return
	var cur := route[_leg[v]]
	var nxt := route[nk]
	var n_next: int = _seg_lanes.get(nxt >> 1, 0)
	if n_next <= 0:
		return
	var lane := _choose_lane(route, nk, _lane[v], n_next, _line[v] >= 0)
	var key := Vector3i(_end_node(cur), LaneGeometry.lane_key(cur >> 1, cur & 1, _lane[v]), LaneGeometry.lane_key(nxt >> 1, nxt & 1, lane))
	_npiece[v] = (_traffic.lanes as LaneGeometry).conn_pieces.get(key, -1)
	_nlane[v] = lane


func _connector_speed(cpid: int, lane_speed: float) -> float:
	var lg: LaneGeometry = _traffic.lanes
	if TrafficRules.turn_of(lg.piece_dir_in[cpid], lg.piece_dir_out[cpid]) != 0:
		return minf(float(_veh["turn_speed_ms"]), lane_speed)
	return minf(float(_veh["straight_speed_ms"]), lane_speed)


# --- Events -------------------------------------------------------------------------

func _schedule(v: int) -> void:
	_ver[v] += 1
	var lg: LaneGeometry = _traffic.lanes
	var last := _on_conn[v] == 0 and _is_last(v)
	var t: float
	if _stop[v] < FREE:
		if _at_transit_stop(v):
			t = TrafficRules.time_to_reach(_stop[v] - 0.3, _s0[v], _t0[v], _v[v], _accel[v], _accel_time) + _dwell[v]
		elif not last:
			return
		else:
			t = TrafficRules.time_to_reach(_stop[v] - 0.3, _s0[v], _t0[v], _v[v], _accel[v], _accel_time) + float(_veh["park_seconds"])
	else:
		t = TrafficRules.time_to_reach(lg.piece_length[_piece[v]], _s0[v], _t0[v], _v[v], _accel[v], _accel_time)
	_push_event(t, v, _ver[v])


func _process_events() -> void:
	var budget := 600
	while not _ev_t.is_empty() and _ev_t[0] <= _time and budget > 0:
		budget -= 1
		var top := _pop_event()
		var v: int = top[1]
		if _alive[v] == 0 or _ver[v] != int(top[2]):
			continue
		if _at_transit_stop(v):
			# Doors closed: on to the next stop.
			var stops: PackedVector2Array = _stops[v]
			_next_stop[v] = (_next_stop[v] + 1) % stops.size()
			_dwell_s[v] = _stop_on_leg(v)
			_resolve(_piece[v])
			if _stop[v] >= FREE:
				_schedule(v)
			continue
		if _on_conn[v] == 0 and _is_last(v) and _stop[v] < FREE:
			trips_done += 1
			_despawn(v)
			continue
		_advance(v)


func _at_transit_stop(v: int) -> bool:
	return _line[v] >= 0 and _on_conn[v] == 0 and _dwell_s[v] >= 0.0 and absf(_stop[v] - _dwell_s[v]) < 0.05


## The vehicle reached the end of its piece: into the junction, or out of it.
func _advance(v: int) -> void:
	var lg: LaneGeometry = _traffic.lanes
	var pid := _piece[v]
	var length := lg.piece_length[pid]
	var route: PackedInt32Array = _route[v]
	var nk := _next_index(v)
	if _on_conn[v] == 0:
		var c := _npiece[v]
		if c < 0 or nk < 0:
			_despawn(v)
			return
		var ahead := _lane_piece(route[nk], _nlane[v])
		if ahead < 0:
			_despawn(v)
			return
		if _lane_full(ahead):
			_wait[v] = 1
			_blocked[v] = true
			_resolve(pid)
			return
		var overflow := maxf(_pos(v) - length, 0.0)
		var next_entry := route[nk]
		_rebase(v, overflow, _connector_speed(c, _traffic.lane_speed(next_entry >> 1, next_entry & 1)), 0.0)
		_fifo_remove(v, pid)
		_piece[v] = c
		_pkey[v] = lg.piece_key[c]
		_on_conn[v] = 1
		_npiece[v] = ahead
		_stop[v] = FREE
		_schedule(v)
		_write(v)
		_resolve(pid)
	else:
		var overflow := maxf(_pos(v) - length, 0.0)
		var ahead := _npiece[v]
		if ahead < 0:
			_despawn(v)
			return
		_leg[v] = nk
		_lane[v] = _nlane[v]
		_enter_lane(v, ahead, overflow)


func _enter_lane(v: int, pid: int, s_start: float) -> void:
	var lg: LaneGeometry = _traffic.lanes
	var route: PackedInt32Array = _route[v]
	var entry := route[_leg[v]]
	var speed: float = _traffic.lane_speed(entry >> 1, entry & 1)
	var fifo: Array = _fifo.get(pid, [])
	if not fifo.is_empty():
		speed = minf(speed, _v[fifo[fifo.size() - 1]])
	_rebase(v, s_start, speed, 0.0)
	_piece[v] = pid
	_pkey[v] = lg.piece_key[pid]
	_on_conn[v] = 0
	_stop[v] = FREE
	_wait[v] = 0
	if _line[v] >= 0:
		_dwell_s[v] = _stop_on_leg(v)
	elif _leg[v] == route.size() - 1:
		var length := lg.piece_length[pid]
		_end_s[v] = clampf(length * _rng.randf_range(0.25, 0.8), minf(s_start + 4.0, length), length)
	fifo.append(v)
	_fifo[pid] = fifo
	_plan_next(v)
	_resolve(pid)
	_schedule(v)
	_write(v)


# --- Spawning and despawning ---------------------------------------------------------

func _update_focus() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var o := cam.global_position
	var dir := cam.project_ray_normal(get_viewport().get_visible_rect().size * 0.5)
	if dir.y < -0.01:
		var t := -o.y / dir.y
		_focus = Vector2(o.x + dir.x * t, o.z + dir.z * t)
	_near = maxf(float(_cfg["lod"]["near_radius_m"]), o.y * 1.3)


func _spawn_some() -> void:
	if not _traffic.trips_ready():
		return
	var hour := TimeSystem.get_visual_hour()
	# Busy cities fill up to the cap of the quality preset; small towns
	# show fewer vehicles, in proportion to the day's trips.
	var fleet := minf(float(_cap), float(_traffic.last_stats.get("trips", 0.0)) * float(_cfg["fleet_per_daily_trip"]))
	var target := int(fleet * TrafficRules.hourly(_cfg["fleet_by_hour"], hour))
	var lod: Dictionary = _cfg["lod"]
	var tries := 0
	while active - line_active < target and tries < int(lod["spawns_per_frame"]):
		tries += 1
		var trip: int = _traffic.pick_trip(hour, _focus, _near, float(lod["far_accept"]))
		if trip < 0:
			continue
		var route: PackedInt32Array = _traffic.route(trip)
		if route.size() >= 2:
			_spawn(trip, route)


func _random_paint() -> Color:
	var r := _rng.randf() * _paint_total
	for entry: Array in _paint:
		if r <= float(entry[1]):
			return entry[0]
	return (_paint[_paint.size() - 1] as Array)[0]


## [model index, paint, second colour, beacon] for a trip.
func _look_for(trip: int) -> Array:
	var kind: int = _traffic.trip_kind(trip)
	var models: Dictionary = _cfg["models"]
	if kind == _traffic.KIND_FREIGHT:
		var liveries: Array = _cfg["liveries"]
		var cab := DataLoader.to_color(liveries[_rng.randi_range(0, liveries.size() - 1)])
		var box := Color(0.93, 0.93, 0.91) if _rng.randf() < 0.6 else DataLoader.to_color(liveries[_rng.randi_range(0, liveries.size() - 1)])
		return [_model_index["truck"], cab, box, 0]
	var cat: int = _traffic.trip_category(trip)
	if cat >= 0:
		var name: String = _traffic.SERVICE_CATEGORIES[cat]
		var model: String = models["service_models"][name]
		var colors: Array = _cfg["service_paint"][name]
		var beacon := 1 if model in ["police", "ambulance", "fire"] else 0
		return [_model_index[model], DataLoader.to_color(colors[0]), DataLoader.to_color(colors[1]), beacon]
	var r := _rng.randf()
	var model := "sedan"
	for entry: Array in models["car_mix"]:
		r -= float(entry[1])
		if r <= 0.0:
			model = entry[0]
			break
	var paint := _random_paint()
	return [_model_index[model], paint, paint, 0]


func _spawn(trip: int, route: PackedInt32Array) -> void:
	var lg: LaneGeometry = _traffic.lanes
	var first := route[0]
	var lanes: int = _seg_lanes.get(first >> 1, 0)
	if lanes <= 0:
		return
	var lane := _choose_lane(route, 0, _rng.randi_range(0, lanes - 1), lanes)
	var pid := _lane_piece(first, lane)
	if pid < 0:
		return
	var length := lg.piece_length[pid]
	var margin := float(_veh["spawn_margin"])
	var look := _look_for(trip)
	var model: int = look[0]
	var s := _free_spot(pid, length * _rng.randf_range(margin, 1.0 - margin), _half_by_model[model])
	if s < 0.0:
		return
	var slot := _take_slot(model)
	if slot < 0:
		return
	var v := _new_id()
	_alive[v] = 1
	_model[v] = model
	_slot[v] = slot
	_route[v] = route
	_leg[v] = 0
	_piece[v] = pid
	_pkey[v] = lg.piece_key[pid]
	_on_conn[v] = 0
	_lane[v] = lane
	_wait[v] = 0
	_line[v] = -1
	_stops[v] = PackedVector2Array()
	_dwell_s[v] = -1.0
	_half[v] = _half_by_model[model]
	_color[v] = look[1]
	_second[v] = look[2]
	_beacon[v] = look[3]
	_seed[v] = _rng.randf()
	_s0[v] = s
	_t0[v] = _time + 0.3
	_v[v] = maxf(_traffic.lane_speed(first >> 1, first & 1), 0.5)
	_accel[v] = 1.0
	_stop[v] = FREE
	_end_s[v] = 0.0
	active += 1
	var fifo: Array = _fifo.get(pid, [])
	var at := fifo.size()
	for i in fifo.size():
		if _pos(fifo[i]) < s:
			at = i
			break
	fifo.insert(at, v)
	_fifo[pid] = fifo
	_plan_next(v)
	_resolve(pid)
	_schedule(v)
	_write(v)


## A start position on a lane clear of the vehicles already there, or -1.
func _free_spot(pid: int, s: float, half: float) -> float:
	var fifo: Array = _fifo.get(pid, [])
	for attempt in 6:
		var clear := true
		for w: int in fifo:
			if absf(_pos(w) - s) < _half[w] + half + _gap:
				clear = false
				break
		if clear:
			return s
		s -= half * 2.0 + _gap
		if s < half:
			return -1.0
	return -1.0


## A bus or tram of line `line_id` waiting at stop `start_stop` of its loop.
## stops: (route index, lane distance on the curb lane) per stop.
func spawn_line_vehicle(line_id: int, route: PackedInt32Array, stops: PackedVector2Array, start_stop: int,
		model_name: String, paint: Color, second: Color, dwell: float) -> int:
	if route.is_empty() or stops.is_empty():
		return -1
	var k := int(stops[start_stop].x)
	var entry := route[k]
	var lanes: int = _seg_lanes.get(entry >> 1, 0)
	if lanes <= 0:
		return -1
	var pid := _lane_piece(entry, lanes - 1)
	if pid < 0:
		return -1
	var model: int = _model_index[model_name]
	var lg: LaneGeometry = _traffic.lanes
	var half := _half_by_model[model]
	# Behind any vehicle already waiting there.
	var s := _free_spot(pid, clampf(stops[start_stop].y, half + 0.5, lg.piece_length[pid]), half)
	if s < 0.0:
		return -1
	var slot := _take_slot(model)
	if slot < 0:
		return -1
	var v := _new_id()
	_alive[v] = 1
	_model[v] = model
	_slot[v] = slot
	_route[v] = route
	_leg[v] = k
	_piece[v] = pid
	_pkey[v] = lg.piece_key[pid]
	_on_conn[v] = 0
	_lane[v] = lanes - 1
	_wait[v] = 0
	_line[v] = line_id
	_stops[v] = stops
	_next_stop[v] = start_stop
	_dwell[v] = dwell
	_half[v] = _half_by_model[model]
	_color[v] = paint
	_second[v] = second
	_beacon[v] = 0
	_seed[v] = _rng.randf()
	_dwell_s[v] = s
	_s0[v] = s
	_t0[v] = _time
	_v[v] = maxf(_traffic.lane_speed(entry >> 1, entry & 1), 0.5)
	_accel[v] = 1.0
	_stop[v] = FREE
	_end_s[v] = 0.0
	active += 1
	line_active += 1
	_line_count[line_id] = int(_line_count.get(line_id, 0)) + 1
	var fifo: Array = _fifo.get(pid, [])
	var at := fifo.size()
	for i in fifo.size():
		if _pos(fifo[i]) < s:
			at = i
			break
	fifo.insert(at, v)
	_fifo[pid] = fifo
	_plan_next(v)
	_resolve(pid)
	_schedule(v)
	_write(v)
	return v


## Removes every vehicle of a transit line.
func despawn_line(line_id: int) -> void:
	for v in _alive.size():
		if _alive[v] == 1 and _line[v] == line_id:
			_despawn(v)


## Vehicles currently serving a line.
func line_vehicles(line_id: int) -> int:
	return int(_line_count.get(line_id, 0))


func _despawn(v: int, resolve: bool = true) -> void:
	if _alive[v] == 0:
		return
	var pid := _piece[v]
	var on_lane := _on_conn[v] == 0
	if on_lane:
		_fifo_remove(v, pid)
	_blocked.erase(v)
	_alive[v] = 0
	_ver[v] += 1
	_release_slot(_model[v], _slot[v])
	_free_ids.append(v)
	active -= 1
	if _line[v] >= 0:
		line_active -= 1
		_line_count[_line[v]] = maxi(int(_line_count.get(_line[v], 0)) - 1, 0)
		_line[v] = -1
	if resolve and on_lane:
		_resolve(pid)


func _new_id() -> int:
	if not _free_ids.is_empty():
		return _free_ids.pop_back()
	var v := _alive.size()
	_alive.append(0)
	_model.append(0)
	_slot.append(0)
	_route.append(PackedInt32Array())
	_leg.append(0)
	_piece.append(0)
	_pkey.append(0)
	_on_conn.append(0)
	_lane.append(0)
	_npiece.append(-1)
	_nlane.append(0)
	_s0.append(0.0)
	_t0.append(0.0)
	_v.append(0.0)
	_stop.append(FREE)
	_accel.append(0.0)
	_end_s.append(0.0)
	_wait.append(0)
	_line.append(-1)
	_stops.append(PackedVector2Array())
	_next_stop.append(0)
	_dwell.append(0.0)
	_dwell_s.append(-1.0)
	_half.append(2.3)
	_ver.append(0)
	_color.append(Color.WHITE)
	_second.append(Color.WHITE)
	_beacon.append(0)
	_seed.append(0.0)
	return v


func _take_slot(model: int) -> int:
	var free: Array = _slot_free[model]
	if free.is_empty():
		return -1
	var slot: int = free.pop_back()
	var used: PackedByteArray = _slot_used[model]
	used[slot] = 1
	_slot_used[model] = used
	if slot + 1 > _slot_high[model]:
		_slot_high[model] = slot + 1
		((_mm[model] as MultiMeshInstance3D).multimesh).visible_instance_count = _slot_high[model]
	return slot


func _release_slot(model: int, slot: int) -> void:
	var mm := (_mm[model] as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(slot, _hidden_transform())
	var used: PackedByteArray = _slot_used[model]
	used[slot] = 0
	_slot_used[model] = used
	var free: Array = _slot_free[model]
	# Keep the list sorted with the smallest slot last, so slots stay packed.
	var at := free.bsearch_custom(slot, func(a: int, b: int) -> bool: return a > b)
	free.insert(at, slot)
	var high := _slot_high[model]
	while high > 0 and used[high - 1] == 0:
		high -= 1
	if high != _slot_high[model]:
		_slot_high[model] = high
		mm.visible_instance_count = high


func _write(v: int) -> void:
	if _alive[v] == 0:
		return
	var lg: LaneGeometry = _traffic.lanes
	var pid := _piece[v]
	var mm := (_mm[_model[v]] as MultiMeshInstance3D).multimesh
	var nxt := _npiece[v]
	var next := Vector3.ZERO
	if nxt >= 0:
		next = Vector3(lg.piece_offset[nxt], lg.piece_count[nxt], lg.piece_length[nxt])
	var piece := Vector3(lg.piece_offset[pid], lg.piece_count[pid], lg.piece_length[pid])
	mm.set_instance_transform(_slot[v], Transform3D(Basis(piece, next, Vector3(_s0[v], _t0[v], _v[v])),
		Vector3(_stop[v], _accel[v], 0.0)))
	var c := _color[v]
	mm.set_instance_color(_slot[v], Color(c.r, c.g, c.b, float(_beacon[v])))
	var sec := _second[v]
	mm.set_instance_custom_data(_slot[v], Color(sec.r, sec.g, sec.b, _seed[v]))


func _rebase_time() -> void:
	var shift := _time - 100.0
	_time -= shift
	for v in _alive.size():
		if _alive[v] == 1:
			_t0[v] -= shift
	for i in _ev_t.size():
		_ev_t[i] -= shift
	for j: Dictionary in _junctions:
		j["next"] = float(j["next"]) - shift
	for v in _alive.size():
		if _alive[v] == 1:
			_write(v)
	RenderingServer.global_shader_parameter_set("traffic_time", _time)


# --- Event heap -----------------------------------------------------------------------

func _push_event(t: float, v: int, ver: int) -> void:
	_ev_t.append(t)
	_ev_id.append(v)
	_ev_ver.append(ver)
	var i := _ev_t.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _ev_t[p] <= _ev_t[i]:
			break
		_swap_events(i, p)
		i = p


func _pop_event() -> Array:
	var top := [_ev_t[0], _ev_id[0], _ev_ver[0]]
	var last := _ev_t.size() - 1
	_ev_t[0] = _ev_t[last]
	_ev_id[0] = _ev_id[last]
	_ev_ver[0] = _ev_ver[last]
	_ev_t.remove_at(last)
	_ev_id.remove_at(last)
	_ev_ver.remove_at(last)
	var n := _ev_t.size()
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var m := l
		if l + 1 < n and _ev_t[l + 1] < _ev_t[l]:
			m = l + 1
		if _ev_t[m] >= _ev_t[i]:
			break
		_swap_events(i, m)
		i = m
	return top


func _swap_events(a: int, b: int) -> void:
	var t := _ev_t[a]
	_ev_t[a] = _ev_t[b]
	_ev_t[b] = t
	var id := _ev_id[a]
	_ev_id[a] = _ev_id[b]
	_ev_id[b] = id
	var ver := _ev_ver[a]
	_ev_ver[a] = _ev_ver[b]
	_ev_ver[b] = ver

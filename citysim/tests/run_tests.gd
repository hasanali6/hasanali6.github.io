extends SceneTree
## Headless unit tests for the render-independent systems.
## Run: godot --headless --path citysim -s res://tests/run_tests.gd
## Exits with the number of failed checks (0 = all passed).

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_data_files()
	_test_clock_ticks()
	_test_clock_speeds_and_pause()
	_test_clock_month_rollover()
	_test_clock_backlog_cap()
	_test_gesture_tap_and_long_press()
	_test_gesture_pan_and_fling()
	_test_gesture_pinch_rotate()
	_test_gesture_tilt()
	_test_map_grid()
	_test_gesture_capture()
	_test_road_types()
	_test_road_straight()
	_test_road_crossing()
	_test_road_t_junction_and_snap()
	_test_road_rejections()
	_test_road_curve_and_remove()
	_test_road_mesh()
	print("Tests: %d checks, %d failed" % [_checks, _failures])
	quit(_failures)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + label)


func _time_config() -> Dictionary:
	return DataLoader.load_json("res://data/time.json")


func _input_config() -> Dictionary:
	return DataLoader.load_json("res://data/input.json")


func _test_data_files() -> void:
	for f in ["game", "time", "input", "camera", "map", "environment", "graphics", "reference_scene", "roads", "economy"]:
		_check(not DataLoader.load_json("res://data/%s.json" % f).is_empty(), "data file %s loads" % f)
	var db := DataLoader.load_files(PackedStringArray(["graphics"]))
	for preset: String in DataLoader.lookup(db, "graphics/preset_order"):
		_check(DataLoader.has_path(db, "graphics/presets/" + preset + "/render_scale"), "preset %s complete" % preset)
	_check(DataLoader.to_color("#ff0000").is_equal_approx(Color.RED), "hex colour parse")


func _test_clock_ticks() -> void:
	var cfg := _time_config()
	var clock := SimClock.new(cfg)
	clock.set_speed_index(1)
	var ticks := 0
	for i in 100:
		ticks += clock.pending_ticks(0.1)
	# 10 real seconds at 1x and 10 Hz -> 100 ticks.
	_check(ticks == int(cfg["tick_rate_hz"]) * 10, "1x yields tick_rate ticks per second (%d)" % ticks)
	var start_minute := clock.minute_of_day
	for i in ticks:
		clock.step()
	var expected := 1440.0 * 10.0 / float(cfg["real_seconds_per_day_at_1x"])
	_check(is_equal_approx(clock.minute_of_day - start_minute, expected), "game minutes advance per day length")


func _test_clock_speeds_and_pause() -> void:
	var clock := SimClock.new(_time_config())
	clock.set_speed_index(3)
	var fast := 0
	for i in 10:
		fast += clock.pending_ticks(0.1)
	clock.set_speed_index(1)
	var normal := 0
	for i in 10:
		normal += clock.pending_ticks(0.1)
	_check(fast == normal * 3, "3x runs three times the ticks (%d vs %d)" % [fast, normal])
	clock.set_speed_index(0)
	_check(clock.is_paused(), "speed 0 is paused")
	_check(clock.pending_ticks(5.0) == 0, "paused clock yields no ticks")


func _test_clock_month_rollover() -> void:
	var cfg := _time_config()
	var clock := SimClock.new(cfg)
	var ticks_per_day := int(round(float(cfg["real_seconds_per_day_at_1x"]) * float(cfg["tick_rate_hz"])))
	var rolled := 0
	for i in ticks_per_day + 1:
		if clock.step():
			rolled += 1
	_check(rolled == 1 and clock.month_index == 1, "one game day equals one month")
	_check(clock.calendar_month() == (int(cfg["start_month"])) % 12, "calendar month advanced")
	clock.month_index = 12 - (int(cfg["start_month"]) - 1)
	_check(clock.year() == int(cfg["start_year"]) + 1 and clock.calendar_month() == 0, "year rolls over into January")


func _test_clock_backlog_cap() -> void:
	var cfg := _time_config()
	var clock := SimClock.new(cfg)
	clock.set_speed_index(3)
	_check(clock.pending_ticks(10.0) == int(cfg["max_ticks_per_frame"]), "long frame is capped")


func _test_gesture_tap_and_long_press() -> void:
	var g := GestureTracker.new(_input_config())
	var taps := []
	var holds := []
	g.tap.connect(func(p: Vector2) -> void: taps.append(p))
	g.long_press.connect(func(p: Vector2) -> void: holds.append(p))
	g.touch_pressed(0, Vector2(100, 100))
	g.update(0.05)
	g.touch_released(0, Vector2(100, 100))
	_check(taps.size() == 1 and holds.is_empty(), "short touch is a tap")
	g.touch_pressed(0, Vector2(200, 200))
	for i in 20:
		g.update(0.05)
	g.touch_released(0, Vector2(200, 200))
	_check(holds.size() == 1 and taps.size() == 1, "held touch is a long press, not a tap")


func _test_gesture_pan_and_fling() -> void:
	var g := GestureTracker.new(_input_config())
	var pans := []
	var flings := []
	g.pan.connect(func(d: Vector2) -> void: pans.append(d))
	g.pan_released.connect(func(v: Vector2) -> void: flings.append(v))
	g.touch_pressed(0, Vector2(100, 100))
	for i in 10:
		g.touch_moved(0, Vector2(100 + (i + 1) * 20, 100))
		g.update(1.0 / 60.0)
	g.touch_released(0, Vector2(300, 100))
	var total := Vector2.ZERO
	for d: Vector2 in pans:
		total += d
	_check(total.x > 150.0, "drag pans (%s)" % str(total))
	_check(flings.size() == 1 and (flings[0] as Vector2).x > 0.0, "release after drag flings")


func _test_gesture_pinch_rotate() -> void:
	var g := GestureTracker.new(_input_config())
	var factor := [1.0]
	var angle := [0.0]
	g.zoom.connect(func(f: float, _c: Vector2) -> void: factor[0] *= f)
	g.rotate.connect(func(a: float) -> void: angle[0] += a)
	g.touch_pressed(0, Vector2(400, 300))
	g.touch_pressed(1, Vector2(600, 300))
	for i in 10:
		g.touch_moved(0, Vector2(400 - (i + 1) * 10, 300))
		g.touch_moved(1, Vector2(600 + (i + 1) * 10, 300))
	_check(factor[0] < 0.8, "spreading fingers zooms in (factor %.2f)" % factor[0])
	var twist_start: float = angle[0]
	g.touch_moved(1, Vector2(700, 380))
	_check(angle[0] - twist_start > 0.1, "twisting fingers rotates")


func _test_gesture_tilt() -> void:
	var g := GestureTracker.new(_input_config())
	var tilt := [0.0]
	var zooms := [0]
	g.tilt.connect(func(d: float) -> void: tilt[0] += d)
	g.zoom.connect(func(_f: float, _c: Vector2) -> void: zooms[0] += 1)
	g.touch_pressed(0, Vector2(400, 400))
	g.touch_pressed(1, Vector2(600, 400))
	for i in 10:
		g.touch_moved(0, Vector2(400, 400 - (i + 1) * 8))
		g.touch_moved(1, Vector2(600, 400 - (i + 1) * 8))
	_check(tilt[0] < -40.0 and zooms[0] == 0, "two-finger vertical slide tilts only (%.1f)" % tilt[0])


func _test_map_grid() -> void:
	_check(MapGrid.world_to_cell(Vector3(-0.1, 0, 15.9), 8.0) == Vector2i(-1, 1), "world to cell floors negatives")
	_check(MapGrid.is_inside(Vector3(1999, 0, -1999), 2000.0), "inside playable")
	_check(not MapGrid.is_inside(Vector3(2001, 0, 0), 2000.0), "outside playable")


func _test_gesture_capture() -> void:
	var g := GestureTracker.new(_input_config())
	var events := []
	var pans := [0]
	g.pointer.connect(func(phase: int, p: Vector2) -> void: events.append([phase, p]))
	g.pan.connect(func(_d: Vector2) -> void: pans[0] += 1)
	g.capture_single = true
	g.touch_pressed(0, Vector2(10, 10))
	g.touch_moved(0, Vector2(60, 10))
	g.touch_released(0, Vector2(60, 10))
	var phases := events.map(func(e: Array) -> int: return e[0])
	_check(phases == [GestureTracker.Pointer.DOWN, GestureTracker.Pointer.MOVE, GestureTracker.Pointer.UP],
		"captured single finger becomes tool pointer events (%s)" % str(phases))
	_check(pans[0] == 0, "captured single finger does not pan the camera")
	events.clear()
	g.touch_pressed(0, Vector2(10, 10))
	g.touch_pressed(1, Vector2(200, 10))
	_check(events.size() == 2 and events[1][0] == GestureTracker.Pointer.CANCEL, "second finger cancels the tool stroke")


func _roads() -> Dictionary:
	return DataLoader.load_json("res://data/roads.json")


func _graph() -> RoadGraph:
	return RoadGraph.new(_roads()["graph"])


func _test_road_types() -> void:
	var types: Dictionary = _roads()["types"]
	_check(is_equal_approx(RoadTypes.total_width(types["street"]), 8.0), "street is 8 m wide")
	_check(is_equal_approx(RoadTypes.total_width(types["avenue"]), 16.0), "avenue is 16 m wide")
	_check(is_equal_approx(RoadTypes.total_width(types["boulevard"]), 24.0), "boulevard is 24 m wide")
	var lanes := RoadTypes.lanes(types["avenue"])
	var fwd := lanes.filter(func(l: Dictionary) -> bool: return l["forward"])
	_check(lanes.size() == 4 and fwd.size() == 2, "avenue has 2 lanes each way")
	_check(fwd.all(func(l: Dictionary) -> bool: return l["offset"] < 0.0), "forward lanes drive on the right")
	var one := RoadTypes.lanes(types["street_oneway"])
	_check(one.size() == 2 and one.all(func(l: Dictionary) -> bool: return l["forward"]), "one-way lanes all forward")


func _test_road_straight() -> void:
	var g := _graph()
	var plan := g.plan_road(Vector2(0, 0), Vector2(100, 0), null)
	_check(plan["ok"], "straight road plans")
	var made := g.commit_road(plan, "street")
	_check(made.size() == 1 and g.nodes.size() == 2 and g.segments.size() == 1, "straight road: 2 nodes, 1 segment")
	_check(is_equal_approx(snappedf((g.segments[made[0]] as RoadGraph.RoadSegment).length, 0.01), 100.0), "segment length is 100 m")


func _test_road_crossing() -> void:
	var g := _graph()
	g.commit_road(g.plan_road(Vector2(-50, 0), Vector2(50, 0), null), "street")
	var plan := g.plan_road(Vector2(0, -50), Vector2(0, 50), null)
	_check(plan["ok"] and (plan["hits"] as Array).size() == 1, "crossing road finds one intersection")
	g.commit_road(plan, "avenue")
	var centre := g.find_node_near(Vector2.ZERO, 0.5)
	_check(centre >= 0 and (g.nodes[centre] as RoadGraph.RoadNode).segments.size() == 4, "crossing becomes a 4-way junction")
	_check(g.segments.size() == 4 and g.nodes.size() == 5, "crossing: 5 nodes, 4 segments")


func _test_road_t_junction_and_snap() -> void:
	var g := _graph()
	g.commit_road(g.plan_road(Vector2(-50, 0), Vector2(50, 0), null), "street")
	# End exactly on the existing road -> T junction, existing road split in two.
	g.commit_road(g.plan_road(Vector2(10, 40), Vector2(10, 0.5), null), "street")
	var t := g.find_node_near(Vector2(10, 0), 1.0)
	_check(t >= 0 and (g.nodes[t] as RoadGraph.RoadNode).segments.size() == 3, "ending on a road makes a T junction")
	# Start on an existing end node -> reuses it.
	var before := g.nodes.size()
	g.commit_road(g.plan_road(Vector2(50.8, 0.4), Vector2(50, 60), null), "street")
	_check(g.nodes.size() == before + 1, "starting at an existing end node reuses it")


func _test_road_rejections() -> void:
	var g := _graph()
	g.commit_road(g.plan_road(Vector2(0, 0), Vector2(100, 0), null), "street")
	_check(g.plan_road(Vector2(0, 0), Vector2(3, 0), null)["error"] == "ROAD_ERR_SHORT", "too short is rejected")
	_check(g.plan_road(Vector2(0, 0), Vector2(100, 0), null)["error"] == "ROAD_ERR_EXISTS", "duplicate road is rejected")
	_check(g.plan_road(Vector2(0, 0), Vector2(100, 8), null)["error"] == "ROAD_ERR_ANGLE", "road on top of another is rejected")
	_check(g.plan_road(Vector2(-10, -40), Vector2(-10, 40), null)["ok"], "unrelated road is fine")


func _test_road_curve_and_remove() -> void:
	var g := _graph()
	var plan := g.plan_road(Vector2(0, 0), Vector2(100, 0), Vector2(50, 50))
	_check(plan["ok"] and float(plan["length"]) > 105.0, "curved road is longer than its chord")
	var made := g.commit_road(plan, "street")
	var mid := g.point_on(made[0], 0.5)
	_check(mid.distance_to(Vector2(50, 25)) < 0.01, "quadratic curve passes through the expected midpoint")
	g.commit_road(g.plan_road(Vector2(50, -20), Vector2(50, 60), null), "street")
	_check(g.segments.size() == 4, "straight road splits the curve where it crosses")
	for sid in g.segments.keys():
		g.remove_segment(sid)
	_check(g.segments.is_empty() and g.nodes.is_empty(), "removing every segment leaves no orphan nodes")


func _test_road_mesh() -> void:
	var cfg := _roads()
	var g := _graph()
	g.commit_road(g.plan_road(Vector2(-60, 0), Vector2(60, 0), null), "avenue")
	g.commit_road(g.plan_road(Vector2(0, -60), Vector2(0, 60), null), "street")
	var centre := g.find_node_near(Vector2.ZERO, 0.5)
	_check(RoadMeshBuilder.is_junction(g, centre, cfg["mesh"]), "4-way node is a junction")
	var radius := RoadMeshBuilder.junction_radius(g, centre, cfg["types"], cfg["mesh"])
	_check(radius > 8.0 and radius < 30.0, "junction radius is sensible (%.1f m)" % radius)
	var junction := RoadMeshBuilder.build_junction(g, centre, cfg["types"], cfg["mesh"])
	_check(junction.data.has("asphalt") and junction.data.has("sidewalk") and junction.data.has("curb"), "junction has asphalt, sidewalk and curbs")
	var seg := g.find_segment_near(Vector2(30, 0), 1.0)["segment"] as int
	var parts := RoadMeshBuilder.build_segment(g, seg, cfg["types"], cfg["mesh"])
	_check(not parts.data.has("median"), "avenue has no median")
	# Every top face must be front-facing from above (Godot: clockwise from the viewer).
	var all_up := true
	for key in ["asphalt", "sidewalk"]:
		var v: PackedVector3Array = parts.data[key]["v"]
		var idx: PackedInt32Array = parts.data[key]["i"]
		for i in range(0, idx.size(), 3):
			var gnorm := (v[idx[i + 1]] - v[idx[i]]).cross(v[idx[i + 2]] - v[idx[i]])
			if gnorm.dot(Vector3.UP) >= 0.0:
				all_up = false
	_check(all_up, "road top faces wind front-facing upwards")
	var v_count := (parts.data["asphalt"]["v"] as PackedVector3Array).size()
	_check((parts.data["asphalt"]["custom"] as PackedFloat32Array).size() == v_count * 4, "asphalt carries lane data per vertex")
	var boulevard := _graph()
	boulevard.commit_road(boulevard.plan_road(Vector2(0, 0), Vector2(80, 0), null), "boulevard")
	var bparts := RoadMeshBuilder.build_segment(boulevard, boulevard.segments.keys()[0], cfg["types"], cfg["mesh"])
	_check(bparts.data.has("median"), "boulevard has a median")

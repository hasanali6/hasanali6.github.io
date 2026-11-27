extends Node
## Drives the SimClock from the frame loop and broadcasts fixed simulation ticks.

var clock: SimClock


func _ready() -> void:
	clock = SimClock.new(GameData.section("time"))


func _process(delta: float) -> void:
	PerfMeter.begin("sim_ticks")
	var due := clock.pending_ticks(delta)
	for i in due:
		var new_month := clock.step()
		_broadcast(EventBus.sim_tick, clock.tick_count, "tick ")
		if new_month:
			PerfMeter.begin("month_end")
			_broadcast(EventBus.month_changed, clock.month_index, "month ")
			PerfMeter.end("month_end")
	PerfMeter.end("sim_ticks")


## Emits the signal; while the performance card is open each listener is
## called one by one instead, so its own time shows up (same order).
func _broadcast(sig: Signal, value: int, prefix: String) -> void:
	if not PerfMeter.detailed:
		sig.emit(value)
		return
	for c: Dictionary in sig.get_connections():
		var callable: Callable = c["callable"]
		var obj: Object = callable.get_object()
		var key: String = prefix + (str((obj as Node).name) if obj is Node else "?") + "." + str(callable.get_method())
		var t0 := Time.get_ticks_usec()
		callable.call(value)
		PerfMeter.add(key, float(Time.get_ticks_usec() - t0) / 1000.0)


func set_speed_index(index: int) -> void:
	clock.set_speed_index(index)
	EventBus.speed_changed.emit(clock.speed_index)


func get_speed_index() -> int:
	return clock.speed_index


func set_hour(hour: float) -> void:
	clock.set_hour(hour)
	EventBus.time_jumped.emit(clock.hour())


func get_visual_hour() -> float:
	return clock.visual_hour()


func get_date_text() -> String:
	return "%s %d" % [tr("MONTH_%d" % (clock.calendar_month() + 1)), clock.year()]


func get_clock_text() -> String:
	var minutes := int(clock.minute_of_day)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func save_state() -> Dictionary:
	return {"minute": clock.minute_of_day, "month": clock.month_index, "ticks": clock.tick_count, "speed": clock.speed_index}


func load_state(state: Dictionary) -> void:
	clock.minute_of_day = float(state.get("minute", clock.minute_of_day))
	clock.month_index = int(state.get("month", 0))
	clock.tick_count = int(state.get("ticks", 0))
	set_speed_index(int(state.get("speed", clock.speed_index)))


func reset_state() -> void:
	clock = SimClock.new(GameData.section("time"))
	EventBus.speed_changed.emit(clock.speed_index)

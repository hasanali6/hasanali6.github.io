extends Node
## Drives the SimClock from the frame loop and broadcasts fixed simulation ticks.

var clock: SimClock


func _ready() -> void:
	clock = SimClock.new(GameData.section("time"))


func _process(delta: float) -> void:
	var due := clock.pending_ticks(delta)
	for i in due:
		var new_month := clock.step()
		EventBus.sim_tick.emit(clock.tick_count)
		if new_month:
			EventBus.month_changed.emit(clock.month_index)


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

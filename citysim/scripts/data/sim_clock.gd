class_name SimClock
extends RefCounted
## Render-independent fixed-step simulation clock.
## One game day (night + day) equals one simulation month. Game speed scales
## how many fixed ticks run per real second; a tick is always the same size,
## so the simulation stays deterministic at every speed.

const MINUTES_PER_DAY := 1440.0

var tick_rate_hz: float
var minutes_per_tick: float
var speed_multipliers: PackedFloat32Array
var max_ticks_per_frame: int
var months_per_year: int
var start_month: int
var start_year: int

var speed_index: int
var tick_count: int = 0
var month_index: int = 0
var minute_of_day: float

var _accumulator: float = 0.0


func _init(config: Dictionary) -> void:
	tick_rate_hz = float(config["tick_rate_hz"])
	minutes_per_tick = MINUTES_PER_DAY / (float(config["real_seconds_per_day_at_1x"]) * tick_rate_hz)
	speed_multipliers = PackedFloat32Array(config["speed_multipliers"])
	max_ticks_per_frame = int(config["max_ticks_per_frame"])
	months_per_year = int(config["months_per_year"])
	start_month = int(config["start_month"]) - 1
	start_year = int(config["start_year"])
	speed_index = int(config["default_speed_index"])
	minute_of_day = float(config["start_hour"]) * 60.0


## Feeds real elapsed time and returns how many fixed ticks are due now.
func pending_ticks(real_delta: float) -> int:
	var multiplier := speed_multipliers[speed_index]
	if multiplier <= 0.0:
		_accumulator = 0.0
		return 0
	_accumulator += real_delta * tick_rate_hz * multiplier
	var due := int(_accumulator)
	_accumulator -= due
	if due > max_ticks_per_frame:
		# Drop the backlog instead of spiralling when a frame stalls.
		due = max_ticks_per_frame
		_accumulator = 0.0
	return due


## Advances one fixed tick. Returns true when a new month (day) began.
func step() -> bool:
	tick_count += 1
	minute_of_day += minutes_per_tick
	if minute_of_day >= MINUTES_PER_DAY:
		minute_of_day -= MINUTES_PER_DAY
		month_index += 1
		return true
	return false


func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, speed_multipliers.size() - 1)


func is_paused() -> bool:
	return speed_multipliers[speed_index] <= 0.0


func set_hour(hour: float) -> void:
	minute_of_day = fposmod(hour * 60.0, MINUTES_PER_DAY)
	_accumulator = 0.0


func hour() -> float:
	return minute_of_day / 60.0


## Hour including the fraction of the next tick, for smooth visuals only.
func visual_hour() -> float:
	return fposmod(minute_of_day + _accumulator * minutes_per_tick, MINUTES_PER_DAY) / 60.0


## 0-based calendar month (0 = January).
func calendar_month() -> int:
	return (start_month + month_index) % months_per_year


func year() -> int:
	return start_year + (start_month + month_index) / months_per_year

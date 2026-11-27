class_name PerfMeter
extends RefCounted
## Cheap per-frame timers for finding what slows a phone down. Systems wrap
## their per-frame work in begin(key) / end(key); the HUD's performance card
## lists the smoothed milliseconds and the worst frame of the last seconds.
## With `detailed` on, TimeSystem also times each simulation listener.

static var detailed: bool = false
static var _start: Dictionary = {}     # key -> usec at begin
static var _avg: Dictionary = {}       # key -> smoothed ms
static var _peak: Dictionary = {}      # key -> worst ms (decays)
static var _total: Dictionary = {}     # key -> ms summed since reset
static var _since_ms: int = 0
const SMOOTHING := 0.05
const PEAK_DECAY := 0.985


static func begin(key: String) -> void:
	_start[key] = Time.get_ticks_usec()


static func end(key: String) -> void:
	var t0: int = _start.get(key, -1)
	if t0 < 0:
		return
	add(key, float(Time.get_ticks_usec() - t0) / 1000.0)


## Adds a measured duration (ms) to `key` (several calls in one frame add up
## only when the caller sums them first; each call is one sample).
static func add(key: String, ms: float) -> void:
	_avg[key] = lerpf(float(_avg.get(key, ms)), ms, SMOOTHING)
	_total[key] = float(_total.get(key, 0.0)) + ms
	_peak[key] = maxf(float(_peak.get(key, 0.0)) * PEAK_DECAY, ms)


## [[key, ms per second of play, smoothed ms per call, worst ms], ...],
## heaviest first. "Per second" is what really costs frames: something
## cheap that runs 300 times a second can matter more than a rare spike.
static func report() -> Array:
	var seconds := maxf(float(Time.get_ticks_msec() - _since_ms) / 1000.0, 0.001)
	var rows := []
	for key: String in _avg:
		rows.append([key, float(_total.get(key, 0.0)) / seconds, float(_avg[key]), float(_peak.get(key, 0.0))])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows


static func reset() -> void:
	_avg.clear()
	_peak.clear()
	_total.clear()
	_since_ms = Time.get_ticks_msec()

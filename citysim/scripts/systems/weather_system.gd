extends Node
## Weather and seasons (autoload, data/weather.json).
##
## The season follows the calendar month (one game day is one month, so a
## season lasts three days). Every few game hours the weather picks a new
## state by the season's odds: clear, cloudy, rain or (in winter) snow, and
## blends into it over about an hour. Rain wets the streets, which dry again
## afterwards; snow settles and melts; leaves turn in autumn.
##
## Everything visual goes through global shader parameters (wetness,
## snow_cover, autumn) and the values the DayNightCycle reads (clouds, light),
## so every material reacts without knowing about the weather. Gameplay:
## slower and fuller roads in rain and snow (routes change), less solar
## power under clouds, a little more wind power in bad weather.

var enabled: bool = true
var state: String = "clear"
var season: String = "spring"
# Smoothed current values.
var clouds: float = 0.0
var rain: float = 0.0
var snowfall: float = 0.0
var light: float = 1.0
var sun_power: float = 1.0
var wind: float = 1.0
var speed: float = 1.0
var capacity: float = 1.0
var wetness: float = 0.0
var snow_cover: float = 0.0
var autumn: float = 0.0

var _cfg: Dictionary
var _states: Dictionary
var _rng := RandomNumberGenerator.new()
var _hours_left: float = 0.0
var _last_abs_hour: float = -1.0
var _sent := Vector3(-1, -1, -1)


func _ready() -> void:
	_cfg = GameData.section("weather")
	_states = _cfg["states"]
	_rng.randomize()
	var settings := ConfigFile.new()
	if settings.load(GraphicsSettings.SETTINGS_PATH) == OK:
		enabled = bool(settings.get_value("game", "weather", true))
	reset_state()


func _process(_delta: float) -> void:
	var c: SimClock = TimeSystem.clock
	var abs_hour := c.month_index * 24.0 + c.minute_of_day / 60.0
	if _last_abs_hour < 0.0:
		_last_abs_hour = abs_hour
	var dh := clampf(abs_hour - _last_abs_hour, 0.0, float(_cfg["max_step_hours"]))
	_last_abs_hour = abs_hour
	_update_season(c)
	if dh > 0.0:
		step(dh)
	_publish()


func _update_season(c: SimClock) -> void:
	var s := str((_cfg["season_of_month"] as Array)[c.calendar_month()])
	if s != season:
		season = s
		_hours_left = 0.0   # new season, new weather
		EventBus.weather_changed.emit(info())


## Advances the weather by `hours` of game time.
func step(hours: float) -> void:
	_hours_left -= hours
	if _hours_left <= 0.0:
		var span: Array = _cfg["duration_hours"]
		_hours_left = _rng.randf_range(float(span[0]), float(span[1]))
		_set_state(_pick_state())
	var t: Dictionary = _states[state]
	var k := clampf(hours / float(_cfg["transition_hours"]), 0.0, 1.0)
	clouds = lerpf(clouds, float(t["clouds"]), k)
	rain = lerpf(rain, float(t["rain"]), k)
	snowfall = lerpf(snowfall, float(t["snowfall"]), k)
	light = lerpf(light, float(t["light"]), k)
	sun_power = lerpf(sun_power, float(t["sun_power"]), k)
	wind = lerpf(wind, float(t["wind"]), k)
	speed = lerpf(speed, float(t["speed"]), k)
	capacity = lerpf(capacity, float(t["capacity"]), k)
	if rain > 0.3:
		wetness = minf(wetness + float(_cfg["wet_per_hour"]) * rain * hours, 1.0)
	else:
		wetness = maxf(wetness - float(_cfg["dry_per_hour"]) * hours, snowfall * 0.3)
	if snowfall > 0.3:
		snow_cover = minf(snow_cover + float(_cfg["snow_cover_per_hour"]) * snowfall * hours, 1.0)
	else:
		var melt := float(_cfg["snow_melt_per_hour"]) * (float(_cfg["winter_melt_factor"]) if season == "winter" else 1.0)
		melt *= 1.0 + rain * 2.0
		snow_cover = maxf(snow_cover - melt * hours, 0.0)
	var target_autumn := float((_cfg["autumn_by_month"] as Array)[TimeSystem.clock.calendar_month()])
	autumn = move_toward(autumn, target_autumn, float(_cfg["autumn_per_hour"]) * hours)


func _pick_state() -> String:
	if not enabled:
		return "clear"
	var weights: Dictionary = (_cfg["season_weights"] as Dictionary)[season]
	var total := 0.0
	for w: float in weights.values():
		total += w
	var r := _rng.randf() * total
	for key: String in weights:
		r -= float(weights[key])
		if r <= 0.0:
			return key
	return "clear"


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	EventBus.weather_changed.emit(info())


func _publish() -> void:
	var v := Vector3(wetness, snow_cover, autumn)
	if v.distance_squared_to(_sent) < 1e-6:
		return
	_sent = v
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", snow_cover)
	RenderingServer.global_shader_parameter_set("autumn", autumn)


func info() -> Dictionary:
	var t: Dictionary = _states[state]
	return {"state": state, "name_key": t["name_key"], "icon": t["icon"], "season": season,
		"season_key": (_cfg["season_names"] as Dictionary)[season]}


## Forces a weather state now (captures, tests).
func force(s: String, settle: bool = true) -> void:
	_set_state(s)
	_hours_left = 12.0
	if settle:
		for i in 10:
			step(1.0)
	_publish()


func set_enabled(on: bool) -> void:
	enabled = on
	var settings := ConfigFile.new()
	settings.load(GraphicsSettings.SETTINGS_PATH)
	settings.set_value("game", "weather", on)
	settings.save(GraphicsSettings.SETTINGS_PATH)
	if not on:
		_set_state("clear")
	_hours_left = 0.0


func reset_state() -> void:
	state = "clear"
	clouds = 0.0
	rain = 0.0
	snowfall = 0.0
	light = 1.0
	sun_power = 1.0
	wind = 1.0
	speed = 1.0
	capacity = 1.0
	wetness = 0.0
	snow_cover = 0.0
	_hours_left = 2.0
	_last_abs_hour = -1.0
	_update_season(TimeSystem.clock)
	autumn = float((_cfg["autumn_by_month"] as Array)[TimeSystem.clock.calendar_month()])
	_sent = Vector3(-1, -1, -1)
	_publish()


func save_state() -> Dictionary:
	return {"state": state, "hours_left": _hours_left, "wetness": wetness, "snow_cover": snow_cover, "autumn": autumn}


func load_state(st: Dictionary) -> void:
	reset_state()
	var s := str(st.get("state", "clear"))
	if _states.has(s):
		state = s
		var t: Dictionary = _states[s]
		clouds = float(t["clouds"])
		rain = float(t["rain"])
		snowfall = float(t["snowfall"])
		light = float(t["light"])
		sun_power = float(t["sun_power"])
		wind = float(t["wind"])
		speed = float(t["speed"])
		capacity = float(t["capacity"])
	_hours_left = float(st.get("hours_left", 2.0))
	wetness = float(st.get("wetness", 0.0))
	snow_cover = float(st.get("snow_cover", 0.0))
	autumn = float(st.get("autumn", autumn))
	_publish()
	EventBus.weather_changed.emit(info())

extends Node
## Sound (autoload, data/audio.json, files in assets/audio/).
##   Ambient: city traffic hum, birds by day, crickets at night, rain and
##            high-altitude wind. Each bed fades with the camera height, the
##            hour, the season and the weather (and the hum with traffic).
##   Effects: building actions, UI taps, notifications and milestones, asked
##            for through EventBus.sfx_requested(name).
##   Music:   one calm loop.
## Three buses (Music, SFX, Ambient) with volumes from the settings card,
## stored in user://settings.cfg. Sound is muted while the app is in the
## background.

const AUDIO_DIR := "res://assets/audio/"
const BUSES: Array[String] = ["Music", "SFX", "Ambient"]

var volumes: Dictionary = {}

var _cfg: Dictionary
var _music: AudioStreamPlayer
var _ambient: Dictionary = {}      # key -> AudioStreamPlayer
var _levels: Dictionary = {}       # key -> current linear level
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}
var _last_play: Dictionary = {}


func _ready() -> void:
	_cfg = GameData.section("audio")
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var settings := ConfigFile.new()
	settings.load(GraphicsSettings.SETTINGS_PATH)
	for bus: String in BUSES:
		set_volume(bus, float(settings.get_value("audio", bus, float(_cfg["default_volume"][bus]))), false)
	_music = _player(str(_cfg["music"]), "Music", true)
	_music.play()
	for key: String in _cfg["ambient"]:
		var entry: Dictionary = _cfg["ambient"][key]
		var p := _player(str(entry["stream"]), "Ambient", true)
		p.volume_db = -80.0
		p.play(randf() * 4.0)
		_ambient[key] = p
		_levels[key] = 0.0
	for i in int(_cfg["sfx_pool"]):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	EventBus.sfx_requested.connect(play)
	EventBus.milestone_reached.connect(func(_l: int, _i: Dictionary) -> void: play("milestone"))
	EventBus.notification_posted.connect(func(category: String, _t: String) -> void:
		if category not in ["save", "progression"]:
			play("notify"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, false)


func _player(file: String, bus: String, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	var stream := _stream(file)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	p.stream = stream
	add_child(p)
	return p


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		_streams[file] = load(AUDIO_DIR + file)
	return _streams[file]


## Plays a short effect by name (file assets/audio/<name>.ogg).
func play(sfx_name: String, volume_db: float = 0.0) -> void:
	var now := Time.get_ticks_msec()
	var gap := int((_cfg["min_repeat_ms"] as Dictionary).get(sfx_name, 60))
	if now - int(_last_play.get(sfx_name, -100000)) < gap:
		return
	_last_play[sfx_name] = now
	var stream := _stream(sfx_name + ".ogg")
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.96, 1.04) if sfx_name in ["ui_click", "build_place", "zone_paint"] else 1.0
	p.play()


func set_volume(bus: String, linear: float, persist: bool = true) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volumes[bus], 0.0001)))
		AudioServer.set_bus_mute(i, volumes[bus] <= 0.001)
	if persist:
		var settings := ConfigFile.new()
		settings.load(GraphicsSettings.SETTINGS_PATH)
		settings.set_value("audio", bus, volumes[bus])
		settings.save(GraphicsSettings.SETTINGS_PATH)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var height := 400.0 if cam == null else cam.global_position.y
	var near := 1.0 - smoothstep(float(_cfg["near_height_m"]), float(_cfg["far_height_m"]), height)
	var low := 1.0 - smoothstep(60.0, float(_cfg["near_height_m"]), height)
	var hour := TimeSystem.get_visual_hour()
	var day := smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(19.5, 21.0, hour))
	var dry := 1.0 - clampf(WeatherSystem.rain + WeatherSystem.snowfall, 0.0, 1.0)
	var season := WeatherSystem.season
	var traffic := 0.35
	var scene := get_tree().current_scene
	if scene != null:
		var vehicles := scene.get_node_or_null("VehicleSystem")
		if vehicles != null:
			traffic = clampf(float(vehicles.active) / float(_cfg["busy_vehicles"]), 0.15, 1.0)
	var target := {
		"city": near * traffic * lerpf(0.55, 1.0, day),
		"birds": low * day * dry * (0.25 if season == "winter" else 1.0),
		"night": low * (1.0 - day) * dry * (0.0 if season == "winter" else (0.5 if season == "autumn" else 1.0)),
		"rain": WeatherSystem.rain * lerpf(0.6, 1.0, near),
		"wind": clampf(smoothstep(300.0, 1600.0, height) * 0.8 + (WeatherSystem.wind - 1.0) + WeatherSystem.snowfall * 0.4, 0.0, 1.0),
	}
	var step := float(_cfg["fade_per_second"]) * delta
	for key: String in _ambient:
		var level := move_toward(float(_levels[key]), float(target[key]), step)
		_levels[key] = level
		var gain := float(_cfg["ambient"][key]["gain"])
		(_ambient[key] as AudioStreamPlayer).volume_db = linear_to_db(maxf(level * gain, 0.0001))

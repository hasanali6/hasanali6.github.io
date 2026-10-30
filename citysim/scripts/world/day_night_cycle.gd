extends WorldEnvironment
## Day/night lighting. Builds the Environment + sky from data/environment.json
## and drives sun/moon direction, colour temperature, sky colours, fog,
## exposure and the global `night_factor` shader parameter from the clock.
## One DirectionalLight is reused: it is the sun by day and the moon by night,
## swapping at the horizon where its energy is zero.

@export var sun_path: NodePath

var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _keys: Array = []
var _latitude: float
var _azimuth_offset: float
var _sun_disk: float
var _moon_disk: float
var _sky_update_delta: float
var _night_full: float
var _night_zero: float
var _shadow_min_energy: float
var _shadows_at_night: bool = false
var _shadows_allowed: bool = true
var _shadow_cap: float
var _shadow_per_view: float
var _shadow_min: float
var _last_sky_height: float = INF


func _ready() -> void:
	_sun = get_node(sun_path) as DirectionalLight3D
	var cfg := GameData.section("environment")
	_latitude = deg_to_rad(float(cfg["latitude_deg"]))
	_azimuth_offset = deg_to_rad(float(cfg["sun_azimuth_offset_deg"]))
	_sun_disk = float(cfg["sun_disk_angle_deg"])
	_moon_disk = float(cfg["moon_disk_angle_deg"])
	_sky_update_delta = float(cfg["sky_update_min_height_delta"])
	_night_full = float(cfg["night_factor_full_at_height"])
	_night_zero = float(cfg["night_factor_zero_at_height"])
	_shadow_min_energy = float(cfg["shadow_min_light_energy"])
	_shadow_per_view = float(cfg["shadow_distance_per_view_m"])
	_shadow_min = float(cfg["shadow_distance_min_m"])
	_keys = _parse_keys(cfg["keys"])
	_build_environment(cfg)
	_setup_sun(cfg)
	_apply_graphics(GraphicsSettings.current_preset)
	EventBus.graphics_preset_changed.connect(_apply_graphics)
	EventBus.time_jumped.connect(func(_h: float) -> void: _last_sky_height = INF)
	_update_lighting(true)


func _process(_delta: float) -> void:
	_update_lighting(false)
	_update_shadow_distance()


## Fits the shadow range to what the camera sees: sharp shadows up close,
## still-present shadows in the zoomed-out map view, capped per quality preset.
func _update_shadow_distance() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var down := maxf(-cam.global_basis.z.y, 0.1)
	var view_distance := cam.global_position.y / down
	var target := clampf(view_distance * _shadow_per_view, _shadow_min, _shadow_cap)
	if absf(target - _sun.directional_shadow_max_distance) > target * 0.05:
		_sun.directional_shadow_max_distance = target


func _parse_keys(raw: Array) -> Array:
	var keys: Array = []
	for k: Dictionary in raw:
		keys.append({
			"h": float(k["sun_height"]),
			"top": DataLoader.to_color(k["top"]),
			"horizon": DataLoader.to_color(k["horizon"]),
			"ground": DataLoader.to_color(k["ground"]),
			"fog": DataLoader.to_color(k["fog"]),
			"kelvin": float(k["light_kelvin"]),
			"light": float(k["light_energy"]),
			"ambient": float(k["ambient_energy"]),
			"ambient_color": DataLoader.to_color(k["ambient_color"]),
			"sky": float(k["sky_energy"]),
			"exposure": float(k["exposure"]),
		})
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["h"] < b["h"])
	return keys


func _build_environment(cfg: Dictionary) -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve = float(cfg["sky_curve"])
	_sky_mat.ground_curve = float(cfg["ground_curve"])
	_sky_mat.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# Incremental updates spread radiance re-filtering over frames (mobile friendly).
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = float(cfg["ambient_sky_contribution"])
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = float(cfg["tonemap_white"])
	env.adjustment_enabled = true
	env.adjustment_saturation = float(cfg["saturation"])
	env.adjustment_contrast = float(cfg["contrast"])
	env.adjustment_brightness = float(cfg["brightness"])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = float(cfg["fog_density"])
	env.fog_sky_affect = float(cfg["fog_sky_affect"])
	env.fog_aerial_perspective = float(cfg["fog_aerial_perspective"])
	env.fog_sun_scatter = float(cfg["fog_sun_scatter"])
	env.fog_height = float(cfg["fog_height"])
	env.fog_height_density = float(cfg["fog_height_density"])
	env.glow_intensity = float(cfg["glow_intensity"])
	env.glow_strength = float(cfg["glow_strength"])
	env.glow_hdr_threshold = float(cfg["glow_hdr_threshold"])
	env.glow_bloom = float(cfg["glow_bloom"])
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment = env


func _setup_sun(cfg: Dictionary) -> void:
	_sun.shadow_enabled = true
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_blur = float(cfg["shadow_blur"])
	_sun.shadow_bias = float(cfg["shadow_bias"])
	_sun.shadow_normal_bias = float(cfg["shadow_normal_bias"])
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY


func _apply_graphics(_preset: String) -> void:
	_shadow_cap = float(GraphicsSettings.get_value("shadow_max_distance_m"))
	_shadows_at_night = bool(GraphicsSettings.get_value("shadows_at_night"))
	_shadows_allowed = bool(GraphicsSettings.get_value("shadows"))
	# One cascade is far cheaper on mobile; two give sharper shadows up close.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS \
		if int(GraphicsSettings.get_value("shadow_splits")) >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	_last_sky_height = INF
	environment.glow_enabled = bool(GraphicsSettings.get_value("glow"))


## Unit vector pointing towards the sun for a given hour (0-24).
func sun_direction(hour: float) -> Vector3:
	var hour_angle := (hour - 12.0) / 24.0 * TAU
	# Simple equatorial orbit tilted by latitude: rises east, sets west.
	# Godot convention: -Z is north, +X is east; the noon sun sits to the south (+Z).
	var dir := Vector3(-sin(hour_angle), cos(hour_angle) * cos(_latitude), cos(hour_angle) * sin(_latitude))
	return dir.rotated(Vector3.UP, _azimuth_offset).normalized()


func _update_lighting(force: bool) -> void:
	var sun_dir := sun_direction(TimeSystem.get_visual_hour())
	var height := sun_dir.y
	var key := _sample(height)
	var is_day := height >= 0.0
	var light_dir := sun_dir if is_day else -sun_dir

	_sun.global_transform = Transform3D(Basis.looking_at(-light_dir, Vector3.FORWARD if absf(light_dir.y) > 0.99 else Vector3.UP), Vector3.ZERO)
	_sun.light_color = kelvin_to_color(key["kelvin"])
	_sun.light_energy = key["light"]
	var want_shadow: bool = _shadows_allowed and key["light"] > _shadow_min_energy and (is_day or _shadows_at_night)
	if _sun.shadow_enabled != want_shadow:
		_sun.shadow_enabled = want_shadow
	_sky_mat.sun_angle_max = _sun_disk if is_day else _moon_disk

	var night := 1.0 - smoothstep(_night_full, _night_zero, height)
	RenderingServer.global_shader_parameter_set("night_factor", night)

	if force or absf(height - _last_sky_height) >= _sky_update_delta:
		_last_sky_height = height
		_sky_mat.sky_top_color = key["top"]
		_sky_mat.sky_horizon_color = key["horizon"]
		_sky_mat.ground_horizon_color = key["horizon"]
		_sky_mat.ground_bottom_color = key["ground"]
		_sky_mat.sky_energy_multiplier = key["sky"]
		_sky_mat.ground_energy_multiplier = key["sky"]
		environment.ambient_light_color = key["ambient_color"]
		environment.ambient_light_energy = key["ambient"]
		environment.fog_light_color = key["fog"]
		environment.tonemap_exposure = key["exposure"]


## Interpolates the data keys at the given sun height.
func _sample(height: float) -> Dictionary:
	if height <= _keys[0]["h"]:
		return _keys[0]
	for i in range(1, _keys.size()):
		var b: Dictionary = _keys[i]
		if height <= b["h"]:
			var a: Dictionary = _keys[i - 1]
			var t := inverse_lerp(a["h"], b["h"], height)
			var out := {}
			for field: String in a.keys():
				out[field] = lerp(a[field], b[field], t)
			return out
	return _keys[_keys.size() - 1]


## Approximate black-body colour (Tanner Helland fit), 1000K - 40000K.
static func kelvin_to_color(kelvin: float) -> Color:
	var t := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var r: float
	var g: float
	var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
		b = 255.0
	return Color(clampf(r, 0.0, 255.0) / 255.0, clampf(g, 0.0, 255.0) / 255.0, clampf(b, 0.0, 255.0) / 255.0)

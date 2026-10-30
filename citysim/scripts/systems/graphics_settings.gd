extends Node
## Applies Low / Medium / High quality presets from data/graphics.json and
## remembers the player's choice. Dynamic resolution lowers the 3D render
## scale when the frame rate drops below target and restores it when stable;
## the 2D UI always stays at native resolution. Scene nodes read preset values via get_value()
## and refresh on EventBus.graphics_preset_changed.

const SETTINGS_PATH := "user://settings.cfg"

var current_preset: String = ""

var _dyn_enabled: bool
var _dyn_target_fps: float
var _dyn_interval: float
var _dyn_raise_after: float
var _dyn_min_scale: float
var _dyn_step: float
var _preset_scale: float = 1.0
var _check_timer: float = 0.0
var _stable_time: float = 0.0


func _ready() -> void:
	Engine.max_fps = GameData.integer("graphics/max_fps")
	var dyn := GameData.section("graphics/dynamic_resolution")
	_dyn_enabled = bool(dyn["enabled"])
	_dyn_target_fps = float(dyn["target_fps"])
	_dyn_interval = float(dyn["check_interval_s"])
	_dyn_raise_after = float(dyn["raise_after_s"])
	_dyn_min_scale = float(dyn["min_scale"])
	_dyn_step = float(dyn["step"])
	var preset := str(GameData.value("graphics/default_preset"))
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := str(cfg.get_value("graphics", "preset", ""))
		if GameData.has("graphics/presets/" + saved):
			preset = saved
	apply_preset(preset, false)


func get_preset_names() -> PackedStringArray:
	return PackedStringArray(GameData.value("graphics/preset_order"))


func get_value(key: String) -> Variant:
	return GameData.value("graphics/presets/%s/%s" % [current_preset, key])


func apply_preset(preset: String, persist: bool = true) -> void:
	current_preset = preset
	var vp := get_tree().root
	_preset_scale = float(get_value("render_scale"))
	# FSR is Forward+ only; the Mobile renderer upscales bilinearly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = _preset_scale
	_stable_time = 0.0
	vp.msaa_3d = int(get_value("msaa")) as Viewport.MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(get_value("fxaa")) else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(int(get_value("shadow_atlas_size")), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		int(get_value("shadow_filter_quality")) as RenderingServer.ShadowQuality)
	if persist:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("graphics", "preset", preset)
		cfg.save(SETTINGS_PATH)
	EventBus.graphics_preset_changed.emit(preset)


func _process(delta: float) -> void:
	if not _dyn_enabled:
		return
	_check_timer += delta
	if _check_timer < _dyn_interval:
		return
	_check_timer = 0.0
	var vp := get_tree().root
	var fps := Engine.get_frames_per_second()
	if fps < _dyn_target_fps:
		_stable_time = 0.0
		vp.scaling_3d_scale = maxf(vp.scaling_3d_scale - _dyn_step, _dyn_min_scale)
	elif vp.scaling_3d_scale < _preset_scale:
		_stable_time += _dyn_interval
		if _stable_time >= _dyn_raise_after:
			_stable_time = 0.0
			vp.scaling_3d_scale = minf(vp.scaling_3d_scale + _dyn_step, _preset_scale)


func get_render_scale() -> float:
	return get_tree().root.scaling_3d_scale

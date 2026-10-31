extends Node
## Applies Low / Medium / High quality presets from data/graphics.json and
## remembers the player's choice. Scene nodes read preset values via get_value()
## and refresh on EventBus.graphics_preset_changed.
##
## Frame pacing: a 60 FPS cap only works when the display refresh rate is a
## multiple of 60. On 90/144 Hz screens a cap plus vsync snaps to half the
## refresh rate (45/72 FPS), so there the cap is lifted and vsync paces frames.
##
## Dynamic resolution watches the measured GPU frame time (not FPS, which is
## also limited by vsync and the CPU) and lowers the 3D render scale when the
## GPU is over budget, restoring it once there is headroom. The UI always stays
## at native resolution.

const SETTINGS_PATH := "user://settings.cfg"

var current_preset: String = ""

var _target_fps: float
var _refresh_hz: float = -1.0
var _dyn_enabled: bool
var _dyn_interval: float
var _dyn_raise_after: float
var _dyn_min_scale: float
var _dyn_step: float
var _gpu_budget_ms: float
var _raise_below_ms: float
var _preset_scale: float = 1.0
var _check_timer: float = 0.0
var _headroom_time: float = 0.0
var _viewport_rid: RID


func _ready() -> void:
	_target_fps = GameData.num("graphics/target_fps")
	_apply_frame_cap()
	var dyn := GameData.section("graphics/dynamic_resolution")
	_dyn_enabled = bool(dyn["enabled"])
	_dyn_interval = float(dyn["check_interval_s"])
	_dyn_raise_after = float(dyn["raise_after_s"])
	_dyn_min_scale = float(dyn["min_scale"])
	_dyn_step = float(dyn["step"])
	_gpu_budget_ms = 1000.0 / _target_fps * float(dyn["gpu_budget_ratio"])
	_raise_below_ms = _gpu_budget_ms * float(dyn["raise_below_ratio"])
	_viewport_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)

	var preset := str(GameData.value("graphics/default_preset"))
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := str(cfg.get_value("graphics", "preset", ""))
		if GameData.has("graphics/presets/" + saved):
			preset = saved
	apply_preset(preset, false)


func _apply_frame_cap() -> void:
	_refresh_hz = DisplayServer.screen_get_refresh_rate()
	if is_nan(_refresh_hz):
		_refresh_hz = -1.0
	var tolerance := GameData.num("graphics/refresh_divisor_tolerance")
	var ratio := _refresh_hz / _target_fps
	if _refresh_hz > 0.0 and absf(ratio - roundf(ratio)) > tolerance:
		Engine.max_fps = 0
	else:
		Engine.max_fps = int(_target_fps)


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
	_headroom_time = 0.0
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
	var gpu_ms := get_gpu_ms()
	var over_budget: bool
	var headroom: bool
	if gpu_ms > 0.0:
		over_budget = gpu_ms > _gpu_budget_ms
		headroom = gpu_ms < _raise_below_ms
	else:
		# No GPU timestamps on this device: fall back to the achievable frame rate.
		var achievable := minf(_target_fps, _refresh_hz) if _refresh_hz > 0.0 else _target_fps
		var fps := float(Engine.get_frames_per_second())
		over_budget = fps < achievable * 0.92
		headroom = not over_budget
	if over_budget:
		_headroom_time = 0.0
		vp.scaling_3d_scale = maxf(vp.scaling_3d_scale - _dyn_step, _dyn_min_scale)
	elif headroom and vp.scaling_3d_scale < _preset_scale:
		_headroom_time += _dyn_interval
		if _headroom_time >= _dyn_raise_after:
			_headroom_time = 0.0
			vp.scaling_3d_scale = minf(vp.scaling_3d_scale + _dyn_step, _preset_scale)
	else:
		_headroom_time = 0.0


func get_render_scale() -> float:
	return get_tree().root.scaling_3d_scale


func get_gpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)


func get_cpu_ms() -> float:
	return Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 \
		+ RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)


func get_refresh_hz() -> float:
	return _refresh_hz

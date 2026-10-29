extends Node
## Applies Low / Medium / High quality presets from data/graphics.json and
## remembers the player's choice. Scene nodes read preset values via get_value()
## and refresh on EventBus.graphics_preset_changed.

const SETTINGS_PATH := "user://settings.cfg"

var current_preset: String = ""


func _ready() -> void:
	Engine.max_fps = GameData.integer("graphics/max_fps")
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
	var scale := float(get_value("render_scale"))
	# FSR is Forward+ only; the Mobile renderer upscales bilinearly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
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

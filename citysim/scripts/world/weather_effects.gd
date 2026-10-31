extends Node3D
## Falling rain and snow around the camera (GPUParticles3D). The amount
## follows the weather (WeatherSystem) and the quality preset
## ("weather_particles": 0 turns the effect off); far above the city the
## particles thin out so the map view stays clear.

const RAIN_LIFETIME := 1.1
const SNOW_LIFETIME := 7.0
const BOX := Vector3(70.0, 30.0, 70.0)

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _cap: int = 0


func _ready() -> void:
	_rain = _make_rain()
	_snow = _make_snow()
	add_child(_rain)
	add_child(_snow)
	_apply_preset(GraphicsSettings.current_preset)
	EventBus.graphics_preset_changed.connect(_apply_preset)


func _apply_preset(_preset: String) -> void:
	_cap = int(GraphicsSettings.get_value("weather_particles"))
	_rain.amount = maxi(_cap, 1)
	_snow.amount = maxi(_cap / 2, 1)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _cap <= 0:
		_rain.emitting = false
		_snow.emitting = false
		return
	# A box in front of the camera, a little above it.
	var fwd := -cam.global_basis.z
	var centre := cam.global_position + fwd * BOX.z * 0.45 + Vector3.UP * 6.0
	var height_fade := 1.0 - smoothstep(180.0, 650.0, cam.global_position.y)
	var rain := WeatherSystem.rain * height_fade
	var snow := WeatherSystem.snowfall * height_fade
	_rain.global_position = centre
	_snow.global_position = centre
	_rain.emitting = rain > 0.05
	_snow.emitting = snow > 0.05
	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	_snow.amount_ratio = clampf(snow, 0.0, 1.0)


func _process_material(gravity: float, spread: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX * 0.5
	pm.direction = Vector3(0.12, -1.0, 0.05)
	pm.spread = spread
	pm.gravity = Vector3(0.0, -gravity, 0.0)
	return pm


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	var pm := _process_material(0.0, 2.0)
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.83, 0.9, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	quad.material = mat
	p.draw_pass_1 = quad
	p.lifetime = RAIN_LIFETIME
	p.local_coords = false
	p.visibility_aabb = AABB(-BOX, BOX * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


func _make_snow() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Snow"
	var pm := _process_material(0.0, 25.0)
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.2
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.97, 0.98, 1.0, 0.9)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	p.draw_pass_1 = quad
	p.lifetime = SNOW_LIFETIME
	p.local_coords = false
	p.visibility_aabb = AABB(-BOX, BOX * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

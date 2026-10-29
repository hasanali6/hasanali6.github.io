extends Node3D
## City camera rig: orbits a focus point on the ground. Zoom distance drives the
## pitch automatically (steep map view high up, shallow street view close in);
## the player can add a limited tilt offset on top. Everything is smoothed.

@onready var camera: Camera3D = $Camera3D

var _min_distance: float
var _max_distance: float
var _pitch_at_min: float
var _pitch_at_max: float
var _pitch_curve: float
var _pitch_limit_low: float
var _pitch_limit_high: float
var _tilt_range: float
var _tilt_per_px: float
var _focus_height_at_min: float
var _min_camera_height: float
var _smoothing: float
var _fling_decay: float
var _fling_min_speed: float
var _fling_max_speed: float
var _pan_pitch_comp_min: float
var _bounds_half: float

var _focus_target: Vector3
var _focus: Vector3
var _yaw_target: float
var _yaw: float
var _distance_target: float
var _distance: float
var _tilt_target: float = 0.0
var _tilt: float = 0.0
var _fling: Vector2 = Vector2.ZERO


func _ready() -> void:
	var cfg := GameData.section("camera")
	camera.fov = float(cfg["fov_deg"])
	camera.near = float(cfg["near_m"])
	camera.far = float(cfg["far_m"])
	_min_distance = float(cfg["min_distance_m"])
	_max_distance = float(cfg["max_distance_m"])
	_pitch_at_min = deg_to_rad(float(cfg["pitch_at_min_distance_deg"]))
	_pitch_at_max = deg_to_rad(float(cfg["pitch_at_max_distance_deg"]))
	_pitch_curve = float(cfg["pitch_curve_exponent"])
	_pitch_limit_low = deg_to_rad(float(cfg["pitch_limit_low_deg"]))
	_pitch_limit_high = deg_to_rad(float(cfg["pitch_limit_high_deg"]))
	_tilt_range = deg_to_rad(float(cfg["tilt_range_deg"]))
	_tilt_per_px = deg_to_rad(float(cfg["tilt_deg_per_px"]))
	_focus_height_at_min = float(cfg["focus_height_at_min_distance_m"])
	_min_camera_height = float(cfg["min_camera_height_m"])
	_smoothing = float(cfg["smoothing"])
	_fling_decay = float(cfg["fling_decay"])
	_fling_min_speed = float(cfg["fling_min_speed_px"])
	_fling_max_speed = float(cfg["fling_max_speed_px"])
	_pan_pitch_comp_min = float(cfg["pan_pitch_compensation_min"])
	_bounds_half = GameData.num("map/playable_size_m") * 0.5

	_focus_target = DataLoader.to_vector3(cfg["start_focus"])
	_yaw_target = deg_to_rad(float(cfg["start_yaw_deg"]))
	_distance_target = clampf(float(cfg["start_distance_m"]), _min_distance, _max_distance)
	_snap_to_targets()

	EventBus.pan_requested.connect(_on_pan)
	EventBus.pan_released.connect(_on_pan_released)
	EventBus.zoom_requested.connect(_on_zoom)
	EventBus.rotate_requested.connect(_on_rotate)
	EventBus.tilt_requested.connect(_on_tilt)
	EventBus.long_pressed.connect(_on_long_pressed)


func _process(delta: float) -> void:
	if _fling.length() > _fling_min_speed:
		_pan_by_screen(_fling * delta)
		_fling *= exp(-_fling_decay * delta)
	else:
		_fling = Vector2.ZERO

	var k := 1.0 - exp(-_smoothing * delta)
	_focus = _focus.lerp(_focus_target, k)
	_yaw = lerpf(_yaw, _yaw_target, k)
	# Zoom is smoothed in log space so it feels even at every height.
	_distance = exp(lerpf(log(_distance), log(_distance_target), k))
	_tilt = lerpf(_tilt, _tilt_target, k)
	_apply_transform()


## Projects a screen point onto the ground plane (y = 0).
func screen_to_ground(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)


func get_zoom_ratio() -> float:
	return inverse_lerp(log(_min_distance), log(_max_distance), log(_distance))


func _snap_to_targets() -> void:
	_focus = _focus_target
	_yaw = _yaw_target
	_distance = _distance_target
	_tilt = _tilt_target
	_apply_transform()


func _pitch_for(distance: float, tilt: float) -> float:
	var t := clampf(inverse_lerp(log(_min_distance), log(_max_distance), log(distance)), 0.0, 1.0)
	var base := lerpf(_pitch_at_min, _pitch_at_max, pow(t, _pitch_curve))
	# Pitch is negative (looking down); positive tilt raises the view.
	return clampf(base + tilt, _pitch_limit_high, _pitch_limit_low)


func _apply_transform() -> void:
	var t := clampf(inverse_lerp(log(_min_distance), log(_max_distance), log(_distance)), 0.0, 1.0)
	var focus := _focus
	focus.y = lerpf(_focus_height_at_min, 0.0, t)
	var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch_for(_distance, _tilt))
	var pos := focus + basis * Vector3(0.0, 0.0, _distance)
	pos.y = maxf(pos.y, _min_camera_height)
	global_transform = Transform3D(basis, pos)


func _world_per_pixel() -> float:
	var h := get_viewport().get_visible_rect().size.y
	return 2.0 * _distance_target * tan(deg_to_rad(camera.fov) * 0.5) / maxf(h, 1.0)


func _pan_by_screen(screen_delta: Vector2) -> void:
	var wpp := _world_per_pixel()
	var pitch := absf(_pitch_for(_distance_target, _tilt_target))
	var depth_scale := 1.0 / maxf(sin(pitch), _pan_pitch_comp_min)
	var right := Vector3(cos(_yaw_target), 0.0, -sin(_yaw_target))
	var forward := Vector3(-sin(_yaw_target), 0.0, -cos(_yaw_target))
	_focus_target -= right * screen_delta.x * wpp
	_focus_target += forward * screen_delta.y * wpp * depth_scale
	_clamp_focus()


func _clamp_focus() -> void:
	_focus_target.x = clampf(_focus_target.x, -_bounds_half, _bounds_half)
	_focus_target.z = clampf(_focus_target.z, -_bounds_half, _bounds_half)
	_focus_target.y = 0.0


func _on_pan(screen_delta: Vector2) -> void:
	_fling = Vector2.ZERO
	_pan_by_screen(screen_delta)


func _on_pan_released(screen_velocity: Vector2) -> void:
	_fling = screen_velocity.limit_length(_fling_max_speed)


func _on_zoom(factor: float, screen_center: Vector2) -> void:
	var old_distance := _distance_target
	_distance_target = clampf(_distance_target * factor, _min_distance, _max_distance)
	var applied := _distance_target / old_distance
	# Keep the ground point under the fingers roughly fixed while zooming.
	var hit: Variant = screen_to_ground(screen_center)
	if hit != null:
		var anchor: Vector3 = hit
		anchor.y = 0.0
		_focus_target = anchor + (_focus_target - anchor) * applied
		_clamp_focus()


func _on_rotate(angle_rad: float) -> void:
	_yaw_target += angle_rad


func _on_tilt(screen_delta_y: float) -> void:
	_tilt_target = clampf(_tilt_target - screen_delta_y * _tilt_per_px, -_tilt_range, _tilt_range)


func _on_long_pressed(screen_pos: Vector2) -> void:
	var hit: Variant = screen_to_ground(screen_pos)
	if hit != null:
		EventBus.ground_long_pressed.emit(hit)

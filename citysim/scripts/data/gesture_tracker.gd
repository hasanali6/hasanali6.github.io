class_name GestureTracker
extends RefCounted
## Turns raw touch points into high-level camera gestures. Pure logic with no
## engine input dependency, so it can be unit-tested headless.
##   1 finger drag            -> pan (+ fling on release)
##   1 finger tap / hold      -> tap / long press
##   2 fingers move together  -> pan
##   2 fingers pinch          -> zoom (keeps panning with the centroid)
##   2 fingers twist          -> rotate (only after a clear twist, so zooming
##                               and panning do not spin the view)
## Tilt has its own buttons in the HUD.
## With capture_single on (a build tool is active) one finger produces tool
## pointer events instead of pan/tap/long press; two fingers still navigate.

signal pan(screen_delta: Vector2)
signal pan_released(screen_velocity: Vector2)
signal zoom(factor: float, screen_center: Vector2)
signal rotate(angle_rad: float)
signal tilt(screen_delta_y: float)
signal tap(screen_pos: Vector2)
signal long_press(screen_pos: Vector2)
signal pointer(phase: int, screen_pos: Vector2)

enum Mode { NONE, PAN, CAPTURE, TWO_UNDECIDED, PINCH_ROTATE, TILT }
enum Pointer { DOWN, MOVE, UP, CANCEL }

var capture_single: bool = false

var long_press_seconds: float
var tap_max_move_px: float
var two_finger_decide_px: float
var two_finger_decide_angle: float
var two_finger_rotate_angle: float
var velocity_smoothing: float

var _touches: Dictionary = {}  # finger index -> Vector2
var _mode: Mode = Mode.NONE
var _clock: float = 0.0
var _press_time: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO
var _moved_far: bool = false
var _long_press_fired: bool = false
var _frame_pan: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _start_centroid: Vector2 = Vector2.ZERO
var _start_dist: float = 0.0
var _start_angle: float = 0.0
var _last_centroid: Vector2 = Vector2.ZERO
var _last_dist: float = 0.0
var _last_angle: float = 0.0
var _zooming: bool = false
var _rotating: bool = false
var _panning: bool = false


func _init(config: Dictionary) -> void:
	long_press_seconds = float(config["long_press_seconds"])
	tap_max_move_px = float(config["tap_max_move_px"])
	two_finger_decide_px = float(config["two_finger_decide_px"])
	two_finger_decide_angle = deg_to_rad(float(config["two_finger_decide_angle_deg"]))
	two_finger_rotate_angle = deg_to_rad(float(config.get("two_finger_rotate_angle_deg", 10.0)))
	velocity_smoothing = float(config["velocity_smoothing"])


func reset() -> void:
	_touches.clear()
	_mode = Mode.NONE
	_velocity = Vector2.ZERO
	_frame_pan = Vector2.ZERO


func touch_count() -> int:
	return _touches.size()


func touch_pressed(index: int, pos: Vector2) -> void:
	_touches[index] = pos
	match _touches.size():
		1:
			if capture_single:
				_mode = Mode.CAPTURE
				pointer.emit(Pointer.DOWN, pos)
				return
			_mode = Mode.PAN
			_press_time = _clock
			_press_pos = pos
			_moved_far = false
			_long_press_fired = false
			_velocity = Vector2.ZERO
			_frame_pan = Vector2.ZERO
		2:
			if _mode == Mode.CAPTURE:
				pointer.emit(Pointer.CANCEL, pos)
			_mode = Mode.TWO_UNDECIDED
			_moved_far = true  # a second finger cancels tap / long press
			_begin_two_finger()


func touch_released(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	_touches.erase(index)
	match _touches.size():
		0:
			if _mode == Mode.CAPTURE:
				pointer.emit(Pointer.UP, pos)
			elif _mode == Mode.PAN:
				if not _moved_far and not _long_press_fired and _clock - _press_time < long_press_seconds:
					tap.emit(pos)
				elif _moved_far:
					pan_released.emit(_velocity)
			_mode = Mode.NONE
		1:
			# Continue panning with the remaining finger, without a tap.
			# While a tool is active the leftover finger does nothing.
			_mode = Mode.NONE if capture_single else Mode.PAN
			_moved_far = true
			_velocity = Vector2.ZERO
			_frame_pan = Vector2.ZERO
		2:
			_begin_two_finger()


func touch_moved(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var old_pos: Vector2 = _touches[index]
	_touches[index] = pos
	if _mode == Mode.CAPTURE:
		pointer.emit(Pointer.MOVE, pos)
	elif _touches.size() == 1 and _mode == Mode.PAN:
		if pos.distance_to(_press_pos) > tap_max_move_px:
			_moved_far = true
		if _moved_far:
			var delta := pos - old_pos
			_frame_pan += delta
			pan.emit(delta)
	elif _touches.size() == 2:
		_update_two_finger()


## Call every frame: long-press timing and fling velocity estimation.
func update(delta: float) -> void:
	_clock += delta
	if _mode == Mode.PAN and _touches.size() == 1:
		if not _moved_far and not _long_press_fired and _clock - _press_time >= long_press_seconds:
			_long_press_fired = true
			long_press.emit(_touches.values()[0])
		if delta > 0.0:
			_velocity = _velocity.lerp(_frame_pan / delta, clampf(1.0 - velocity_smoothing, 0.0, 1.0))
		_frame_pan = Vector2.ZERO


func _two_points() -> Array[Vector2]:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _begin_two_finger() -> void:
	var p := _two_points()
	_start_centroid = (p[0] + p[1]) * 0.5
	_start_dist = maxf(p[0].distance_to(p[1]), 1.0)
	_start_angle = (p[1] - p[0]).angle()
	_last_centroid = _start_centroid
	_last_dist = _start_dist
	_last_angle = _start_angle
	_zooming = false
	_rotating = false
	_panning = false


func _update_two_finger() -> void:
	var p := _two_points()
	var centroid := (p[0] + p[1]) * 0.5
	var dist := maxf(p[0].distance_to(p[1]), 1.0)
	var angle := (p[1] - p[0]).angle()
	# Each part of the gesture starts once it is clearly meant.
	if not _zooming and absf(dist - _start_dist) > two_finger_decide_px:
		_zooming = true
	if not _rotating and absf(wrapf(angle - _start_angle, -PI, PI)) > two_finger_rotate_angle:
		_rotating = true
	if not _panning and centroid.distance_to(_start_centroid) > two_finger_decide_px:
		_panning = true
	if _zooming or _rotating or _panning:
		_mode = Mode.PINCH_ROTATE
	if _zooming:
		zoom.emit(_last_dist / dist, centroid)
	if _rotating:
		rotate.emit(wrapf(angle - _last_angle, -PI, PI))
	if _panning or _zooming:
		pan.emit(centroid - _last_centroid)
	_last_centroid = centroid
	_last_dist = dist
	_last_angle = angle

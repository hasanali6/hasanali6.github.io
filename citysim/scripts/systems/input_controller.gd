extends Node
## Converts touch and (desktop) mouse input into gestures on the EventBus.
## Uses _unhandled_input so touches on UI controls never move the camera.

var tracker: GestureTracker

var _wheel_step: float
var _rotate_per_px: float
var _tilt_px_scale: float
var _right_dragging: bool = false


func _ready() -> void:
	var cfg := GameData.section("input")
	tracker = GestureTracker.new(cfg)
	_wheel_step = float(cfg["mouse_wheel_zoom_step"])
	_rotate_per_px = float(cfg["mouse_rotate_rad_per_px"])
	_tilt_px_scale = float(cfg["mouse_tilt_px_scale"])
	tracker.pan.connect(EventBus.pan_requested.emit)
	tracker.pan_released.connect(EventBus.pan_released.emit)
	tracker.zoom.connect(EventBus.zoom_requested.emit)
	tracker.rotate.connect(EventBus.rotate_requested.emit)
	tracker.tilt.connect(EventBus.tilt_requested.emit)
	tracker.tap.connect(EventBus.tapped.emit)
	tracker.long_press.connect(EventBus.long_pressed.emit)


func _process(delta: float) -> void:
	tracker.update(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		tracker.reset()
		_right_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			tracker.touch_pressed(touch.index, touch.position)
		else:
			tracker.touch_released(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		tracker.touch_moved(drag.index, drag.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_handle_mouse_motion(event as InputEventMouseMotion)


# Desktop testing: left drag = pan, right drag = rotate/tilt, wheel = zoom.
func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				tracker.touch_pressed(0, mb.position)
			else:
				tracker.touch_released(0, mb.position)
		MOUSE_BUTTON_RIGHT:
			_right_dragging = mb.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				EventBus.zoom_requested.emit(1.0 / _wheel_step, mb.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				EventBus.zoom_requested.emit(_wheel_step, mb.position)


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		tracker.touch_moved(0, mm.position)
	if _right_dragging:
		EventBus.rotate_requested.emit(-mm.relative.x * _rotate_per_px)
		EventBus.tilt_requested.emit(mm.relative.y * _tilt_px_scale)

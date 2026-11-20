extends Node
## Converts touch and (desktop) mouse input into gestures on the EventBus.
## Uses _unhandled_input so touches on UI controls never move the camera.

var tracker: GestureTracker
## One finger moves the camera even though a build tool is open (HUD toggle).
var camera_mode: bool = false
var _tool: String = ""

var _wheel_step: float
var _rotate_per_px: float
var _tilt_px_scale: float
var _right_dragging: bool = false
var _key_pan: float
var _key_fast: float
var _key_rotate: float
var _key_tilt: float
var _key_zoom: float
var _last_speed: int = 1


func _ready() -> void:
	var cfg := GameData.section("input")
	tracker = GestureTracker.new(cfg)
	_wheel_step = float(cfg["mouse_wheel_zoom_step"])
	_rotate_per_px = float(cfg["mouse_rotate_rad_per_px"])
	_tilt_px_scale = float(cfg["mouse_tilt_px_scale"])
	_key_pan = float(cfg.get("key_pan_px_per_s", 900.0))
	_key_fast = float(cfg.get("key_fast_multiplier", 2.5))
	_key_rotate = float(cfg.get("key_rotate_rad_per_s", 1.6))
	_key_tilt = float(cfg.get("key_tilt_px_per_s", 260.0))
	_key_zoom = float(cfg.get("key_zoom_per_s", 2.2))
	EventBus.speed_changed.connect(func(i: int) -> void:
		if i > 0:
			_last_speed = i)
	tracker.pan.connect(EventBus.pan_requested.emit)
	tracker.pan_released.connect(EventBus.pan_released.emit)
	tracker.zoom.connect(EventBus.zoom_requested.emit)
	tracker.rotate.connect(EventBus.rotate_requested.emit)
	tracker.tilt.connect(EventBus.tilt_requested.emit)
	tracker.tap.connect(EventBus.tapped.emit)
	tracker.long_press.connect(EventBus.long_pressed.emit)
	tracker.pointer.connect(EventBus.tool_pointer.emit)
	EventBus.build_tool_selected.connect(func(tool: String, _options: Dictionary) -> void:
		_tool = tool
		if tool == "" and camera_mode:
			camera_mode = false
			EventBus.camera_mode_changed.emit(false)
		_apply_capture())


## Switches one-finger input between building and moving the camera while a
## tool stays open.
func set_camera_mode(on: bool) -> void:
	if on == camera_mode:
		return
	camera_mode = on
	tracker.reset()
	_apply_capture()
	EventBus.camera_mode_changed.emit(on)


func _apply_capture() -> void:
	tracker.capture_single = _tool != "" and not camera_mode


func _process(delta: float) -> void:
	tracker.update(delta)
	_keyboard_camera(delta)


## PC: hold WASD / arrows to move, Q/E to turn, R/F to tilt, +/- (or
## PageUp/PageDown) to zoom; Shift moves faster. Skipped while a text box
## has focus (district names).
func _keyboard_camera(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x -= 1.0
	var fast := _key_fast if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if move != Vector2.ZERO:
		# Same as dragging the map with a finger in the opposite direction.
		EventBus.pan_requested.emit(move.normalized() * _key_pan * fast * delta)
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		turn -= 1.0
	if turn != 0.0:
		EventBus.rotate_requested.emit(turn * _key_rotate * delta)
	var tilt := 0.0
	if Input.is_physical_key_pressed(KEY_R):
		tilt -= 1.0
	if Input.is_physical_key_pressed(KEY_F):
		tilt += 1.0
	if tilt != 0.0:
		EventBus.tilt_requested.emit(tilt * _key_tilt * delta)
	var zoom := 0.0
	if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD) or Input.is_physical_key_pressed(KEY_PAGEUP):
		zoom -= 1.0
	if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT) or Input.is_physical_key_pressed(KEY_PAGEDOWN):
		zoom += 1.0
	if zoom != 0.0:
		var centre := get_viewport().get_visible_rect().size * 0.5
		EventBus.zoom_requested.emit(exp(zoom * log(_key_zoom) * delta * fast), centre)


## PC: Space pauses / resumes, 1-3 set the speed, Ctrl+Z undoes.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			var now := TimeSystem.get_speed_index()
			TimeSystem.set_speed_index(0 if now > 0 else _last_speed)
		KEY_1, KEY_KP_1:
			TimeSystem.set_speed_index(1)
		KEY_2, KEY_KP_2:
			TimeSystem.set_speed_index(2)
		KEY_3, KEY_KP_3:
			TimeSystem.set_speed_index(3)
		KEY_Z:
			if key.ctrl_pressed or key.meta_pressed:
				var rt: Node = get_tree().current_scene.get_node_or_null("RoadTool") if get_tree().current_scene != null else null
				if rt != null:
					rt.undo_last()
		_:
			return
	get_viewport().set_input_as_handled()


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

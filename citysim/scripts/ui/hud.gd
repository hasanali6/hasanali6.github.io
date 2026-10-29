extends CanvasLayer
## Phase 1 HUD, built in code: top bar (date, clock, speed, FPS, settings),
## bottom tool bar (tools unlock in later phases), toast notifications,
## settings panel and the long-press location info panel.
## All touch targets are at least MIN_TOUCH (≈48 dp on a 1080p phone).

const MIN_TOUCH := 84.0
const FONT_SIZE := 24
const TOAST_SECONDS := 2.6
const BACK_EXIT_WINDOW := 2.0

const TOOLS: PackedStringArray = [
	"TOOL_ROADS", "TOOL_ZONING", "TOOL_SERVICES", "TOOL_UTILITIES",
	"TOOL_TRANSIT", "TOOL_DISTRICTS", "TOOL_ECONOMY", "TOOL_OVERLAYS",
]
const SPEED_KEYS: PackedStringArray = ["SPEED_PAUSE", "SPEED_1", "SPEED_2", "SPEED_3"]

var _root: MarginContainer
var _date_label: Label
var _clock_label: Label
var _fps_label: Label
var _speed_buttons: Array[Button] = []
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer: float = 0.0
var _settings_panel: PanelContainer
var _info_panel: PanelContainer
var _info_label: Label
var _time_slider: HSlider
var _time_dragging: bool = false
var _quality_buttons: Dictionary = {}
var _last_back_press: float = -INF
var _cell_size: float
var _playable_half: float


func _ready() -> void:
	_cell_size = GameData.num("map/cell_size_m")
	_playable_half = GameData.num("map/playable_size_m") * 0.5

	_root = MarginContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _build_theme()
	add_child(_root)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(layout)
	layout.add_child(_build_top_bar())
	layout.add_child(_build_toast())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)
	layout.add_child(_build_tool_bar())

	_settings_panel = _build_settings_panel()
	_root.add_child(_settings_panel)
	_info_panel = _build_info_panel()
	_root.add_child(_info_panel)

	EventBus.speed_changed.connect(_on_speed_changed)
	EventBus.ground_long_pressed.connect(_on_ground_long_pressed)
	EventBus.notification_posted.connect(func(_c: String, text: String) -> void: show_toast(text))
	EventBus.graphics_preset_changed.connect(_on_preset_changed)
	_on_speed_changed(TimeSystem.get_speed_index())
	_on_preset_changed(GraphicsSettings.current_preset)


func _process(delta: float) -> void:
	_date_label.text = TimeSystem.get_date_text()
	_clock_label.text = TimeSystem.get_clock_text()
	if _fps_label.visible:
		_fps_label.text = tr("LABEL_FPS") % Engine.get_frames_per_second()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_panel.modulate.a = clampf(_toast_timer / 0.4, 0.0, 1.0)
		_toast_panel.visible = _toast_timer > 0.0
	if _settings_panel.visible and not _time_dragging:
		_time_slider.set_value_no_signal(TimeSystem.get_visual_hour())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_requested()


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	_toast_timer = TOAST_SECONDS


# --- Building blocks -------------------------------------------------------

func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.08, 0.09, 0.78)
	panel.set_corner_radius_all(12)
	panel.set_content_margin_all(10)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.17, 0.19, 0.92)
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.23, 0.26, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.25, 0.42, 0.58, 0.95)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.12, 0.12, 0.13, 0.7)
	for state: String in ["normal", "focus"]:
		theme.set_stylebox(state, "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", Color(0.92, 0.92, 0.9))
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_color", "Label", Color(0.93, 0.93, 0.91))
	return theme


func _make_button(text_key: String, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text_key
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(MIN_TOUCH, MIN_TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var date_box := VBoxContainer.new()
	date_box.add_theme_constant_override("separation", 0)
	_date_label = Label.new()
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", FONT_SIZE + 6)
	date_box.add_child(_clock_label)
	date_box.add_child(_date_label)
	date_box.custom_minimum_size.x = 170
	row.add_child(date_box)

	var group := ButtonGroup.new()
	for i in SPEED_KEYS.size():
		var b := _make_button(SPEED_KEYS[i], true)
		b.button_group = group
		b.pressed.connect(TimeSystem.set_speed_index.bind(i))
		_speed_buttons.append(b)
		row.add_child(b)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)

	_fps_label = Label.new()
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fps_label.size_flags_vertical = Control.SIZE_FILL
	row.add_child(_fps_label)

	var settings := _make_button("BTN_SETTINGS")
	settings.pressed.connect(func() -> void:
		_info_panel.visible = false
		_settings_panel.visible = not _settings_panel.visible)
	row.add_child(settings)
	return bar


func _build_toast() -> Control:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	_toast_label = Label.new()
	_toast_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_toast_panel.add_child(_toast_label)
	center.add_child(_toast_panel)
	return center


func _build_tool_bar() -> Control:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for key in TOOLS:
		var b := _make_button(key)
		b.custom_minimum_size.x = 128
		b.pressed.connect(func() -> void: show_toast(tr("TOOL_LOCKED") % tr(key)))
		row.add_child(b)
	center.add_child(bar)
	return center


func _build_settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = 520
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title := Label.new()
	title.text = "SETTINGS_TITLE"
	title.add_theme_font_size_override("font_size", FONT_SIZE + 4)
	col.add_child(title)

	var q_label := Label.new()
	q_label.text = "SETTINGS_QUALITY"
	col.add_child(q_label)
	var q_row := HBoxContainer.new()
	var group := ButtonGroup.new()
	for preset in GraphicsSettings.get_preset_names():
		var b := _make_button("QUALITY_" + preset.to_upper(), true)
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			GraphicsSettings.apply_preset(preset)
			show_toast(tr("NOTIFY_QUALITY") % tr("QUALITY_" + preset.to_upper())))
		_quality_buttons[preset] = b
		q_row.add_child(b)
	col.add_child(q_row)

	var grid := CheckButton.new()
	grid.text = "SETTINGS_GRID"
	grid.custom_minimum_size.y = MIN_TOUCH
	grid.focus_mode = Control.FOCUS_NONE
	grid.toggled.connect(EventBus.grid_overlay_toggled.emit)
	col.add_child(grid)

	var fps := CheckButton.new()
	fps.text = "SETTINGS_SHOW_FPS"
	fps.custom_minimum_size.y = MIN_TOUCH
	fps.focus_mode = Control.FOCUS_NONE
	fps.button_pressed = true
	fps.toggled.connect(func(on: bool) -> void: _fps_label.visible = on)
	col.add_child(fps)

	var t_label := Label.new()
	t_label.text = "SETTINGS_TIME"
	col.add_child(t_label)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 23.99
	_time_slider.step = 0.05
	_time_slider.custom_minimum_size.y = MIN_TOUCH
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.value_changed.connect(TimeSystem.set_hour)
	_time_slider.drag_started.connect(func() -> void: _time_dragging = true)
	_time_slider.drag_ended.connect(func(_changed: bool) -> void: _time_dragging = false)
	col.add_child(_time_slider)

	var close := _make_button("BTN_CLOSE")
	close.pressed.connect(func() -> void: _settings_panel.visible = false)
	col.add_child(close)
	return panel


func _build_info_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = 420
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "INFO_TITLE"
	title.add_theme_font_size_override("font_size", FONT_SIZE + 4)
	col.add_child(title)
	_info_label = Label.new()
	_info_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_info_label)
	var close := _make_button("BTN_CLOSE")
	close.pressed.connect(func() -> void: _info_panel.visible = false)
	col.add_child(close)
	return panel


# --- Reactions -------------------------------------------------------------

func _apply_safe_area() -> void:
	var window := get_viewport().get_visible_rect().size
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var margin := 12.0
	var left := margin
	var top := margin
	var right := margin
	var bottom := margin
	if screen.x > 0.0 and screen.y > 0.0 and safe.size.x > 0:
		var s := window / screen
		left += safe.position.x * s.x
		top += safe.position.y * s.y
		right += (screen.x - safe.end.x) * s.x
		bottom += (screen.y - safe.end.y) * s.y
	_root.add_theme_constant_override("margin_left", int(left))
	_root.add_theme_constant_override("margin_top", int(top))
	_root.add_theme_constant_override("margin_right", int(right))
	_root.add_theme_constant_override("margin_bottom", int(bottom))


func _on_speed_changed(index: int) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == index)


func _on_preset_changed(preset: String) -> void:
	for key: String in _quality_buttons:
		(_quality_buttons[key] as Button).set_pressed_no_signal(key == preset)


func _on_ground_long_pressed(world_pos: Vector3) -> void:
	var cell := MapGrid.world_to_cell(world_pos, _cell_size)
	var inside := MapGrid.is_inside(world_pos, _playable_half)
	_info_label.text = "%s\n%s\n%s" % [
		tr("INFO_POSITION") % [world_pos.x, world_pos.z],
		tr("INFO_CELL") % [cell.x, cell.y],
		tr("INFO_INSIDE") if inside else tr("INFO_OUTSIDE"),
	]
	_settings_panel.visible = false
	_info_panel.visible = true


func _on_back_requested() -> void:
	if _settings_panel.visible or _info_panel.visible:
		_settings_panel.visible = false
		_info_panel.visible = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_back_press < BACK_EXIT_WINDOW:
		get_tree().quit()
	else:
		_last_back_press = now
		show_toast(tr("NOTIFY_PRESS_BACK_AGAIN"))

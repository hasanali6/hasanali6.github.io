extends CanvasLayer
## City-builder HUD in the familiar mobile layout: resource pills top-left,
## clock and speed top-centre, money and settings top-right, quick buttons on
## the left edge, a big round build button bottom-right that opens the build
## category tray. Built in code; look comes from UiStyle.
## All touch targets are at least MIN_TOUCH (≈48 dp on a 1080p phone).

const MIN_TOUCH := 84.0
const FONT_SIZE := 24
const BADGE := 56.0
const BUILD_SIZE := 128.0
const TRAY_BUTTON := 88.0
const TOAST_SECONDS := 2.6
const TRAY_FADE := 0.15
const BACK_EXIT_WINDOW := 2.0

## Build tray categories: [label key, icon, colour].
const BUILD_TOOLS: Array = [
	["TOOL_ROADS", "route", UiStyle.SLATE],
	["TOOL_BUILDINGS", "building-2", UiStyle.ORANGE],
	["TOOL_ZONING", "grid-3x3", UiStyle.GREEN],
	["TOOL_SERVICES", "shield-plus", UiStyle.RED],
	["TOOL_UTILITIES", "zap", UiStyle.GOLD],
	["TOOL_TRANSIT", "bus", UiStyle.BLUE],
	["TOOL_DISTRICTS", "map", UiStyle.PURPLE],
]
## Info overlay layers: [key, label key, colour].
const OVERLAYS: Array = [
	["power", "SVC_CAT_POWER", UiStyle.GOLD], ["water", "SVC_CAT_WATER", UiStyle.BLUE],
	["health", "SVC_CAT_HEALTH", UiStyle.RED], ["education", "SVC_CAT_EDUCATION", UiStyle.PURPLE],
	["police", "SVC_CAT_POLICE", UiStyle.BLUE], ["fire", "SVC_CAT_FIRE", UiStyle.ORANGE],
	["garbage", "SVC_CAT_GARBAGE", UiStyle.GREEN], ["deathcare", "SVC_CAT_DEATHCARE", UiStyle.SLATE],
	["pollution", "OVERLAY_POLLUTION", UiStyle.SLATE], ["happiness", "OVERLAY_HAPPINESS", UiStyle.GREEN],
	["traffic", "OVERLAY_TRAFFIC", UiStyle.ORANGE],
]
## Speed buttons: [icon, badge text].
const SPEEDS: Array = [["pause", ""], ["play", ""], ["fast-forward", "2"], ["fast-forward", "3"]]

var _layer: Control
var _safe: MarginContainer
var _clock_label: Label
var _date_label: Label
var _population_label: Label
var _happiness_label: Label
var _money_label: Label
var _perf_label: Label
var _speed_buttons: Array[Button] = []
var _build_button: Button
var _tray: PanelContainer
var _tray_tween: Tween
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer: float = 0.0
var _settings_panel: PanelContainer
var _info_panel: PanelContainer
var _info_label: Label
var _info_title: Label
var _time_slider: HSlider
var _time_dragging: bool = false
var _quality_buttons: Dictionary = {}
var _grid_check: CheckButton
var _road_panel: PanelContainer
var _road_type_buttons: Dictionary = {}
var _road_mode_buttons: Dictionary = {}
var _road_type: String = ""
var _road_mode: String = "straight"
var _zone_panel: PanelContainer
var _zone_buttons: Dictionary = {}
var _zone_mode_buttons: Dictionary = {}
var _zone_key: String = ""
var _zone_mode: String = "brush"
var _building_shown_frame: int = -1
var _cost_pill: PanelContainer
var _economy: EconomyPanel
var _catalog: CatalogPanel
var _rci: RciBars
var _money_delta: Label
var _cost_label: Label
var _cost_ok_badge: Control
var _cost_bad_badge: Control
var _last_back_press: float = -INF
var _overlay_panel: PanelContainer
var _overlay_buttons: Dictionary = {}
var _overlay_legend: Label
var _overlay_key: String = ""
var _cell_size: float
var _playable_half: float


func _ready() -> void:
	_cell_size = GameData.num("map/cell_size_m")
	_playable_half = GameData.num("map/playable_size_m") * 0.5

	_safe = MarginContainer.new()
	_safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.theme = UiStyle.build_theme(FONT_SIZE)
	add_child(_safe)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_layer)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	_place(_build_resources(), Vector2(0, 0), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	_place(_build_time_controls(), Vector2(0.5, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	_place(_build_top_right(), Vector2(1, 0), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	_place(_build_left_column(), Vector2(0, 0.5), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH)
	_place(_build_build_button(), Vector2(1, 1), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	_tray = _build_tray()
	_road_panel = _build_road_panel()
	_place(_road_panel, Vector2(0.5, 1), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_zone_panel = _build_zone_panel()
	_place(_zone_panel, Vector2(0.5, 1), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_catalog = CatalogPanel.new(FONT_SIZE, MIN_TOUCH, _close_catalog)
	_overlay_panel = _build_overlay_panel()
	# Beside the left buttons, so the city stays visible under the colours.
	_place(_overlay_panel, Vector2(0, 0.5), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH, Vector2(MIN_TOUCH + 26, 70))
	_place(_catalog.panel, Vector2(0.5, 1), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_rci = _build_rci()
	_place(_rci.get_parent(), Vector2(0, 0), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END, Vector2(0, 96))
	_cost_pill = _build_cost_pill()
	_layer.add_child(_cost_pill)
	_place(_tray, Vector2(1, 1), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN, Vector2(-BUILD_SIZE - 16, 0))
	_perf_label = _build_perf_label()
	_place(_perf_label, Vector2(0, 1), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	_toast_panel = _build_toast()
	_place(_toast_panel, Vector2(0.5, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END, Vector2(0, 150))
	_settings_panel = _build_settings_panel()
	_place(_settings_panel, Vector2(0.5, 0.5), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_info_panel = _build_info_panel()
	_place(_info_panel, Vector2(0.5, 0.5), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_economy = EconomyPanel.new(FONT_SIZE, MIN_TOUCH)
	_place(_economy.card, Vector2(0.5, 0.5), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)

	EventBus.speed_changed.connect(_on_speed_changed)
	EventBus.ground_long_pressed.connect(_on_ground_long_pressed)
	EventBus.notification_posted.connect(func(_c: String, text: String) -> void: show_toast(text))
	EventBus.graphics_preset_changed.connect(_on_preset_changed)
	EventBus.tapped.connect(func(_p: Vector2) -> void: _set_tray_open(false))
	EventBus.money_changed.connect(func(balance: int) -> void: _money_label.text = UiStyle.format_int(balance))
	EventBus.road_preview_changed.connect(_on_road_preview)
	EventBus.building_inspected.connect(_on_building_inspected)
	EventBus.city_stats_changed.connect(_on_city_stats)
	EventBus.demand_changed.connect(func(d: Dictionary) -> void: _rci.set_values(d))
	EventBus.budget_settled.connect(_on_budget)
	# While placing a service, show its coverage like city builders do.
	EventBus.build_tool_selected.connect(func(tool: String, options: Dictionary) -> void:
		var item: Dictionary = options.get("item", {})
		if tool == "place" and item.has("category"):
			_select_overlay(str(item["category"]))
		elif tool == "place" and not _overlay_panel.visible:
			_select_overlay(""))
	EventBus.road_inspected.connect(_on_road_inspected)
	EventBus.traffic_updated.connect(func() -> void:
		if _overlay_panel.visible:
			_refresh_overlay_legend())
	EventBus.services_changed.connect(func() -> void:
		if _overlay_panel.visible:
			_refresh_overlay_legend())
	_on_speed_changed(TimeSystem.get_speed_index())
	_on_preset_changed(GraphicsSettings.current_preset)


func _process(delta: float) -> void:
	# Only touch label text when it changes; re-layout every frame is wasted work.
	_set_text(_clock_label, TimeSystem.get_clock_text())
	_set_text(_date_label, TimeSystem.get_date_text())
	if _perf_label.visible:
		var hz := GraphicsSettings.get_refresh_hz()
		_set_text(_perf_label, tr("LABEL_PERF") % [
			Engine.get_frames_per_second(), GraphicsSettings.get_gpu_ms(), GraphicsSettings.get_cpu_ms(),
			("%d Hz" % roundi(hz)) if hz > 0.0 else "? Hz", roundi(GraphicsSettings.get_render_scale() * 100.0)])
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


# --- Layout helpers ---------------------------------------------------------

## Anchors a control to a point of the safe area and lets it grow from there.
func _place(control: Control, anchor: Vector2, grow_h: Control.GrowDirection,
		grow_v: Control.GrowDirection, offset: Vector2 = Vector2.ZERO) -> void:
	_layer.add_child(control)
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = offset.x
	control.offset_right = offset.x
	control.offset_top = offset.y
	control.offset_bottom = offset.y
	control.grow_horizontal = grow_h
	control.grow_vertical = grow_v


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _label(text: String, size: int = FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Resource pill: coloured icon badge + value.
func _pill(icon_name: String, color: Color, min_width: float) -> Array:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pill.add_child(row)
	row.add_child(UiStyle.badge(icon_name, color, BADGE))
	var value := _label("")
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value.custom_minimum_size.x = min_width
	row.add_child(value)
	return [pill, value]


# --- Sections ---------------------------------------------------------------

func _build_resources() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var pop := _pill("users", UiStyle.BLUE, 70)
	_population_label = pop[1]
	_population_label.text = UiStyle.format_int(0)
	row.add_child(pop[0])
	var happy := _pill("smile", UiStyle.GREEN, 50)
	_happiness_label = happy[1]
	# Happiness is computed from Phase 4 on; until then there is nothing to show.
	_happiness_label.text = "—"
	row.add_child(happy[0])
	return row


func _build_time_controls() -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	var clock_pill := PanelContainer.new()
	clock_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock_box := UiStyle.pill_box()
	clock_box.content_margin_left = 22
	clock_pill.add_theme_stylebox_override("panel", clock_box)
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 12)
	clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_clock_label = _label("", FONT_SIZE + 6)
	_clock_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_date_label = _label("", FONT_SIZE - 4)
	_date_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	clock_row.add_child(_clock_label)
	clock_row.add_child(_date_label)
	clock_pill.add_child(clock_row)
	col.add_child(clock_pill)

	var speeds := HBoxContainer.new()
	speeds.alignment = BoxContainer.ALIGNMENT_CENTER
	speeds.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in SPEEDS.size():
		var b := UiStyle.round_button(SPEEDS[i][0], UiStyle.SLATE, MIN_TOUCH * 0.82, true, UiStyle.GREEN)
		b.custom_minimum_size = Vector2(MIN_TOUCH, MIN_TOUCH * 0.82)
		b.button_group = group
		b.pressed.connect(TimeSystem.set_speed_index.bind(i))
		if SPEEDS[i][1] != "":
			var tag := _label(SPEEDS[i][1], FONT_SIZE - 6)
			tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			tag.position -= Vector2(10, 30)
			b.add_child(tag)
		_speed_buttons.append(b)
		speeds.add_child(b)
	col.add_child(speeds)
	return col


func _build_top_right() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var money := _pill("coins", UiStyle.GOLD, 120)
	_money_label = money[1]
	_money_label.text = UiStyle.format_int(EconomySystem.balance)
	# Monthly net under the balance, like the treasury line in city builders.
	var value_col := VBoxContainer.new()
	value_col.add_theme_constant_override("separation", -6)
	var parent := _money_label.get_parent()
	parent.remove_child(_money_label)
	value_col.add_child(_money_label)
	_money_delta = _label("", FONT_SIZE - 8)
	_money_delta.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value_col.add_child(_money_delta)
	parent.add_child(value_col)
	money[0].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(money[0])
	var settings := UiStyle.round_button("settings", UiStyle.SLATE, MIN_TOUCH)
	settings.pressed.connect(func() -> void:
		_info_panel.visible = false
		_set_tray_open(false)
		_settings_panel.visible = not _settings_panel.visible)
	row.add_child(settings)
	return row


func _build_left_column() -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 14)
	var overlays := UiStyle.round_button("layers", UiStyle.TEAL, MIN_TOUCH)
	overlays.pressed.connect(func() -> void:
		if _overlay_panel.visible:
			_close_overlay_panel()
		else:
			_open_overlay_panel())
	col.add_child(overlays)
	var economy := UiStyle.round_button("chart-no-axes-column", UiStyle.GREEN, MIN_TOUCH)
	economy.pressed.connect(func() -> void:
		_settings_panel.visible = false
		_info_panel.visible = false
		_set_tray_open(false)
		_economy.open())
	col.add_child(economy)
	return col


func _build_build_button() -> Control:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", -10)
	_build_button = UiStyle.round_button("hard-hat", UiStyle.ORANGE, BUILD_SIZE, true, UiStyle.ORANGE.darkened(0.1))
	_build_button.toggled.connect(_set_tray_open)
	col.add_child(_build_button)
	var caption := _label("LABEL_BUILD", FONT_SIZE - 2)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)
	return col


func _build_tray() -> PanelContainer:
	var tray := PanelContainer.new()
	tray.visible = false
	var box := UiStyle.pill_box()
	box.set_corner_radius_all(28)
	box.set_content_margin_all(14)
	tray.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	tray.add_child(row)
	for entry: Array in BUILD_TOOLS:
		var key: String = entry[0]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var b := UiStyle.round_button(entry[1], entry[2], TRAY_BUTTON)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if key == "TOOL_ROADS":
			b.pressed.connect(_open_road_panel)
		elif key == "TOOL_BUILDINGS":
			b.pressed.connect(_open_catalog.bind("buildings"))
		elif key == "TOOL_SERVICES":
			b.pressed.connect(_open_catalog.bind("services"))
		elif key == "TOOL_UTILITIES":
			b.pressed.connect(_open_catalog.bind("utilities"))
		elif key == "TOOL_ZONING":
			b.pressed.connect(_open_zone_panel)
		else:
			b.pressed.connect(func() -> void: show_toast(tr("TOOL_LOCKED") % tr(key)))
		col.add_child(b)
		var caption := _label(key, FONT_SIZE - 6)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(caption)
		row.add_child(col)
	return tray


func _build_perf_label() -> Label:
	var l := _label("", FONT_SIZE - 8)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _build_toast() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pill.add_child(row)
	row.add_child(UiStyle.badge("bell", UiStyle.ORANGE, BADGE * 0.8))
	_toast_label = _label("", FONT_SIZE - 2)
	_toast_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(_toast_label)
	return pill


## Light menu card with a coloured header, a title and a round close button.
func _card(title_key: String, width: float) -> Array:
	return UiStyle.card(title_key, width, FONT_SIZE, MIN_TOUCH)


func _build_settings_panel() -> PanelContainer:
	var parts := _card("SETTINGS_TITLE", 560)
	var content: VBoxContainer = parts[1]
	content.add_child(_label("SETTINGS_QUALITY", FONT_SIZE - 2))
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for preset in GraphicsSettings.get_preset_names():
		var b := Button.new()
		b.text = "QUALITY_" + preset.to_upper()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_group = group
		b.custom_minimum_size.y = MIN_TOUCH * 0.8
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			GraphicsSettings.apply_preset(preset)
			show_toast(tr("NOTIFY_QUALITY") % tr("QUALITY_" + preset.to_upper())))
		_quality_buttons[preset] = b
		q_row.add_child(b)
	content.add_child(q_row)

	var grid := CheckButton.new()
	grid.text = "SETTINGS_GRID"
	grid.custom_minimum_size.y = MIN_TOUCH * 0.8
	grid.focus_mode = Control.FOCUS_NONE
	grid.toggled.connect(EventBus.grid_overlay_toggled.emit)
	_grid_check = grid
	content.add_child(grid)

	var perf := CheckButton.new()
	perf.text = "SETTINGS_SHOW_FPS"
	perf.custom_minimum_size.y = MIN_TOUCH * 0.8
	perf.focus_mode = Control.FOCUS_NONE
	perf.button_pressed = true
	perf.toggled.connect(func(on: bool) -> void: _perf_label.visible = on)
	content.add_child(perf)

	content.add_child(_label("SETTINGS_TIME", FONT_SIZE - 2))
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 23.99
	_time_slider.step = 0.05
	_time_slider.custom_minimum_size.y = MIN_TOUCH * 0.7
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.value_changed.connect(TimeSystem.set_hour)
	_time_slider.drag_started.connect(func() -> void: _time_dragging = true)
	_time_slider.drag_ended.connect(func(_changed: bool) -> void: _time_dragging = false)
	content.add_child(_time_slider)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 10)
	var save := Button.new()
	save.text = "SETTINGS_SAVE"
	save.focus_mode = Control.FOCUS_NONE
	save.custom_minimum_size.y = MIN_TOUCH * 0.8
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func() -> void: _save_system().save_game())
	save_row.add_child(save)
	var fresh := Button.new()
	fresh.text = "SETTINGS_NEW_CITY"
	fresh.focus_mode = Control.FOCUS_NONE
	fresh.custom_minimum_size.y = MIN_TOUCH * 0.8
	fresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fresh.pressed.connect(_confirm_new_city)
	save_row.add_child(fresh)
	content.add_child(save_row)
	return parts[0]


func _build_info_panel() -> PanelContainer:
	var parts := _card("INFO_TITLE", 440)
	# Card -> column -> header -> header row -> title label.
	_info_title = (parts[0] as Control).get_child(0).get_child(0).get_child(0).get_child(0) as Label
	_info_label = _label("", FONT_SIZE - 2)
	_info_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	(parts[1] as VBoxContainer).add_child(_info_label)
	return parts[0]


func _build_road_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var box := UiStyle.pill_box()
	box.set_corner_radius_all(28)
	box.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var mode_group := ButtonGroup.new()
	for entry: Array in [["straight", "slash", "MODE_STRAIGHT"], ["curve", "spline", "MODE_CURVE"], ["bulldoze", "trash-2", "MODE_BULLDOZE"]]:
		var mode: String = entry[0]
		var b := UiStyle.round_button(entry[1], UiStyle.SLATE, MIN_TOUCH, true,
			UiStyle.RED if mode == "bulldoze" else UiStyle.GREEN)
		b.button_group = mode_group
		b.pressed.connect(func() -> void: _select_road(_road_type, mode))
		_road_mode_buttons[mode] = b
		top.add_child(b)
		var caption := _label(entry[2], FONT_SIZE - 4)
		top.add_child(caption)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	var close := UiStyle.round_button("x", UiStyle.RED, MIN_TOUCH * 0.85)
	close.pressed.connect(_close_road_panel)
	top.add_child(close)
	col.add_child(top)

	var types_row := HBoxContainer.new()
	types_row.add_theme_constant_override("separation", 10)
	var type_group := ButtonGroup.new()
	for type: String in GameData.value("roads/order"):
		var cfg := GameData.section("roads/types/" + type)
		var b := UiStyle.chip_button("", UiStyle.SLATE, UiStyle.BLUE, Vector2(150, MIN_TOUCH))
		b.text = "%s\n%s" % [tr(cfg["name_key"]), tr("ROAD_TYPE_INFO") % [roundi(RoadTypes.total_width(cfg)), int(cfg["cost_per_m"])]]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", FONT_SIZE - 6)
		b.button_group = type_group
		b.pressed.connect(func() -> void: _select_road(type, _road_mode))
		_road_type_buttons[type] = b
		types_row.add_child(b)
	col.add_child(types_row)
	return panel


func _build_zone_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var box := UiStyle.pill_box()
	box.set_corner_radius_all(28)
	box.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var mode_group := ButtonGroup.new()
	for entry: Array in [["brush", "paintbrush", "MODE_BRUSH"], ["fill", "paint-bucket", "MODE_FILL"], ["erase", "eraser", "MODE_ERASE"]]:
		var mode: String = entry[0]
		var b := UiStyle.round_button(entry[1], UiStyle.SLATE, MIN_TOUCH, true,
			UiStyle.RED if mode == "erase" else UiStyle.GREEN)
		b.button_group = mode_group
		b.pressed.connect(func() -> void: _select_zone(_zone_key, mode))
		_zone_mode_buttons[mode] = b
		top.add_child(b)
		top.add_child(_label(entry[2], FONT_SIZE - 4))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	var close := UiStyle.round_button("x", UiStyle.RED, MIN_TOUCH * 0.85)
	close.pressed.connect(_close_zone_panel)
	top.add_child(close)
	col.add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for key: String in GameData.value("zones/order"):
		var cfg := GameData.section("zones/types/" + key)
		var color := DataLoader.to_color(cfg["color"])
		var b := UiStyle.chip_button(cfg["short_key"], color.darkened(0.25), color.lightened(0.15), Vector2(118, MIN_TOUCH))
		b.add_theme_font_size_override("font_size", FONT_SIZE - 6)
		b.button_group = group
		b.pressed.connect(func() -> void: _select_zone(key, _zone_mode if _zone_mode != "erase" else "brush"))
		_zone_buttons[key] = b
		row.add_child(b)
	col.add_child(row)
	return panel


func _open_zone_panel() -> void:
	_close_overlay_panel()
	_road_panel.visible = false
	_catalog.panel.visible = false
	_cost_pill.visible = false
	_set_tray_open(false)
	_settings_panel.visible = false
	_info_panel.visible = false
	_zone_panel.visible = true
	_build_button.get_parent().visible = false
	if _zone_key == "":
		_zone_key = str((GameData.value("zones/order") as Array)[0])
	_select_zone(_zone_key, _zone_mode)


func _close_zone_panel() -> void:
	_zone_panel.visible = false
	_build_button.get_parent().visible = true
	EventBus.build_tool_selected.emit("", {})


func _select_zone(key: String, mode: String) -> void:
	_zone_key = key
	_zone_mode = mode
	for k: String in _zone_buttons:
		(_zone_buttons[k] as Button).set_pressed_no_signal(k == key and mode != "erase")
	for k: String in _zone_mode_buttons:
		(_zone_mode_buttons[k] as Button).set_pressed_no_signal(k == mode)
	EventBus.build_tool_selected.emit("zone", {"zone": key, "mode": mode})


func _on_building_inspected(info: Dictionary) -> void:
	_building_shown_frame = Engine.get_process_frames()
	var lines := PackedStringArray([tr(info["zone_key"])])
	if str(info.get("service", "")) != "":
		_service_info(info, lines)
		_show_info(lines)
		return
	if info.get("burned", false):
		lines.append(tr("BUILDING_BURNED"))
	elif info.get("abandoned", false):
		lines.append(tr("BUILDING_ABANDONED"))
	if info["zone_key"] != "BUILD_PARK":
		lines.append(tr("BUILDING_LEVEL") % [info["level"], info["floors"]])
	if int(info.get("households_cap", 0)) > 0:
		lines.append(tr("BUILDING_HOMES") % [info["households"], info["households_cap"]])
	if int(info.get("jobs", 0)) > 0:
		lines.append(tr("BUILDING_JOBS") % [info["employees"], info["jobs"]])
		lines.append(tr("BUILDING_PROFIT") % UiStyle.format_int(roundi(float(info["profit"]))))
	if info["zone_key"] != "BUILD_PARK" and not info.get("abandoned", false):
		if int(info.get("households_cap", 0)) > 0 and int(info.get("households", 0)) > 0:
			lines.append(tr("BUILDING_PEOPLE") % [int(info.get("residents", 0)), roundi(float(info.get("happiness", 0.0)))])
		lines.append(tr("BUILDING_UTILITIES") % [_yes_no(info.get("power", true)), _yes_no(info.get("water", true)),
			_yes_no(info.get("sewage", true))])
		if info.get("polluted_water", false):
			lines.append(tr("BUILDING_POLLUTED_WATER"))
		if int(info.get("no_utility_months", 0)) > 0:
			lines.append(tr("BUILDING_UTILITY_WARNING") % maxi(GameData.integer("services/effects/abandon_without_utility_months")
				- int(info["no_utility_months"]), 1))
		var cov: Dictionary = info.get("coverage", {})
		var pct := func(key: String) -> int: return roundi(ServiceRules.category_coverage(cov, key) * 100.0)
		lines.append(tr("BUILDING_COVERAGE") % [pct.call("health"), pct.call("education"), pct.call("police"),
			pct.call("fire"), pct.call("garbage"), pct.call("deathcare")])
		if float(info.get("pollution", 0.0)) > 0.02:
			lines.append(tr("BUILDING_POLLUTION") % roundi(float(info["pollution"]) * 100.0))
		if float(info.get("commute", -1.0)) >= 0.0 and int(info.get("households", 0)) > 0:
			lines.append(tr("BUILDING_COMMUTE") % roundi(float(info["commute"])))
	lines.append(tr("BUILDING_SIZE") % [roundi(info["width"]), roundi(info["depth"])])
	_show_info(lines)


func _on_road_inspected(info: Dictionary) -> void:
	_building_shown_frame = Engine.get_process_frames()
	var lines := PackedStringArray([tr(info["type_key"])])
	lines.append(tr("ROAD_INFO_LANES") % [int(info["lanes"]), roundi(float(info["limit_kmh"]))])
	lines.append(tr("ROAD_INFO_DAILY") % UiStyle.format_int(roundi(float(info["daily"]))))
	lines.append(tr("ROAD_INFO_LOAD") % [roundi(float(info["ratio"]) * 100.0), roundi(float(info["speed_kmh"]))])
	lines.append(tr("ROAD_INFO_LENGTH") % roundi(float(info["length"])))
	_show_info(lines)
	_info_title.text = "ROAD_INFO_TITLE"


func _show_info(lines: PackedStringArray) -> void:
	_info_title.text = "BUILDING_INFO_TITLE"
	_info_label.text = "\n".join(lines)
	_settings_panel.visible = false
	_set_tray_open(false)
	_info_panel.visible = true


func _yes_no(on: bool) -> String:
	return tr("WORD_YES") if on else tr("WORD_NO")


## Info card lines for a service or utility building.
func _service_info(info: Dictionary, lines: PackedStringArray) -> void:
	var d: Dictionary = _service_system().building_details(int(info.get("id", -1)))
	if d.is_empty():
		return
	lines.append(tr("SVC_INFO_UPKEEP") % [UiStyle.format_int(roundi(float(d["upkeep"]))),
		roundi(EconomySystem.service_budget(str(d["category"])) * 100.0)])
	if float(d["power"]) > 0.0:
		lines.append(tr("SVC_INFO_POWER") % float(d["power"]))
	if float(d["water"]) > 0.0:
		lines.append(tr("SVC_INFO_WATER") % UiStyle.format_int(roundi(float(d["water"]))))
	if float(d["sewage"]) > 0.0:
		lines.append(tr("SVC_INFO_SEWAGE") % UiStyle.format_int(roundi(float(d["sewage"]))))
	if float(d["capacity"]) > 0.0:
		lines.append(tr("SVC_INFO_CAPACITY") % [UiStyle.format_int(int(d["served"])), UiStyle.format_int(roundi(float(d["capacity"])))])
	if float(d["radius"]) > 0.0:
		lines.append(tr("SVC_INFO_RADIUS") % (float(d["radius"]) / 1000.0))
	if float(d["storage_max"]) > 0.0:
		lines.append(tr("SVC_INFO_STORAGE") % [UiStyle.format_int(roundi(float(d["storage"]))), UiStyle.format_int(roundi(float(d["storage_max"])))])
	if float(d["load"]) < 0.99:
		lines.append(tr("SVC_INFO_OVERLOADED") % roundi(float(d["load"]) * 100.0))


func _build_rci() -> RciBars:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyle.pill_box()
	box.set_corner_radius_all(18)
	box.set_content_margin_all(6)
	pill.add_theme_stylebox_override("panel", box)
	var bars := RciBars.new()
	for key: String in ["ZONE_RCI_R", "ZONE_RCI_C", "ZONE_RCI_O", "ZONE_RCI_I"]:
		bars.letters.append(tr(key))
	bars.colors = [UiStyle.GREEN, UiStyle.BLUE, UiStyle.PURPLE, UiStyle.GOLD]
	pill.add_child(bars)
	return bars


func _on_city_stats(stats: Dictionary) -> void:
	_population_label.text = UiStyle.format_int(int(stats.get("population", 0)))
	_happiness_label.text = "—" if int(stats.get("population", 0)) == 0 else "%d%%" % roundi(float(stats.get("happiness", 50.0)))


func _on_budget(ledger: Dictionary) -> void:
	var net := roundi(float(ledger.get("net", 0.0)))
	_money_delta.text = ("+" if net >= 0 else "") + UiStyle.format_int(net) + tr("ECON_PER_MONTH")
	_money_delta.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65) if net >= 0 else Color(1.0, 0.6, 0.6))


func _open_catalog(group: String) -> void:
	_road_panel.visible = false
	_zone_panel.visible = false
	_overlay_panel.visible = false
	_cost_pill.visible = false
	_set_tray_open(false)
	_settings_panel.visible = false
	_info_panel.visible = false
	_build_button.get_parent().visible = false
	if group == "buildings":
		_catalog.open("BUILD_CATALOG", GameData.value("catalog/items"))
	else:
		_catalog.open("SVC_CATALOG_" + group.to_upper(), _service_system().catalog_items(group))


func _service_system() -> Node:
	return get_tree().current_scene.get_node("ServiceSystem")


# --- Info overlays ---------------------------------------------------------------

func _build_overlay_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var box := UiStyle.pill_box()
	box.set_corner_radius_all(24)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var top := HBoxContainer.new()
	var title := _label("TOOL_OVERLAYS", FONT_SIZE - 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := UiStyle.round_button("x", UiStyle.RED, MIN_TOUCH * 0.7)
	close.pressed.connect(_close_overlay_panel)
	top.add_child(close)
	col.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for entry: Array in OVERLAYS:
		var key: String = entry[0]
		var color: Color = entry[2]
		var b := UiStyle.chip_button(entry[1], color.darkened(0.25), color.lightened(0.1), Vector2(132, MIN_TOUCH * 0.62))
		b.add_theme_font_size_override("font_size", FONT_SIZE - 7)
		b.button_group = group
		b.pressed.connect(func() -> void: _select_overlay(key if _overlay_key != key else ""))
		_overlay_buttons[key] = b
		grid.add_child(b)
	col.add_child(grid)
	_overlay_legend = _label("", FONT_SIZE - 8)
	_overlay_legend.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_overlay_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_legend.custom_minimum_size.x = 400
	col.add_child(_overlay_legend)
	return panel


func _open_overlay_panel() -> void:
	_set_tray_open(false)
	_settings_panel.visible = false
	_info_panel.visible = false
	_overlay_panel.visible = true
	_select_overlay(_overlay_key if _overlay_key != "" else "power")


func _close_overlay_panel() -> void:
	_overlay_panel.visible = false
	_select_overlay("")


func _select_overlay(key: String) -> void:
	_overlay_key = key
	for k: String in _overlay_buttons:
		(_overlay_buttons[k] as Button).set_pressed_no_signal(k == key)
	EventBus.overlay_selected.emit(key)
	_refresh_overlay_legend()


func _refresh_overlay_legend() -> void:
	var text := ""
	match _overlay_key:
		"":
			text = ""
		"power", "water":
			var totals: Dictionary = _service_system().utility_totals()
			var t: Array = totals[_overlay_key]
			if _overlay_key == "power":
				text = tr("OVERLAY_POWER_TOTAL") % [float(t[0]), float(t[1])]
			else:
				var sw: Array = totals["sewage"]
				text = tr("OVERLAY_WATER_TOTAL") % [UiStyle.format_int(roundi(float(t[0]))), UiStyle.format_int(roundi(float(t[1]))),
					UiStyle.format_int(roundi(float(sw[0]))), UiStyle.format_int(roundi(float(sw[1])))]
		"pollution":
			text = tr("OVERLAY_LEGEND_POLLUTION")
		"traffic":
			var traffic := get_tree().current_scene.get_node("TrafficSystem")
			var vehicles := get_tree().current_scene.get_node("VehicleSystem")
			text = tr("OVERLAY_LEGEND_TRAFFIC") % [roundi(float(traffic.last_stats.get("avg_commute", 0.0))), int(vehicles.active)]
		_:
			text = tr("OVERLAY_LEGEND")
	_overlay_legend.text = text


func _close_catalog() -> void:
	_catalog.panel.visible = false
	_cost_pill.visible = false
	if not _overlay_panel.visible:
		_select_overlay("")
	_build_button.get_parent().visible = true
	EventBus.build_tool_selected.emit("", {})


func _save_system() -> Node:
	return get_tree().current_scene.get_node("SaveSystem")


var _new_city_armed: float = -INF


## Asks for a second tap within a few seconds before wiping the city.
func _confirm_new_city() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _new_city_armed < BACK_EXIT_WINDOW * 2.0:
		_save_system().new_city()
	else:
		_new_city_armed = now
		show_toast(tr("NOTIFY_NEW_CITY_CONFIRM"))


func _build_cost_pill() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	_cost_ok_badge = UiStyle.badge("coins", UiStyle.GOLD, BADGE * 0.8)
	_cost_bad_badge = UiStyle.badge("ban", UiStyle.RED, BADGE * 0.8)
	row.add_child(_cost_ok_badge)
	row.add_child(_cost_bad_badge)
	_cost_label = _label("", FONT_SIZE - 2)
	_cost_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(_cost_label)
	return pill


func _open_road_panel() -> void:
	_close_overlay_panel()
	_zone_panel.visible = false
	_catalog.panel.visible = false
	_set_tray_open(false)
	_settings_panel.visible = false
	_info_panel.visible = false
	_road_panel.visible = true
	_build_button.get_parent().visible = false
	EventBus.grid_overlay_toggled.emit(true)
	if _road_type == "":
		_road_type = str((GameData.value("roads/order") as Array)[0])
	_select_road(_road_type, _road_mode)


func _close_road_panel() -> void:
	_road_panel.visible = false
	_cost_pill.visible = false
	_build_button.get_parent().visible = true
	EventBus.grid_overlay_toggled.emit(_grid_check.button_pressed)
	EventBus.build_tool_selected.emit("", {})


func _select_road(type: String, mode: String) -> void:
	_road_type = type
	_road_mode = mode
	for key: String in _road_type_buttons:
		(_road_type_buttons[key] as Button).set_pressed_no_signal(key == type)
	for key: String in _road_mode_buttons:
		(_road_mode_buttons[key] as Button).set_pressed_no_signal(key == mode)
	EventBus.build_tool_selected.emit("road", {"type": type, "mode": mode})


func _on_road_preview(info: Dictionary) -> void:
	if not info.get("active", false):
		_cost_pill.visible = false
		return
	var valid: bool = info.get("valid", false)
	_cost_ok_badge.visible = valid
	_cost_bad_badge.visible = not valid
	var length := roundi(float(info.get("length", 0.0)))
	if info.has("refund"):
		_cost_label.text = tr("ROAD_REFUND") % UiStyle.format_int(info["refund"])
	elif not valid:
		_cost_label.text = tr(info.get("error", ""))
	elif info.has("hint"):
		_cost_label.text = "%s · %s" % [UiStyle.format_int(info["cost"]), tr(info["hint"])]
	else:
		_cost_label.text = tr("ROAD_COST") % [UiStyle.format_int(info["cost"]), length]
	_cost_pill.visible = true
	_cost_pill.reset_size()
	var local: Vector2 = info.get("screen_pos", Vector2.ZERO) - _layer.global_position
	_cost_pill.position = local + Vector2(-_cost_pill.size.x * 0.5, -130.0)


# --- Reactions --------------------------------------------------------------

func _set_tray_open(open: bool) -> void:
	_build_button.set_pressed_no_signal(open)
	if _tray_tween:
		_tray_tween.kill()
	if open:
		_settings_panel.visible = false
		_info_panel.visible = false
		_tray.visible = true
	_tray_tween = create_tween()
	_tray_tween.tween_property(_tray, "modulate:a", 1.0 if open else 0.0, TRAY_FADE)
	if not open:
		_tray_tween.tween_callback(func() -> void: _tray.visible = false)


func _apply_safe_area() -> void:
	var window := get_viewport().get_visible_rect().size
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var margin := 14.0
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
	_safe.add_theme_constant_override("margin_left", int(left))
	_safe.add_theme_constant_override("margin_top", int(top))
	_safe.add_theme_constant_override("margin_right", int(right))
	_safe.add_theme_constant_override("margin_bottom", int(bottom))


func _on_speed_changed(index: int) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == index)


func _on_preset_changed(preset: String) -> void:
	for key: String in _quality_buttons:
		(_quality_buttons[key] as Button).set_pressed_no_signal(key == preset)


func _on_ground_long_pressed(world_pos: Vector3) -> void:
	_show_location.call_deferred(world_pos)


func _show_location(world_pos: Vector3) -> void:
	if _building_shown_frame == Engine.get_process_frames():
		return
	_info_title.text = "INFO_TITLE"
	var cell := MapGrid.world_to_cell(world_pos, _cell_size)
	var inside := MapGrid.is_inside(world_pos, _playable_half)
	_info_label.text = "%s\n%s\n%s" % [
		tr("INFO_POSITION") % [world_pos.x, world_pos.z],
		tr("INFO_CELL") % [cell.x, cell.y],
		tr("INFO_INSIDE") if inside else tr("INFO_OUTSIDE"),
	]
	_settings_panel.visible = false
	_set_tray_open(false)
	_info_panel.visible = true


func _on_back_requested() -> void:
	if _road_panel.visible:
		_close_road_panel()
		return
	if _zone_panel.visible:
		_close_zone_panel()
		return
	if _catalog.panel.visible:
		_close_catalog()
		return
	if _overlay_panel.visible:
		_close_overlay_panel()
		return
	if _economy.card.visible:
		_economy.card.visible = false
		return
	if _settings_panel.visible or _info_panel.visible or _tray.visible:
		_settings_panel.visible = false
		_info_panel.visible = false
		_set_tray_open(false)
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_back_press < BACK_EXIT_WINDOW:
		get_tree().quit()
	else:
		_last_back_press = now
		show_toast(tr("NOTIFY_PRESS_BACK_AGAIN"))

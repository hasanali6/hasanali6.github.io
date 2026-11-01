class_name TransitPanel
extends RefCounted
## Bottom panel of the transit tool ("Ulaşım"):
##   row 1: bus / tram / metro, what the line being drawn costs (or why it cannot be
##          built), open the line, clear the stops, close;
##   row 2: one chip per line in its colour, and the shared ticket price;
##   row 3: the chosen line: riders, how full it is, length, vehicles (- / +)
##          and delete.
## While the panel is open, taps on roads add stops (TransitSystem).

const GAP := 10

var panel: PanelContainer
var closed: Callable

var _transit: Node
var _font: int
var _touch: float
var _type: String = "bus"
var _type_buttons: Dictionary = {}
var _info: Label
var _lines_row: HBoxContainer
var _ticket_label: Label
var _detail: HBoxContainer
var _detail_label: Label
var _vehicle_label: Label
var _selected: int = -1


func _init(transit: Node, font_size: int, min_touch: float, on_close: Callable) -> void:
	_transit = transit
	_font = font_size
	_touch = min_touch
	closed = on_close
	panel = PanelContainer.new()
	panel.visible = false
	var box := UiStyle.pill_box()
	box.set_corner_radius_all(28)
	box.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", GAP)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", GAP)
	var group := ButtonGroup.new()
	for type: String in ["bus", "tram", "metro"]:
		var cfg := GameData.section("transit/types/" + type)
		var color: Color = {"bus": UiStyle.BLUE, "tram": UiStyle.TEAL, "metro": UiStyle.PURPLE}[type]
		var b := UiStyle.chip_button(cfg["name_key"], color.darkened(0.3), color.lightened(0.1), Vector2(130, min_touch * 0.72))
		b.add_theme_font_size_override("font_size", font_size - 5)
		b.button_group = group
		b.pressed.connect(_select_type.bind(type))
		_type_buttons[type] = b
		top.add_child(b)
	_info = UiStyle.label("", font_size - 5)
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.custom_minimum_size.x = 300
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_info)
	var open := _action("TRANSIT_OPEN", UiStyle.GREEN, 150)
	open.pressed.connect(func() -> void:
		if _transit.finish_draft():
			_selected = int((_transit.lines.back() as Dictionary)["id"])
			_refresh())
	top.add_child(open)
	var clear := _action("TRANSIT_CLEAR", UiStyle.SLATE, 120)
	clear.pressed.connect(func() -> void: _transit.cancel_draft())
	top.add_child(clear)
	var close := UiStyle.round_button("x", UiStyle.RED, min_touch * 0.8)
	close.pressed.connect(func() -> void: closed.call())
	top.add_child(close)
	col.add_child(top)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", GAP)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, min_touch * 0.7)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines_row = HBoxContainer.new()
	_lines_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_lines_row)
	mid.add_child(scroll)
	mid.add_child(UiStyle.label("TRANSIT_TICKET", font_size - 5))
	var minus := _small("−")
	minus.pressed.connect(func() -> void: _transit.set_ticket(_transit.ticket_price - float(GameData.value("transit/ticket/step"))))
	mid.add_child(minus)
	_ticket_label = UiStyle.label("", font_size - 4)
	_ticket_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ticket_label.custom_minimum_size.x = 64
	_ticket_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_ticket_label)
	var plus := _small("+")
	plus.pressed.connect(func() -> void: _transit.set_ticket(_transit.ticket_price + float(GameData.value("transit/ticket/step"))))
	mid.add_child(plus)
	col.add_child(mid)

	_detail = HBoxContainer.new()
	_detail.add_theme_constant_override("separation", GAP)
	_detail_label = UiStyle.label("", font_size - 6)
	_detail_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(_detail_label)
	_detail.add_child(UiStyle.label("TRANSIT_VEHICLES", font_size - 5))
	var less := _small("−")
	less.pressed.connect(func() -> void: _change_vehicles(-1))
	_detail.add_child(less)
	_vehicle_label = UiStyle.label("", font_size - 4)
	_vehicle_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_vehicle_label.custom_minimum_size.x = 40
	_vehicle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_child(_vehicle_label)
	var more := _small("+")
	more.pressed.connect(func() -> void: _change_vehicles(1))
	_detail.add_child(more)
	var trash := UiStyle.round_button("trash-2", UiStyle.RED, min_touch * 0.66)
	trash.pressed.connect(func() -> void:
		if _selected >= 0:
			_transit.delete_line(_selected)
			_selected = -1
			_refresh())
	_detail.add_child(trash)
	col.add_child(_detail)

	EventBus.transit_changed.connect(_refresh_if_open)
	EventBus.mobility_reported.connect(func(_r: Dictionary) -> void: _refresh_if_open())
	EventBus.transit_draft_changed.connect(_on_draft)


func _action(text_key: String, color: Color, width: float) -> Button:
	var b := UiStyle.chip_button(text_key, color.darkened(0.15), color.darkened(0.3), Vector2(width, _touch * 0.72))
	b.toggle_mode = false
	b.add_theme_font_size_override("font_size", _font - 5)
	return b


func _small(text: String) -> Button:
	var b := UiStyle.chip_button(text, UiStyle.SLATE, UiStyle.SLATE.darkened(0.2), Vector2(56, _touch * 0.62))
	b.toggle_mode = false
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_theme_font_size_override("font_size", _font)
	return b


func open() -> void:
	panel.visible = true
	for k: String in _type_buttons:
		UiStyle.set_locked(_type_buttons[k], not ProgressionSystem.is_unlocked("transit:" + k))
	if _selected < 0 and not _transit.lines.is_empty():
		_selected = int((_transit.lines[0] as Dictionary)["id"])
	_select_type(_type)
	_refresh()


func _select_type(type: String) -> void:
	if ProgressionSystem.warn_if_locked("transit:" + type, str(GameData.value("transit/types/%s/name_key" % type))):
		type = _type if ProgressionSystem.is_unlocked("transit:" + _type) else "bus"
	_type = type
	for k: String in _type_buttons:
		(_type_buttons[k] as Button).set_pressed_no_signal(k == type)
	EventBus.build_tool_selected.emit("transit", {"type": type})


func _change_vehicles(delta: int) -> void:
	var line: Dictionary = _transit.line_by_id(_selected)
	if not line.is_empty():
		_transit.set_vehicles(_selected, int(line["vehicles"]) + delta)


func _on_draft(info: Dictionary) -> void:
	if not panel.visible:
		return
	var error := str(info.get("error", ""))
	var stops := int(info.get("stops", 0))
	if error != "":
		_info.text = TranslationServer.translate(error)
		_info.add_theme_color_override("font_color", Color(1.0, 0.62, 0.58))
		return
	_info.remove_theme_color_override("font_color")
	var metro := bool(GameData.section("transit/types/" + str(info.get("type", "bus"))).get("underground", false))
	if stops == 0:
		_info.text = TranslationServer.translate("TRANSIT_HINT_METRO" if metro else "TRANSIT_HINT")
	else:
		_info.text = TranslationServer.translate("TRANSIT_DRAFT_METRO" if metro else "TRANSIT_DRAFT") % [stops, float(info.get("length", 0.0)) / 1000.0,
			UiStyle.format_int(int(info.get("cost", 0)))]


func _refresh_if_open() -> void:
	if panel.visible:
		_refresh()


func _refresh() -> void:
	_ticket_label.text = ("%.1f" % _transit.ticket_price).replace(".", ",")
	for child in _lines_row.get_children():
		_lines_row.remove_child(child)
		child.queue_free()
	var group := ButtonGroup.new()
	if _transit.line_by_id(_selected).is_empty():
		_selected = -1 if _transit.lines.is_empty() else int((_transit.lines[0] as Dictionary)["id"])
	if _transit.lines.is_empty():
		_lines_row.add_child(UiStyle.label("TRANSIT_NO_LINES", _font - 6))
	for line: Dictionary in _transit.lines:
		var color: Color = _transit.line_color(line)
		var b := UiStyle.chip_button(_transit.line_name(line), color.darkened(0.2), color.lightened(0.15), Vector2(150, _touch * 0.62))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", _font - 7)
		b.button_group = group
		b.button_pressed = int(line["id"]) == _selected
		var id := int(line["id"])
		b.pressed.connect(func() -> void:
			_selected = id
			_refresh())
		_lines_row.add_child(b)
	var sel: Dictionary = _transit.line_by_id(_selected)
	_detail.visible = not sel.is_empty()
	if sel.is_empty():
		return
	_vehicle_label.text = str(int(sel["vehicles"]))
	if not sel["ok"]:
		_detail_label.text = TranslationServer.translate("TRANSIT_BROKEN") % TranslationServer.translate(str(sel["error"]))
		return
	var riders: float = _transit.riders(_selected)
	var full := roundi(riders / maxf(float(_transit.capacity(sel)), 1.0) * 100.0)
	_detail_label.text = TranslationServer.translate("TRANSIT_LINE_INFO") % [_transit.line_name(sel),
		UiStyle.format_int(roundi(riders)), mini(full, 999), float(sel["length"]) / 1000.0,
		(sel["points"] as Array).size(), roundi(float(_transit.headway_s(sel)) / 60.0 * 10.0) / 10.0]

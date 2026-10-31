class_name DistrictPanel
extends RefCounted
## Bottom panel of the district tool ("Bölgeler"):
##   row 1: drawing hint, corner count or why the outline is not valid,
##          create, clear, close;
##   row 2: one chip per district in its colour;
##   row 3: the chosen district: its name (editable), its four policies,
##          people living there, delete.
## While the panel is open, taps on the map add corners (DistrictSystem).

const GAP := 10

var panel: PanelContainer
var closed: Callable

var _districts: Node
var _font: int
var _touch: float
var _info: Label
var _row: HBoxContainer
var _detail: HBoxContainer
var _name_edit: LineEdit
var _policy_buttons: Dictionary = {}
var _stats_label: Label
var _selected: int = -1


func _init(districts: Node, font_size: int, min_touch: float, on_close: Callable) -> void:
	_districts = districts
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
	top.add_child(UiStyle.badge("map", UiStyle.PURPLE, min_touch * 0.62))
	_info = UiStyle.label("", font_size - 5)
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.custom_minimum_size.x = 420
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_info)
	var create := _action("DISTRICT_FINISH", UiStyle.GREEN, 170)
	create.pressed.connect(func() -> void:
		if _districts.finish_draft():
			_selected = int((_districts.districts.back() as Dictionary)["id"])
			_refresh())
	top.add_child(create)
	var clear := _action("TRANSIT_CLEAR", UiStyle.SLATE, 120)
	clear.pressed.connect(func() -> void: _districts.cancel_draft())
	top.add_child(clear)
	var close := UiStyle.round_button("x", UiStyle.RED, min_touch * 0.8)
	close.pressed.connect(func() -> void: closed.call())
	top.add_child(close)
	col.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(900, min_touch * 0.7)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_row)
	col.add_child(scroll)

	_detail = HBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(190, min_touch * 0.62)
	_name_edit.add_theme_font_size_override("font_size", font_size - 6)
	_name_edit.max_length = 24
	_name_edit.text_submitted.connect(func(text: String) -> void:
		_districts.rename(_selected, text)
		_name_edit.release_focus())
	_name_edit.focus_exited.connect(func() -> void:
		if _selected >= 0:
			_districts.rename(_selected, _name_edit.text))
	_detail.add_child(_name_edit)
	var policies: Dictionary = GameData.section("districts/policies")
	for key: String in GameData.value("districts/order"):
		var b := UiStyle.chip_button(policies[key]["name_key"], UiStyle.SLATE.darkened(0.2), UiStyle.GREEN.darkened(0.1),
			Vector2(150, min_touch * 0.62))
		b.add_theme_font_size_override("font_size", font_size - 9)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.toggled.connect(func(on: bool) -> void:
			if _selected >= 0:
				_districts.set_policy(_selected, key, on))
		_policy_buttons[key] = b
		_detail.add_child(b)
	var trash := UiStyle.round_button("trash-2", UiStyle.RED, min_touch * 0.62)
	trash.pressed.connect(func() -> void:
		if _selected >= 0:
			_districts.delete_district(_selected)
			_selected = -1
			_refresh())
	_detail.add_child(trash)
	col.add_child(_detail)
	_stats_label = UiStyle.label("", font_size - 7)
	_stats_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_stats_label)

	EventBus.districts_changed.connect(func() -> void:
		if panel.visible:
			_refresh())
	EventBus.district_draft_changed.connect(_on_draft)
	EventBus.district_reported.connect(func(_r: Dictionary) -> void:
		if panel.visible:
			_refresh())


func _action(text_key: String, color: Color, width: float) -> Button:
	var b := UiStyle.chip_button(text_key, color.darkened(0.15), color.darkened(0.3), Vector2(width, _touch * 0.72))
	b.toggle_mode = false
	b.add_theme_font_size_override("font_size", _font - 5)
	return b


func open() -> void:
	panel.visible = true
	EventBus.build_tool_selected.emit("district", {})
	_refresh()


func _on_draft(info: Dictionary) -> void:
	if not panel.visible:
		return
	var error := str(info.get("error", ""))
	var points := int(info.get("points", 0))
	if error != "":
		_info.text = TranslationServer.translate(error)
		_info.add_theme_color_override("font_color", Color(1.0, 0.62, 0.58))
		return
	_info.remove_theme_color_override("font_color")
	if points == 0:
		_info.text = TranslationServer.translate("DISTRICT_HINT")
	else:
		_info.text = TranslationServer.translate("DISTRICT_DRAFT") % points


func _refresh() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	if _districts.district_by_id(_selected).is_empty():
		_selected = -1 if _districts.districts.is_empty() else int((_districts.districts[0] as Dictionary)["id"])
	if _districts.districts.is_empty():
		_row.add_child(UiStyle.label("DISTRICT_NONE", _font - 6))
	var colors: Array = GameData.value("districts/colors")
	var group := ButtonGroup.new()
	for d: Dictionary in _districts.districts:
		var color := DataLoader.to_color(colors[int(d["color"]) % colors.size()])
		var b := UiStyle.chip_button(str(d["name"]), color.darkened(0.25), color.lightened(0.1), Vector2(150, _touch * 0.62))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", _font - 7)
		b.button_group = group
		b.button_pressed = int(d["id"]) == _selected
		var id := int(d["id"])
		b.pressed.connect(func() -> void:
			_selected = id
			_refresh())
		_row.add_child(b)
	var sel: Dictionary = _districts.district_by_id(_selected)
	_detail.visible = not sel.is_empty()
	_stats_label.visible = not sel.is_empty()
	if sel.is_empty():
		return
	if not _name_edit.has_focus():
		_name_edit.text = str(sel["name"])
	for key: String in _policy_buttons:
		(_policy_buttons[key] as Button).set_pressed_no_signal(int(sel["flags"]) & int(_districts.flag(key)) != 0)
	var st: Dictionary = _districts.stats.get(int(sel["id"]), {})
	_stats_label.text = TranslationServer.translate("DISTRICT_STATS") % [UiStyle.format_int(int(st.get("residents", 0))),
		int(st.get("buildings", 0)), roundi(TransitRules.polygon_area(sel["points"]) / 10000.0 * 10.0) / 10.0]

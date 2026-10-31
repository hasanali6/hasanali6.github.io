class_name CatalogPanel
extends RefCounted
## Bottom panel listing hand-placeable items: buildings and parks
## (data/catalog.json), or city services and utilities (data/services.json).
## Each chip shows the name, the price and, for services, the monthly upkeep.
## Picking one switches the BuildTool on; the close button switches it off.

var panel: PanelContainer
var closed: Callable

var _font: int
var _touch: float
var _title: Label
var _row: HBoxContainer
var _scroll: ScrollContainer
var _buttons: Dictionary = {}
var _items: Dictionary = {}
var _first: String = ""
var _current: String = ""


func _init(font_size: int, min_touch: float, on_close: Callable) -> void:
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
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var top := HBoxContainer.new()
	_title = UiStyle.label("BUILD_CATALOG", font_size - 2)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close := UiStyle.round_button("x", UiStyle.RED, min_touch * 0.85)
	close.pressed.connect(func() -> void: closed.call())
	top.add_child(close)
	col.add_child(top)

	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(960, min_touch + 10)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_scroll.add_child(_row)
	col.add_child(_scroll)


## Shows the given items under a title and selects the first one.
func open(title_key: String, items: Array) -> void:
	_title.text = title_key
	for child in _row.get_children():
		_row.remove_child(child)
		child.free()
	_buttons.clear()
	_items.clear()
	_first = ""
	var categories := GameData.section("services/categories")
	var group := ButtonGroup.new()
	for item: Dictionary in items:
		var color: Color
		if item.has("category"):
			color = DataLoader.to_color(categories[item["category"]]["color"])
		elif item.has("extractor"):
			color = DataLoader.to_color(GameData.value("resources/types/%s/color" % item["extractor"]))
		elif str(item["zone"]) == "":
			color = UiStyle.GREEN.darkened(0.2)
		else:
			color = DataLoader.to_color(GameData.value("zones/types/%s/color" % item["zone"]))
		var b := UiStyle.chip_button("", color.darkened(0.25), color.lightened(0.15), Vector2(176, _touch))
		var price := UiStyle.format_int(int(item["cost"]))
		if item.has("upkeep"):
			price += " · " + TranslationServer.translate("CAT_UPKEEP") % UiStyle.format_int(int(item["upkeep"]))
		b.text = "%s\n%s" % [TranslationServer.translate(item["name_key"]), price]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", _font - 6)
		b.button_group = group
		var id := str(item["id"])
		_items[id] = item
		b.pressed.connect(_select.bind(id))
		_buttons[id] = b
		_row.add_child(b)
		var locked := not ProgressionSystem.is_unlocked(_unlock_id(item))
		UiStyle.set_locked(b, locked)
		if _first == "" and not locked:
			_first = id
	_scroll.scroll_horizontal = 0
	panel.visible = true
	_current = ""
	if _first != "":
		_select(_first)


func _unlock_id(item: Dictionary) -> String:
	return ("svc:" if item.has("service") else "item:") + str(item["id"])


func _select(id: String) -> void:
	var item: Dictionary = _items[id]
	if ProgressionSystem.warn_if_locked(_unlock_id(item), item["name_key"]):
		for k: String in _buttons:
			(_buttons[k] as Button).set_pressed_no_signal(k == _current)
		return
	_current = id
	for k: String in _buttons:
		(_buttons[k] as Button).set_pressed_no_signal(k == id)
	EventBus.build_tool_selected.emit("place", {"item": _items[id]})

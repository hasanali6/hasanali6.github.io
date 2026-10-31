class_name CatalogPanel
extends RefCounted
## Bottom panel listing hand-placeable buildings and parks (data/catalog.json).
## Picking one switches the BuildTool on; the close button switches it off.

var panel: PanelContainer
var closed: Callable

var _buttons: Dictionary = {}
var _items: Dictionary = {}


func _init(font_size: int, min_touch: float, on_close: Callable) -> void:
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
	var title := UiStyle.label("BUILD_CATALOG", font_size - 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := UiStyle.round_button("x", UiStyle.RED, min_touch * 0.85)
	close.pressed.connect(func() -> void: closed.call())
	top.add_child(close)
	col.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(920, min_touch + 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	col.add_child(scroll)
	var group := ButtonGroup.new()
	for item: Dictionary in GameData.value("catalog/items"):
		var zone := str(item["zone"])
		var color := UiStyle.GREEN.darkened(0.2) if zone == "" else DataLoader.to_color(GameData.value("zones/types/%s/color" % zone))
		var b := UiStyle.chip_button("", color.darkened(0.25), color.lightened(0.15), Vector2(150, min_touch))
		b.text = "%s\n%s" % [TranslationServer.translate(item["name_key"]), UiStyle.format_int(int(item["cost"]))]
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", font_size - 6)
		b.button_group = group
		var id := str(item["id"])
		_items[id] = item
		b.pressed.connect(_select.bind(id))
		_buttons[id] = b
		row.add_child(b)


func open() -> void:
	panel.visible = true
	var first := str((GameData.value("catalog/items") as Array)[0]["id"])
	_select(first)


func _select(id: String) -> void:
	for k: String in _buttons:
		(_buttons[k] as Button).set_pressed_no_signal(k == id)
	EventBus.build_tool_selected.emit("place", {"item": _items[id]})

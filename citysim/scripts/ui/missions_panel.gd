class_name MissionsPanel
extends RefCounted
## The missions card (trophy button): the city's three short-term goals with
## their progress and rewards, the city's average land value and crime, and
## a button to (re)start the tutorial.

var card: PanelContainer

var _life: Node
var _font: int
var _touch: float
var _rows: VBoxContainer
var _summary: Label


func _init(life: Node, font_size: int, min_touch: float) -> void:
	_life = life
	_font = font_size
	_touch = min_touch
	var parts := UiStyle.card("MISSIONS_TITLE", 620, font_size, min_touch)
	card = parts[0]
	var content: VBoxContainer = parts[1]
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	content.add_child(_rows)
	_summary = UiStyle.label("", font_size - 6)
	_summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary)
	var tut := Button.new()
	tut.text = "MISSIONS_TUTORIAL"
	tut.focus_mode = Control.FOCUS_NONE
	tut.custom_minimum_size.y = min_touch * 0.75
	tut.pressed.connect(func() -> void:
		_life.start_tutorial()
		card.visible = false)
	content.add_child(tut)
	EventBus.life_changed.connect(func() -> void:
		if card.visible:
			_refresh())


func open() -> void:
	_refresh()
	card.visible = true


func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var rows: Array = _life.mission_rows()
	if rows.is_empty():
		_rows.add_child(UiStyle.label("MISSIONS_NONE", _font - 4))
	for r: Dictionary in rows:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var top := HBoxContainer.new()
		var text := UiStyle.label(str(r["text"]), _font - 4)
		text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(text)
		var reward := UiStyle.label("+" + UiStyle.format_int(int(r["reward"])), _font - 4)
		reward.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		reward.add_theme_color_override("font_color", UiStyle.GREEN.darkened(0.25))
		top.add_child(reward)
		box.add_child(top)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = float(r["progress"]) * 100.0
		bar.custom_minimum_size.y = 18
		bar.add_theme_stylebox_override("background", UiStyle.flat_box(Color(0.82, 0.86, 0.9), 9))
		bar.add_theme_stylebox_override("fill", UiStyle.flat_box(UiStyle.GOLD, 9))
		bar.add_theme_font_size_override("font_size", _font - 10)
		box.add_child(bar)
		_rows.add_child(box)
	var s: Dictionary = _life.last_stats
	_summary.text = TranslationServer.translate("MISSIONS_SUMMARY") % [roundi(float(s.get("land_value", 0.0)) * 100.0),
		roundi(float(s.get("crime", 0.0)) * 100.0), int(s.get("fires", 0))]

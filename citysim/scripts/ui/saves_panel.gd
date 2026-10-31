class_name SavesPanel
extends RefCounted
## The saves card: the autosave and three manual slots, each with its date,
## population, money and milestone. Slots can be saved over and any save
## loaded; loading asks for a second tap within a few seconds.

const CONFIRM_SECONDS := 4.0

var card: PanelContainer

var _save: Node
var _font: int
var _touch: float
var _rows: VBoxContainer
var _armed: String = ""
var _armed_at: float = -INF


func _init(save_system: Node, font_size: int, min_touch: float) -> void:
	_save = save_system
	_font = font_size
	_touch = min_touch
	var parts := UiStyle.card("SAVES_TITLE", 720, font_size, min_touch)
	card = parts[0]
	var content: VBoxContainer = parts[1]
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	content.add_child(_rows)
	var hint := UiStyle.label("SAVES_HINT", font_size - 8)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	EventBus.saves_changed.connect(func() -> void:
		if card.visible:
			_refresh())


func open() -> void:
	_armed = ""
	_refresh()
	card.visible = true


func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry: Dictionary in _save.list_saves():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name := "SAVES_AUTO" if entry["key"] == "auto" else TranslationServer.translate("SAVES_SLOT") % int(entry["slot"])
		var text := TranslationServer.translate(name)
		var meta: Dictionary = entry["meta"]
		if not entry["exists"]:
			text += "\n" + TranslationServer.translate("SAVES_EMPTY")
		elif not meta.is_empty():
			var when := Time.get_datetime_string_from_unix_time(int(meta.get("saved_unix", 0)) + _tz_offset(), true)
			var level := int(meta.get("level", 0))
			text += "\n" + TranslationServer.translate("SAVES_META") % [when.left(16),
				TranslationServer.translate(ProgressionSystem.milestone(level)["name_key"]),
				UiStyle.format_int(int(meta.get("population", 0))), UiStyle.format_int(int(meta.get("balance", 0)))]
		var label := UiStyle.label(text, _font - 6)
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var path: String = entry["path"]
		if entry["key"] == "slot":
			var save := Button.new()
			save.text = "SAVES_SAVE"
			save.focus_mode = Control.FOCUS_NONE
			save.custom_minimum_size = Vector2(150, _touch * 0.7)
			save.pressed.connect(func() -> void: _save.save_game(path))
			row.add_child(save)
		var load := Button.new()
		load.text = "SAVES_LOAD"
		load.focus_mode = Control.FOCUS_NONE
		load.disabled = not entry["exists"]
		load.custom_minimum_size = Vector2(150, _touch * 0.7)
		load.pressed.connect(_confirm_load.bind(path))
		row.add_child(load)
		_rows.add_child(row)


func _confirm_load(path: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _armed == path and now - _armed_at < CONFIRM_SECONDS:
		_save.request_load(path)
		return
	_armed = path
	_armed_at = now
	EventBus.notification_posted.emit("save", TranslationServer.translate("SAVES_CONFIRM_LOAD"))


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

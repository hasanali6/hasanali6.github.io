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
var _files: VBoxContainer


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
	# Moving the city between the phone and the PC.
	var move := HBoxContainer.new()
	move.add_theme_constant_override("separation", 10)
	var export_b := _button("SAVES_EXPORT")
	export_b.pressed.connect(_export)
	move.add_child(export_b)
	var import_b := _button("SAVES_IMPORT")
	import_b.pressed.connect(_import)
	move.add_child(import_b)
	content.add_child(move)
	_files = VBoxContainer.new()
	_files.add_theme_constant_override("separation", 6)
	_files.visible = false
	content.add_child(_files)
	var hint := UiStyle.label("SAVES_HINT", font_size - 8)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	EventBus.saves_changed.connect(func() -> void:
		if card.visible:
			_refresh())


func open() -> void:
	_armed = ""
	_files.visible = false
	_refresh()
	card.visible = true


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(220, _touch * 0.7)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _say(text: String) -> void:
	EventBus.notification_posted.emit("save", text)


## Saves the city and copies it to Documents/SehirSim; the PC also opens
## that folder. Move the file to the other device (cable, Drive, WhatsApp...)
## and use Ice aktar there.
func _export() -> void:
	var path: String = _save.export_city()
	if path == "":
		_say(TranslationServer.translate("SAVES_EXPORT_FAILED"))
		return
	_say(TranslationServer.translate("SAVES_EXPORTED") % path)
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		OS.shell_open(path.get_base_dir())


## Picks a city file: the system's file picker when there is one, and in any
## case a list of the city files found in Documents/SehirSim and Downloads.
func _import() -> void:
	_show_found_files()
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show(TranslationServer.translate("SAVES_IMPORT"), SaveSystem.export_dir(), "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.save"]),
			func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
				if ok and not paths.is_empty():
					_import_file(paths[0]))


func _show_found_files() -> void:
	for child in _files.get_children():
		_files.remove_child(child)
		child.queue_free()
	var found: Array = SaveSystem.importable_files()
	var title := UiStyle.label("SAVES_FOUND" if not found.is_empty() else "SAVES_NONE_FOUND", _font - 8)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_files.add_child(title)
	for i in mini(found.size(), 5):
		var entry: Dictionary = found[i]
		var row := HBoxContainer.new()
		var name := UiStyle.label(str(entry["name"]), _font - 8)
		name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var take := Button.new()
		take.text = "SAVES_TAKE"
		take.focus_mode = Control.FOCUS_NONE
		take.custom_minimum_size = Vector2(130, _touch * 0.6)
		var path: String = entry["path"]
		take.pressed.connect(func() -> void: _import_file(path))
		row.add_child(take)
		_files.add_child(row)
	_files.visible = true


func _import_file(path: String) -> void:
	var err: String = _save.import_city(path)
	if err != "":
		_say(TranslationServer.translate(err))
		return
	_files.visible = false
	_say(TranslationServer.translate("SAVES_IMPORTED"))
	_refresh()


func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry: Dictionary in _save.list_saves():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name := "SAVES_AUTO" if entry["key"] == "auto" else ("SAVES_IMPORTED_ROW" if entry["key"] == "imported" else TranslationServer.translate("SAVES_SLOT") % int(entry["slot"]))
		var text := TranslationServer.translate(name)
		var meta: Dictionary = entry["meta"]
		if str(meta.get("city_name", "")) != "":
			text += " · " + str(meta["city_name"])
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

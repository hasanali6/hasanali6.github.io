class_name CheatsPanel
extends RefCounted
## The sandbox card (Ayarlar → Hileler): add money, open every milestone,
## unlimited money, fast growth and automatic densification.

var card: PanelContainer

var _font: int
var _checks: Dictionary = {}   # option key -> CheckButton
var _touch: float


func _init(font_size: int, min_touch: float) -> void:
	_font = font_size
	_touch = min_touch
	var parts := UiStyle.card("CHEATS_TITLE", 640, font_size, min_touch)
	card = parts[0]
	var content: VBoxContainer = parts[1]
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 10)
	for amount: int in [100000, 1000000, 10000000]:
		var b := _button("+" + UiStyle.format_int(amount))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.pressed.connect(func() -> void: Cheats.add_money(amount))
		money_row.add_child(b)
	content.add_child(money_row)
	var unlock := _button("CHEATS_UNLOCK_ALL")
	unlock.pressed.connect(func() -> void:
		ProgressionSystem.unlock_all()
		EventBus.notification_posted.emit("progression", TranslationServer.translate("NOTIFY_UNLOCKED_ALL")))
	content.add_child(unlock)
	for entry: Array in [["unlimited_money", "CHEATS_UNLIMITED"], ["fast_growth", "CHEATS_FAST_GROWTH"], ["densify", "CHEATS_DENSIFY"]]:
		var key: String = entry[0]
		var check := CheckButton.new()
		check.text = entry[1]
		check.focus_mode = Control.FOCUS_NONE
		check.custom_minimum_size.y = min_touch * 0.75
		check.button_pressed = bool(Cheats.get(key))
		check.toggled.connect(func(on: bool) -> void: Cheats.set_option(key, on))
		content.add_child(check)
		_checks[key] = check
	# Try out the city's emergencies (also work with Disasters switched off).
	var life_row := HBoxContainer.new()
	life_row.add_theme_constant_override("separation", 10)
	for entry: Array in [["CHEATS_EARTHQUAKE", "earthquake"], ["CHEATS_FLOOD", "flood"], ["CHEATS_FIRE", "fire"]]:
		var b := _button(entry[0])
		var what: String = entry[1]
		b.pressed.connect(func() -> void:
			var life: Node = (Engine.get_main_loop() as SceneTree).current_scene.get_node_or_null("CityLifeSystem")
			if life == null:
				return
			card.visible = false
			if what == "earthquake":
				life.earthquake()
			elif what == "flood" and life.flood() == 0:
				EventBus.notification_posted.emit("disaster", TranslationServer.translate("NOTIFY_FLOOD_NONE"))
			elif what == "fire":
				life.ignite_random()
			return)
		life_row.add_child(b)
	content.add_child(life_row)
	var hint := UiStyle.label("CHEATS_HINT", font_size - 8)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = _touch * 0.75
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func open() -> void:
	for key: String in _checks:
		(_checks[key] as CheckButton).set_pressed_no_signal(bool(Cheats.get(key)))
	card.visible = true

class_name EconomyPanel
extends RefCounted
## The economy card: three tabs.
##   Bütçe   : last month's income and expenses line by line, and the net.
##   Vergiler: tax sliders per zone group, residential also per education level.
##   Kredi   : the single loan: amount, limit, interest, instalment, borrow/repay.

const ROW_HEIGHT := 46.0

var card: PanelContainer

var _font: int
var _touch: float
var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _budget_rows: Dictionary = {}
var _net_label: Label
var _tax_sliders: Dictionary = {}
var _tax_values: Dictionary = {}
var _loan_label: Label


func _init(font_size: int, min_touch: float) -> void:
	_font = font_size
	_touch = min_touch
	var parts := UiStyle.card("ECON_TITLE", 640, font_size, min_touch)
	card = parts[0]
	var content: VBoxContainer = parts[1]

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for key: String in ["budget", "taxes", "loan"]:
		var b := Button.new()
		b.text = "ECON_TAB_" + key.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = min_touch * 0.75
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show.bind(key))
		_tab_buttons[key] = b
		tabs.add_child(b)
	content.add_child(tabs)

	_pages["budget"] = _build_budget()
	_pages["taxes"] = _build_taxes()
	_pages["loan"] = _build_loan()
	for page: Control in _pages.values():
		content.add_child(page)
	_show("budget")

	EventBus.budget_settled.connect(func(_l: Dictionary) -> void: _refresh_budget())
	EventBus.taxes_changed.connect(_refresh_taxes)
	EventBus.loan_changed.connect(_refresh_loan)
	EventBus.money_changed.connect(func(_b: int) -> void: _refresh_loan())


func open() -> void:
	_refresh_budget()
	_refresh_taxes()
	_refresh_loan()
	card.visible = true


func _show(key: String) -> void:
	for k: String in _pages:
		(_pages[k] as Control).visible = k == key
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == key)


func _row(text_key: String) -> Array:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT * 0.7
	var name := UiStyle.label(text_key, _font - 4)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var value := UiStyle.label("", _font - 4)
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return [row, value]


# --- Budget --------------------------------------------------------------------

func _build_budget() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(UiStyle.label("ECON_INCOME", _font - 2))
	for key: String in ["residential", "commercial", "office", "industrial", "subsidy"]:
		var r := _row("ECON_IN_" + key.to_upper())
		_budget_rows["in_" + key] = r[1]
		col.add_child(r[0])
	col.add_child(UiStyle.label("ECON_EXPENSES", _font - 2))
	for key: String in ["roads", "loan"]:
		var r := _row("ECON_OUT_" + key.to_upper())
		_budget_rows["out_" + key] = r[1]
		col.add_child(r[0])
	var c := _row("ECON_CONSTRUCTION")
	_budget_rows["construction"] = c[1]
	col.add_child(c[0])
	var n := _row("ECON_NET")
	_net_label = n[1]
	_net_label.add_theme_font_size_override("font_size", _font)
	col.add_child(n[0])
	return col


func _refresh_budget() -> void:
	var ledger := EconomySystem.last_ledger
	var income: Dictionary = ledger.get("income", {})
	var expenses: Dictionary = ledger.get("expenses", {})
	for key: String in ["residential", "commercial", "office", "industrial", "subsidy"]:
		(_budget_rows["in_" + key] as Label).text = "+" + UiStyle.format_int(roundi(float(income.get(key, 0.0))))
	for key: String in ["roads", "loan"]:
		(_budget_rows["out_" + key] as Label).text = _minus(float(expenses.get(key, 0.0)))
	(_budget_rows["construction"] as Label).text = _minus(float(ledger.get("construction", 0.0)))
	var net := roundi(float(ledger.get("net", 0.0)))
	_net_label.text = ("+" if net >= 0 else "") + UiStyle.format_int(net) + tr("ECON_PER_MONTH")
	_net_label.add_theme_color_override("font_color", Color(0.16, 0.55, 0.25) if net >= 0 else Color(0.8, 0.2, 0.2))


func _minus(value: float) -> String:
	var v := roundi(value)
	return "0" if v == 0 else "-" + UiStyle.format_int(v)


# --- Taxes ---------------------------------------------------------------------

func _build_taxes() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var tax_min := GameData.num("economy/taxes/min")
	var tax_max := GameData.num("economy/taxes/max")
	var entries := [["residential", "ECON_TAX_RESIDENTIAL"]]
	for e in GameData.integer("economy/education_levels"):
		entries.append(["edu%d" % e, "ECON_TAX_EDU_%d" % e])
	entries.append_array([["commercial", "ECON_TAX_COMMERCIAL"], ["office", "ECON_TAX_OFFICE"], ["industrial", "ECON_TAX_INDUSTRIAL"]])
	for entry: Array in entries:
		var key: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name := UiStyle.label(entry[1], _font - 4 if key.begins_with("edu") else _font - 2)
		name.custom_minimum_size.x = 230
		row.add_child(name)
		var slider := HSlider.new()
		slider.min_value = tax_min
		slider.max_value = tax_max
		slider.step = 1.0
		slider.focus_mode = Control.FOCUS_NONE
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = _touch * 0.6
		slider.value_changed.connect(_on_tax.bind(key))
		row.add_child(slider)
		var value := UiStyle.label("", _font - 2)
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.custom_minimum_size.x = 70
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_tax_sliders[key] = slider
		_tax_values[key] = value
		col.add_child(row)
	col.add_child(UiStyle.label("ECON_TAX_HINT", _font - 6))
	return col


func _on_tax(value: float, key: String) -> void:
	if key.begins_with("edu"):
		EconomySystem.set_residential_edu_tax(int(key.substr(3)), value)
	else:
		EconomySystem.set_tax(key, value)


func _refresh_taxes() -> void:
	for key: String in _tax_sliders:
		var v: float
		if key.begins_with("edu"):
			v = EconomySystem.residential_rate(int(key.substr(3)))
		else:
			v = EconomySystem.tax_rate(key)
		(_tax_sliders[key] as HSlider).set_value_no_signal(v)
		(_tax_values[key] as Label).text = "%d%%" % roundi(v)


# --- Loan ------------------------------------------------------------------------

func _build_loan() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_loan_label = UiStyle.label("", _font - 2)
	_loan_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_loan_label)
	var step := GameData.num("economy/loan/step")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for entry: Array in [["ECON_LOAN_TAKE", step], ["ECON_LOAN_REPAY", -step], ["ECON_LOAN_REPAY_ALL", -INF]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = _touch * 0.8
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var delta: float = entry[1]
		b.pressed.connect(func() -> void:
			var target := 0.0 if is_inf(delta) else EconomySystem.loan + delta
			if not EconomySystem.set_loan(target):
				EventBus.notification_posted.emit("economy", tr("ROAD_ERR_MONEY")))
		row.add_child(b)
	col.add_child(row)
	return col


func _refresh_loan() -> void:
	var limit := EconomySystem.loan_limit()
	_loan_label.text = "%s\n%s\n%s" % [
		tr("ECON_LOAN_DEBT") % [UiStyle.format_int(roundi(EconomySystem.loan)), UiStyle.format_int(limit)],
		tr("ECON_LOAN_RATE") % (EconomySystem.loan_rate * 100.0),
		tr("ECON_LOAN_PAYMENT") % [UiStyle.format_int(roundi(EconomySystem.loan_payment)), EconomySystem.loan_months_left],
	]

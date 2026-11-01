class_name EconomyPanel
extends RefCounted
## The economy card: four tabs.
##   Bütçe     : last month's income and expenses line by line, and the net.
##   Vergiler  : tax sliders per zone group, residential also per education level.
##   Hizmetler : budget per service category (50..150 %), electricity and
##               water fees, and how much of the utility capacity is in use.
##   Kredi     : the single loan: amount, limit, interest, instalment, borrow/repay.
##   İlerleme  : population milestones, progress to the next one and what it
##               unlocks.

const ROW_HEIGHT := 40.0
const INCOME_KEYS := ["residential", "commercial", "office", "industrial", "subsidy", "power_fees", "water_fees", "tickets", "parking", "tourism", "milestones"]

var card: PanelContainer

var _font: int
var _touch: float
var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _budget_rows: Dictionary = {}
var _net_label: Label
var _tax_sliders: Dictionary = {}
var _tax_values: Dictionary = {}
var _svc_sliders: Dictionary = {}
var _svc_values: Dictionary = {}
var _utility_label: Label
var _loan_label: Label
var _production_label: Label
var _progress_label: Label
var _progress_bar: ProgressBar
var _milestone_list: Label
var _categories: Dictionary


func _init(font_size: int, min_touch: float) -> void:
	_font = font_size
	_touch = min_touch
	_categories = GameData.section("services/categories")
	var parts := UiStyle.card("ECON_TITLE", 760, font_size, min_touch)
	card = parts[0]
	var content: VBoxContainer = parts[1]

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for key: String in ["budget", "taxes", "services", "loan", "production", "progress"]:
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
	_pages["services"] = _build_services()
	_pages["loan"] = _build_loan()
	_pages["production"] = _build_production()
	_pages["progress"] = _build_progress()
	for page: Control in _pages.values():
		content.add_child(page)
	_show("budget")

	EventBus.budget_settled.connect(func(_l: Dictionary) -> void: _refresh_budget())
	EventBus.taxes_changed.connect(_refresh_taxes)
	EventBus.service_budgets_changed.connect(_refresh_services)
	EventBus.services_changed.connect(func() -> void:
		if card.visible:
			_refresh_utilities())
	EventBus.loan_changed.connect(_refresh_loan)
	EventBus.progression_changed.connect(_refresh_progress)
	EventBus.companies_reported.connect(func(_r: Dictionary) -> void:
		if card.visible:
			_refresh_production())
	EventBus.city_stats_changed.connect(func(_s: Dictionary) -> void:
		if card.visible and _pages["progress"].visible:
			_refresh_progress())
	EventBus.money_changed.connect(func(_b: int) -> void: _refresh_loan())


func open() -> void:
	_refresh_budget()
	_refresh_taxes()
	_refresh_services()
	_refresh_loan()
	_refresh_progress()
	_refresh_production()
	card.visible = true


func _show(key: String) -> void:
	for k: String in _pages:
		(_pages[k] as Control).visible = k == key
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	if key == "services":
		_refresh_utilities()


func _row(text_key: String) -> Array:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT * 0.75
	var name := UiStyle.label(text_key, _font - 5)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var value := UiStyle.label("", _font - 5)
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return [row, value]


# --- Budget --------------------------------------------------------------------

func _build_budget() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	var income := VBoxContainer.new()
	income.add_theme_constant_override("separation", 0)
	income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	income.add_child(UiStyle.label("ECON_INCOME", _font - 3))
	for key: String in INCOME_KEYS:
		var r := _row("ECON_IN_" + key.to_upper())
		_budget_rows["in_" + key] = r[1]
		income.add_child(r[0])
	columns.add_child(income)
	var expenses := VBoxContainer.new()
	expenses.add_theme_constant_override("separation", 0)
	expenses.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expenses.add_child(UiStyle.label("ECON_EXPENSES", _font - 3))
	for key: String in _expense_keys():
		var r := _row(_expense_label(key))
		_budget_rows["out_" + key] = r[1]
		expenses.add_child(r[0])
	var c := _row("ECON_CONSTRUCTION")
	_budget_rows["construction"] = c[1]
	expenses.add_child(c[0])
	columns.add_child(expenses)
	page.add_child(columns)
	var n := _row("ECON_NET")
	_net_label = n[1]
	_net_label.add_theme_font_size_override("font_size", _font)
	page.add_child(n[0])
	return page


func _expense_keys() -> Array:
	var keys := ["roads"]
	keys.append_array(_categories.keys())
	keys.append_array(["transit", "parks", "recycling", "loan"])
	return keys


func _expense_label(key: String) -> String:
	return str(_categories[key]["name_key"]) if _categories.has(key) else "ECON_OUT_" + key.to_upper()


func _refresh_budget() -> void:
	var ledger := EconomySystem.last_ledger
	var income: Dictionary = ledger.get("income", {})
	var expenses: Dictionary = ledger.get("expenses", {})
	for key: String in INCOME_KEYS:
		(_budget_rows["in_" + key] as Label).text = "+" + UiStyle.format_int(roundi(float(income.get(key, 0.0))))
	for key: String in _expense_keys():
		(_budget_rows["out_" + key] as Label).text = _minus(float(expenses.get(key, 0.0)))
	(_budget_rows["construction"] as Label).text = _minus(float(ledger.get("construction", 0.0)))
	var net := roundi(float(ledger.get("net", 0.0)))
	_net_label.text = ("+" if net >= 0 else "") + UiStyle.format_int(net) + tr("ECON_PER_MONTH")
	_net_label.add_theme_color_override("font_color", Color(0.16, 0.55, 0.25) if net >= 0 else Color(0.8, 0.2, 0.2))


func _minus(value: float) -> String:
	var v := roundi(value)
	return "0" if v == 0 else "-" + UiStyle.format_int(v)


# --- Taxes ---------------------------------------------------------------------

func _slider_row(name_key: String, lo: float, hi: float, step: float, name_width: float, on_change: Callable) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := UiStyle.label(name_key, _font - 4)
	name.custom_minimum_size.x = name_width
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = _touch * 0.55
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	var value := UiStyle.label("", _font - 4)
	value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return [row, slider, value]


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
		var r := _slider_row(entry[1], tax_min, tax_max, 1.0, 230, _on_tax.bind(key))
		_tax_sliders[key] = r[1]
		_tax_values[key] = r[2]
		col.add_child(r[0])
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


# --- Services -------------------------------------------------------------------

func _build_services() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(UiStyle.label("ECON_SVC_BUDGETS", _font - 3))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 0)
	var lo := GameData.num("services/budget/min") * 100.0
	var hi := GameData.num("services/budget/max") * 100.0
	for cat: String in _categories:
		var r := _slider_row(_categories[cat]["name_key"], lo, hi, 5.0, 120, _on_service_budget.bind(cat))
		(r[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_svc_sliders[cat] = r[1]
		_svc_values[cat] = r[2]
		grid.add_child(r[0])
	col.add_child(grid)
	col.add_child(UiStyle.label("ECON_SVC_FEES", _font - 3))
	var fees := GridContainer.new()
	fees.columns = 2
	fees.add_theme_constant_override("h_separation", 24)
	var flo := GameData.num("services/fees/min") * 100.0
	var fhi := GameData.num("services/fees/max") * 100.0
	for kind: String in ["power", "water"]:
		var r := _slider_row("ECON_FEE_" + kind.to_upper(), flo, fhi, 5.0, 120, _on_fee.bind(kind))
		(r[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_svc_sliders["fee_" + kind] = r[1]
		_svc_values["fee_" + kind] = r[2]
		fees.add_child(r[0])
	col.add_child(fees)
	_utility_label = UiStyle.label("", _font - 5)
	_utility_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(_utility_label)
	var hint := UiStyle.label("ECON_SVC_HINT", _font - 7)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 700
	col.add_child(hint)
	return col


func _on_service_budget(value: float, category: String) -> void:
	EconomySystem.set_service_budget(category, value / 100.0)


func _on_fee(value: float, kind: String) -> void:
	EconomySystem.set_utility_fee(kind, value / 100.0)


func _refresh_services() -> void:
	for key: String in _svc_sliders:
		var v: float
		if key.begins_with("fee_"):
			v = EconomySystem.utility_fee(key.substr(4)) * 100.0
		else:
			v = EconomySystem.service_budget(key) * 100.0
		(_svc_sliders[key] as HSlider).set_value_no_signal(v)
		(_svc_values[key] as Label).text = "%d%%" % roundi(v)


func _refresh_utilities() -> void:
	var services := card.get_tree().current_scene.get_node_or_null("ServiceSystem") if card.is_inside_tree() else null
	if services == null:
		return
	var totals: Dictionary = services.utility_totals()
	var p: Array = totals["power"]
	var w: Array = totals["water"]
	var s: Array = totals["sewage"]
	_utility_label.text = tr("ECON_UTIL_SUMMARY") % [snappedf(float(p[0]), 0.1), snappedf(float(p[1]), 0.1),
		UiStyle.format_int(roundi(float(w[0]))), UiStyle.format_int(roundi(float(w[1]))),
		UiStyle.format_int(roundi(float(s[0]))), UiStyle.format_int(roundi(float(s[1])))]


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


# --- Progress ---------------------------------------------------------------------

func _build_progress() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_progress_label = UiStyle.label("", _font - 2)
	_progress_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.step = 0.001
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 22
	var fill := UiStyle.flat_box(UiStyle.GREEN, 10)
	var bg := UiStyle.flat_box(Color(0.78, 0.81, 0.85), 10)
	_progress_bar.add_theme_stylebox_override("fill", fill)
	_progress_bar.add_theme_stylebox_override("background", bg)
	col.add_child(_progress_bar)
	_milestone_list = UiStyle.label("", _font - 6)
	_milestone_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_milestone_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_milestone_list)
	return col


func _refresh_progress() -> void:
	var level := ProgressionSystem.level
	var ms := ProgressionSystem.milestones()
	var current: Dictionary = ms[level]
	var pop := ProgressionSystem.population
	var text := tr("PROGRESS_CURRENT") % [tr(current["name_key"]), UiStyle.format_int(pop)]
	if level + 1 < ms.size():
		var next: Dictionary = ms[level + 1]
		text += "\n" + tr("PROGRESS_NEXT") % [tr(next["name_key"]), UiStyle.format_int(int(next["population"])),
			UiStyle.format_int(int(next["reward"]))]
		var names := PackedStringArray()
		for id: String in next.get("unlocks", []):
			names.append(tr(ProgressionSystem.unlock_name_key(id)))
		if next.has("area_half_m"):
			names.append(tr("PROGRESS_AREA") % (float(next["area_half_m"]) * 2.0 / 1000.0))
		if not names.is_empty():
			text += "\n" + tr("PROGRESS_UNLOCKS") % ", ".join(names)
	else:
		text += "\n" + tr("PROGRESS_MAX")
	_progress_label.text = text
	_progress_bar.value = ProgressionSystem.progress()
	var lines := PackedStringArray()
	for i in ms.size():
		var m: Dictionary = ms[i]
		lines.append("%s %s · %s" % ["✔" if i <= level else "○", tr(m["name_key"]), UiStyle.format_int(int(m["population"]))])
	_milestone_list.text = "   ".join(lines)


# --- Production -------------------------------------------------------------------

func _build_production() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_production_label = UiStyle.label("", _font - 4)
	_production_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_production_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_production_label)
	return col


func _refresh_production() -> void:
	var companies := (Engine.get_main_loop() as SceneTree).current_scene.get_node_or_null("CompanySystem")
	if companies == null:
		return
	var rep: Dictionary = companies.last_report
	var raw: Dictionary = rep.get("raw", {})
	var by_type: Dictionary = raw.get("by_type", {})
	var types: Dictionary = GameData.section("resources/types")
	var parts := PackedStringArray()
	for key: String in types:
		parts.append("%s %s" % [tr(types[key]["name_key"]), UiStyle.format_int(roundi(float(by_type.get(key, 0.0))))])
	var count := 0
	for c: Dictionary in companies.companies.values():
		if c["kind"] == "extractor":
			count += 1
	var f := func(v: Variant) -> String: return UiStyle.format_int(roundi(float(v)))
	_production_label.text = "\n".join(PackedStringArray([
		tr("PROD_EXTRACTORS") % count,
		tr("PROD_RAW") % [f.call(raw.get("produced", 0.0)), ", ".join(parts)],
		tr("PROD_RAW_USE") % [f.call(raw.get("needed", 0.0)), f.call(raw.get("local", 0.0)), f.call(raw.get("imported", 0.0))],
		tr("PROD_RAW_EXPORT") % f.call(raw.get("exported", 0.0)),
		tr("PROD_GOODS") % [f.call(rep.get("goods_produced", 0.0)), f.call(rep.get("goods_sold", 0.0))],
		tr("PROD_TRADE") % [f.call(rep.get("exports", 0.0)), f.call(rep.get("imports", 0.0))],
		tr("PROD_HINT"),
	]))

extends Node
## One company per commercial, office, industrial or mixed building.
##   industrial : workers produce goods; goods go to the city's shops first,
##                the rest is exported (cheaper). Raw input is bought in.
##   commercial : sells goods to households; buys from local industry or,
##                when that is not enough, imports at a higher price.
##   extractor  : farms, lumber camps, mines and oil wells (placed by hand on
##                a resource) produce raw material by richness and workers.
##                Factories use the city's raw material first (cheaper than
##                importing it); the rest is exported by highway. Ore and oil
##                run out; farms and forests suffer from pollution.
##   office     : workers produce services sold at a value per worker.
## Each month a company books revenue, wages and goods costs, pays tax on
## profit, and adjusts how many of its job slots it wants filled. Companies
## that stay deep in debt go bankrupt and their building is abandoned.
## Without electricity or water a company works at a fraction of its output.

@export var building_system_path: NodePath
@export var road_network_path: NodePath

var _port: bool = false   # a working port: sea trade, better prices
var companies: Dictionary = {}   # building id -> record
var last_report: Dictionary = {}

var _buildings: Node
var _cfg: Dictionary
var _money: Dictionary
var _rng := RandomNumberGenerator.new()
var _vacant: Dictionary = {}     # building id -> true while it has open slots
var _shops: Dictionary = {}      # bucket -> PackedInt32Array of shop building ids
var _shop_bucket: float = 256.0
var _no_utility_output: float


func _ready() -> void:
	_buildings = get_node(building_system_path)
	_cfg = GameData.section("economy/companies")
	_money = GameData.section("economy/money")
	_no_utility_output = GameData.num("services/effects/no_utility_company_output")
	_rng.randomize()
	EventBus.buildings_changed.connect(_sync)
	EventBus.month_changed.connect(_on_month)


func _sync() -> void:
	var records: Dictionary = _buildings.buildings
	for bid: int in records:
		var b: Dictionary = records[bid]
		var slots: PackedInt32Array = b.get("job_slots", PackedInt32Array())
		var total := 0
		for s in slots:
			total += s
		if total <= 0 or b.get("abandoned", false):
			continue
		if not companies.has(bid):
			companies[bid] = {
				"kind": b["company_kind"], "slots": slots, "employees": PackedInt32Array([0, 0, 0]),
				"target": 1.0, "money": float(_cfg["start_money"]), "sales": 0.0, "profit": 0.0,
				"loss_months": 0, "profit_months": 0, "pos": b["centre"],
			}
		else:
			companies[bid]["slots"] = slots
		_update_vacancy(bid)
	for bid: int in companies.keys():
		if not records.has(bid) or records[bid].get("abandoned", false):
			close(bid)
	_rebuild_shop_index()


func close(bid: int) -> void:
	if not companies.has(bid):
		return
	companies.erase(bid)
	_vacant.erase(bid)
	EventBus.company_closed.emit(bid)


func _open(c: Dictionary, level: int) -> int:
	var slots: PackedInt32Array = c["slots"]
	var employees: PackedInt32Array = c["employees"]
	return floori(slots[level] * float(c["target"])) - employees[level]


func _update_vacancy(bid: int) -> void:
	var c: Dictionary = companies[bid]
	var open := false
	for level in 3:
		if _open(c, level) > 0:
			open = true
	if open:
		_vacant[bid] = true
	else:
		_vacant.erase(bid)


## Finds a job for a worker with the given education near a home position.
## Overqualified workers may take lower-level jobs. Returns a job code or -1.
func try_hire(education: int, near: Vector2, samples: int) -> int:
	if _vacant.is_empty():
		return HouseholdData.NO_JOB
	var keys := _vacant.keys()
	var radius := float(_cfg["job_radius_m"])
	var best := -1
	var best_level := 0
	var best_score := -INF
	for n in samples:
		var bid: int = keys[_rng.randi_range(0, keys.size() - 1)]
		var c: Dictionary = companies[bid]
		var dist := (c["pos"] as Vector2).distance_to(near)
		if dist > radius:
			continue
		for level in range(education, -1, -1):
			if _open(c, level) > 0:
				var score := (1.0 if level == education else 0.6 - 0.1 * (education - level)) - 0.5 * dist / radius
				if score > best_score:
					best_score = score
					best = bid
					best_level = level
				break
	if best < 0:
		return HouseholdData.NO_JOB
	var employees: PackedInt32Array = companies[best]["employees"]
	employees[best_level] += 1
	companies[best]["employees"] = employees
	_update_vacancy(best)
	return HouseholdData.job_code(best, best_level)


func release(code: int) -> void:
	if code == HouseholdData.NO_JOB:
		return
	var bid := HouseholdData.job_company(code)
	if not companies.has(bid):
		return
	var employees: PackedInt32Array = companies[bid]["employees"]
	var level := HouseholdData.job_level(code)
	employees[level] = maxi(employees[level] - 1, 0)
	companies[bid]["employees"] = employees
	_update_vacancy(bid)


func sell_goods(shop: int, units: float) -> void:
	if companies.has(shop):
		companies[shop]["sales"] += units


# --- Shop lookup -------------------------------------------------------------

func _rebuild_shop_index() -> void:
	_shops.clear()
	for bid: int in companies:
		var c: Dictionary = companies[bid]
		if c["kind"] != "commercial":
			continue
		var key := Vector2i(floori((c["pos"] as Vector2).x / _shop_bucket), floori((c["pos"] as Vector2).y / _shop_bucket))
		var list: PackedInt32Array = _shops.get(key, PackedInt32Array())
		list.append(bid)
		_shops[key] = list
	EventBus.shops_changed.emit()


## Closest shop within the shopping radius, or -1.
func nearest_shop(pos: Vector2) -> int:
	var radius := float(_cfg["shop_radius_m"])
	var reach := ceili(radius / _shop_bucket)
	var centre := Vector2i(floori(pos.x / _shop_bucket), floori(pos.y / _shop_bucket))
	var best := -1
	var best_d := radius
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			for bid in _shops.get(centre + Vector2i(dx, dy), PackedInt32Array()):
				var d := (companies[bid]["pos"] as Vector2).distance_to(pos)
				if d < best_d:
					best_d = d
					best = bid
	return best


# --- Monthly books -----------------------------------------------------------

## 1 with electricity and water, a fraction without.
## Whether a company's road reaches an outside connection (trade by highway).
func _linked(bid: int) -> bool:
	if road_network_path.is_empty() or _port:
		return true   # a port trades by sea
	var b: Dictionary = _buildings.buildings.get(bid, {})
	return get_node(road_network_path).is_reachable(int(b.get("segment", -1)))


func _output_factor(bid: int) -> float:
	var b: Dictionary = _buildings.buildings.get(bid, {})
	return 1.0 if b.get("power", true) and b.get("water", true) else _no_utility_output


func _on_month(_m: int) -> void:
	_port = _buildings.count_style("port") > 0
	var port_bonus := GameData.num("catalog/port_trade_bonus") if _port else 0.0
	var wages: Array = _money["wage_by_education"]
	var units_per: Array = _cfg["industry_units_per_worker"]
	var office_value: Array = _cfg["office_value_per_worker"]
	var sales_total := 0.0
	var production_total := 0.0
	var res_types: Dictionary = GameData.section("resources/types")
	var raw_produced := 0.0
	var raw_by_type := {}
	var records0: Dictionary = _buildings.buildings
	for bid: int in companies:
		var c: Dictionary = companies[bid]
		if c["kind"] == "extractor":
			var b: Dictionary = records0.get(bid, {})
			var t: Dictionary = res_types.get(str(b.get("extractor", "")), {})
			if t.is_empty():
				continue
			var per: Array = t["units_per_worker"]
			var raw := 0.0
			for level in 3:
				raw += (c["employees"] as PackedInt32Array)[level] * float(per[level])
			raw *= float(b.get("richness", 0.0)) * _output_factor(bid)
			if bool(t["pollution_sensitive"]):
				raw *= 1.0 - clampf(float(b.get("pollution", 0.0)), 0.0, 1.0) * 0.7
			if b.has("deposit"):
				var left := float(b["deposit"])
				raw = minf(raw, left)
				b["deposit"] = left - raw
				if left > 0.0 and left - raw <= 0.0:
					EventBus.notification_posted.emit("economy", tr("NOTIFY_DEPOSIT_EMPTY") % tr(str(t["name_key"])))
			c["units"] = raw
			raw_produced += raw
			raw_by_type[b["extractor"]] = float(raw_by_type.get(b["extractor"], 0.0)) + raw
		elif c["kind"] == "commercial":
			sales_total += c["sales"]
		elif c["kind"] == "industrial":
			var units := 0.0
			for level in 3:
				units += (c["employees"] as PackedInt32Array)[level] * float(units_per[level])
			units *= _output_factor(bid)
			c["units"] = units
			production_total += units
	var local := minf(sales_total, production_total)
	var local_share_sales := 0.0 if sales_total <= 0.0 else local / sales_total
	var local_share_prod := 0.0 if production_total <= 0.0 else local / production_total
	# Raw material: the city's own first, the rest imported / exported.
	var raw_needed := production_total * GameData.num("resources/raw_per_good")
	var raw_local := minf(raw_produced, raw_needed)
	var raw_share_need := 0.0 if raw_needed <= 0.0 else raw_local / raw_needed
	var raw_share_prod := 0.0 if raw_produced <= 0.0 else raw_local / raw_produced
	var local_raw_price := GameData.num("resources/local_raw_price")
	var raw_export_price := GameData.num("resources/raw_export_price")

	var report := {
		"taxes": {"commercial": 0.0, "office": 0.0, "industrial": 0.0},
		"goods_sold": sales_total, "goods_produced": production_total,
		"imports": sales_total - local, "exports": production_total - local, "bankrupt": 0, "overflow": 0.0,
		"raw": {"produced": raw_produced, "needed": raw_needed, "local": raw_local, "imported": raw_needed - raw_local,
			"exported": raw_produced - raw_local, "by_type": raw_by_type},
	}
	var records: Dictionary = _buildings.buildings
	for bid: int in companies.keys():
		var c: Dictionary = companies[bid]
		var employees: PackedInt32Array = c["employees"]
		var wage_bill := 0.0
		for level in 3:
			wage_bill += employees[level] * float(wages[level])
		var revenue := 0.0
		var costs := wage_bill
		var output := _output_factor(bid)
		match c["kind"]:
			"commercial":
				var import_price := float(_cfg["import_price"]) * (1.0 if _linked(bid) else float(_cfg["isolated_import_factor"])) * (1.0 - port_bonus)
				# A shop can only serve so much per worker; the rest shop elsewhere.
				var capacity := float(employees[0] + employees[1] + employees[2]) * float(_cfg["shop_units_per_worker"]) * output
				var units := minf(float(c["sales"]), capacity)
				report["overflow"] += float(c["sales"]) - units
				revenue = units * float(_money["retail_price"])
				costs += units * (local_share_sales * float(_cfg["wholesale_price"]) + (1.0 - local_share_sales) * import_price)
			"industrial":
				var units: float = c.get("units", 0.0)
				var export_price := float(_cfg["export_price"]) * (1.0 if _linked(bid) else float(_cfg["isolated_export_factor"])) * (1.0 + port_bonus)
				revenue = units * (local_share_prod * float(_cfg["wholesale_price"]) + (1.0 - local_share_prod) * export_price)
				var raw_import := float(_cfg["industry_raw_cost_per_unit"]) * (1.0 if _linked(bid) else float(_cfg["isolated_import_factor"])) * (1.0 - port_bonus)
				costs += units * GameData.num("resources/raw_per_good") * (raw_share_need * local_raw_price + (1.0 - raw_share_need) * raw_import)
			"extractor":
				var raw: float = c.get("units", 0.0)
				var away := raw_export_price * (1.0 if _linked(bid) else float(_cfg["isolated_export_factor"])) * (1.0 + port_bonus)
				revenue = raw * (raw_share_prod * local_raw_price + (1.0 - raw_share_prod) * away)
			"office":
				for level in 3:
					revenue += employees[level] * float(office_value[level]) * output
		var profit := revenue - costs
		var tax_group := "industrial" if c["kind"] == "extractor" else str(c["kind"])
		var tax := maxf(profit, 0.0) * EconomySystem.tax_rate(tax_group) / 100.0 * EconomySystem.city_share()
		report["taxes"][tax_group] += tax
		c["money"] += profit - tax
		c["profit"] = profit
		c["sales"] = 0.0
		var margin := profit / maxf(revenue, 1.0)
		if margin > float(_cfg["hire_margin"]):
			c["target"] = minf(float(c["target"]) + float(_cfg["hire_step"]), 1.0)
		elif margin < float(_cfg["fire_margin"]):
			c["target"] = maxf(float(c["target"]) - float(_cfg["hire_step"]), float(_cfg["min_target"]))
			_lay_off_excess(bid, c)
		c["profit_months"] = c["profit_months"] + 1 if profit > 0.0 else 0
		c["loss_months"] = c["loss_months"] + 1 if c["money"] < float(_cfg["bankrupt_money"]) else 0
		if records.has(bid):
			var b: Dictionary = records[bid]
			b["employees"] = employees[0] + employees[1] + employees[2]
			b["profit"] = profit
			b["profit_months"] = c["profit_months"]
		_update_vacancy(bid)
		if c["loss_months"] >= int(_cfg["bankrupt_months"]):
			report["bankrupt"] += 1
			EventBus.company_bankrupt.emit(bid)
	last_report = report
	EventBus.companies_reported.emit(report)


## Releases workers above the company's current staffing target.
func _lay_off_excess(bid: int, c: Dictionary) -> void:
	var employees: PackedInt32Array = c["employees"]
	for level in 3:
		var excess := -_open(c, level)
		if excess > 0:
			employees[level] -= excess
			EventBus.workers_laid_off.emit(bid, level, excess)
	c["employees"] = employees


func stats() -> Dictionary:
	var jobs := {"commercial": 0, "industrial": 0, "office": 0}
	var vacant := 0
	for c: Dictionary in companies.values():
		var slots: PackedInt32Array = c["slots"]
		jobs["industrial" if c["kind"] == "extractor" else c["kind"]] += slots[0] + slots[1] + slots[2]
		for level in 3:
			vacant += maxi(_open(c, level), 0)
	var sold := float(last_report.get("goods_sold", 0.0))
	return {
		"goods_overflow_ratio": 0.0 if sold <= 0.0 else float(last_report.get("overflow", 0.0)) / sold,
		"commercial_jobs": jobs["commercial"], "industrial_jobs": jobs["industrial"], "office_jobs": jobs["office"],
		"vacant_jobs": vacant, "import_ratio": 0.0 if sold <= 0.0 else float(last_report.get("imports", 0.0)) / sold,
	}


func save_state() -> Dictionary:
	var out := {}
	for bid: int in companies:
		var c: Dictionary = companies[bid]
		out[str(bid)] = {"target": c["target"], "money": c["money"], "profit": c["profit"],
			"loss_months": c["loss_months"], "profit_months": c["profit_months"]}
	return {"companies": out}


## Restores company finances; employees are rebuilt from the households' jobs.
func load_state(state: Dictionary) -> void:
	_sync()
	var saved: Dictionary = state.get("companies", {})
	for key: String in saved:
		var bid := int(key)
		if companies.has(bid):
			var c: Dictionary = companies[bid]
			for field: String in saved[key]:
				c[field] = saved[key][field]
			c["employees"] = PackedInt32Array([0, 0, 0])


## Re-registers a saved worker in its company (used when loading).
func restore_worker(code: int) -> bool:
	var bid := HouseholdData.job_company(code)
	if not companies.has(bid):
		return false
	var employees: PackedInt32Array = companies[bid]["employees"]
	employees[HouseholdData.job_level(code)] += 1
	companies[bid]["employees"] = employees
	return true


func refresh_vacancies() -> void:
	for bid: int in companies:
		_update_vacancy(bid)

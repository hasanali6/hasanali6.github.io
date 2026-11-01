extends Node
## Households: where they live, work and shop, what they earn and pay, how
## happy they are and how they change over time.
##
## Simulation LOD: households live in HouseholdData packed arrays and each one
## is updated once per game month, spread evenly over that month's ticks (a
## cursor walks the arrays a few entries per tick), so cost per frame stays
## flat however big the city grows. Monthly totals are reported on month end.
##
## Housing choice: an immigrant (or a household that must move) samples a few
## free homes and picks the best score from rent, shop access, a park nearby
## and a little randomness. Job choice: CompanySystem.try_hire samples nearby
## companies, preferring a job matching the worker's education.
##
## City services (ServiceSystem writes them onto the building records) add
## to happiness, lower the death rate (health care) and decide how far
## children growing up in a home get in school. Homes without electricity
## or water are avoided by newcomers. Long commutes (road travel times from
## the TrafficSystem) and traffic noise outside the home lower happiness.

@export var building_system_path: NodePath
@export var company_system_path: NodePath
@export var traffic_system_path: NodePath
@export var district_system_path: NodePath
@export var road_network_path: NodePath

var data := HouseholdData.new()
var last_report: Dictionary = {}

var _buildings: Node
var _companies: Node
var _rng := RandomNumberGenerator.new()
var _hh: Dictionary
var _money: Dictionary
var _life: Dictionary
var _mig: Dictionary
var _happy: Dictionary
var _default_tax: float
var _ticks_per_month: int
var _homes: Dictionary = {}       # building id -> {cap, residents: PackedInt32Array, rent, pos, shop}
var _vacant: Dictionary = {}      # building id -> true
var _parks := PackedVector2Array()
var _cursor: int = 0
var _budget: float = 0.0
var _immigration: float = 0.0
var _demand_res: float = 0.0
var _no_utility_score: float
var _traffic: Node
var _commute_cfg: Dictionary
var _noise_happiness: float
var _districts: Node

# Live counters (kept exact on every change).
var population: int = 0
var workers: int = 0
var employed: int = 0
var unemployed_by_edu := PackedInt32Array([0, 0, 0])

# Accumulated over the current month.
var _acc := {}


func _ready() -> void:
	_buildings = get_node(building_system_path)
	_companies = get_node(company_system_path)
	_rng.randomize()
	_hh = GameData.section("economy/households")
	_money = GameData.section("economy/money")
	_life = GameData.section("economy/lifecycle")
	_mig = GameData.section("economy/migration")
	_happy = GameData.section("economy/happiness")
	_default_tax = GameData.num("economy/taxes/default")
	_ticks_per_month = int(GameData.num("time/real_seconds_per_day_at_1x") * GameData.num("time/tick_rate_hz"))
	_no_utility_score = GameData.num("services/effects/no_utility_home_score")
	_commute_cfg = GameData.section("traffic/commute")
	_noise_happiness = GameData.num("traffic/noise/happiness")
	if not traffic_system_path.is_empty():
		_traffic = get_node(traffic_system_path)
	if not district_system_path.is_empty():
		_districts = get_node(district_system_path)
	_reset_month()
	EventBus.sim_tick.connect(_on_tick)
	EventBus.month_changed.connect(_on_month)
	EventBus.buildings_changed.connect(_sync_homes)
	EventBus.company_closed.connect(_on_company_closed)
	EventBus.workers_laid_off.connect(_on_laid_off)
	EventBus.shops_changed.connect(_refresh_shops)
	EventBus.demand_changed.connect(func(d: Dictionary) -> void: _demand_res = d["migration"])


func _reset_month() -> void:
	_acc = {"tax": 0.0, "income": 0.0, "rent": 0.0, "goods": 0.0, "unmet": 0.0, "happy_sum": 0.0, "happy_n": 0, "deaths": 0}


# --- Homes -----------------------------------------------------------------------

func _sync_homes() -> void:
	var records: Dictionary = _buildings.buildings
	_parks = PackedVector2Array()
	for bid: int in records:
		var b: Dictionary = records[bid]
		if str(b["style"]).begins_with("park"):
			_parks.append(b["centre"])
		var cap: int = 0 if b.get("abandoned", false) else int(b.get("households_cap", 0))
		if cap <= 0 and not _homes.has(bid):
			continue
		if not _homes.has(bid):
			_homes[bid] = {"cap": cap, "residents": PackedInt32Array(), "pos": b["centre"], "shop": -1}
			_homes[bid]["shop"] = _companies.nearest_shop(b["centre"])
		var home: Dictionary = _homes[bid]
		home["cap"] = cap
		home["rent"] = EconomyRules.rent(b["zone_key"], b["level"], _money)
		while (home["residents"] as PackedInt32Array).size() > cap:
			var residents: PackedInt32Array = home["residents"]
			var i := residents[residents.size() - 1]
			_relocate_or_leave(i, bid)
		_update_vacancy(bid)
	for bid: int in _homes.keys():
		if not records.has(bid):
			var residents: PackedInt32Array = (_homes[bid]["residents"] as PackedInt32Array).duplicate()
			for i in residents:
				_relocate_or_leave(i, bid)
			_homes.erase(bid)
			_vacant.erase(bid)
	_write_occupancy()


func _update_vacancy(bid: int) -> void:
	var home: Dictionary = _homes[bid]
	if (home["residents"] as PackedInt32Array).size() < int(home["cap"]):
		_vacant[bid] = true
	else:
		_vacant.erase(bid)


## Households per home onto the building records; with people = true also
## residents and children (monthly, for the service load figures).
func _write_occupancy(people_too: bool = false) -> void:
	var records: Dictionary = _buildings.buildings
	for bid: int in _homes:
		if not records.has(bid):
			continue
		var residents: PackedInt32Array = _homes[bid]["residents"]
		var b: Dictionary = records[bid]
		b["occupants"] = residents.size()
		if people_too:
			var people := 0
			var children := 0
			for i in residents:
				people += data.members(i)
				children += data.children[i]
			b["residents"] = people
			b["children"] = children


func _refresh_shops() -> void:
	for home: Dictionary in _homes.values():
		home["shop"] = _companies.nearest_shop(home["pos"])


func _near_park(pos: Vector2) -> bool:
	var r := float(_happy["park_radius_m"])
	for p in _parks:
		if p.distance_to(pos) <= r:
			return true
	return false


func _pick_home(max_rent: float, exclude: int) -> int:
	if _vacant.is_empty():
		return -1
	var keys := _vacant.keys()
	var best := -1
	var best_score := -INF
	for n in int(_mig["candidates_sampled"]):
		var bid: int = keys[_rng.randi_range(0, keys.size() - 1)]
		if bid == exclude:
			continue
		var home: Dictionary = _homes[bid]
		if float(home["rent"]) > max_rent:
			continue
		var score := -float(home["rent"]) / 1000.0 + _rng.randf() * 0.3
		var b: Dictionary = _buildings.buildings.get(bid, {})
		if not (b.get("power", true) and b.get("water", true)):
			score += _no_utility_score
		if int(home["shop"]) >= 0:
			score += 0.5
		if _near_park(home["pos"]):
			score += 0.3
		if score > best_score:
			best_score = score
			best = bid
	return best


func _move_in(i: int, bid: int) -> void:
	var home: Dictionary = _homes[bid]
	var residents: PackedInt32Array = home["residents"]
	residents.append(i)
	home["residents"] = residents
	data.home[i] = bid
	_update_vacancy(bid)


func _move_out(i: int, bid: int) -> void:
	if not _homes.has(bid):
		return
	var home: Dictionary = _homes[bid]
	var residents: PackedInt32Array = home["residents"]
	var idx := residents.find(i)
	if idx >= 0:
		residents.remove_at(idx)
	home["residents"] = residents
	_update_vacancy(bid)


func _relocate_or_leave(i: int, from: int) -> void:
	_move_out(i, from)
	var target := _pick_home(INF, from)
	if target >= 0:
		_move_in(i, target)
	else:
		_leave(i)


func _leave(i: int) -> void:
	if data.alive[i] == 0:
		return
	_move_out(i, data.home[i])
	_count(i, -1)
	for k in data.adults[i]:
		_companies.release(data.job[i * HouseholdData.MAX_ADULTS + k])
	data.remove(i)


# --- Counters ------------------------------------------------------------------------

## Adds (sign = 1) or removes (sign = -1) a household's members from the counters.
func _count(i: int, sign: int) -> void:
	population += sign * data.members(i)
	workers += sign * data.adults[i]
	for k in data.adults[i]:
		var slot := i * HouseholdData.MAX_ADULTS + k
		if data.job[slot] == HouseholdData.NO_JOB:
			unemployed_by_edu[data.edu[slot]] += sign
		else:
			employed += sign


func _set_job(i: int, k: int, code: int) -> void:
	var slot := i * HouseholdData.MAX_ADULTS + k
	var was := data.job[slot]
	if was == code:
		return
	if was == HouseholdData.NO_JOB:
		unemployed_by_edu[data.edu[slot]] -= 1
		employed += 1
	if code == HouseholdData.NO_JOB:
		employed -= 1
		unemployed_by_edu[data.edu[slot]] += 1
	data.job[slot] = code


func _on_company_closed(bid: int) -> void:
	for i in data.capacity():
		if data.alive[i] == 0:
			continue
		for k in data.adults[i]:
			var code := data.job[i * HouseholdData.MAX_ADULTS + k]
			if code != HouseholdData.NO_JOB and HouseholdData.job_company(code) == bid:
				_set_job(i, k, HouseholdData.NO_JOB)


## A company shrinks: `count` workers at that job level lose their job.
func _on_laid_off(bid: int, level: int, count: int) -> void:
	var left := count
	var target := HouseholdData.job_code(bid, level)
	for i in data.capacity():
		if left <= 0:
			return
		if data.alive[i] == 0:
			continue
		for k in data.adults[i]:
			if left > 0 and data.job[i * HouseholdData.MAX_ADULTS + k] == target:
				_set_job(i, k, HouseholdData.NO_JOB)
				left -= 1


# --- Simulation ------------------------------------------------------------------------

func _random_education() -> int:
	var w: Array = _hh["immigrant_education_weights"]
	var r := _rng.randf()
	var acc := 0.0
	for e in w.size():
		acc += float(w[e])
		if r <= acc:
			return e
	return w.size() - 1


func _on_tick(_t: int) -> void:
	var per_month := float(_mig["immigrants_per_month_base"]) + float(_mig["immigrants_per_month_per_demand"]) * maxf(_demand_res, 0.0)
	per_month *= Cheats.growth_factor()
	# Newcomers arrive by highway: a town not linked to one grows slower.
	if not road_network_path.is_empty() and not get_node(road_network_path).city_connected():
		per_month *= float(_mig.get("isolated_factor", 0.5))
	if _demand_res > -0.2 and not _vacant.is_empty():
		_immigration += per_month / _ticks_per_month
		while _immigration >= 1.0:
			_immigration -= 1.0
			_spawn_immigrant()
	var n := data.capacity()
	if n == 0:
		return
	# Exactly one update per household per month: carry the fractional share.
	_budget += float(n) / _ticks_per_month
	while _budget >= 1.0:
		_budget -= 1.0
		_cursor = (_cursor + 1) % n
		if data.alive[_cursor] == 1:
			_update(_cursor)


func _spawn_immigrant() -> void:
	var bid := _pick_home(INF, -1)
	if bid < 0:
		return
	var adults_range: Array = _hh["immigrant_adults"]
	var children_range: Array = _hh["immigrant_children"]
	var money_range: Array = _hh["immigrant_money"]
	var adults := _rng.randi_range(int(adults_range[0]), int(adults_range[1]))
	var seniors := 1 if _rng.randf() < float(_hh["senior_chance"]) else 0
	var edus := []
	for k in adults:
		edus.append(_random_education())
	var i := data.add(bid, adults, _rng.randi_range(int(children_range[0]), int(children_range[1])), seniors, edus,
		_rng.randf_range(float(money_range[0]), float(money_range[1])))
	_move_in(i, bid)
	_count(i, 1)
	_seek_jobs(i)
	_write_occupancy_one(bid)


func _write_occupancy_one(bid: int) -> void:
	var records: Dictionary = _buildings.buildings
	if records.has(bid) and _homes.has(bid):
		records[bid]["occupants"] = (_homes[bid]["residents"] as PackedInt32Array).size()


func _seek_jobs(i: int) -> void:
	var home: Dictionary = _homes.get(data.home[i], {})
	if home.is_empty():
		return
	for k in data.adults[i]:
		var slot := i * HouseholdData.MAX_ADULTS + k
		if data.job[slot] == HouseholdData.NO_JOB:
			var code: int = _companies.try_hire(data.edu[slot], home["pos"], int(_mig["candidates_sampled"]))
			if code != HouseholdData.NO_JOB:
				_set_job(i, k, code)


## The monthly update of one household.
func _update(i: int) -> void:
	var bid := data.home[i]
	if not _homes.has(bid):
		_leave(i)
		return
	var home: Dictionary = _homes[bid]
	var wages: Array = _money["wage_by_education"]
	var income := float(_money["pension"]) * data.seniors[i]
	var tax := 0.0
	var working := 0
	for k in data.adults[i]:
		var slot := i * HouseholdData.MAX_ADULTS + k
		var code := data.job[slot]
		if code != HouseholdData.NO_JOB:
			var wage := float(wages[HouseholdData.job_level(code)])
			income += wage
			tax += wage * EconomySystem.residential_rate(data.edu[slot]) / 100.0 * EconomySystem.city_share()
			working += 1
		elif population < int(_money["unemployment_aid_until_population"]):
			income += float(_money["unemployment_aid"])
	var units := data.members(i) * float(_money["goods_per_person"])
	var shop := int(home["shop"])
	var goods_cost := 0.0
	if shop >= 0:
		_companies.sell_goods(shop, units)
		goods_cost = units * float(_money["retail_price"])
	else:
		_acc["unmet"] += units
	_acc["goods"] += units
	var rent := float(home["rent"])
	data.money[i] += income - rent - goods_cost - tax
	data.income[i] = income
	data.broke[i] = mini(data.broke[i] + 1, 255) if data.money[i] < 0.0 else 0
	_acc["tax"] += tax
	_acc["income"] += income
	_acc["rent"] += rent

	var ratio := 0.0 if data.adults[i] == 0 else float(working) / data.adults[i]
	var avg_tax := EconomySystem.residential_rate(data.edu[i * HouseholdData.MAX_ADULTS])
	var h := EconomyRules.happiness(ratio, data.adults[i] > 0, data.broke[i] > 0, shop >= 0, avg_tax,
		_near_park(home["pos"]), _happy, _default_tax)
	var record: Dictionary = _buildings.buildings.get(bid, {})
	h += float(record.get("service_happiness", 0.0))
	if _districts != null and not record.is_empty():
		h += float(_districts.happiness_of(record))
	if _traffic != null:
		var commute := _commute_of(i, record)
		if commute >= 0.0:
			h += TrafficRules.commute_happiness(commute, _commute_cfg)
		h += _noise_happiness * float(_traffic.noise(int(record.get("segment", -1))))
	h = clampf(h, 0.0, 100.0)
	data.happiness[i] = h
	_acc["happy_sum"] += h
	_acc["happy_n"] += 1

	_lifecycle(i)
	if data.alive[i] == 0:
		return
	if data.members(i) == 0:
		_leave(i)
		return
	if h < float(_mig["unhappy_leave_threshold"]) and _rng.randf() < float(_mig["unhappy_leave_chance"]):
		_leave(i)
		return
	if data.broke[i] >= int(_money["broke_months_to_move"]):
		var cheaper := _pick_home(rent * 0.9, bid)
		if cheaper >= 0:
			_move_out(i, bid)
			_move_in(i, cheaper)
			data.broke[i] = 0
		else:
			_leave(i)
			return
	_seek_jobs(i)


func _lifecycle(i: int) -> void:
	var before := data.members(i)
	var record: Dictionary = _buildings.buildings.get(data.home[i], {})
	_count(i, -1)
	if data.adults[i] > 0 and data.children[i] < int(_hh["max_children"]) and _rng.randf() < float(_life["birth_chance"]):
		data.children[i] += 1
	if data.children[i] > 0 and _rng.randf() < float(_life["child_grows_chance"]):
		if data.adults[i] < HouseholdData.MAX_ADULTS:
			data.children[i] -= 1
			data.add_adult(i, _grown_education(record))
	if data.adults[i] > 0 and _rng.randf() < float(_life["retire_chance"]):
		_companies.release(data.remove_adult(i, data.adults[i] - 1))
		data.seniors[i] += 1
	if data.seniors[i] > 0 and _rng.randf() < float(_life["senior_death_chance"]) * float(record.get("death_mult", 1.0)):
		data.seniors[i] -= 1
		_acc["deaths"] += 1
	_count(i, 1)
	# A grown-up child may start a household of its own.
	if data.adults[i] >= 2 and _rng.randf() < float(_life["move_out_chance"]):
		var target := _pick_home(INF, data.home[i])
		if target >= 0:
			var slot := i * HouseholdData.MAX_ADULTS + data.adults[i] - 1
			var education := data.edu[slot]
			_count(i, -1)
			_companies.release(data.remove_adult(i, data.adults[i] - 1))
			_count(i, 1)
			var share := maxf(data.money[i] * 0.3, 0.0)
			data.money[i] -= share
			var j := data.add(target, 1, 0, 0, [education], share)
			_move_in(j, target)
			_count(j, 1)
	if data.members(i) != before:
		_write_occupancy_one(data.home[i])


## Education a child reaches growing up in this home: high school and then
## university need those schools covering it.
func _grown_education(record: Dictionary) -> int:
	var chance: Vector2 = record.get("edu_chance", Vector2.ZERO)
	if _rng.randf() >= chance.x:
		return 0
	return 2 if _rng.randf() < chance.y else 1


func _on_month(_m: int) -> void:
	var n: int = _acc["happy_n"]
	last_report = {
		"population": population, "residential_tax": _acc["tax"], "income": _acc["income"], "rent": _acc["rent"],
		"happiness": 50.0 if n == 0 else _acc["happy_sum"] / n,
		"goods_unmet_ratio": 0.0 if _acc["goods"] <= 0.0 else _acc["unmet"] / _acc["goods"],
		"deaths": _acc["deaths"],
	}
	_write_occupancy(true)
	_write_building_happiness()
	_reset_month()
	EventBus.citizens_reported.emit(last_report)


## Average road commute (minutes) of a household's workers, or -1 if nobody
## works. Pairs the traffic assignment has not seen yet are estimated from
## the straight distance.
func _commute_of(i: int, record: Dictionary) -> float:
	var records: Dictionary = _buildings.buildings
	var home_seg := int(record.get("segment", -1))
	var total := 0.0
	var n := 0
	for k in data.adults[i]:
		var code := data.job[i * HouseholdData.MAX_ADULTS + k]
		if code == HouseholdData.NO_JOB:
			continue
		var work: Dictionary = records.get(HouseholdData.job_company(code), {})
		if work.is_empty():
			continue
		var minutes: float = _traffic.commute_minutes(home_seg, int(work.get("segment", -1)))
		if minutes < 0.0:
			var dist := (record.get("centre", Vector2.ZERO) as Vector2).distance_to(work["centre"])
			minutes = dist * 1.3 / float(_commute_cfg["fallback_speed_ms"]) / 60.0
		total += minutes
		n += 1
	return -1.0 if n == 0 else total / n


func _write_building_happiness() -> void:
	var records: Dictionary = _buildings.buildings
	for bid: int in _homes:
		if not records.has(bid):
			continue
		var residents: PackedInt32Array = _homes[bid]["residents"]
		var total := 0.0
		var commute_sum := 0.0
		var commute_n := 0
		for i in residents:
			total += data.happiness[i]
			if _traffic != null:
				var c := _commute_of(i, records[bid])
				if c >= 0.0:
					commute_sum += c
					commute_n += 1
		records[bid]["happiness"] = 0.0 if residents.is_empty() else total / residents.size()
		records[bid]["commute"] = -1.0 if commute_n == 0 else commute_sum / commute_n


func stats() -> Dictionary:
	var homes := 0
	var occupied := 0
	for home: Dictionary in _homes.values():
		homes += int(home["cap"])
		occupied += (home["residents"] as PackedInt32Array).size()
	var unemployed := unemployed_by_edu[0] + unemployed_by_edu[1] + unemployed_by_edu[2]
	return {
		"population": population, "workers": workers, "unemployed": unemployed,
		"unemployed_by_edu": [unemployed_by_edu[0], unemployed_by_edu[1], unemployed_by_edu[2]],
		"homes": homes, "empty_homes": homes - occupied,
		"happiness": float(last_report.get("happiness", 50.0)),
		"goods_unmet_ratio": float(last_report.get("goods_unmet_ratio", 0.0)),
	}


# --- Save / load ------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"alive": data.alive, "home": data.home, "adults": data.adults, "children": data.children,
		"seniors": data.seniors, "edu": data.edu, "job": data.job, "money": data.money,
		"happiness": data.happiness, "broke": data.broke, "income": data.income,
	}


func load_state(state: Dictionary) -> void:
	# Homes start empty: residents lists of the city before refer to the old
	# household table.
	_homes = {}
	_vacant = {}
	_sync_homes()
	data = HouseholdData.new()
	population = 0
	workers = 0
	employed = 0
	unemployed_by_edu = PackedInt32Array([0, 0, 0])
	var alive := PackedByteArray(state.get("alive", PackedByteArray()))
	var homes := PackedInt32Array(state.get("home", PackedInt32Array()))
	var adults := PackedByteArray(state.get("adults", PackedByteArray()))
	var children := PackedByteArray(state.get("children", PackedByteArray()))
	var seniors := PackedByteArray(state.get("seniors", PackedByteArray()))
	var edus := PackedByteArray(state.get("edu", PackedByteArray()))
	var jobs := PackedInt32Array(state.get("job", PackedInt32Array()))
	var money := PackedFloat32Array(state.get("money", PackedFloat32Array()))
	var happiness := PackedFloat32Array(state.get("happiness", PackedFloat32Array()))
	for s in alive.size():
		if alive[s] == 0 or not _homes.has(homes[s]):
			continue
		var bid := homes[s]
		if (_homes[bid]["residents"] as PackedInt32Array).size() >= int(_homes[bid]["cap"]):
			continue
		var e := []
		for k in HouseholdData.MAX_ADULTS:
			e.append(edus[s * HouseholdData.MAX_ADULTS + k])
		var i := data.add(bid, adults[s], children[s], seniors[s], e, money[s])
		data.happiness[i] = happiness[s]
		_move_in(i, bid)
		_count(i, 1)
		for k in data.adults[i]:
			var code := jobs[s * HouseholdData.MAX_ADULTS + k]
			if code != HouseholdData.NO_JOB and _companies.restore_worker(code):
				_set_job(i, k, code)
	_companies.refresh_vacancies()
	_write_occupancy(true)

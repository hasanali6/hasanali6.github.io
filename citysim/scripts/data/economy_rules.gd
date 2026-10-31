class_name EconomyRules
extends RefCounted
## Pure economy formulas shared by the citizen, company, demand and budget
## systems. Every number comes from data/economy.json (passed in as config).

const GROUPS: PackedStringArray = ["residential", "commercial", "office", "industrial"]


static func zone_group(zones_cfg: Dictionary, zone_key: String) -> String:
	return str(zones_cfg[zone_key]["group"]) if zones_cfg.has(zone_key) else ""


## Households a building can house. Mixed buildings keep the ground floor for shops.
static func households_capacity(zone_key: String, floors: int, cells: int, households_cfg: Dictionary) -> int:
	var per: Dictionary = households_cfg["per_floor_per_cell"]
	if not per.has(zone_key):
		return 0
	var usable := floors - 1 if zone_key == "mixed" else floors
	return maxi(roundi(float(per[zone_key]) * maxi(usable, 1) * cells), 1)


## Job slots split by education level (index 0..2).
static func job_slots(zone_key: String, group: String, floors: int, cells: int, companies_cfg: Dictionary) -> PackedInt32Array:
	var slots := PackedInt32Array([0, 0, 0])
	var per: Dictionary = companies_cfg["jobs_per_floor_per_cell"]
	if not per.has(zone_key):
		return slots
	var job_floors := 1 if zone_key == "mixed" else floors
	var total := maxi(roundi(float(per[zone_key]) * job_floors * cells), 1)
	var kind := company_kind(zone_key, group)
	var mix: Array = companies_cfg["education_mix"][kind]
	var assigned := 0
	for e in 3:
		slots[e] = floori(total * float(mix[e]))
		assigned += slots[e]
	slots[0] += total - assigned
	return slots


static func company_kind(zone_key: String, group: String) -> String:
	if zone_key == "mixed":
		return "commercial"
	return group


static func rent(zone_key: String, level: int, money_cfg: Dictionary) -> float:
	var base: Dictionary = money_cfg["rent_by_zone"]
	var factor: Array = money_cfg["rent_level_factor"]
	return float(base.get(zone_key, 0.0)) * float(factor[clampi(level - 1, 0, factor.size() - 1)])


static func happiness(employed_ratio: float, has_workers: bool, broke: bool, has_shop: bool,
		tax_rate: float, near_park: bool, cfg: Dictionary, default_tax: float) -> float:
	var h := float(cfg["base"])
	if has_workers:
		h += lerpf(float(cfg["unemployed"]), float(cfg["employed"]), employed_ratio)
	h += float(cfg["broke"]) if broke else float(cfg["money_ok"])
	h += float(cfg["goods_ok"]) if has_shop else float(cfg["no_shop"])
	h += float(cfg["tax_per_point_over_default"]) * (tax_rate - default_tax)
	if near_park:
		h += float(cfg["park_bonus"])
	return clampf(h, 0.0, 100.0)


static func loan_limit(population: int, cfg: Dictionary) -> int:
	var step := int(cfg["step"])
	var raw := float(cfg["limit_base"]) + float(cfg["limit_per_citizen"]) * population
	return int(floorf(raw / step)) * step


## Annual interest grows with how much of the limit is borrowed.
static func loan_interest(amount: float, limit: float, cfg: Dictionary) -> float:
	var use := 0.0 if limit <= 0.0 else clampf(amount / limit, 0.0, 1.0)
	return lerpf(float(cfg["interest_min"]), float(cfg["interest_max"]), use)


## Fixed monthly instalment that repays `amount` over `months` (annuity).
static func loan_payment(amount: float, annual_rate: float, months: int) -> float:
	if amount <= 0.0 or months <= 0:
		return 0.0
	var r := annual_rate / 12.0
	if r <= 0.0:
		return amount / months
	return amount * r / (1.0 - pow(1.0 + r, -months))


static func subsidy(population: int, cfg: Dictionary) -> float:
	return maxf(float(cfg["subsidy_base"]) - float(cfg["subsidy_per_citizen"]) * population, 0.0)


## Demand per zone group in -1..1 from city statistics, plus "migration"
## (attractiveness to newcomers, without the free-homes penalty). stats keys:
## population, workers, unemployed, unemployed_by_edu (3), vacant_jobs,
## homes, empty_homes, happiness, goods_unmet_ratio, import_ratio,
## commercial_jobs, industrial_jobs, office_jobs.
static func demand(stats: Dictionary, taxes: Dictionary, cfg: Dictionary, default_tax: float) -> Dictionary:
	var pop := float(stats["population"])
	var workers := maxf(float(stats["workers"]), 30.0)
	var unemployed := float(stats["unemployed"])
	var edu: Array = stats["unemployed_by_edu"]
	var start := float(cfg["start_residential"]) * maxf(1.0 - pop / float(cfg["start_fade_population"]), 0.0)

	# How attractive the city is to newcomers (drives immigration into free homes).
	var migration := start
	migration += float(cfg["job_balance_weight"]) * (float(stats["vacant_jobs"]) - unemployed) / workers
	migration += float(cfg["happiness_weight"]) * (float(stats["happiness"]) - 50.0) / 50.0
	migration -= float(cfg["tax_weight"]) * (float(taxes["residential"]) - default_tax)
	# Building more homes only makes sense once the free ones are filling up;
	# a healthy vacancy buffer is not penalised, and not before people arrive.
	var vacancy := float(stats["empty_homes"]) / maxf(float(stats["homes"]), 10.0)
	var maturity := clampf(pop / float(cfg["start_fade_population"]), 0.0, 1.0)
	var res := migration - float(cfg["empty_home_weight"]) * maxf(vacancy - float(cfg["healthy_vacancy"]), 0.0) * maturity

	var com := -0.2
	if pop >= float(cfg["min_commercial_customers"]):
		var want := pop * float(cfg["commercial_jobs_per_citizen"])
		com = float(cfg["goods_weight"]) * float(stats["goods_unmet_ratio"])
		com += 0.8 * clampf((want - float(stats["commercial_jobs"])) / maxf(want, 1.0), -1.0, 1.0)
	com -= float(cfg["tax_weight"]) * (float(taxes["commercial"]) - default_tax)

	var ind := -0.2
	if pop >= float(cfg["min_industry_population"]):
		var want_i := pop * float(cfg["industrial_jobs_per_citizen"])
		ind = 0.8 * clampf((want_i - float(stats["industrial_jobs"])) / maxf(want_i, 1.0), -1.0, 1.0)
		ind += 0.6 * float(stats["import_ratio"])
		ind += 0.4 * float(edu[0]) / workers
	ind -= float(cfg["tax_weight"]) * (float(taxes["industrial"]) - default_tax)

	var off := -0.2
	if pop >= float(cfg["min_office_population"]):
		var want_o := pop * float(cfg["office_jobs_per_citizen"])
		off = 0.8 * clampf((want_o - float(stats["office_jobs"])) / maxf(want_o, 1.0), -1.0, 1.0)
		off += 0.8 * float(edu[2]) / workers
	off -= float(cfg["tax_weight"]) * (float(taxes["office"]) - default_tax)

	return {
		"residential": clampf(res, -1.0, 1.0), "migration": clampf(migration, -1.0, 1.0), "commercial": clampf(com, -1.0, 1.0),
		"industrial": clampf(ind, -1.0, 1.0), "office": clampf(off, -1.0, 1.0),
	}

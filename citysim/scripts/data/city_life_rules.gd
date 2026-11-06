class_name CityLifeRules
extends RefCounted
## Pure rules behind land value, crime, fires and missions (CityLifeSystem
## gathers the inputs and applies the results). Every weight comes from
## data/life.json.


## Land value 0..1 of a spot. f: park (0..1 closeness to the best park),
## water (0..1 closeness to a shore), transit (0..1 stop access), services
## (0..1 average coverage), pollution, noise, crime (0..1), nuisance (0..1).
static func land_value(f: Dictionary, cfg: Dictionary) -> float:
	var v := float(cfg["base"])
	v += float(cfg["park_weight"]) * float(f.get("park", 0.0))
	v += float(cfg["water_weight"]) * float(f.get("water", 0.0))
	v += float(cfg["transit_weight"]) * float(f.get("transit", 0.0))
	v += float(cfg["service_weight"]) * float(f.get("services", 0.0))
	v -= float(cfg["pollution_weight"]) * float(f.get("pollution", 0.0))
	v -= float(cfg["noise_weight"]) * float(f.get("noise", 0.0))
	v -= float(cfg["crime_weight"]) * float(f.get("crime", 0.0))
	v -= float(f.get("nuisance", 0.0))
	return clampf(v, 0.0, 1.0)


## 1 at the spot, 0 at the radius and beyond.
static func closeness(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return clampf(1.0 - distance / radius, 0.0, 1.0)


## Multiplier between lo (value 0) and hi (value 1).
static func scale(value: float, lo: float, hi: float) -> float:
	return lerpf(lo, hi, clampf(value, 0.0, 1.0))


## Land value a building needs before it may grow to `next_level`
## (0 = no requirement).
static func level_requirement(next_level: int, cfg: Dictionary) -> float:
	return float((cfg["level_requirement"] as Dictionary).get(str(next_level), 0.0))


## Crime 0..1 of a building before smoothing. f: floors, happiness (0..100,
## -1 = nobody lives there), unemployment (city rate 0..1), abandoned
## (0..1 share of empty buildings nearby), police (coverage 0..1).
static func crime(f: Dictionary, cfg: Dictionary) -> float:
	var c := float(cfg["base"])
	c += float(cfg["density_weight"]) * clampf(float(f.get("floors", 1)) / float(cfg["density_floors"]), 0.0, 1.0)
	var happy := float(f.get("happiness", -1.0))
	if happy >= 0.0:
		c += float(cfg["unhappy_weight"]) * clampf(1.0 - happy / 100.0, 0.0, 1.0)
	c += float(cfg["unemployment_weight"]) * clampf(float(f.get("unemployment", 0.0)), 0.0, 1.0)
	c += float(cfg["abandoned_weight"]) * clampf(float(f.get("abandoned", 0.0)), 0.0, 1.0)
	c *= 1.0 - float(cfg["police_reduction"]) * clampf(float(f.get("police", 0.0)), 0.0, 1.0)
	return clampf(c, 0.0, 1.0)


## Next crime value: moves part of the way from old to target each month.
static func smooth(old: float, target: float, k: float) -> float:
	return lerpf(old, target, clampf(k, 0.0, 1.0))


## What happens to a fire after `t` seconds (game time) with fire coverage
## `cover` 0..1: "out" once the fire brigade arrived and put it out, "down"
## once the building burnt down, else "burning".
static func fire_state(t: float, cover: float, cfg: Dictionary) -> String:
	if cover > 0.02 and t >= float(cfg["put_out_seconds"]) / cover:
		return "out"
	if t >= float(cfg["burn_down_seconds"]):
		return "down"
	return "burning"


## Mission reward for a city of `population`.
static func mission_reward(population: int, cfg: Dictionary) -> int:
	var r := float(cfg["reward_base"]) + float(cfg["reward_per_person"]) * population
	return int(minf(roundf(r / 1000.0) * 1000.0, float(cfg["reward_max"])))


## A new mission of `kind` from the city's current stats (see
## CityLifeSystem.stats()). Returns {} when the kind does not fit right now.
static func make_mission(kind: String, s: Dictionary, cfg: Dictionary) -> Dictionary:
	var pop := int(s.get("population", 0))
	var min_pop := int((cfg["min_population_for"] as Dictionary).get(kind, 0))
	if pop < min_pop:
		return {}
	var m := {"kind": kind, "reward": mission_reward(pop, cfg)}
	match kind:
		"population":
			m["target"] = maxi(roundi(maxf(pop * 1.25, pop + 60) / 10.0) * 10, 50)
		"happiness":
			var h := float(s.get("happiness", 50.0))
			if h >= 85.0:
				return {}
			m["target"] = minf(roundf(maxf(h + 6.0, 60.0)), 90.0)
		"crime":
			var c := float(s.get("crime", 0.0))
			if c < 0.12:
				return {}
			m["target"] = snappedf(maxf(c * 0.7, 0.08), 0.01)
		"land_value":
			var v := float(s.get("land_value", 0.0))
			if v > 0.8:
				return {}
			m["target"] = snappedf(minf(v + 0.06, 0.85), 0.01)
		"parks":
			m["start"] = int(s.get("parks", 0))
			m["target"] = int(s.get("parks", 0)) + (2 if pop < 2000 else 3)
		"transit":
			m["target"] = int(s.get("transit_lines", 0)) + 1
		"budget":
			m["target"] = maxi(roundi(maxf(float(s.get("net", 0.0)), 0.0) / 1000.0) * 1000 + 2000, 2000)
		"services":
			var cov := float(s.get("coverage", 0.0))
			if cov > 0.9:
				return {}
			m["target"] = snappedf(minf(cov + 0.12, 0.95), 0.01)
		_:
			return {}
	return m


## Progress 0..1 of a mission against the city's current stats.
static func mission_progress(m: Dictionary, s: Dictionary) -> float:
	var target := float(m["target"])
	match str(m["kind"]):
		"population":
			return clampf(float(s.get("population", 0)) / target, 0.0, 1.0)
		"happiness":
			return clampf(float(s.get("happiness", 0.0)) / target, 0.0, 1.0)
		"crime":
			var c := float(s.get("crime", 1.0))
			return 1.0 if c <= target else clampf(target / maxf(c, 1e-4), 0.0, 0.99)
		"land_value":
			return clampf(float(s.get("land_value", 0.0)) / target, 0.0, 1.0)
		"parks":
			var start := float(m.get("start", 0))
			return clampf((float(s.get("parks", 0)) - start) / maxf(target - start, 1.0), 0.0, 1.0)
		"transit":
			return clampf(float(s.get("transit_lines", 0)) / target, 0.0, 1.0)
		"budget":
			return clampf(float(s.get("net", 0.0)) / target, 0.0, 1.0)
		"services":
			return clampf(float(s.get("coverage", 0.0)) / target, 0.0, 1.0)
	return 0.0


## True once a tutorial step's goal is met. s: CityLifeSystem tutorial stats.
static func tutorial_done(step_id: String, s: Dictionary) -> bool:
	match step_id:
		"road":
			return int(s.get("roads_built", 0)) > 0
		"res":
			return int(s.get("res_cells", 0)) >= 8
		"jobs":
			return int(s.get("com_cells", 0)) >= 4 and int(s.get("ind_cells", 0)) >= 4
		"power":
			return int(s.get("power", 0)) > 0
		"water":
			return int(s.get("water", 0)) > 0
		"grow":
			return int(s.get("population", 0)) >= 40
		"safety":
			return int(s.get("safety", 0)) > 0
		"layers":
			return bool(s.get("layer_seen", false))
		"missions":
			return bool(s.get("missions_seen", false))
	return true

class_name ProgressionRules
extends RefCounted
## Pure milestone maths (data/progression.json), testable headless.
## Milestones are ordered by population; reaching one unlocks its list of
## ids ("road:avenue", "zone:office", "item:tower", "svc:hospital",
## "transit:tram", "districts"), raises the loan limit and may widen the
## buildable area.


## Highest milestone index reached with this population.
static func level_for(population: int, milestones: Array) -> int:
	var level := 0
	for i in milestones.size():
		if population >= int((milestones[i] as Dictionary)["population"]):
			level = i
	return level


## Milestone index that unlocks an id, or -1 if no milestone lists it
## (such ids are always available).
static func unlock_level(id: String, milestones: Array) -> int:
	for i in milestones.size():
		if id in ((milestones[i] as Dictionary).get("unlocks", []) as Array):
			return i
	return -1


static func is_unlocked(id: String, level: int, milestones: Array) -> bool:
	return unlock_level(id, milestones) <= level


## Half size of the buildable square at a level: the last milestone up to
## it that sets one.
static func area_half(level: int, milestones: Array, fallback: float) -> float:
	var half := fallback
	for i in mini(level + 1, milestones.size()):
		var m: Dictionary = milestones[i]
		if m.has("area_half_m"):
			half = float(m["area_half_m"])
	return half


## 0..1 progress from the current milestone to the next (1 at the last).
static func progress(population: int, level: int, milestones: Array) -> float:
	if level + 1 >= milestones.size():
		return 1.0
	var a := float((milestones[level] as Dictionary)["population"])
	var b := float((milestones[level + 1] as Dictionary)["population"])
	return clampf((population - a) / maxf(b - a, 1.0), 0.0, 1.0)

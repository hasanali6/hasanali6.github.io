extends Node
## Progression (autoload): population milestones from Mezra to Megakent
## (data/progression.json). The town starts with a small set of roads,
## zones and services and a smaller buildable square; each milestone pays a
## reward, raises the loan limit and unlocks more of them. Locked tools stay
## visible in the menus with the milestone that opens them.
##
## Saves keep the highest milestone reached so rewards are paid once; old
## saves without it start at the milestone their population has reached.

const DEV_UNLOCK_ALL := -2

var level: int = 0
var population: int = 0

var _milestones: Array = []
var _fallback_half: float = 2000.0


func _ready() -> void:
	_milestones = GameData.value("progression/milestones")
	_fallback_half = GameData.num("map/playable_size_m") * 0.5
	EventBus.city_stats_changed.connect(_on_stats)


func milestones() -> Array:
	return _milestones


func milestone(i: int) -> Dictionary:
	return _milestones[clampi(i, 0, _milestones.size() - 1)]


func is_unlocked(id: String) -> bool:
	return ProgressionRules.is_unlocked(id, level, _milestones)


## Milestone that unlocks an id ({} if always available).
func requirement(id: String) -> Dictionary:
	var i := ProgressionRules.unlock_level(id, _milestones)
	return {} if i < 0 else _milestones[i]


## "Kasaba (1.000 nüfus)" for a locked id.
func requirement_text(id: String) -> String:
	var m := requirement(id)
	if m.is_empty():
		return ""
	return tr("LOCKED_NEEDS") % [tr(m["name_key"]), UiStyle.format_int(int(m["population"]))]


## Shows why a tool is locked; returns true if it is.
func warn_if_locked(id: String, name_key: String) -> bool:
	if is_unlocked(id):
		return false
	EventBus.notification_posted.emit("progression", tr("LOCKED_TOAST") % [tr(name_key), requirement_text(id)])
	return true


## Half size (m) of the square around the centre where roads may be built.
func area_half() -> float:
	return minf(ProgressionRules.area_half(level, _milestones, _fallback_half), _fallback_half)


func loan_limit() -> int:
	return int(milestone(level)["loan_limit"])


func progress() -> float:
	return ProgressionRules.progress(population, level, _milestones)


func _on_stats(stats: Dictionary) -> void:
	population = int(stats.get("population", 0))
	var reached := ProgressionRules.level_for(population, _milestones)
	if reached <= level:
		return
	var unlocked: Array = []
	var reward := 0
	for i in range(level + 1, reached + 1):
		var m: Dictionary = _milestones[i]
		reward += int(m["reward"])
		unlocked.append_array(m.get("unlocks", []))
	level = reached
	if reward > 0:
		EconomySystem.add_bonus(reward)
	var m: Dictionary = _milestones[level]
	EventBus.milestone_reached.emit(level, {"name_key": m["name_key"], "reward": reward, "unlocks": unlocked})
	EventBus.progression_changed.emit()
	var names := PackedStringArray()
	for id: String in unlocked:
		names.append(tr(unlock_name_key(id)))
	var text := tr("NOTIFY_MILESTONE") % [tr(m["name_key"]), UiStyle.format_int(reward)]
	if not names.is_empty():
		text += " " + tr("NOTIFY_MILESTONE_UNLOCKS") % ", ".join(names.slice(0, 4))
	EventBus.notification_posted.emit("progression", text)


## Translation key naming an unlock id.
func unlock_name_key(id: String) -> String:
	var parts := id.split(":")
	match parts[0]:
		"road":
			return str(GameData.value("roads/types/%s/name_key" % parts[1]))
		"zone":
			return str(GameData.value("zones/types/%s/name_key" % parts[1]))
		"transit":
			return str(GameData.value("transit/types/%s/name_key" % parts[1]))
		"districts":
			return "TOOL_DISTRICTS"
		"item":
			for item: Dictionary in GameData.value("catalog/items"):
				if item["id"] == parts[1]:
					return str(item["name_key"])
		"svc":
			for item: Dictionary in GameData.value("services/types"):
				if item["id"] == parts[1]:
					return str(item["name_key"])
	return id


## Everything open (captures and tests).
func unlock_all() -> void:
	level = _milestones.size() - 1
	EventBus.progression_changed.emit()


func reset_state() -> void:
	level = 0
	population = 0
	EventBus.progression_changed.emit()


func save_state() -> Dictionary:
	return {"level": level}


## Old saves have no entry: the level follows the saved population without
## paying rewards again.
func load_state(state: Dictionary, saved_population: int) -> void:
	level = maxi(int(state.get("level", -1)), ProgressionRules.level_for(saved_population, _milestones))
	population = saved_population
	EventBus.progression_changed.emit()

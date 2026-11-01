extends Node
## Saves and restores the whole city. Autosaves every few game months and
## whenever the app is sent to the background or closed (Android may kill a
## backgrounded game), plus three manual slots. Each save is a versioned
## binary Variant dictionary in user://saves/ with a small JSON file beside
## it (date, population, money, milestone) so the slot list opens fast.
## On start the autosave is loaded if it exists; loading a slot reloads the
## scene first so nothing of the previous city is left behind.

const SAVE_DIR := "user://saves/"
const AUTOSAVE := "user://saves/autosave.save"
const PENDING := "user://saves/pending_load.txt"
const SLOT_COUNT := 3

@export var road_network_path: NodePath
@export var zone_system_path: NodePath
@export var building_system_path: NodePath
@export var company_system_path: NodePath
@export var citizen_system_path: NodePath
@export var demand_system_path: NodePath
@export var service_system_path: NodePath
@export var transit_system_path: NodePath
@export var district_system_path: NodePath

var _months_since_save: int = 0
var _loading: bool = false


func _ready() -> void:
	EventBus.month_changed.connect(_on_month)
	_load_on_start.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _on_month(_m: int) -> void:
	_months_since_save += 1
	if _months_since_save >= GameData.integer("economy/budget/autosave_months"):
		save_game.call_deferred()


static func slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.save" % slot


static func meta_path(save_path: String) -> String:
	return save_path.get_basename() + ".json"


func save_game(path: String = AUTOSAVE) -> bool:
	if _loading:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var citizens := get_node(citizen_system_path)
	var state := {
		"version": GameData.integer("game/save_version"),
		"saved_unix": Time.get_unix_time_from_system(),
		"time": TimeSystem.save_state(),
		"economy": EconomySystem.save_state(),
		"progression": ProgressionSystem.save_state(),
		"weather": WeatherSystem.save_state(),
		"roads": get_node(road_network_path).save_state(),
		"zones": get_node(zone_system_path).save_state(),
		"buildings": get_node(building_system_path).save_state(),
		"companies": get_node(company_system_path).save_state(),
		"citizens": citizens.save_state(),
		"demand": get_node(demand_system_path).save_state(),
		"services": get_node(service_system_path).save_state(),
	}
	if not transit_system_path.is_empty():
		state["transit"] = get_node(transit_system_path).save_state()
	if not district_system_path.is_empty():
		state["districts"] = get_node(district_system_path).save_state()
	var veg: Node = get_parent().get_node_or_null("Vegetation")
	if veg != null:
		state["vegetation"] = veg.save_state()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s" % path)
		return false
	file.store_var(state)
	file.close()
	var meta := {
		"saved_unix": state["saved_unix"], "population": int(citizens.population), "balance": EconomySystem.balance,
		"level": ProgressionSystem.level, "date": TimeSystem.get_date_text(),
	}
	var mf := FileAccess.open(meta_path(path), FileAccess.WRITE)
	if mf != null:
		mf.store_string(JSON.stringify(meta))
	_months_since_save = 0
	EventBus.notification_posted.emit("save", tr("NOTIFY_SAVED"))
	EventBus.saves_changed.emit()
	return true


func load_game(path: String = AUTOSAVE) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var state: Variant = file.get_var()
	if typeof(state) != TYPE_DICTIONARY or int(state.get("version", -1)) != GameData.integer("game/save_version"):
		push_warning("SaveSystem: incompatible save ignored")
		return false
	_loading = true
	TimeSystem.load_state(state["time"])
	EconomySystem.load_state(state["economy"])
	get_node(road_network_path).load_state(state["roads"])
	get_node(zone_system_path).load_state(state["zones"])
	get_node(building_system_path).load_state(state["buildings"])
	get_node(company_system_path).load_state(state["companies"])
	get_node(citizen_system_path).load_state(state["citizens"])
	get_node(demand_system_path).load_state(state["demand"])
	# Saves from before city services have no "services" entry.
	get_node(service_system_path).load_state(state.get("services", {}))
	# Saves from before transport and districts have neither entry.
	if not district_system_path.is_empty():
		get_node(district_system_path).load_state(state.get("districts", {}))
	if not transit_system_path.is_empty():
		get_node(transit_system_path).load_state(state.get("transit", {}))
	# Saves from before milestones start at the one their population reached.
	ProgressionSystem.load_state(state.get("progression", {}), int(get_node(citizen_system_path).population))
	WeatherSystem.load_state(state.get("weather", {}))
	var veg: Node = get_parent().get_node_or_null("Vegetation")
	if veg != null:
		veg.load_state(state.get("vegetation", {}))
	_loading = false
	EventBus.notification_posted.emit("save", tr("NOTIFY_LOADED"))
	return true


## Loads a save into a fresh scene: the scene reloads and picks it up on start.
func request_load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(PENDING, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(path)
	f.close()
	_loading = true
	get_tree().reload_current_scene()
	return true


## Autosave and slots for the UI: [{key, path, exists, meta}].
func list_saves() -> Array:
	var out := [{"key": "auto", "path": AUTOSAVE}]
	for s in range(1, SLOT_COUNT + 1):
		out.append({"key": "slot", "slot": s, "path": slot_path(s)})
	for entry: Dictionary in out:
		var path: String = entry["path"]
		entry["exists"] = FileAccess.file_exists(path)
		entry["meta"] = {}
		if entry["exists"] and FileAccess.file_exists(meta_path(path)):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path(path)))
			if typeof(parsed) == TYPE_DICTIONARY:
				entry["meta"] = parsed
	return out


func _load_on_start() -> void:
	if FileAccess.file_exists(PENDING):
		var path := FileAccess.get_file_as_string(PENDING).strip_edges()
		DirAccess.remove_absolute(PENDING)
		if load_game(path):
			# The loaded city carries on as the autosave.
			save_game.call_deferred()
			return
	load_game()


## Wipes the autosave and restarts with an empty map (slots are kept).
func new_city() -> void:
	for path in [AUTOSAVE, meta_path(AUTOSAVE)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_loading = true
	TimeSystem.reset_state()
	EconomySystem.reset_state()
	ProgressionSystem.reset_state()
	WeatherSystem.reset_state()
	get_tree().reload_current_scene()

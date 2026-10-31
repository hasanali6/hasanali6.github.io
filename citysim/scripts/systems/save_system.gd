extends Node
## Saves and restores the whole city. Autosaves every few game months and
## whenever the app is sent to the background or closed (Android may kill a
## backgrounded game). The file is a versioned binary Variant dictionary in
## user://saves/. On start the autosave is loaded if it exists.

const SAVE_DIR := "user://saves/"
const AUTOSAVE := "user://saves/autosave.save"

@export var road_network_path: NodePath
@export var zone_system_path: NodePath
@export var building_system_path: NodePath
@export var company_system_path: NodePath
@export var citizen_system_path: NodePath
@export var demand_system_path: NodePath

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


func save_game(path: String = AUTOSAVE) -> bool:
	if _loading:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var state := {
		"version": GameData.integer("game/save_version"),
		"saved_unix": Time.get_unix_time_from_system(),
		"time": TimeSystem.save_state(),
		"economy": EconomySystem.save_state(),
		"roads": get_node(road_network_path).save_state(),
		"zones": get_node(zone_system_path).save_state(),
		"buildings": get_node(building_system_path).save_state(),
		"companies": get_node(company_system_path).save_state(),
		"citizens": get_node(citizen_system_path).save_state(),
		"demand": get_node(demand_system_path).save_state(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s" % path)
		return false
	file.store_var(state)
	_months_since_save = 0
	EventBus.notification_posted.emit("save", tr("NOTIFY_SAVED"))
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
	_loading = false
	EventBus.notification_posted.emit("save", tr("NOTIFY_LOADED"))
	return true


func _load_on_start() -> void:
	load_game()


## Wipes the autosave and restarts with an empty map.
func new_city() -> void:
	if FileAccess.file_exists(AUTOSAVE):
		DirAccess.remove_absolute(AUTOSAVE)
	_loading = true
	TimeSystem.reset_state()
	EconomySystem.reset_state()
	get_tree().reload_current_scene()

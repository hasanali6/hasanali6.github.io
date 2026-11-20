class_name SaveSystem
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
## A save brought in from another device (Kayitlar -> Ice aktar); it is
## listed with the slots and only replaces the city when loaded on purpose.
const IMPORTED := "user://saves/imported.save"
## Folder (inside Documents) where exported cities go.
const EXPORT_FOLDER := "SehirSim"

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
	var life: Node = get_parent().get_node_or_null("CityLifeSystem")
	if life != null:
		state["life"] = life.save_state()
	# Write to a temporary file first and keep the previous save as .bak: a
	# crash or a full disk in the middle of writing never costs the city.
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s" % tmp)
		return false
	file.store_var(state)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.copy_absolute(tmp, path)
		DirAccess.remove_absolute(tmp)
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


## Reads a save file brought up to the current version ({} if unusable).
static func read_state(path: String) -> Dictionary:
	return SaveFormat.read_state(path, GameData.integer("game/save_version"))


func load_game(path: String = AUTOSAVE) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var state := read_state(path)
	if state.is_empty() and FileAccess.file_exists(path + ".bak"):
		push_warning("SaveSystem: %s unreadable, using the backup" % path)
		state = read_state(path + ".bak")
	if state.is_empty():
		# Never let the next autosave overwrite a city we could not read:
		# move it aside so it can still be recovered.
		var keep := path.get_basename() + "_okunamadi_%d.save" % int(Time.get_unix_time_from_system())
		DirAccess.rename_absolute(path, keep)
		push_warning("SaveSystem: unreadable save kept as %s" % keep)
		EventBus.notification_posted.emit("save", tr("NOTIFY_SAVE_UNREADABLE"))
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
	var life: Node = get_parent().get_node_or_null("CityLifeSystem")
	if life != null:
		life.load_state(state.get("life", {}))
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
	if FileAccess.file_exists(IMPORTED):
		out.append({"key": "imported", "path": IMPORTED})
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


# --- Moving a city between devices --------------------------------------------------

## Folder exported cities go to: Documents/SehirSim (on Android the shared
## Documents folder, reachable from any file manager).
static func export_dir() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs == "":
		docs = OS.get_user_data_dir()
	return docs.path_join(EXPORT_FOLDER)


## Saves the city now and copies it to export_dir() as
## sehir_YYYY-MM-DD_HH-MM.save. Returns the file's path, or "" on failure.
func export_city() -> String:
	if not save_game():
		return ""
	var dir := export_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_").left(16)
	var target := dir.path_join("sehir_%s.save" % stamp)
	var bytes := FileAccess.get_file_as_bytes(AUTOSAVE)
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null or bytes.is_empty():
		push_warning("SaveSystem: cannot export to %s (%s)" % [target, error_string(FileAccess.get_open_error())])
		return ""
	f.store_buffer(bytes)
	f.close()
	return target


## Copies a city file from another device into the "imported" entry of the
## save list (the current city is not touched until it is loaded). Returns
## "" when it worked, else a translation key saying why not.
func import_city(source: String) -> String:
	var state := read_state(source)
	if state.is_empty():
		return "SAVES_IMPORT_BAD"
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var bytes := FileAccess.get_file_as_bytes(source)
	var f := FileAccess.open(IMPORTED, FileAccess.WRITE)
	if f == null:
		return "SAVES_IMPORT_FAILED"
	f.store_buffer(bytes)
	f.close()
	var econ: Dictionary = state.get("economy", {})
	var people := 0
	var cit: Dictionary = state.get("citizens", {})
	if cit.has("alive"):
		var alive: PackedByteArray = cit["alive"]
		for i in alive.size():
			if alive[i] != 0:
				people += int(cit["adults"][i]) + int(cit["children"][i]) + int(cit["seniors"][i])
	var meta := {
		"saved_unix": int(state.get("saved_unix", Time.get_unix_time_from_system())),
		"population": people,
		"balance": int(econ.get("balance", 0)),
		"level": int((state.get("progression", {}) as Dictionary).get("level", 0)),
	}
	var mf := FileAccess.open(meta_path(IMPORTED), FileAccess.WRITE)
	if mf != null:
		mf.store_string(JSON.stringify(meta))
	EventBus.saves_changed.emit()
	return ""


## City files found where a transfer usually lands (exports, Downloads),
## newest first: [{path, name, unix}].
static func importable_files() -> Array:
	var out := []
	var seen := {}
	for dir: String in [export_dir(), OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]:
		if dir == "" or not DirAccess.dir_exists_absolute(dir):
			continue
		for name in DirAccess.get_files_at(dir):
			if not name.ends_with(".save"):
				continue
			var path := dir.path_join(name)
			if seen.has(path):
				continue
			seen[path] = true
			out.append({"path": path, "name": name, "unix": int(FileAccess.get_modified_time(path))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["unix"]) > int(b["unix"]))
	return out

class_name SaveFormat
extends RefCounted
## Reading city save files and bringing old ones up to date. Kept free of
## autoloads so the unit tests can use it (SaveSystem passes the version).

## Reads a save file into a state dictionary brought up to the current
## version, or {} when it is not a city save (or comes from a newer game).
static func read_state(path: String, current: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return {}
	var state: Variant = file.get_var()
	file.close()
	if typeof(state) != TYPE_DICTIONARY or not (state as Dictionary).has("roads") or not (state as Dictionary).has("time"):
		return {}
	return migrate(state, current)


## Brings an older save up to the current version one step at a time (every
## format change adds a step here instead of making old cities unreadable).
## A save from a newer version of the game is refused, never changed.
static func migrate(state: Dictionary, current: int) -> Dictionary:
	var version := int(state.get("version", 1))
	if version > current:
		push_warning("SaveSystem: save from a newer game version (%d > %d)" % [version, current])
		return {}
	while version < current:
		match version:
			_:
				pass   # no format changes yet; later steps go here
		version += 1
	state["version"] = current
	return state

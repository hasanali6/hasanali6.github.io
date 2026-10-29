class_name DataLoader
extends RefCounted
## Loads balancing/config JSON files from res://data. Pure static helpers so
## headless tests can use them without the GameData autoload.

const DATA_DIR := "res://data/"


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DataLoader: missing file '%s'" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataLoader: '%s' is not a JSON object" % path)
		return {}
	return parsed


## Loads every named file (without extension) into one dictionary keyed by name.
static func load_files(names: PackedStringArray, dir_path: String = DATA_DIR) -> Dictionary:
	var db := {}
	for file_name in names:
		db[file_name] = load_json(dir_path + file_name + ".json")
	return db


## Resolves a slash separated path such as "camera/fov_deg".
static func lookup(db: Dictionary, path: String) -> Variant:
	var node: Variant = db
	for part in path.split("/"):
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		else:
			push_error("DataLoader: missing key '%s'" % path)
			return null
	return node


static func has_path(db: Dictionary, path: String) -> bool:
	var node: Variant = db
	for part in path.split("/"):
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		else:
			return false
	return true


static func to_color(value: Variant) -> Color:
	if value is String:
		return Color.html(value)
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	push_error("DataLoader: cannot convert %s to Color" % str(value))
	return Color.MAGENTA


static func to_vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	push_error("DataLoader: cannot convert %s to Vector3" % str(value))
	return Vector3.ZERO

extends Node
## Shared read-only data service. Every tunable number lives in res://data/*.json
## and is read through here; code never hard-codes balancing values.

const FILES: PackedStringArray = [
	"game", "time", "input", "camera", "map", "environment", "graphics", "reference_scene",
	"roads", "economy", "zones", "catalog", "vegetation", "services", "traffic", "transit", "districts",
	"progression", "weather", "audio",
]

var _db: Dictionary = {}


func _init() -> void:
	_db = DataLoader.load_files(FILES)


func _ready() -> void:
	TranslationServer.set_locale(str(value("game/locale")))


func value(path: String) -> Variant:
	return DataLoader.lookup(_db, path)


func has(path: String) -> bool:
	return DataLoader.has_path(_db, path)


func num(path: String) -> float:
	return float(value(path))


func integer(path: String) -> int:
	return int(value(path))


func flag(path: String) -> bool:
	return bool(value(path))


func color(path: String) -> Color:
	return DataLoader.to_color(value(path))


func vec3(path: String) -> Vector3:
	return DataLoader.to_vector3(value(path))


func section(path: String) -> Dictionary:
	var v: Variant = value(path)
	return v if v is Dictionary else {}

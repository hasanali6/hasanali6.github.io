class_name ResourceMap
extends RefCounted
## Natural resources of the map (data/resources.json): fertile soil, forest,
## ore and oil as smooth noise fields. richness() is 0..1 (0 = none, below
## the "low" threshold), none on water. Pure and deterministic, so the same
## seed always gives the same map and it can be tested headless.

var _fields: Dictionary = {}      # field -> [FastNoiseLite, low, high]

static var _shared: ResourceMap


static func shared() -> ResourceMap:
	if _shared == null:
		var data: Node = (Engine.get_main_loop() as SceneTree).root.get_node("GameData")
		_shared = ResourceMap.new(data.call("section", "resources/fields"))
	return _shared


func _init(fields: Dictionary) -> void:
	for key: String in fields:
		var f: Dictionary = fields[key]
		var n := FastNoiseLite.new()
		n.seed = int(f["seed"])
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = float(f["frequency"])
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		_fields[key] = [n, float(f["low"]), float(f["high"])]


## 0..1 richness of a field at a map point.
func richness(field: String, p: Vector2) -> float:
	if not _fields.has(field):
		return 0.0
	var entry: Array = _fields[field]
	var v := ((entry[0] as FastNoiseLite).get_noise_2d(p.x, p.y) + 1.0) * 0.5
	return smoothstep(float(entry[1]), float(entry[2]), v)


## Average richness over a lot (centre and four corners).
func lot_richness(field: String, centre: Vector2, w: float, d: float) -> float:
	var sum := richness(field, centre)
	for k in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)]:
		sum += richness(field, centre + Vector2(k.x * w, k.y * d))
	return sum / 5.0

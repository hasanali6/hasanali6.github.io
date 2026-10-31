class_name MapWater
extends RefCounted
## Rivers and lakes of the map (data/map.json "water"). The river is a
## polyline smoothed with Catmull-Rom; lakes are ellipses. Provides a signed
## distance (negative inside water) used by roads, zoning, trees and service
## placement. The same maths runs in water_common.gdshaderinc for the visuals.

const MAX_SHADER_POINTS := 96
const MAX_LAKES := 4
const COARSE_SKIP_M := 160.0  # beyond this the coarse river distance is good enough

var river := PackedVector2Array()
var river_half: float
var lakes: Array[Vector4] = []   # centre x, centre z, radius x, radius z
var bank_width: float

static var _shared: MapWater


## The map's water, built from GameData on first use. Looked up at runtime so
## this class still compiles in headless tests that have no autoloads.
static func shared() -> MapWater:
	if _shared == null:
		var data: Node = (Engine.get_main_loop() as SceneTree).root.get_node("GameData")
		_shared = MapWater.new(data.call("section", "map/water"))
	return _shared


func _init(cfg: Dictionary) -> void:
	river_half = float(cfg["river_width_m"]) * 0.5
	bank_width = float(cfg["bank_width_m"])
	var ctrl := PackedVector2Array()
	for p: Array in cfg["river_points"]:
		ctrl.append(Vector2(float(p[0]), float(p[1])))
	river = _catmull_rom(ctrl, int(cfg["river_subdivisions"]))
	for l: Array in cfg["lakes"]:
		if lakes.size() < MAX_LAKES:
			lakes.append(Vector4(float(l[0]), float(l[1]), float(l[2]), float(l[3])))


static func _catmull_rom(ctrl: PackedVector2Array, subdiv: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ctrl.size() < 2:
		return ctrl
	for i in ctrl.size() - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
		for s in subdiv:
			var t := float(s) / subdiv
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[ctrl.size() - 1])
	return out


## Signed distance to the nearest water edge (negative = in the water).
## A coarse pass over every 4th river point skips the fine pass when far away.
func distance(p: Vector2) -> float:
	var d := INF
	var last := river.size() - 1
	for i in range(0, last, 4):
		d = minf(d, _segment_distance(p, river[i], river[mini(i + 4, last)]))
	if d - river_half < COARSE_SKIP_M:
		d = INF
		for i in last:
			d = minf(d, _segment_distance(p, river[i], river[i + 1]))
	d -= river_half
	for l in lakes:
		var rel := Vector2((p.x - l.x) / l.z, (p.y - l.y) / l.w)
		d = minf(d, (rel.length() - 1.0) * minf(l.z, l.w))
	return d


func is_water(p: Vector2, margin: float = 0.0) -> bool:
	return distance(p) < margin


## Metres of the quadratic curve (a, c, b) that run over water.
func curve_water_length(a: Vector2, c: Vector2, b: Vector2) -> float:
	var n := RoadGraph.sample_count(a, c, b, 4.0)
	var wet := 0
	for i in n + 1:
		if distance(RoadGraph.bezier(a, c, b, float(i) / n)) < 0.0:
			wet += 1
	return RoadGraph.curve_length(a, c, b, 4.0) * float(wet) / float(n + 1)


## True if the quadratic curve (a, c, b) passes within `margin` of water.
func curve_hits_water(a: Vector2, c: Vector2, b: Vector2, margin: float, step: float) -> bool:
	var n := RoadGraph.sample_count(a, c, b, step)
	for i in n + 1:
		if distance(RoadGraph.bezier(a, c, b, float(i) / n)) < margin:
			return true
	return false


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Uniform values for the shaders (water_common.gdshaderinc).
func apply_to_material(mat: ShaderMaterial) -> void:
	var pts := PackedVector2Array()
	var stride := maxi(ceili(float(river.size()) / MAX_SHADER_POINTS), 1)
	for i in range(0, river.size(), stride):
		pts.append(river[i])
	if pts[pts.size() - 1] != river[river.size() - 1] and pts.size() < MAX_SHADER_POINTS:
		pts.append(river[river.size() - 1])
	var count := pts.size()
	while pts.size() < MAX_SHADER_POINTS:
		pts.append(Vector2.ZERO)
	var lake_arr: Array[Vector4] = []
	for l in lakes:
		lake_arr.append(l)
	while lake_arr.size() < MAX_LAKES:
		lake_arr.append(Vector4(0, 0, 1, 1))
	mat.set_shader_parameter("river_points", pts)
	mat.set_shader_parameter("river_count", count)
	mat.set_shader_parameter("river_half", river_half)
	mat.set_shader_parameter("lakes", lake_arr)
	mat.set_shader_parameter("lake_count", lakes.size())

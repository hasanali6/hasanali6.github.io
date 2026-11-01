class_name LeisureModels
extends RefCounted
## Procedural models of the leisure catalogue (data/catalog.json "leisure"):
## parks (playground, statue park, football pitch, botanical garden, zoo,
## amusement park) and the sea front (beach, pier, lighthouse, marina, beach
## café, seafront hotel). Same lot coordinates as ServiceModels: u across the
## lot, v towards the street (+depth/2), heights in metres. Piers and marina
## docks run from the lot out over the nearest water.

## Lot ground per style (lot_ground.gdshader kinds; 9 = sand).
const LOT_KINDS := {
	"park_playground": 8, "park_statue": 1, "park_sports": 4, "park_garden": 0, "park_zoo": 8,
	"park_amusement": 1, "park_beach": 9, "park_pier": 1, "park_lighthouse": 7, "park_marina": 3,
	"beach_cafe": 1, "sea_hotel": 1,
}

const WHITE := Color(0.94, 0.95, 0.96)
const WOOD := Color(0.55, 0.38, 0.22)
const DECK := Color(0.66, 0.5, 0.33)
const STONE := Color(0.72, 0.71, 0.68)
const BRONZE := Color(0.45, 0.33, 0.18)
const STEEL := Color(0.55, 0.58, 0.62)
const GLASS := Color(0.62, 0.82, 0.88)
const LEAF: Array[Color] = [Color(0.27, 0.55, 0.22), Color(0.33, 0.6, 0.25), Color(0.22, 0.47, 0.2), Color(0.4, 0.62, 0.28)]
const FUN: Array[Color] = [Color(0.92, 0.25, 0.22), Color(0.98, 0.75, 0.15), Color(0.2, 0.55, 0.92), Color(0.3, 0.75, 0.35), Color(0.75, 0.35, 0.85), Color(0.98, 0.5, 0.15)]


static func has_style(style: String) -> bool:
	return LOT_KINDS.has(style)


static func lot_kind(style: String) -> int:
	return int(LOT_KINDS.get(style, 8))


## Extra meshes: crown (sphere), cone and ring (torus, lying flat).
static func build_meshes(add: Callable) -> void:
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.roughness = 0.85
	var crown := SphereMesh.new()
	crown.radius = 0.5
	crown.height = 1.0
	crown.radial_segments = 10
	crown.rings = 6
	crown.material = plain
	add.call("crown", crown, true, false)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 1
	cone.material = plain
	add.call("cone", cone, true, false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.47
	ring.outer_radius = 0.5
	ring.rings = 40
	ring.ring_segments = 6
	ring.material = plain
	add.call("ring", ring, true, false)


# --- Helpers ----------------------------------------------------------------------------

static func _put(out: Array[Dictionary], ctx: Dictionary, key: String, u: float, v: float,
		w: float, h: float, d: float, color: Color, y0: float = 0.0, custom: Color = Color()) -> void:
	ServiceModels._put(out, ctx, key, u, v, w, h, d, color, y0, custom)


## A piece with free axes (world vectors, already scaled) centred at height y.
static func _free(out: Array[Dictionary], ctx: Dictionary, key: String, p: Vector2, y: float,
		x: Vector3, up: Vector3, z: Vector3, color: Color) -> void:
	var e: float = ctx["e"]
	out.append({"key": key, "xf": Transform3D(Basis(x, up * e, z), Vector3(p.x, y * e, p.y)), "color": color, "custom": Color()})


static func _tree(out: Array[Dictionary], ctx: Dictionary, u: float, v: float, size: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	_put(out, ctx, "chimney", u, v, 0.35 * size, 2.2 * size, 0.35 * size, WOOD)
	_put(out, ctx, "crown", u, v, 3.4 * size, 3.6 * size, 3.4 * size, LEAF[rng.randi_range(0, LEAF.size() - 1)], 1.8 * size)


static func _bench(out: Array[Dictionary], ctx: Dictionary, u: float, v: float) -> void:
	_put(out, ctx, "roof_box", u, v, 1.8, 0.1, 0.5, WOOD, 0.45)
	_put(out, ctx, "roof_box", u, v - 0.25, 1.8, 0.45, 0.08, WOOD, 0.5)


static func _lamp(out: Array[Dictionary], ctx: Dictionary, u: float, v: float) -> void:
	_put(out, ctx, "chimney", u, v, 0.14, 4.0, 0.14, Color(0.25, 0.27, 0.3))
	_put(out, ctx, "crown", u, v, 0.5, 0.5, 0.5, Color(1.0, 0.95, 0.8), 4.0)


static func _umbrella(out: Array[Dictionary], ctx: Dictionary, u: float, v: float, color: Color, r: float = 1.4) -> void:
	_put(out, ctx, "chimney", u, v, 0.08, 2.3, 0.08, WHITE)
	_put(out, ctx, "cone", u, v, r * 2.0, 0.6, r * 2.0, color, 2.0)


static func _fence(out: Array[Dictionary], ctx: Dictionary, u0: float, v0: float, u1: float, v1: float, h: float, color: Color) -> void:
	var a := ServiceModels._pos(ctx, u0, v0)
	var b := ServiceModels._pos(ctx, u1, v1)
	var along := b - a
	var length := along.length()
	if length < 0.1:
		return
	var dir := Vector3(along.x, 0, along.y) / length
	var side := Vector3.UP.cross(dir)
	_free(out, ctx, "roof_box", (a + b) * 0.5, h * 0.5, side * 0.12, Vector3.UP * h, dir * length, color)


## A simple figure (statue or person) facing the street, bottom at y0.
static func _figure(out: Array[Dictionary], ctx: Dictionary, u: float, v: float, y0: float, s: float, color: Color) -> void:
	for side in [-1.0, 1.0]:
		_put(out, ctx, "roof_box", u + side * 0.18 * s, v, 0.22 * s, 0.9 * s, 0.25 * s, color, y0)
	_put(out, ctx, "roof_box", u, v, 0.62 * s, 0.75 * s, 0.32 * s, color, y0 + 0.9 * s)
	_put(out, ctx, "roof_box", u + 0.4 * s, v, 0.16 * s, 0.85 * s, 0.16 * s, color, y0 + 1.45 * s)   # raised arm
	_put(out, ctx, "roof_box", u - 0.38 * s, v, 0.15 * s, 0.6 * s, 0.15 * s, color, y0 + 1.05 * s)
	_put(out, ctx, "crown", u, v, 0.34 * s, 0.38 * s, 0.34 * s, color, y0 + 1.65 * s)


## A wooden deck from the lot out over the nearest water (piers, marina docks).
## Returns [start point, direction, length] or [] when no water is near.
static func _deck_out(out: Array[Dictionary], ctx: Dictionary, extra: float, width: float) -> Array:
	var c: Vector2 = ctx["centre"]
	var hit := ServiceModels._towards_water(c)
	var dir: Vector2 = hit[0]
	if dir == Vector2.ZERO or float(hit[1]) > 120.0:
		return []
	var length := float(hit[1]) + extra
	var dir3 := Vector3(dir.x, 0, dir.y)
	var side := Vector3.UP.cross(dir3)
	_free(out, ctx, "roof_box", c + dir * length * 0.5, 1.3, side * width, Vector3.UP * 0.25, dir3 * length, DECK)
	var k := 4.0
	while k < length:
		for sgn in [-0.45, 0.45]:
			var q: Vector2 = c + dir * k + Vector2(side.x, side.z) * width * sgn
			_free(out, ctx, "chimney", q, 0.6, Vector3.RIGHT * 0.35, Vector3.UP * 1.4, Vector3.BACK * 0.35, WOOD.darkened(0.3))
			_free(out, ctx, "roof_box", q, 1.85, side * 0.08, Vector3.UP * 0.9, dir3 * 6.0, WHITE)
		k += 6.0
	return [c, dir, length]


# --- Styles -------------------------------------------------------------------------------

static func parts(b: Dictionary, ctx: Dictionary, out: Array[Dictionary]) -> void:
	var s := float(b["seed"])
	var rng: RandomNumberGenerator = ctx["rng"]
	var w: float = ctx["lot_w"]
	var d: float = ctx["lot_d"]
	match str(b["style"]):
		"park_playground":
			_put(out, ctx, "roof_box", -3.5, -3.0, 5.0, 0.25, 5.0, Color(0.86, 0.78, 0.58))   # sandpit
			_put(out, ctx, "roof_box", 3.0, -3.5, 2.0, 2.4, 2.0, FUN[0])                         # slide tower
			_put(out, ctx, "cone", 3.0, -3.5, 2.6, 1.4, 2.6, FUN[2], 2.4)
			var pa := ServiceModels._pos(ctx, 3.0, -1.2)
			var fz: Vector3 = ctx["fz"]
			var dx: Vector3 = ctx["dx"]
			_free(out, ctx, "roof_box", pa, 1.2, dx * 0.9, (Vector3.UP * 2.3 + fz * 3.0).normalized() * 0.12, (fz * 3.0 - Vector3.UP * 2.3).normalized() * 3.8, FUN[1])
			for u in [-5.0, -1.5]:                                                              # swing frame
				_put(out, ctx, "roof_box", u, 3.5, 0.15, 2.6, 0.15, STEEL)
			_put(out, ctx, "roof_box", -3.25, 3.5, 3.7, 0.15, 0.15, STEEL, 2.6)
			for u in [-4.2, -2.3]:
				_put(out, ctx, "roof_box", u, 3.5, 0.5, 0.08, 0.35, FUN[3], 0.6)
			_bench(out, ctx, 4.5, 5.5)
			_tree(out, ctx, -6.0, -6.0, 1.0)
			_tree(out, ctx, 6.0, 6.0, 0.9)
		"park_statue":
			_put(out, ctx, "roof_box", 0, 0, 3.4, 1.6, 3.4, STONE)
			_put(out, ctx, "roof_box", 0, 0, 2.6, 0.3, 2.6, STONE.darkened(0.1), 1.6)
			_figure(out, ctx, 0, 0, 1.9, 2.0, BRONZE)
			for k in 4:
				var a := TAU * (k + 0.5) / 4.0
				_tree(out, ctx, cos(a) * 5.6, sin(a) * 5.6, 0.9)
				_put(out, ctx, "roof_box", cos(a + PI / 4.0) * 4.6, sin(a + PI / 4.0) * 4.6, 1.6, 0.35, 1.6, FUN[k % FUN.size()].lightened(0.2))
			_bench(out, ctx, -2.5, 5.2)
			_bench(out, ctx, 2.5, 5.2)
			_lamp(out, ctx, 0, 6.5)
		"park_sports":
			var pv := -0.21 * d
			var half_u := w * 0.5 - 1.6
			for sgn in [-1.0, 1.0]:
				var gu: float = sgn * half_u
				for off in [-2.4, 2.4]:
					_put(out, ctx, "roof_box", gu, pv + off, 0.15, 2.4, 0.15, WHITE)
				_put(out, ctx, "roof_box", gu, pv, 0.15, 0.15, 4.95, WHITE, 2.35)
				_put(out, ctx, "chimney", sgn * (w * 0.5 - 0.6), -d * 0.5 + 1.0, 0.3, 14.0, 0.3, STEEL)
				_put(out, ctx, "roof_box", sgn * (w * 0.5 - 0.6), -d * 0.5 + 1.0, 2.2, 1.0, 0.4, Color(0.95, 0.95, 0.85), 14.0)
			for k in 3:                                                                          # small stand
				_put(out, ctx, "roof_box", 0, d * 0.5 - 8.5 - k * 0.9, w * 0.55, 0.6 + k * 0.6, 0.9, FUN[2].darkened(0.1 * k))
			_put(out, ctx, "roof_box", 0, d * 0.5 - 9.4, w * 0.6, 0.12, 3.2, WHITE, 3.6)
		"park_garden":
			_put(out, ctx, "dome", 0, -d * 0.18, 15.0, 9.0, 15.0, GLASS)
			_put(out, ctx, "roof_box", 0, -d * 0.18 + 7.6, 3.0, 2.6, 1.0, WHITE)
			_put(out, ctx, "basin", -w * 0.28, d * 0.2, 7.0, 0.2, 5.0, Color(0.3, 0.6, 0.7), 0.05)
			for k in 6:
				var bu := w * 0.12 + (k % 2) * 4.5
				var bv := d * 0.06 + int(k / 2) * 3.5
				_put(out, ctx, "roof_box", bu, bv, 3.6, 0.45, 2.0, FUN[k % FUN.size()].lightened(0.15))
			for k in 6:
				var a := TAU * k / 6.0 + s
				_tree(out, ctx, cos(a) * w * 0.4, sin(a) * d * 0.4, 0.8 + rng.randf() * 0.4)
			_bench(out, ctx, -3.0, d * 0.42)
		"park_zoo":
			var hw := w * 0.5 - 0.6
			var hd := d * 0.5 - 0.6
			_fence(out, ctx, -hw, -hd, hw, -hd, 2.0, Color(0.35, 0.3, 0.22))
			_fence(out, ctx, -hw, -hd, -hw, hd, 2.0, Color(0.35, 0.3, 0.22))
			_fence(out, ctx, hw, -hd, hw, hd, 2.0, Color(0.35, 0.3, 0.22))
			_fence(out, ctx, -hw, hd, -3.0, hd, 2.0, Color(0.35, 0.3, 0.22))
			_fence(out, ctx, 3.0, hd, hw, hd, 2.0, Color(0.35, 0.3, 0.22))
			for sgn in [-1.0, 1.0]:                                                              # entrance gate
				_put(out, ctx, "roof_box", sgn * 3.4, hd, 1.2, 5.0, 1.2, STONE)
			_put(out, ctx, "roof_box", 0, hd, 8.0, 1.4, 1.0, Color(0.2, 0.5, 0.25), 5.0)
			# Four enclosures with low fences, a pond and animals.
			for q in 4:
				var cu := (-1.0 if q % 2 == 0 else 1.0) * w * 0.25
				var cv := (-1.0 if q < 2 else 1.0) * d * 0.22 - 2.0
				var hu := w * 0.2
				var hv := d * 0.17
				_fence(out, ctx, cu - hu, cv - hv, cu + hu, cv - hv, 1.1, WOOD)
				_fence(out, ctx, cu - hu, cv + hv, cu + hu, cv + hv, 1.1, WOOD)
				_fence(out, ctx, cu - hu, cv - hv, cu - hu, cv + hv, 1.1, WOOD)
				_fence(out, ctx, cu + hu, cv - hv, cu + hu, cv + hv, 1.1, WOOD)
				_tree(out, ctx, cu - hu * 0.6, cv - hv * 0.6, 1.0)
				match q:
					0:   # elephants
						for k in 2:
							var eu := cu + (k - 0.5) * 4.0
							_put(out, ctx, "roof_box", eu, cv, 1.6, 1.9, 3.2, Color(0.5, 0.5, 0.52), 1.0)
							_put(out, ctx, "roof_box", eu, cv + 1.9, 1.3, 1.3, 1.0, Color(0.5, 0.5, 0.52), 1.9)
							_put(out, ctx, "roof_box", eu, cv + 2.5, 0.35, 1.6, 0.35, Color(0.48, 0.48, 0.5), 0.8)
							for lu in [-0.5, 0.5]:
								for lv in [-1.1, 1.1]:
									_put(out, ctx, "roof_box", eu + lu, cv + lv, 0.45, 1.0, 0.45, Color(0.46, 0.46, 0.48))
						_put(out, ctx, "basin", cu + hu * 0.4, cv + hv * 0.4, 5.0, 0.2, 4.0, Color(0.3, 0.55, 0.65), 0.05)
					1:   # giraffes
						for k in 2:
							var gu := cu + (k - 0.5) * 4.5
							var tone := Color(0.85, 0.65, 0.3)
							_put(out, ctx, "roof_box", gu, cv, 1.0, 1.0, 2.2, tone, 1.8)
							_put(out, ctx, "roof_box", gu, cv + 1.0, 0.35, 2.6, 0.35, tone, 2.6)
							_put(out, ctx, "roof_box", gu, cv + 1.3, 0.4, 0.4, 0.8, tone.darkened(0.2), 5.1)
							for lu in [-0.35, 0.35]:
								for lv in [-0.8, 0.8]:
									_put(out, ctx, "roof_box", gu + lu, cv + lv, 0.18, 1.8, 0.18, tone.darkened(0.15))
					2:   # lions on rocks
						_put(out, ctx, "mound", cu, cv, 7.0, 2.5, 6.0, Color(0.55, 0.5, 0.45))
						for k in 2:
							var lu2 := cu + (k - 0.5) * 3.0
							_put(out, ctx, "roof_box", lu2, cv + 3.6, 0.9, 0.8, 1.8, Color(0.8, 0.62, 0.32), 0.4)
							_put(out, ctx, "crown", lu2, cv + 4.5, 1.0, 1.0, 1.0, Color(0.6, 0.4, 0.2), 0.8)
					_:   # zebras
						for k in 3:
							var zu := cu + (k - 1.0) * 3.0
							_put(out, ctx, "roof_box", zu, cv, 0.7, 0.8, 1.6, WHITE, 0.9)
							_put(out, ctx, "roof_box", zu, cv, 0.72, 0.15, 1.62, Color(0.1, 0.1, 0.1), 1.35)
							_put(out, ctx, "roof_box", zu, cv + 1.0, 0.35, 0.8, 0.35, WHITE, 1.4)
			_lamp(out, ctx, -4.5, hd - 4.0)
			_lamp(out, ctx, 4.5, hd - 4.0)
		"park_amusement":
			# Ferris wheel at the back, standing across the lot.
			var wc := ServiceModels._pos(ctx, -w * 0.18, -d * 0.22)
			var radius := 13.0
			var hub_y := radius + 2.5
			var dx2: Vector3 = ctx["dx"]
			var fz2: Vector3 = ctx["fz"]
			_free(out, ctx, "ring", wc, hub_y, dx2 * radius * 2.0, fz2 * 0.6, Vector3.DOWN * radius * 2.0, STEEL.lightened(0.2))
			for k in 8:
				var a := TAU * k / 8.0
				var spoke := Vector3(0, sin(a), 0) * radius + dx2 * cos(a) * radius
				var mid := wc + Vector2(dx2.x, dx2.z) * cos(a) * radius * 0.5
				_free(out, ctx, "roof_box", mid, hub_y + sin(a) * radius * 0.5, spoke.normalized().cross(fz2).normalized() * 0.18,
					spoke * 1.0, fz2 * 0.18, STEEL)
				var cab := wc + Vector2(dx2.x, dx2.z) * cos(a) * radius
				_free(out, ctx, "roof_box", cab, hub_y + sin(a) * radius - 1.0, dx2 * 1.6, Vector3.UP * 1.6, fz2 * 1.6, FUN[k % FUN.size()])
			for sgn in [-1.0, 1.0]:
				for side in [-1.0, 1.0]:
					var foot: Vector2 = wc + Vector2(dx2.x, dx2.z) * side * 5.0 + Vector2(fz2.x, fz2.z) * sgn * 1.2
					var top: Vector2 = wc + Vector2(fz2.x, fz2.z) * sgn * 1.2
					var leg := Vector3(top.x - foot.x, hub_y, top.y - foot.y)
					_free(out, ctx, "roof_box", (foot + top) * 0.5, hub_y * 0.5, leg.cross(fz2).normalized() * 0.4, leg, fz2 * 0.4, WHITE)
			# Roller coaster: a looping track on stilts along the right side.
			var n := 28
			for k in n:
				var t0 := TAU * k / n
				var t1 := TAU * (k + 1) / n
				var cu := w * 0.22
				var cv := -d * 0.05
				var a0 := Vector2(cos(t0) * w * 0.2, sin(t0) * d * 0.32)
				var a1 := Vector2(cos(t1) * w * 0.2, sin(t1) * d * 0.32)
				var h0 := 3.0 + 6.0 * (0.5 + 0.5 * sin(t0 * 2.0))
				var h1 := 3.0 + 6.0 * (0.5 + 0.5 * sin(t1 * 2.0))
				var p0 := ServiceModels._pos(ctx, cu + a0.x, cv + a0.y)
				var p1 := ServiceModels._pos(ctx, cu + a1.x, cv + a1.y)
				var seg := Vector3(p1.x - p0.x, h1 - h0, p1.y - p0.y)
				var flat := Vector3(seg.x, 0, seg.z).normalized()
				_free(out, ctx, "roof_box", (p0 + p1) * 0.5, (h0 + h1) * 0.5, Vector3.UP.cross(flat) * 1.4, Vector3.UP * 0.3, seg, FUN[0])
				if k % 2 == 0:
					_free(out, ctx, "chimney", p0, h0 * 0.5, Vector3.RIGHT * 0.3, Vector3.UP * h0, Vector3.BACK * 0.3, WHITE)
			# Carousel and stalls along the street.
			_put(out, ctx, "tank", -w * 0.25, d * 0.28, 7.0, 0.6, 7.0, Color(0.85, 0.82, 0.75))
			for k in 6:
				var a := TAU * k / 6.0
				_put(out, ctx, "chimney", -w * 0.25 + cos(a) * 2.8, d * 0.28 + sin(a) * 2.8, 0.15, 3.0, 0.15, Color(0.95, 0.8, 0.3), 0.6)
			_put(out, ctx, "cone", -w * 0.25, d * 0.28, 8.0, 2.4, 8.0, FUN[0], 3.6)
			for k in 3:
				var su := w * 0.05 + k * 5.0
				_put(out, ctx, "roof_box", su, d * 0.4, 3.6, 2.4, 2.6, WHITE)
				_put(out, ctx, "roof_box", su, d * 0.4 + 0.4, 4.0, 0.25, 3.4, FUN[(k + 2) % FUN.size()], 2.4)
			_tree(out, ctx, -w * 0.42, d * 0.42, 0.9)
			_tree(out, ctx, w * 0.42, d * 0.42, 0.9)
		"park_beach":
			for k in 10:
				var bu := -w * 0.4 + (k % 5) * w * 0.2
				var bv := -d * 0.15 + int(k / 5) * d * 0.3
				_umbrella(out, ctx, bu, bv, FUN[(k + int(s)) % FUN.size()])
				_put(out, ctx, "roof_box", bu + 1.3, bv, 0.8, 0.3, 2.0, WHITE, 0.2)
			# Lifeguard tower.
			for lu in [-0.7, 0.7]:
				for lv in [-0.7, 0.7]:
					_put(out, ctx, "roof_box", w * 0.4 + lu, -d * 0.4 + lv, 0.15, 3.0, 0.15, WHITE)
			_put(out, ctx, "roof_box", w * 0.4, -d * 0.4, 2.2, 1.8, 2.2, Color(0.9, 0.2, 0.18), 3.0)
			_put(out, ctx, "roof_box", w * 0.4, -d * 0.4, 2.6, 0.15, 2.6, WHITE, 4.8)
			# Volleyball net.
			for nu in [-3.5, 3.5]:
				_put(out, ctx, "roof_box", nu, d * 0.38, 0.1, 2.4, 0.1, WHITE)
			_put(out, ctx, "roof_box", 0, d * 0.38, 7.0, 0.8, 0.04, Color(0.9, 0.9, 0.9), 1.6)
		"park_pier":
			_put(out, ctx, "roof_box", 0, d * 0.25, 4.5, 3.0, 3.5, Color(0.25, 0.55, 0.75))
			_put(out, ctx, "roof_box", 0, d * 0.25, 5.4, 0.25, 4.4, WHITE, 3.0)
			_lamp(out, ctx, -w * 0.35, d * 0.4)
			_lamp(out, ctx, w * 0.35, d * 0.4)
			var deck := _deck_out(out, ctx, 70.0, 4.5)
			if not deck.is_empty():
				var end: Vector2 = (deck[0] as Vector2) + (deck[1] as Vector2) * float(deck[2])
				var dir: Vector2 = deck[1]
				var dir3 := Vector3(dir.x, 0, dir.y)
				_free(out, ctx, "roof_box", end - dir * 4.0, 1.3, Vector3.UP.cross(dir3) * 10.0, Vector3.UP * 0.25, dir3 * 8.0, DECK)
				_free(out, ctx, "roof_box", end - dir * 4.0, 3.0, Vector3.UP.cross(dir3) * 3.0, Vector3.UP * 3.2, dir3 * 3.0, Color(0.95, 0.9, 0.8))
				_free(out, ctx, "cone", end - dir * 4.0, 5.4, Vector3.RIGHT * 4.5, Vector3.UP * 1.6, Vector3.BACK * 4.5, Color(0.85, 0.2, 0.18))
		"park_lighthouse":
			var stripes := 6
			for k in stripes:
				var r := 4.0 - k * 0.35
				var col := WHITE if k % 2 == 0 else Color(0.85, 0.15, 0.13)
				_put(out, ctx, "tank", 0, -2.0, r, 4.0, r, col, k * 4.0)
			_put(out, ctx, "tank", 0, -2.0, 2.4, 2.4, 2.4, GLASS.lightened(0.3), 24.0)
			_put(out, ctx, "tank", 0, -2.0, 3.4, 0.3, 3.4, Color(0.2, 0.22, 0.25), 24.0)
			_put(out, ctx, "cone", 0, -2.0, 3.0, 1.8, 3.0, Color(0.2, 0.22, 0.25), 26.4)
			out.append({"key": "beacon", "xf": Transform3D(Basis((ctx["dx"] as Vector3) * 2.5, Vector3.UP * float(ctx["e"]) * 2.5, (ctx["fz"] as Vector3) * 2.5),
				Vector3(ServiceModels._pos(ctx, 0, -2.0).x, 25.2 * float(ctx["e"]), ServiceModels._pos(ctx, 0, -2.0).y)), "color": Color.WHITE, "custom": Color(s * 0.137, 0, 0, 0)})
			_put(out, ctx, "house", 0, d * 0.28, 6.0, 3.2, 4.5, WHITE, 0, Color(s, 0.3, 3.0, 0.0))
			_put(out, ctx, "roof_box", 0, d * 0.28, 6.4, 0.6, 4.9, Color(0.5, 0.25, 0.2), 3.2)
		"park_marina":
			_put(out, ctx, "office", -w * 0.2, d * 0.2, 12.0, 6.0, 8.0, WHITE, 0, ServiceModels._facade(s, 0.55, 3.0))
			_put(out, ctx, "roof_box", -w * 0.2, d * 0.2, 13.0, 0.3, 9.0, Color(0.2, 0.45, 0.7), 6.0)
			_put(out, ctx, "chimney", w * 0.3, d * 0.3, 0.15, 9.0, 0.15, WHITE)
			_put(out, ctx, "roof_box", w * 0.3 + 0.8, d * 0.3, 1.6, 1.0, 0.05, Color(0.15, 0.35, 0.8), 7.8)
			var dock := _deck_out(out, ctx, 50.0, 3.0)
			if not dock.is_empty():
				var c0: Vector2 = dock[0]
				var dir: Vector2 = dock[1]
				var length := float(dock[2])
				var dir3 := Vector3(dir.x, 0, dir.y)
				var side := Vector3.UP.cross(dir3)
				var side2 := Vector2(side.x, side.z)
				var k := maxf(length - 48.0, 8.0)
				var boat := 0
				while k < length - 2.0:
					var base := c0 + dir * k
					for sgn in [-1.0, 1.0]:
						_free(out, ctx, "roof_box", base + side2 * sgn * 7.0, 1.2, side * 12.0, Vector3.UP * 0.22, dir3 * 1.6, DECK)
						var bp: Vector2 = base + side2 * sgn * 7.0 + dir * 3.0
						_free(out, ctx, "roof_box", bp, 0.6, side * 8.0, Vector3.UP * 1.1, dir3 * 2.6, WHITE)
						_free(out, ctx, "roof_box", bp - side2 * sgn * 1.0, 1.5, side * 3.0, Vector3.UP * 0.9, dir3 * 1.8, Color(0.25, 0.3, 0.4))
						if boat % 2 == 0:
							_free(out, ctx, "chimney", bp + side2 * sgn * 1.0, 5.5, Vector3.RIGHT * 0.12, Vector3.UP * 9.0, Vector3.BACK * 0.12, WHITE)
						boat += 1
					k += 9.0
		"beach_cafe":
			_put(out, ctx, "house", 0, -d * 0.12, w * 0.6, 3.6, d * 0.45, Color(0.97, 0.94, 0.85), 0, Color(s, 0.55, 2.5, 0.0))
			_put(out, ctx, "roof_box", 0, -d * 0.12 + 1.2, w * 0.7, 0.25, d * 0.6, Color(0.15, 0.55, 0.75), 3.6)
			for k in 4:
				var tu := -w * 0.3 + k * w * 0.2
				_put(out, ctx, "tank", tu, d * 0.3, 1.0, 0.75, 1.0, WHITE)
				_umbrella(out, ctx, tu, d * 0.3, FUN[(k + 1) % FUN.size()], 1.2)
		"sea_hotel":
			var floors := maxi(int(b["floors"]), 6)
			var h := 3.2 * floors
			_put(out, ctx, "tower", 0, -d * 0.1, w * 0.7, h, d * 0.45, Color(0.95, 0.93, 0.88), 0, ServiceModels._facade(s, 0.7, 3.2))
			for k in range(1, floors):
				_put(out, ctx, "roof_box", 0, -d * 0.1 + d * 0.235, w * 0.72, 0.15, 1.2, WHITE, k * 3.2)
			_put(out, ctx, "roof_box", 0, -d * 0.1, w * 0.6, 1.2, d * 0.3, Color(0.8, 0.8, 0.82), h)
			_put(out, ctx, "basin", -w * 0.2, d * 0.34, w * 0.4, 0.2, d * 0.18, Color(0.3, 0.7, 0.85), 0.08)
			_umbrella(out, ctx, w * 0.25, d * 0.34, FUN[2], 1.3)
			_umbrella(out, ctx, w * 0.38, d * 0.3, FUN[1], 1.3)

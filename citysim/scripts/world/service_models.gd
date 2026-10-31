class_name ServiceModels
extends RefCounted
## Procedural models of service and utility buildings, drawn through the
## building MultiMeshes. Each style lays out its pieces in lot coordinates:
## u across the lot (along ctx.dx), v towards the street (v = +depth/2 is the
## street edge), heights in metres. Extra meshes made here: tank (cylinder),
## dome, cooling tower, basin water, wind rotor, solar panel and smoke plume.

const ROTOR_SHADER := preload("res://assets/materials/rotor.gdshader")
const SOLAR_SHADER := preload("res://assets/materials/solar_panel.gdshader")
const SMOKE_SHADER := preload("res://assets/materials/smoke.gdshader")

## Lot ground look per style (lot_ground.gdshader kinds).
const LOT_KINDS := {
	"svc_coal": 7, "svc_gas": 7, "svc_wind": 8, "svc_solar": 7, "svc_pump": 3, "svc_outlet": 3,
	"svc_treatment": 3, "svc_clinic": 1, "svc_hospital": 1, "svc_school": 4, "svc_highschool": 4,
	"svc_university": 8, "svc_police": 2, "svc_fire": 3, "svc_landfill": 5, "svc_incinerator": 3,
	"svc_cemetery": 6, "svc_crematorium": 8,
}
## Meshes whose origin is at their base instead of their centre.
const BASE_ORIGIN := ["house_roof"]

const WHITE := Color(0.94, 0.95, 0.96)
const CONCRETE := Color(0.76, 0.75, 0.72)
const RED := Color(0.86, 0.17, 0.15)
const STEAM := Color(0.97, 0.97, 0.98, 0.9)
const SMOKE := Color(0.52, 0.52, 0.54, 0.8)
const DEBRIS: Array[Color] = [Color(0.2, 0.45, 0.85), Color(0.85, 0.25, 0.2), Color(0.95, 0.8, 0.2), Color(0.92, 0.92, 0.9), Color(0.3, 0.65, 0.3)]


static func lot_kind(style: String) -> int:
	return int(LOT_KINDS.get(style, 3))


# --- Meshes -------------------------------------------------------------------------

## Adds the extra meshes through add.call(key, mesh, colors, custom) and
## returns the keys that must not cast shadows.
static func build_meshes(add: Callable) -> PackedStringArray:
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.roughness = 0.8
	var tank := CylinderMesh.new()
	tank.top_radius = 0.5
	tank.bottom_radius = 0.5
	tank.height = 1.0
	tank.radial_segments = 16
	tank.rings = 1
	tank.material = plain
	add.call("tank", tank, true, false)

	var dome := lathe(_dome_profile(), 16)
	dome.surface_set_material(0, plain)
	add.call("dome", dome, true, false)
	# Landfill heaps: the dome shape in dull, rough earth.
	var earth := StandardMaterial3D.new()
	earth.vertex_color_use_as_albedo = true
	earth.roughness = 1.0
	earth.metallic_specular = 0.12
	earth.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var mound := lathe(_dome_profile(), 14)
	mound.surface_set_material(0, earth)
	add.call("mound", mound, true, false)

	# Open at the top, so its inside must be drawn as well.
	var cooling_mat := plain.duplicate() as StandardMaterial3D
	cooling_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cooling := lathe(_cooling_profile(), 20)
	cooling.surface_set_material(0, cooling_mat)
	add.call("cooling", cooling, true, false)

	var water_mat := StandardMaterial3D.new()
	water_mat.vertex_color_use_as_albedo = true
	water_mat.roughness = 0.3
	water_mat.metallic_specular = 0.5
	var basin := CylinderMesh.new()
	basin.top_radius = 0.5
	basin.bottom_radius = 0.5
	basin.height = 1.0
	basin.radial_segments = 20
	basin.rings = 1
	basin.material = water_mat
	add.call("basin", basin, true, false)

	var rotor_mat := ShaderMaterial.new()
	rotor_mat.shader = ROTOR_SHADER
	var rotor := _rotor_mesh()
	rotor.surface_set_material(0, rotor_mat)
	add.call("rotor", rotor, true, true)

	var solar_mat := ShaderMaterial.new()
	solar_mat.shader = SOLAR_SHADER
	var panel := BoxMesh.new()
	panel.material = solar_mat
	add.call("solar", panel, false, false)

	var smoke_noise := NoiseTexture2D.new()
	smoke_noise.width = 128
	smoke_noise.height = 128
	smoke_noise.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.022
	fnl.fractal_octaves = 3
	smoke_noise.noise = fnl
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = SMOKE_SHADER
	smoke_mat.set_shader_parameter("noise_tex", smoke_noise)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = smoke_mat
	add.call("smoke", quad, true, true)
	return PackedStringArray(["smoke", "basin"])


## Surface of revolution around y from (radius, y) points listed bottom to
## top, wound for Godot (clockwise front faces) with smooth normals.
static func lathe(profile: PackedVector2Array, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		for k in segments:
			var t0 := TAU * k / segments
			var t1 := TAU * (k + 1) / segments
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			var mid := (t0 + t1) * 0.5
			var out := Vector3(cos(mid), 0.0, sin(mid))
			if a.x > 1e-4:
				_tri(st, p00, p01, p11, out)
			if b.x > 1e-4:
				_tri(st, p00, p11, p10, out)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Quarter circle: radius 0.5 at the bottom (y = -0.5) to the apex at y = 0.5.
static func _dome_profile() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 8:
		var a := PI * 0.5 * i / 7.0
		out.append(Vector2(0.5 * cos(a), -0.5 + sin(a)))
	return out


## Hyperboloid cooling tower: wide base, waist at three quarters, flared lip.
static func _cooling_profile() -> PackedVector2Array:
	var out := PackedVector2Array()
	var waist_y := 0.25
	var waist := 0.31
	for i in 11:
		var y := -0.5 + i / 10.0
		var r: float
		if y <= waist_y:
			var k := (waist_y - y) / (waist_y + 0.5)
			r = waist + (0.5 - waist) * k * k
		else:
			var k := (y - waist_y) / (0.5 - waist_y)
			r = waist + (0.36 - waist) * k * k
		out.append(Vector2(r, y))
	return out


## Three tapered blades and a hub in the xy plane (radius 1, spin axis z).
static func _rotor_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var z := Vector3(0, 0, 0.014)
	for i in 3:
		var a := TAU * i / 3.0 + PI * 0.5
		var d := Vector3(cos(a), sin(a), 0)
		var w := Vector3(-sin(a), cos(a), 0)
		var r0 := 0.05
		var w0 := 0.05
		var w1 := 0.014
		_block(st, [d * r0 - w * w0, d * r0 + w * w0, d + w * w1, d - w * w1], z)
	var h := 0.065
	_block(st, [Vector3(-h, -h, 0), Vector3(h, -h, 0), Vector3(h, h, 0), Vector3(-h, h, 0)], Vector3(0, 0, h))
	st.generate_normals()
	return st.commit()


## Prism from a quad outline in the xy plane extruded by ±z.
static func _block(st: SurfaceTool, ring: Array, z: Vector3) -> void:
	var back: Array[Vector3] = []
	var front: Array[Vector3] = []
	var centre := Vector3.ZERO
	for p: Vector3 in ring:
		back.append(p - z)
		front.append(p + z)
		centre += p
	centre /= ring.size()
	var faces := [[back[0], back[1], back[2], back[3]], [front[0], front[1], front[2], front[3]]]
	for k in 4:
		var n := (k + 1) % 4
		faces.append([back[k], back[n], front[n], front[k]])
	for f: Array in faces:
		var fc: Vector3 = (f[0] + f[1] + f[2] + f[3]) / 4.0
		var out: Vector3 = fc - centre
		_tri(st, f[0], f[1], f[2], out)
		_tri(st, f[0], f[2], f[3], out)


# --- Layout helpers -------------------------------------------------------------------

static func _pos(ctx: Dictionary, u: float, v: float) -> Vector2:
	return (ctx["centre"] as Vector2) + (ctx["side"] as Vector2) * u + (ctx["f"] as Vector2) * v


## A unit piece of size w (across) x h x d (towards the street), bottom at y0,
## at lot coordinates (u, v). turn = true lays its x axis along the street
## direction instead (w then runs along v).
static func _put(parts: Array[Dictionary], ctx: Dictionary, key: String, u: float, v: float,
		w: float, h: float, d: float, color: Color, y0: float = 0.0, custom: Color = Color(), turn: bool = false) -> void:
	var e: float = ctx["e"]
	var p := _pos(ctx, u, v)
	var basis := Basis(ctx["dx"] * w, Vector3.UP * h * e, ctx["fz"] * d)
	if turn:
		basis = Basis(ctx["fz"] * w, Vector3.UP * h * e, -(ctx["dx"] as Vector3) * d)
	var y := y0 * e if key in BASE_ORIGIN else (y0 + h * 0.5) * e
	parts.append({"key": key, "xf": Transform3D(basis, Vector3(p.x, y, p.y)), "color": color, "custom": custom})


## Plume rising from (u, v) at height y_base; grows in at the end of construction.
static func _smoke(parts: Array[Dictionary], ctx: Dictionary, u: float, v: float, y_base: float,
		w: float, h: float, color: Color, seed: float) -> void:
	var e: float = ctx["e"]
	var p := _pos(ctx, u, v)
	var he := maxf(h * e * e * e, 0.01)
	parts.append({"key": "smoke", "xf": Transform3D(Basis(Vector3.RIGHT * w, Vector3.UP * he, Vector3.BACK),
		Vector3(p.x, y_base * e + he * 0.5, p.y)), "color": color, "custom": Color(fposmod(seed * 0.137, 1.0), 0, 0, 0)})


static func _shadow(parts: Array[Dictionary], ctx: Dictionary, u: float, v: float, w: float, d: float) -> void:
	var spread: float = ctx["spread"]
	var p := _pos(ctx, u, v)
	parts.append({"key": "contact", "xf": Transform3D(Basis(ctx["dx"] * (w + spread * 2.0), Vector3.UP, ctx["fz"] * (d + spread * 2.0)),
		Vector3(p.x, 0.07, p.y)), "color": Color.WHITE, "custom": Color(w, d, 0.0, 0.0)})


static func _facade(seed: float, ratio: float, spacing: float) -> Color:
	return Color(seed, ratio, spacing, 0.0)


static func _roof_units(parts: Array[Dictionary], ctx: Dictionary, u: float, v: float, w: float, d: float, h: float) -> void:
	var grey := Color(0.78, 0.8, 0.83)
	_put(parts, ctx, "roof_box", u - w * 0.18, v - d * 0.15, w * 0.24, 1.8, d * 0.24, grey, h)
	_put(parts, ctx, "roof_box", u + w * 0.25, v + d * 0.2, 1.4, 1.0, 1.4, grey.darkened(0.1), h)


static func _flag(parts: Array[Dictionary], ctx: Dictionary, u: float, v: float, h: float) -> void:
	_put(parts, ctx, "chimney", u, v, 0.16, h, 0.16, WHITE)
	_put(parts, ctx, "roof_box", u + 0.85, v, 1.6, 1.0, 0.06, Color(0.88, 0.1, 0.14), h - 1.1)


static func _car(parts: Array[Dictionary], ctx: Dictionary, u: float, v: float, body: Color, light: Color) -> void:
	_put(parts, ctx, "roof_box", u, v, 1.9, 1.1, 4.3, body, 0.25)
	_put(parts, ctx, "roof_box", u, v - 0.2, 1.6, 0.7, 2.2, Color(0.2, 0.24, 0.3), 1.35)
	_put(parts, ctx, "roof_box", u, v - 0.2, 1.2, 0.2, 0.4, light, 2.05)


static func _truck(parts: Array[Dictionary], ctx: Dictionary, u: float, v: float, body: Color) -> void:
	_put(parts, ctx, "roof_box", u, v, 2.4, 2.4, 7.4, body, 0.35)
	_put(parts, ctx, "roof_box", u, v + 3.0, 2.3, 1.0, 1.3, Color(0.2, 0.24, 0.3), 1.7)
	_put(parts, ctx, "roof_box", u, v - 0.6, 0.7, 0.35, 5.8, Color(0.8, 0.8, 0.82), 2.75)


## Direction (unit, in the ground plane) and distance from p to the nearest water.
static func _towards_water(p: Vector2) -> Array:
	var water := MapWater.shared()
	var d0 := water.distance(p)
	var g := Vector2(water.distance(p + Vector2(4, 0)) - water.distance(p - Vector2(4, 0)),
		water.distance(p + Vector2(0, 4)) - water.distance(p - Vector2(0, 4)))
	return [Vector2.ZERO if g.length() < 1e-4 else -g.normalized(), d0]


## Pipe from the lot centre into the nearest water; a dark stain where a
## sewage outlet empties.
static func _pipe_to_water(parts: Array[Dictionary], ctx: Dictionary, diameter: float, color: Color, stain: bool) -> void:
	var c: Vector2 = ctx["centre"]
	var hit := _towards_water(c)
	var dir: Vector2 = hit[0]
	if dir == Vector2.ZERO:
		return
	var length := clampf(float(hit[1]) + 5.0, 4.0, 70.0)
	var dir3 := Vector3(dir.x, 0.0, dir.y)
	var x := dir3.cross(Vector3.UP).normalized()
	var e: float = ctx["e"]
	var mid := c + dir * length * 0.5
	parts.append({"key": "tank", "xf": Transform3D(Basis(x * diameter, dir3 * length * e, Vector3.UP * diameter),
		Vector3(mid.x, 0.7, mid.y)), "color": color, "custom": Color()})
	if stain:
		var end := c + dir * length
		parts.append({"key": "contact", "xf": Transform3D(Basis(Vector3.RIGHT * 18.0, Vector3.UP, Vector3.BACK * 18.0),
			Vector3(end.x, 0.12, end.y)), "color": Color.WHITE, "custom": Color(7.0, 7.0, 0.0, 0.0)})


# --- Styles ------------------------------------------------------------------------------

static func parts(b: Dictionary, ctx: Dictionary, out: Array[Dictionary]) -> void:
	var s := float(b["seed"])
	var rng: RandomNumberGenerator = ctx["rng"]
	match str(b["style"]):
		"svc_coal":
			_put(out, ctx, "factory", -5, 5, 15, 14, 13, Color(0.66, 0.64, 0.6), 0, _facade(s, 0.3, 6.0))
			_put(out, ctx, "factory", -5, -6, 11, 24, 9, Color(0.54, 0.54, 0.56), 0, _facade(s + 3.0, 0.25, 6.0))
			_shadow(out, ctx, -5, 0, 15, 22)
			for k in 2:
				var cu := -11.5 + k * 4.0
				_put(out, ctx, "chimney", cu, -12, 2.8, 42, 2.8, CONCRETE)
				_put(out, ctx, "chimney", cu, -12, 2.45, 6, 2.45, RED, 42)
				_smoke(out, ctx, cu, -12, 48, 9, 44, SMOKE, s + k)
			_put(out, ctx, "cooling", 8.5, -7, 15, 26, 15, Color(0.82, 0.81, 0.78))
			_smoke(out, ctx, 8.5, -7, 25, 15, 50, STEAM, s + 5.0)
			_put(out, ctx, "mound", 9, 4, 11, 4, 8, Color(0.12, 0.12, 0.13))
			for k in 3:
				_put(out, ctx, "roof_box", 6 + k * 3.2, 12.5, 2.2, 2.6, 2.0, Color(0.55, 0.57, 0.6))
		"svc_gas":
			_put(out, ctx, "factory", -3.5, 4, 13, 11, 12, Color(0.86, 0.87, 0.89), 0, _facade(s, 0.35, 5.0))
			_put(out, ctx, "roof_box", -3.5, 4, 13.2, 1.0, 12.2, Color(0.2, 0.45, 0.78), 8.5)
			_shadow(out, ctx, -3.5, 4, 13, 12)
			for k in 2:
				var tv := -6.0 + k * 8.5
				_put(out, ctx, "tank", 7, tv, 6.5, 7, 6.5, WHITE)
				_put(out, ctx, "dome", 7, tv, 6.5, 1.6, 6.5, WHITE, 7)
			_put(out, ctx, "chimney", -8, -7.5, 2.2, 26, 2.2, Color(0.72, 0.73, 0.76))
			_smoke(out, ctx, -8, -7.5, 26, 7, 30, Color(0.86, 0.87, 0.9, 0.6), s)
			_put(out, ctx, "roof_box", 1.5, -8, 6, 1.0, 1.0, Color(0.55, 0.55, 0.58), 3)
		"svc_wind":
			var tower_h := 44.0
			_put(out, ctx, "tank", 0, 0, 4, 0.6, 4, CONCRETE)
			_put(out, ctx, "chimney", 0, 0, 2.2, tower_h, 2.2, Color(0.93, 0.94, 0.95))
			_put(out, ctx, "roof_box", 0, -0.6, 2.4, 2.6, 6.0, Color(0.93, 0.94, 0.95), tower_h)
			var e: float = ctx["e"]
			var r := 18.0 * e
			var p := _pos(ctx, 0, 2.6)
			out.append({"key": "rotor", "xf": Transform3D(Basis(ctx["dx"] * r, Vector3.UP * r, ctx["fz"] * r),
				Vector3(p.x, (tower_h + 1.3) * e, p.y)), "color": Color(0.96, 0.96, 0.97), "custom": Color(fposmod(s * 0.371, 1.0), 0, 0, 0)})
		"svc_solar":
			var e: float = ctx["e"]
			var tilt := Basis((ctx["dx"] as Vector3).normalized(), deg_to_rad(24.0))
			for k in 4:
				var p := _pos(ctx, 0, -8.4 + k * 5.4)
				out.append({"key": "solar", "xf": Transform3D(tilt * Basis(ctx["dx"] * 20.0 * e, Vector3.UP * 0.18 * e, ctx["fz"] * 4.2 * e),
					Vector3(p.x, 1.3 * e, p.y)), "color": Color.WHITE, "custom": Color()})
			for k in 2:
				_put(out, ctx, "roof_box", -8 + k * 3.5, 10.5, 2.2, 2.2, 1.6, Color(0.88, 0.89, 0.9))
		"svc_pump":
			_put(out, ctx, "house", -2, 2, 9, 5, 7, Color(0.6, 0.72, 0.82), 0, _facade(s, 0.5, 2.4))
			_put(out, ctx, "house_roof", -2, 2, 9.6, 2.4, 7.6, Color(0.22, 0.36, 0.56), 5)
			_shadow(out, ctx, -2, 2, 9, 7)
			_put(out, ctx, "tank", 4.5, -3.5, 5, 6.5, 5, Color(0.3, 0.53, 0.78))
			_put(out, ctx, "dome", 4.5, -3.5, 5, 1.2, 5, Color(0.3, 0.53, 0.78), 6.5)
			_pipe_to_water(out, ctx, 0.9, Color(0.36, 0.42, 0.48), false)
		"svc_outlet":
			_put(out, ctx, "factory", 0, 3, 6, 3.2, 6, CONCRETE, 0, _facade(s, 0.15, 5.0))
			_put(out, ctx, "roof_box", 0, 3, 3, 1.2, 3, Color(0.45, 0.5, 0.45), 3.2)
			_pipe_to_water(out, ctx, 1.4, Color(0.42, 0.42, 0.4), true)
		"svc_treatment":
			for k in 2:
				var bu := -5.5 + k * 11.0
				_put(out, ctx, "tank", bu, -5, 9.5, 1.8, 9.5, CONCRETE)
				_put(out, ctx, "basin", bu, -5, 8.6, 0.1, 8.6, Color(0.16, 0.32, 0.3), 1.62)
				_put(out, ctx, "roof_box", bu, -5, 9.0, 0.35, 0.7, Color(0.5, 0.5, 0.52), 1.95)
			_put(out, ctx, "office", -4, 6.5, 11, 6.5, 7, Color(0.88, 0.87, 0.83), 0, _facade(s, 0.5, 2.6))
			_shadow(out, ctx, -4, 6.5, 11, 7)
			_put(out, ctx, "roof_box", 6, 6, 8, 2.0, 6.5, CONCRETE)
			_put(out, ctx, "roof_box", 6, 6, 7.2, 0.1, 5.7, Color(0.28, 0.48, 0.43), 1.88)
			_pipe_to_water(out, ctx, 1.0, Color(0.4, 0.42, 0.44), false)
		"svc_clinic":
			_put(out, ctx, "office", 0, 1, 13, 8, 10, WHITE, 0, _facade(s, 0.55, 2.6))
			_shadow(out, ctx, 0, 1, 13, 10)
			_put(out, ctx, "roof_box", 0, 6.08, 2.6, 0.75, 0.16, RED, 5.6)
			_put(out, ctx, "roof_box", 0, 6.08, 0.75, 2.6, 0.16, RED, 4.68)
			_put(out, ctx, "roof_box", 3.5, 7.1, 4.5, 0.3, 2.2, WHITE, 3.4)
			_roof_units(out, ctx, 0, 1, 13, 10, 8)
		"svc_hospital":
			var h1 := 21.0
			_put(out, ctx, "office", 0, 3.5, 20, h1, 13, WHITE, 0, _facade(s, 0.6, 2.8))
			_put(out, ctx, "office", -3.5, -8.5, 13, 12, 11, Color(0.9, 0.92, 0.94), 0, _facade(s + 2.0, 0.5, 2.6))
			_shadow(out, ctx, 0, -2, 20, 24)
			_put(out, ctx, "roof_box", 0, 3.5, 7, 0.12, 2.2, RED, h1)
			_put(out, ctx, "roof_box", 0, 3.5, 2.2, 0.12, 7, RED, h1)
			_put(out, ctx, "roof_box", 0, 10.08, 3.2, 0.9, 0.16, RED, h1 - 4.0)
			_put(out, ctx, "roof_box", 0, 10.08, 0.9, 3.2, 0.16, RED, h1 - 5.15)
			_put(out, ctx, "tank", -3.5, -8.5, 9.4, 0.2, 9.4, WHITE, 12)
			_put(out, ctx, "tank", -3.5, -8.5, 8.4, 0.26, 8.4, Color(0.3, 0.31, 0.34), 12)
			for k in 2:
				_put(out, ctx, "roof_box", -4.8 + k * 2.6, -8.5, 0.45, 0.06, 3.6, WHITE, 12.26)
			_put(out, ctx, "roof_box", -3.5, -8.5, 2.6, 0.06, 0.45, WHITE, 12.26)
			_put(out, ctx, "roof_box", 0, 11.5, 8, 0.35, 3, WHITE, 3.8)
			_roof_units(out, ctx, 5, 6, 8, 5, h1)
		"svc_school":
			_put(out, ctx, "apartment", 0, 7, 14, 7, 8, Color(0.8, 0.44, 0.32), 0, _facade(s, 0.55, 2.6))
			_put(out, ctx, "house_roof", 0, 7, 14.6, 2.6, 8.6, Color(0.52, 0.28, 0.24), 7)
			_shadow(out, ctx, 0, 7, 14, 8)
			_put(out, ctx, "roof_box", 4, 11.6, 4, 0.3, 1.4, Color(0.95, 0.75, 0.2), 2.8)
			_flag(out, ctx, -7.2, 11.4, 9)
		"svc_highschool":
			_put(out, ctx, "apartment", -1, 7, 20, 10.5, 8, Color(0.84, 0.52, 0.36), 0, _facade(s, 0.55, 2.8))
			_put(out, ctx, "apartment", 9, 3.5, 4.5, 7.5, 6, Color(0.8, 0.48, 0.33), 0, _facade(s + 1.0, 0.5, 2.6))
			_put(out, ctx, "roof_box", -1, 7, 20.4, 0.6, 8.4, Color(0.95, 0.95, 0.92), 10.5)
			_shadow(out, ctx, 0, 6, 22, 9)
			_roof_units(out, ctx, -1, 7, 20, 8, 11.1)
			_flag(out, ctx, -11.2, 11.6, 10)
		"svc_university":
			var stone := Color(0.88, 0.82, 0.7)
			_put(out, ctx, "office", 0, -9, 20, 14, 11, stone, 0, _facade(s, 0.45, 3.0))
			_put(out, ctx, "tank", 0, -9, 7.6, 2.2, 7.6, stone, 14)
			_put(out, ctx, "dome", 0, -9, 7.6, 5, 7.6, Color(0.36, 0.6, 0.55), 16.2)
			_put(out, ctx, "chimney", 0, -9, 0.5, 2.5, 0.5, Color(0.86, 0.74, 0.38), 21.2)
			_shadow(out, ctx, 0, -9, 20, 11)
			for k in 6:
				_put(out, ctx, "tank", -6.25 + k * 2.5, -2.4, 0.9, 10, 0.9, Color(0.96, 0.94, 0.9))
			_put(out, ctx, "roof_box", 0, -2.4, 16, 1.4, 3.0, stone.lightened(0.1), 10)
			for side in [-1.0, 1.0]:
				_put(out, ctx, "apartment", side * 12.5, 4, 6, 10.5, 15, stone.darkened(0.04), 0, _facade(s + side, 0.5, 2.8))
				_put(out, ctx, "house_roof", side * 12.5, 4, 15.6, 2.4, 6.6, Color(0.5, 0.3, 0.25), 10.5, Color(), true)
				_shadow(out, ctx, side * 12.5, 4, 6, 15)
		"svc_police":
			_put(out, ctx, "office", 0, -3, 13, 7.6, 9, Color(0.32, 0.45, 0.72), 0, _facade(s, 0.5, 2.6))
			_put(out, ctx, "roof_box", 0, -3, 13.3, 0.7, 9.3, Color(0.93, 0.94, 0.97), 7.6)
			_put(out, ctx, "roof_box", 0, 1.58, 5.0, 0.9, 0.16, Color(0.95, 0.95, 1.0), 5.6)
			_put(out, ctx, "chimney", 4.5, -5, 0.25, 9, 0.25, Color(0.8, 0.8, 0.82), 8.3)
			_shadow(out, ctx, 0, -3, 13, 9)
			for k in 2:
				_car(out, ctx, -3.0 + k * 2.6, 4.8, Color(0.95, 0.95, 0.97), Color(0.15, 0.35, 0.9))
		"svc_fire":
			var red := Color(0.8, 0.18, 0.14)
			_put(out, ctx, "apartment", -1.5, -2, 12, 8, 11, red, 0, _facade(s, 0.4, 2.6))
			for k in 3:
				_put(out, ctx, "roof_box", -5.4 + k * 3.9, 3.58, 3.2, 4.4, 0.16, Color(0.92, 0.9, 0.85))
			_put(out, ctx, "roof_box", -1.5, -2, 12.3, 0.6, 11.3, Color(0.95, 0.95, 0.92), 8)
			_put(out, ctx, "apartment", 6, -4.5, 3.2, 15, 3.2, red.darkened(0.1), 0, _facade(s + 1.0, 0.3, 3.0))
			_shadow(out, ctx, -0.5, -2.5, 14, 12)
			_truck(out, ctx, -3.5, 5.6, red)
		"svc_landfill":
			var mounds := [[-6.0, -6.0, 17.0, 6.5, 15.0, Color(0.66, 0.52, 0.34)],
				[7.5, -3.0, 12.0, 4.5, 12.0, Color(0.6, 0.55, 0.36)], [-3.0, 6.0, 10.0, 3.0, 8.0, Color(0.5, 0.58, 0.32)]]
			for m: Array in mounds:
				_put(out, ctx, "mound", m[0], m[1], m[2], m[3], m[4], m[5])
			for k in 12:
				var m: Array = mounds[k % 2]
				var a := rng.randf() * TAU
				var rr := sqrt(rng.randf()) * 0.75
				var lift := float(m[3]) * sqrt(maxf(1.0 - rr * rr, 0.0)) - 0.35
				_put(out, ctx, "roof_box", float(m[0]) + cos(a) * rr * float(m[2]) * 0.5, float(m[1]) + sin(a) * rr * float(m[4]) * 0.5,
					rng.randf_range(0.8, 1.8), 0.6, rng.randf_range(0.8, 1.8), DEBRIS[k % DEBRIS.size()], lift)
			_put(out, ctx, "house", 11, 11, 6, 3.4, 5, Color(0.85, 0.82, 0.7), 0, _facade(s, 0.5, 2.4))
			_put(out, ctx, "house_roof", 11, 11, 6.4, 1.4, 5.4, Color(0.35, 0.4, 0.45), 3.4)
			_put(out, ctx, "roof_box", 3, 9, 2.6, 2.2, 4.2, Color(0.95, 0.72, 0.12), 0.3)
		"svc_incinerator":
			_put(out, ctx, "factory", -2, 3, 17, 13, 14, Color(0.58, 0.63, 0.58), 0, _facade(s, 0.3, 6.0))
			_put(out, ctx, "factory", -6, -7.5, 9, 8, 6, Color(0.5, 0.54, 0.5), 0, _facade(s + 1.0, 0.2, 6.0))
			_shadow(out, ctx, -2, 0, 17, 20)
			_put(out, ctx, "chimney", 7, -7, 3.2, 38, 3.2, Color(0.82, 0.82, 0.82))
			_put(out, ctx, "chimney", 7, -7, 3.0, 4, 3.0, RED, 34)
			_smoke(out, ctx, 7, -7, 38, 9, 38, SMOKE, s)
		"svc_cemetery":
			var grey := Color(0.66, 0.66, 0.68)
			for row in [-6.0, 0.0, 6.0]:
				for k in 4:
					for sgn in [-1.0, 1.0]:
						var u: float = sgn * (2.2 + k * 2.0)
						if row > 4.0 and u < -3.5:
							continue
						_put(out, ctx, "roof_box", u, row, 0.9, 1.0 + rng.randf() * 0.4, 0.28, grey * (0.9 + rng.randf() * 0.2))
			_put(out, ctx, "house", -7, 8.5, 5.5, 4.2, 6.5, Color(0.93, 0.92, 0.88), 0, _facade(s, 0.3, 2.0))
			_put(out, ctx, "house_roof", -7, 8.5, 7.0, 2.6, 6.0, Color(0.32, 0.32, 0.36), 4.2, Color(), true)
			_put(out, ctx, "chimney", -7, 11.2, 0.35, 4.5, 0.35, Color(0.32, 0.32, 0.36), 4.2)
			_shadow(out, ctx, -7, 8.5, 5.5, 6.5)
		"svc_crematorium":
			_put(out, ctx, "house", 0, 1.5, 12, 5, 8, Color(0.84, 0.82, 0.78), 0, _facade(s, 0.35, 2.4))
			_put(out, ctx, "roof_box", 0, 1.5, 12.4, 0.5, 8.4, Color(0.4, 0.4, 0.42), 5)
			_put(out, ctx, "chimney", 4, -4, 1.5, 15, 1.5, Color(0.62, 0.6, 0.58))
			_shadow(out, ctx, 0, 1.5, 12, 8)
			_smoke(out, ctx, 4, -4, 15, 4, 16, Color(0.8, 0.8, 0.82, 0.4), s)

extends Node3D
## Terrain: a flat ground covering the playable 4 km x 4 km map plus a locked
## ring that fades into the fog, rivers and lakes (MapWater) with sandy banks,
## a ring of mountains on the horizon, and the forest density map shared by the
## terrain shader (far canopy colour) and the vegetation system (tree spots).
## Also owns world <-> zoning cell conversion helpers.

const TERRAIN_SHADER := preload("res://assets/materials/terrain.gdshader")
const WATER_SHADER := preload("res://assets/materials/water.gdshader")
const MOUNTAIN_SHADER := preload("res://assets/materials/mountains.gdshader")

var cell_size: float
var playable_half: float
var forest_image: Image
var forest_extent: float
var _forest_bytes := PackedByteArray()
var _forest_size: int = 0

var _material: ShaderMaterial
var _albedo_noise: NoiseTexture2D
var _normal_noise: NoiseTexture2D


func _ready() -> void:
	cell_size = GameData.num("map/cell_size_m")
	playable_half = GameData.num("map/playable_size_m") * 0.5
	var extent := GameData.num("map/terrain_extent_m")
	_build_noise()
	_build_forest_mask()

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(extent, extent)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.material_override = _build_material()
	add_child(ground)
	_build_water()
	_build_mountains()

	EventBus.grid_overlay_toggled.connect(set_grid_visible)
	EventBus.graphics_preset_changed.connect(_apply_graphics)
	_apply_graphics(GraphicsSettings.current_preset)


func _apply_graphics(_preset: String) -> void:
	_material.set_shader_parameter("detail_enabled", bool(GraphicsSettings.get_value("terrain_detail")))


func _build_noise() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = GameData.integer("map/noise_seed")
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = GameData.num("map/noise_frequency")
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = GameData.integer("map/noise_octaves")
	var size := GameData.integer("map/noise_texture_size")
	_albedo_noise = NoiseTexture2D.new()
	_albedo_noise.width = size
	_albedo_noise.height = size
	_albedo_noise.seamless = true
	_albedo_noise.noise = noise
	_normal_noise = NoiseTexture2D.new()
	_normal_noise.width = size
	_normal_noise.height = size
	_normal_noise.seamless = true
	_normal_noise.as_normal_map = true
	_normal_noise.bump_strength = GameData.num("map/normal_bump_strength")
	_normal_noise.noise = noise


## Forest density 0..1 over a square around the map centre; no forest in or
## right next to water. Built once on start (a few ten thousand noise samples).
func _build_forest_mask() -> void:
	var cfg := GameData.section("map/forest")
	var size := int(cfg["mask_size"])
	forest_extent = float(cfg["mask_extent_m"])
	var noise := FastNoiseLite.new()
	noise.seed = int(cfg["seed"])
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(cfg["noise_frequency"])
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var threshold := float(cfg["threshold"])
	var water := MapWater.shared()
	forest_image = Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var p := (Vector2(x + 0.5, y + 0.5) / size - Vector2(0.5, 0.5)) * forest_extent
			var v := smoothstep(threshold, threshold + 0.18, noise.get_noise_2dv(p))
			# A wide margin keeps every tree spot (bilinear between pixels) out of the water.
			if v > 0.0 and water.distance(p) < float(cfg["water_margin_m"]):
				v = 0.0
			forest_image.set_pixel(x, y, Color(v, v, v))
	_forest_bytes = forest_image.get_data()
	_forest_size = size


## Forest density at a world point (bilinear), 0 outside the mask.
func forest_density(p: Vector2) -> float:
	var size := _forest_size
	var uv := (p / forest_extent + Vector2(0.5, 0.5)) * size - Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= size - 1 or uv.y >= size - 1:
		return 0.0
	var x0 := int(uv.x)
	var y0 := int(uv.y)
	var fx := uv.x - x0
	var fy := uv.y - y0
	var i := y0 * size + x0
	var a := lerpf(_forest_bytes[i], _forest_bytes[i + 1], fx)
	var b := lerpf(_forest_bytes[i + size], _forest_bytes[i + size + 1], fx)
	return lerpf(a, b, fy) / 255.0


func _build_material() -> ShaderMaterial:
	var water := GameData.section("map/water")
	var forest := GameData.section("map/forest")
	_material = ShaderMaterial.new()
	_material.shader = TERRAIN_SHADER
	_material.set_shader_parameter("noise_tex", _albedo_noise)
	_material.set_shader_parameter("noise_normal", _normal_noise)
	_material.set_shader_parameter("grass_a", GameData.color("map/grass_color_a"))
	_material.set_shader_parameter("grass_b", GameData.color("map/grass_color_b"))
	_material.set_shader_parameter("dry_grass", GameData.color("map/dry_grass_color"))
	_material.set_shader_parameter("dirt", GameData.color("map/dirt_color"))
	_material.set_shader_parameter("border_color", GameData.color("map/border_line_color"))
	_material.set_shader_parameter("grid_color", GameData.color("map/grid_line_color"))
	_material.set_shader_parameter("playable_half", playable_half)
	_material.set_shader_parameter("locked_darken", GameData.num("map/locked_area_darken"))
	_material.set_shader_parameter("locked_desaturate", GameData.num("map/locked_area_desaturate"))
	_material.set_shader_parameter("cell_size", cell_size)
	_material.set_shader_parameter("grid_fade_distance", GameData.num("map/grid_fade_distance_m"))
	_material.set_shader_parameter("base_roughness", GameData.num("map/roughness"))
	_material.set_shader_parameter("normal_strength", GameData.num("map/normal_strength"))
	_material.set_shader_parameter("grid_strength", 0.0)
	_material.set_shader_parameter("forest_mask", ImageTexture.create_from_image(forest_image))
	_material.set_shader_parameter("forest_extent", forest_extent)
	_material.set_shader_parameter("canopy_color", DataLoader.to_color(forest["canopy_color"]))
	_material.set_shader_parameter("canopy_strength", float(forest["canopy_strength"]))
	_material.set_shader_parameter("sand_color", DataLoader.to_color(water["sand_color"]))
	_material.set_shader_parameter("wet_sand_color", DataLoader.to_color(water["wet_sand_color"]))
	_material.set_shader_parameter("bank_width", float(water["bank_width_m"]))
	MapWater.shared().apply_to_material(_material)
	return _material


func _build_water() -> void:
	var cfg := GameData.section("map/water")
	var water := MapWater.shared()
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("wave_normal", _normal_noise)
	mat.set_shader_parameter("noise_tex", _albedo_noise)
	mat.set_shader_parameter("deep_color", DataLoader.to_color(cfg["deep_color"]))
	mat.set_shader_parameter("shallow_color", DataLoader.to_color(cfg["shallow_color"]))
	mat.set_shader_parameter("foam_color", DataLoader.to_color(cfg["foam_color"]))
	water.apply_to_material(mat)
	var y := float(cfg["water_level_m"])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var pts := water.river
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var na := _ribbon_normal(pts, i) * water.river_half
		var nb := _ribbon_normal(pts, i + 1) * water.river_half
		_quad(st, a + na, b + nb, b - nb, a - na, y)
	for l in water.lakes:
		var steps := 64
		for s in steps:
			var t0 := TAU * s / steps
			var t1 := TAU * (s + 1) / steps
			var c := Vector2(l.x, l.y)
			var p0 := c + Vector2(cos(t0) * l.z, sin(t0) * l.w)
			var p1 := c + Vector2(cos(t1) * l.z, sin(t1) * l.w)
			_tri(st, c, p0, p1, y)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _ribbon_normal(pts: PackedVector2Array, i: int) -> Vector2:
	var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
	return Vector2(-d.y, d.x)


## Adds a triangle facing up (Godot: clockwise seen from above).
static func _tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	var va := Vector3(a.x, y, a.y)
	var vb := Vector3(b.x, y, b.y)
	var vc := Vector3(c.x, y, c.y)
	if (vb - va).cross(vc - va).y > 0.0:
		var tmp := vb
		vb = vc
		vc = tmp
	st.add_vertex(va)
	st.add_vertex(vb)
	st.add_vertex(vc)


static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float) -> void:
	_tri(st, a, b, c, y)
	_tri(st, a, c, d, y)


## Ring of noise mountains beyond the playable map, rising from the plain.
func _build_mountains() -> void:
	var cfg := GameData.section("map/mountains")
	var inner := float(cfg["inner_radius_m"])
	var outer := float(cfg["outer_radius_m"])
	var radial := int(cfg["radial_steps"])
	var angular := int(cfg["angular_steps"])
	var max_h := float(cfg["max_height_m"])
	var noise := FastNoiseLite.new()
	noise.seed = int(cfg["seed"])
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(cfg["noise_frequency"])
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 4
	var grid: Array[PackedVector3Array] = []
	for r in radial + 1:
		var f := float(r) / radial
		var radius := lerpf(inner, outer, f)
		var ramp := smoothstep(0.0, 0.45, f)
		var row := PackedVector3Array()
		for a in angular:
			var ang := TAU * a / angular
			var p := Vector2(cos(ang), sin(ang)) * radius
			var n := clampf(noise.get_noise_2dv(p) * 0.5 + 0.5, 0.0, 1.0)
			row.append(Vector3(p.x, pow(n, 1.6) * max_h * ramp, p.y))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in radial:
		for a in angular:
			var a2 := (a + 1) % angular
			var v0 := grid[r][a]
			var v1 := grid[r][a2]
			var v2 := grid[r + 1][a2]
			var v3 := grid[r + 1][a]
			for tri: Array in [[v0, v1, v2], [v0, v2, v3]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				# Clockwise from above = front face for Godot.
				if (p1 - p0).cross(p2 - p0).y > 0.0:
					var tmp := p1
					p1 = p2
					p2 = tmp
				st.add_vertex(p0)
				st.add_vertex(p1)
				st.add_vertex(p2)
	st.index()
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = MOUNTAIN_SHADER
	mat.set_shader_parameter("grass_color", DataLoader.to_color(cfg["grass_color"]))
	mat.set_shader_parameter("rock_color", DataLoader.to_color(cfg["rock_color"]))
	mat.set_shader_parameter("snow_color", DataLoader.to_color(cfg["snow_color"]))
	mat.set_shader_parameter("snow_height", float(cfg["snow_height_m"]))
	mat.set_shader_parameter("noise_tex", _albedo_noise)
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func set_grid_visible(enabled: bool) -> void:
	_material.set_shader_parameter("grid_strength", GameData.num("map/grid_line_strength") if enabled else 0.0)


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return MapGrid.world_to_cell(world_pos, cell_size)


func is_inside_playable(world_pos: Vector3) -> bool:
	return MapGrid.is_inside(world_pos, playable_half)

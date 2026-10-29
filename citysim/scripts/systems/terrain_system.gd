extends Node3D
## Phase 1 terrain: a flat ground covering the playable 4 km x 4 km map plus a
## surrounding locked ring that fades into the fog. Also owns world <-> zoning
## cell conversion so later systems share one definition of the 8 m grid.

const TERRAIN_SHADER := preload("res://assets/materials/terrain.gdshader")

var cell_size: float
var playable_half: float

var _material: ShaderMaterial


func _ready() -> void:
	cell_size = GameData.num("map/cell_size_m")
	playable_half = GameData.num("map/playable_size_m") * 0.5
	var extent := GameData.num("map/terrain_extent_m")

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(extent, extent)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.material_override = _build_material()
	add_child(ground)

	EventBus.grid_overlay_toggled.connect(set_grid_visible)


func _build_material() -> ShaderMaterial:
	var noise := FastNoiseLite.new()
	noise.seed = GameData.integer("map/noise_seed")
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = GameData.num("map/noise_frequency")
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = GameData.integer("map/noise_octaves")

	var size := GameData.integer("map/noise_texture_size")
	var albedo_noise := NoiseTexture2D.new()
	albedo_noise.width = size
	albedo_noise.height = size
	albedo_noise.seamless = true
	albedo_noise.noise = noise
	var normal_noise := NoiseTexture2D.new()
	normal_noise.width = size
	normal_noise.height = size
	normal_noise.seamless = true
	normal_noise.as_normal_map = true
	normal_noise.bump_strength = GameData.num("map/normal_bump_strength")
	normal_noise.noise = noise

	_material = ShaderMaterial.new()
	_material.shader = TERRAIN_SHADER
	_material.set_shader_parameter("noise_tex", albedo_noise)
	_material.set_shader_parameter("noise_normal", normal_noise)
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
	return _material


func set_grid_visible(enabled: bool) -> void:
	_material.set_shader_parameter("grid_strength", GameData.num("map/grid_line_strength") if enabled else 0.0)


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return MapGrid.world_to_cell(world_pos, cell_size)


func is_inside_playable(world_pos: Vector3) -> bool:
	return MapGrid.is_inside(world_pos, playable_half)

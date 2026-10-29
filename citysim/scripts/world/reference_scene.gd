extends Node3D
## DEBUG / placeholder scenery for Phase 1 only: a small grid of PBR blocks,
## sidewalks and trees so lighting, shadows, fog, scale and the night window
## lights can be judged on device. Replaced by real roads (Phase 2) and grown
## buildings (Phase 3). Toggle with data/reference_scene.json -> "enabled".
## Everything is drawn with MultiMesh (one draw call per kind).

const BUILDING_SHADER := preload("res://assets/materials/building_placeholder.gdshader")
const FOLIAGE_SHADER := preload("res://assets/materials/tree_foliage.gdshader")
const CONTACT_SHADER := preload("res://assets/materials/contact_shadow.gdshader")
const ASPHALT_SHADER := preload("res://assets/materials/asphalt.gdshader")

var _rng := RandomNumberGenerator.new()
var _cfg: Dictionary
var _building_mmi: MultiMeshInstance3D
var _tree_mmi: MultiMeshInstance3D


func _ready() -> void:
	_cfg = GameData.section("reference_scene")
	if not bool(_cfg["enabled"]):
		queue_free()
		return
	_rng.seed = int(_cfg["seed"])
	_build()
	_apply_graphics(GraphicsSettings.current_preset)
	EventBus.graphics_preset_changed.connect(_apply_graphics)


func _build() -> void:
	var cell := GameData.num("map/cell_size_m")
	var blocks_x := int(_cfg["blocks_x"])
	var blocks_z := int(_cfg["blocks_z"])
	var block_w := int(_cfg["block_cells_x"]) * cell
	var block_d := int(_cfg["block_cells_z"]) * cell
	var street := float(_cfg["street_width_m"])
	var walk := float(_cfg["sidewalk_width_m"])
	var curb := float(_cfg["sidewalk_height_m"])
	var park: Array = _cfg["park_block"]
	var total_w := blocks_x * (block_w + street)
	var total_d := blocks_z * (block_d + street)

	var buildings: Array[Dictionary] = []
	var slabs: Array[Transform3D] = []
	var slab_colors: Array[Color] = []
	var trees: Array[Vector3] = []
	var sidewalk_color := DataLoader.to_color(_cfg["sidewalk_color"])
	var grass_color := DataLoader.to_color(_cfg["park_grass_color"])

	for bi in blocks_x:
		for bj in blocks_z:
			var x0 := -total_w * 0.5 + street * 0.5 + bi * (block_w + street)
			var z0 := -total_d * 0.5 + street * 0.5 + bj * (block_d + street)
			var center := Vector3(x0 + block_w * 0.5, 0.0, z0 + block_d * 0.5)
			slabs.append(_box(center + Vector3(0, curb * 0.5, 0), Vector3(block_w + walk * 2.0, curb, block_d + walk * 2.0)))
			slab_colors.append(sidewalk_color)
			_add_street_trees(trees, center, block_w + walk, block_d + walk, curb)
			if bi == int(park[0]) and bj == int(park[1]):
				slabs.append(_box(center + Vector3(0, curb + 0.02, 0), Vector3(block_w, 0.04, block_d)))
				slab_colors.append(grass_color)
				for i in int(_cfg["park_tree_count"]):
					trees.append(Vector3(x0 + _rng.randf() * block_w, curb, z0 + _rng.randf() * block_d))
			else:
				_add_block_lots(buildings, x0, z0, block_w, block_d, cell, curb)

	_add_asphalt(total_w, total_d)
	_add_slabs(slabs, slab_colors)
	_add_buildings(buildings)
	_add_contact_shadows(buildings, curb)
	_add_trees(trees)


func _box(center: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), center)


func _add_block_lots(out: Array[Dictionary], x0: float, z0: float, w: float, d: float, cell: float, base_y: float) -> void:
	var setback := float(_cfg["lot_setback_m"])
	var row_depth := d * 0.5
	for row in 2:
		var cx := 0.0
		while cx < w - 0.01:
			var lot_cells := _rng.randi_range(int(_cfg["lot_min_cells"]), int(_cfg["lot_max_cells"]))
			var lot_w := minf(lot_cells * cell, w - cx)
			var center := Vector3(x0 + cx + lot_w * 0.5, 0.0, z0 + row_depth * (row + 0.5))
			var height := _lot_height(center)
			out.append({
				"center": center + Vector3(0.0, base_y + height * 0.5, 0.0),
				"size": Vector3(lot_w - setback * 2.0, height, row_depth - setback * 2.0),
			})
			cx += lot_w


func _lot_height(center: Vector3) -> float:
	var falloff := float(_cfg["tower_falloff_m"])
	var centrality := exp(-Vector2(center.x, center.z).length() / falloff)
	var fmin := int(_cfg["floors_min"])
	var fmax := int(_cfg["floors_max"])
	var r := _rng.randf()
	var floors := fmin + int((fmax - fmin) * centrality * r * r)
	if centrality > 0.5 and _rng.randf() < float(_cfg["tower_chance"]):
		floors = int(lerpf(fmax * 0.6, fmax, _rng.randf()))
	return float(_cfg["ground_floor_height_m"]) + maxi(floors - 1, 1) * float(_cfg["residential_floor_height_m"])


func _add_street_trees(out: Array[Vector3], center: Vector3, w: float, d: float, y: float) -> void:
	var spacing := float(_cfg["street_tree_spacing_m"])
	var hx := w * 0.5
	var hz := d * 0.5
	var x := -hx + spacing
	while x < hx - spacing * 0.5:
		out.append(center + Vector3(x, y, -hz))
		out.append(center + Vector3(x, y, hz))
		x += spacing
	var z := -hz + spacing
	while z < hz - spacing * 0.5:
		out.append(center + Vector3(-hx, y, z))
		out.append(center + Vector3(hx, y, z))
		z += spacing


func _add_asphalt(total_w: float, total_d: float) -> void:
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.noise = FastNoiseLite.new()
	var mat := ShaderMaterial.new()
	mat.shader = ASPHALT_SHADER
	mat.set_shader_parameter("noise_tex", noise)
	mat.set_shader_parameter("base_color", DataLoader.to_color(_cfg["asphalt_color"]))
	mat.set_shader_parameter("patch_color", DataLoader.to_color(_cfg["asphalt_patch_color"]))
	var plane := PlaneMesh.new()
	plane.size = Vector2(total_w, total_d)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_slabs(transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82
	var mesh := BoxMesh.new()
	mesh.material = mat
	var mm := _new_multimesh(mesh, transforms.size(), true, false)
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _add_buildings(buildings: Array[Dictionary]) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = BUILDING_SHADER
	mat.set_shader_parameter("glass_color", DataLoader.to_color(_cfg["glass_color"]))
	mat.set_shader_parameter("light_color", DataLoader.to_color(_cfg["window_light_color"]))
	mat.set_shader_parameter("light_energy", float(_cfg["window_light_energy"]))
	mat.set_shader_parameter("floor_height", float(_cfg["residential_floor_height_m"]))
	mat.set_shader_parameter("ground_floor_height", float(_cfg["ground_floor_height_m"]))
	mat.set_shader_parameter("lit_ratio", float(_cfg["lit_window_ratio"]))
	var mesh := BoxMesh.new()
	mesh.material = mat
	var palette: Array = _cfg["wall_palette"]
	var mm := _new_multimesh(mesh, buildings.size(), true, true)
	for i in buildings.size():
		var b := buildings[i]
		mm.set_instance_transform(i, _box(b["center"], b["size"]))
		mm.set_instance_color(i, DataLoader.to_color(palette[_rng.randi_range(0, palette.size() - 1)]))
		mm.set_instance_custom_data(i, _facade_style(b["size"]))
	_building_mmi = MultiMeshInstance3D.new()
	_building_mmi.multimesh = mm
	add_child(_building_mmi)


## Per-building facade parameters packed for the shader (see INSTANCE_CUSTOM).
func _facade_style(size: Vector3) -> Color:
	var curtain := 0.0
	if size.y >= float(_cfg["curtain_wall_min_height_m"]) and _rng.randf() < float(_cfg["curtain_wall_chance"]):
		curtain = 1.0
	return Color(
		_rng.randf() * 100.0,
		_rng.randf_range(float(_cfg["window_ratio_min"]), float(_cfg["window_ratio_max"])),
		_rng.randf_range(float(_cfg["window_spacing_min_m"]), float(_cfg["window_spacing_max_m"])),
		curtain)


func _add_contact_shadows(buildings: Array[Dictionary], ground_y: float) -> void:
	var spread := float(_cfg["contact_shadow_spread_m"])
	var mat := ShaderMaterial.new()
	mat.shader = CONTACT_SHADER
	mat.set_shader_parameter("spread", spread)
	mat.set_shader_parameter("strength", float(_cfg["contact_shadow_strength"]))
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := _new_multimesh(quad, buildings.size(), false, true)
	for i in buildings.size():
		var size: Vector3 = buildings[i]["size"]
		var c: Vector3 = buildings[i]["center"]
		var basis := Basis.from_scale(Vector3(size.x + spread * 2.0, 1.0, size.z + spread * 2.0))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(c.x, ground_y + 0.02, c.z)))
		mm.set_instance_custom_data(i, Color(size.x, size.z, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_trees(positions: Array[Vector3]) -> void:
	var mm := _new_multimesh(_build_tree_mesh(), positions.size(), true, false)
	var colors: Array = _cfg["tree_colors"]
	var smin := float(_cfg["tree_scale_min"])
	var smax := float(_cfg["tree_scale_max"])
	for i in positions.size():
		var s := _rng.randf_range(smin, smax)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.15), s))
		mm.set_instance_transform(i, Transform3D(basis, positions[i]))
		var c := DataLoader.to_color(colors[_rng.randi_range(0, colors.size() - 1)])
		mm.set_instance_color(i, c * _rng.randf_range(0.88, 1.08))
	_tree_mmi = MultiMeshInstance3D.new()
	_tree_mmi.multimesh = mm
	add_child(_tree_mmi)


func _build_tree_mesh() -> ArrayMesh:
	var trunk_h := float(_cfg["tree_trunk_height_m"])
	var crown_r := float(_cfg["tree_crown_radius_m"])
	var mesh := ArrayMesh.new()

	var trunk := CylinderMesh.new()
	var trunk_r := float(_cfg["tree_trunk_radius_m"])
	trunk.top_radius = trunk_r * 0.6
	trunk.bottom_radius = trunk_r
	trunk.height = trunk_h + crown_r
	trunk.radial_segments = 5
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, trunk.height * 0.5, 0)))
	st.commit(mesh)

	var blob := SphereMesh.new()
	blob.radius = crown_r
	blob.height = crown_r * 1.7
	blob.radial_segments = 9
	blob.rings = 6
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lumps := [
		[Vector3(0, trunk_h + crown_r * 0.8, 0), 0.85],
		[Vector3(crown_r * 0.55, trunk_h + crown_r * 0.5, crown_r * 0.2), 0.6],
		[Vector3(-crown_r * 0.45, trunk_h + crown_r * 0.6, -crown_r * 0.4), 0.62],
		[Vector3(-crown_r * 0.2, trunk_h + crown_r * 0.45, crown_r * 0.55), 0.55],
		[Vector3(crown_r * 0.25, trunk_h + crown_r * 1.25, -crown_r * 0.15), 0.55],
		[Vector3(-crown_r * 0.3, trunk_h + crown_r * 1.15, crown_r * 0.2), 0.5],
	]
	for lump: Array in lumps:
		var s: float = lump[1]
		st.append_from(blob, 0, Transform3D(Basis.from_scale(Vector3(s, s, s)), lump[0]))
	st.commit(mesh)

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = DataLoader.to_color(_cfg["tree_trunk_color"])
	trunk_mat.roughness = 0.95
	var crown_mat := ShaderMaterial.new()
	crown_mat.shader = FOLIAGE_SHADER
	crown_mat.set_shader_parameter("crown_base", trunk_h)
	crown_mat.set_shader_parameter("crown_top", trunk_h + crown_r * 1.8)
	crown_mat.set_shader_parameter("wobble", float(_cfg["tree_wobble_m"]))
	crown_mat.set_shader_parameter("ao_min", float(_cfg["tree_ao_min"]))
	mesh.surface_set_material(0, trunk_mat)
	mesh.surface_set_material(1, crown_mat)
	return mesh


func _new_multimesh(mesh: Mesh, count: int, colors: bool, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _apply_graphics(_preset: String) -> void:
	var detail := float(GraphicsSettings.get_value("detail_draw_distance_m"))
	var trees := float(GraphicsSettings.get_value("tree_draw_distance_m"))
	_building_mmi.visibility_range_end = detail
	_tree_mmi.visibility_range_end = trees

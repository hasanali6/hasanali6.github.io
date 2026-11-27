class_name PowerLines
extends Node3D
## Wooden electricity poles with wires along the streets whose network has
## power, on the side across from the street lamps. Redrawn when the set of
## powered roads changes (EventBus.services_changed, roads_changed). Poles
## and wires vanish beyond the preset's detail distance like other clutter.

const ROOF_SHADER := preload("res://assets/materials/roof.gdshader")
const SKIP_TYPES := ["highway", "overpass"]

var _services: Node
var _net: Node
var _poles: MultiMeshInstance3D
var _wires: MultiMeshInstance3D
var _mat: ShaderMaterial
var _signature: int = 0
var _cfg: Dictionary


func setup(services: Node, net: Node) -> void:
	_services = services
	_net = net
	_cfg = GameData.section("services/power_lines")
	_mat = ShaderMaterial.new()
	_mat.shader = ROOF_SHADER
	_mat.set_shader_parameter("roughness", 0.9)
	var height := float(_cfg["pole_height_m"])
	var pole := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.09
	shaft.bottom_radius = 0.13
	shaft.height = height
	shaft.radial_segments = 5
	shaft.rings = 1
	shaft.cap_bottom = false
	st.append_from(shaft, 0, Transform3D(Basis(), Vector3(0, height * 0.5, 0)))
	var bar := BoxMesh.new()
	bar.size = Vector3(0.1, 0.1, 1.5)
	st.append_from(bar, 0, Transform3D(Basis(), Vector3(0, height - 0.35, 0)))
	st.commit(pole)
	pole.surface_set_material(0, _mat)
	_poles = _make(pole, "PowerPoles")
	var wire := BoxMesh.new()
	wire.size = Vector3(1.0, 1.0, 1.0)
	wire.material = _mat
	_wires = _make(wire, "PowerWires")
	_apply_distance()
	EventBus.services_changed.connect(_refresh)
	EventBus.roads_changed.connect(func() -> void:
		_signature = 0
		_refresh())
	EventBus.graphics_preset_changed.connect(func(_p: String) -> void: _apply_distance())


func _make(mesh: Mesh, node_name: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _apply_distance() -> void:
	_mat.set_shader_parameter("detail_hide_distance", float(GraphicsSettings.get_value("detail_draw_distance_m")))


## Road segments that carry power (their network has supply).
func powered_segments() -> PackedInt32Array:
	var out := PackedInt32Array()
	var graph: RoadGraph = _net.graph
	for seg: RoadGraph.RoadSegment in graph.segments.values():
		if seg.type in SKIP_TYPES or graph.is_elevated(seg.id):
			continue
		var s: Dictionary = _services._supply_done.get(_services.network_of_segment.get(seg.id, -1), {})
		if not s.is_empty() and float(s["power"]) > 0.0:
			out.append(seg.id)
	return out


func _refresh() -> void:
	var segs := powered_segments()
	var sig := hash(segs)
	if sig == _signature:
		return
	_signature = sig
	var graph: RoadGraph = _net.graph
	var spacing := float(_cfg["spacing_m"])
	var height := float(_cfg["pole_height_m"])
	var wood := Color(0.36, 0.27, 0.2).srgb_to_linear()
	var cable := Color(0.12, 0.12, 0.13)
	var poles: Array[Transform3D] = []
	var wires: Array[Transform3D] = []
	for sid: int in segs:
		var seg: RoadGraph.RoadSegment = graph.segments[sid]
		var t: Dictionary = _net.type_config(seg.type)
		var trim_a := RoadMeshBuilder.junction_radius(graph, seg.a, _net.types, _net.mesh_cfg)
		var trim_b := RoadMeshBuilder.junction_radius(graph, seg.b, _net.types, _net.mesh_cfg)
		var usable := seg.length - trim_a - trim_b
		if usable < spacing * 0.5:
			continue
		var count := maxi(floori(usable / spacing), 1) + 1
		var hw := RoadTypes.half_width(t) - 0.45
		var prev := Vector3.INF
		for i in count:
			var s := trim_a + usable * float(i) / float(count - 1) if count > 1 else seg.length * 0.5
			var tt := s / seg.length
			var p := graph.point_on(seg.id, tt)
			var d := graph.tangent_on(seg.id, tt)
			var left := Vector2(-d.y, d.x)
			# Across the road from the lamps (they stand on the left side).
			var base := p - left * hw
			var along := Vector3(d.x, 0, d.y)
			var basis := Basis(Vector3.UP.cross(along), Vector3.UP, along)
			poles.append(Transform3D(basis, Vector3(base.x, 0.0, base.y)))
			var top := Vector3(base.x, height - 0.3, base.y)
			if prev != Vector3.INF:
				var mid := (prev + top) * 0.5
				var span := top - prev
				var z := span.normalized()
				var x := Vector3.UP.cross(z).normalized()
				# Two thin cables, one on each end of the cross bar.
				for k in [-0.6, 0.6]:
					wires.append(Transform3D(Basis(x * 0.035, Vector3.UP * 0.035, z * span.length()), mid + x * k))
			prev = top
	_fill(_poles.multimesh, poles, wood)
	_fill(_wires.multimesh, wires, cable)


func _fill(mm: MultiMesh, transforms: Array[Transform3D], color: Color) -> void:
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, color)

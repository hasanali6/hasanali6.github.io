extends Node3D
## People walking on the sidewalks (decoration). Streets in front of busy
## buildings get more walkers: residents plus workers of the buildings on a
## street, one walker per `people_per_walker`, up to `max_per_segment`; the
## busiest streets are served first up to a cap per quality preset. Each
## walker strolls there and back along a stretch of sidewalk; the movement
## runs in the shader on the game clock (traffic_time), so it pauses with the
## game. Rebuilt monthly and after road or building changes.

const SHADER := preload("res://assets/materials/pedestrian.gdshader")
const CAP := {"low": 400, "medium": 1200, "high": 2500}
const PEOPLE_PER_WALKER := 12.0
const MAX_PER_SEGMENT := 10
const SIDEWALK_Y := 0.16

@export var road_network_path: NodePath
@export var building_system_path: NodePath

var _net: Node
var _buildings: Node
var _mmi: MultiMeshInstance3D
var _pending := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_net = get_node(road_network_path)
	_buildings = get_node(building_system_path)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _person_mesh()
	mm.custom_aabb = AABB(Vector3(-2600, -5, -2600), Vector3(5200, 20, 5200))
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Walkers"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	EventBus.month_changed.connect(func(_m: int) -> void: _queue())
	EventBus.buildings_changed.connect(_queue)
	EventBus.graphics_preset_changed.connect(func(_p: String) -> void: _queue())
	_queue()


func _queue() -> void:
	if _pending:
		return
	_pending = true
	get_tree().create_timer(1.0).timeout.connect(_rebuild)


func _rebuild() -> void:
	_pending = false
	var people := {}
	for b: Dictionary in _buildings.buildings.values():
		var seg := int(b.get("segment", -1))
		if seg < 0 or b.get("abandoned", false):
			continue
		var n := int(b.get("residents", b.get("occupants", 0))) + int(b.get("employees", 0))
		if n > 0:
			people[seg] = int(people.get(seg, 0)) + n
	var segs := people.keys()
	segs.sort_custom(func(a: int, c: int) -> bool: return int(people[a]) > int(people[c]))
	var cap := int(CAP.get(GraphicsSettings.current_preset, 1200))
	var rg: RoadGraph = _net.graph
	var xforms: Array = []
	var custom: Array = []
	_rng.seed = 4242
	for sid: int in segs:
		if xforms.size() >= cap:
			break
		var seg: RoadGraph.RoadSegment = rg.segments.get(sid)
		if seg == null:
			continue
		var t: Dictionary = _net.type_config(seg.type)
		var walk_w := float(t.get("sidewalk_width_m", 0.0))
		if walk_w < 1.0:
			continue
		var offset := RoadTypes.carriageway_width(t) * 0.5 + walk_w * 0.5
		var count := mini(int(ceil(float(people[sid]) / PEOPLE_PER_WALKER)), MAX_PER_SEGMENT)
		for k in count:
			if xforms.size() >= cap:
				break
			var side := 1.0 if k % 2 == 0 else -1.0
			var t0 := _rng.randf_range(0.08, 0.7)
			var span := minf(_rng.randf_range(12.0, 36.0) / maxf(seg.length, 1.0), 0.9 - t0)
			if span <= 0.02:
				continue
			var a := _side_point(rg, sid, t0, offset * side + _rng.randf_range(-0.25, 0.25))
			var b := _side_point(rg, sid, t0 + span, offset * side + _rng.randf_range(-0.25, 0.25))
			var d := b - a
			if d.length() < 2.0:
				continue
			var z := Vector3(d.x, 0, d.y).normalized()
			xforms.append(Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), Vector3(a.x, SIDEWALK_Y, a.y)))
			custom.append(Color(d.length(), _rng.randf_range(1.0, 1.5), _rng.randf(), _rng.randf()))
	var mm := _mmi.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, custom[i])


func _side_point(rg: RoadGraph, sid: int, t: float, offset: float) -> Vector2:
	var p := rg.point_on(sid, t)
	var d := rg.tangent_on(sid, t).normalized()
	return p + Vector2(-d.y, d.x) * offset


## A person 1.75 m tall facing +z: legs, shirt and head (part id in UV.x).
static func _person_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(side * 0.1, 0.43, 0), Vector3(0.15, 0.86, 0.2), 0.0)
	_box(st, Vector3(0, 1.17, 0), Vector3(0.46, 0.64, 0.26), 1.0)
	_box(st, Vector3(0, 1.6, 0), Vector3(0.22, 0.24, 0.22), 2.0)
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	m.surface_set_material(0, mat)
	return m


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, part: float) -> void:
	var h := s * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		var q: Array[Vector3] = [corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]]]
		var out := ((q[0] + q[1] + q[2] + q[3]) * 0.25 - c).normalized()
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var a := q[tri[0]]
			var b := q[tri[1]]
			var cc := q[tri[2]]
			if (b - a).cross(cc - a).dot(out) > 0.0:
				var tmp := b
				b = cc
				cc = tmp
			for v: Vector3 in [a, b, cc]:
				st.set_uv(Vector2(part, 0.0))
				st.set_normal(out)
				st.add_vertex(v)

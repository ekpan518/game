class_name TireTrail
extends Node3D

const MAX_SAMPLES := 48
const SAMPLE_LIFETIME := 1.2
const MIN_SAMPLE_DISTANCE := 0.12
const RIBBON_WIDTH := 0.105

var left_samples: Array[Dictionary] = []
var right_samples: Array[Dictionary] = []

var _left_mesh: ImmediateMesh
var _right_mesh: ImmediateMesh
var _material: StandardMaterial3D
var _left_break := true
var _right_break := true

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	_left_mesh = _make_ribbon("LeftRibbon")
	_right_mesh = _make_ribbon("RightRibbon")

func set_trail_state(active: bool, left_world: Vector3, right_world: Vector3, delta: float) -> void:
	_age_samples(left_samples, delta)
	_age_samples(right_samples, delta)
	if active:
		_left_break = _add_sample(left_samples, left_world, _left_break)
		_right_break = _add_sample(right_samples, right_world, _right_break)
	else:
		_left_break = true
		_right_break = true
	_draw_ribbon(_left_mesh, left_samples)
	_draw_ribbon(_right_mesh, right_samples)

func clear() -> void:
	left_samples.clear()
	right_samples.clear()
	_left_break = true
	_right_break = true
	if _left_mesh != null:
		_left_mesh.clear_surfaces()
	if _right_mesh != null:
		_right_mesh.clear_surfaces()

func _make_ribbon(node_name: String) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.top_level = true
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.mesh = mesh
	add_child(instance)
	return mesh

func _age_samples(samples: Array[Dictionary], delta: float) -> void:
	for index in range(samples.size() - 1, -1, -1):
		var sample := samples[index]
		sample.age += maxf(delta, 0.0)
		if sample.age >= SAMPLE_LIFETIME:
			samples.remove_at(index)
		else:
			samples[index] = sample
	if not samples.is_empty():
		samples[0].break_before = true

func _add_sample(samples: Array[Dictionary], world_point: Vector3, break_before: bool) -> bool:
	if not samples.is_empty() and samples.back().point.distance_to(world_point) < MIN_SAMPLE_DISTANCE:
		return break_before
	samples.append({"point": world_point, "age": 0.0, "break_before": break_before})
	if samples.size() > MAX_SAMPLES:
		samples.remove_at(0)
		samples[0].break_before = true
	return false

func _draw_ribbon(mesh: ImmediateMesh, samples: Array[Dictionary]) -> void:
	mesh.clear_surfaces()
	if samples.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for index in range(1, samples.size()):
		var current := samples[index]
		if current.break_before:
			continue
		var previous := samples[index - 1]
		var start: Vector3 = previous.point
		var finish: Vector3 = current.point
		var direction := finish - start
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			continue
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * (RIBBON_WIDTH * 0.5)
		var old_color := Color(0.025, 0.025, 0.035, 0.38 * (1.0 - previous.age / SAMPLE_LIFETIME))
		var new_color := Color(0.025, 0.025, 0.035, 0.38 * (1.0 - current.age / SAMPLE_LIFETIME))
		_vertex(mesh, start - side, old_color)
		_vertex(mesh, start + side, old_color)
		_vertex(mesh, finish + side, new_color)
		_vertex(mesh, start - side, old_color)
		_vertex(mesh, finish + side, new_color)
		_vertex(mesh, finish - side, new_color)
	mesh.surface_end()

func _vertex(mesh: ImmediateMesh, point: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(point)

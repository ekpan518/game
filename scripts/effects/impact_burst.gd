class_name ImpactBurst
extends Node3D

const SOUND_FACTORY = preload("res://scripts/audio/arcade_sound_factory.gd")
const MIN_PITCH_SCALE := 0.96
const MAX_PITCH_SCALE := 1.04

static var _shared_pitch_rng := RandomNumberGenerator.new()
static var _shared_pitch_rng_seeded := false

signal finished(effect: ImpactBurst)

@onready var ring: MeshInstance3D = $Ring
@onready var sparks: CPUParticles3D = $Sparks
@onready var audio: AudioStreamPlayer3D = $Audio

var _elapsed := 0.0
var _duration := 0.0
var _ring_material: StandardMaterial3D
var _spark_material: StandardMaterial3D
var _pending_feedback: ImpactFeedback
var _ring_size := 1.0

func _ready() -> void:
	var ring_source := TorusMesh.new()
	ring_source.inner_radius = 0.91
	ring_source.outer_radius = 1.0
	ring_source.rings = 8
	ring_source.ring_segments = 24
	var ring_arrays := ring_source.surface_get_arrays(0)
	var ring_rotation := Basis(Vector3.RIGHT, PI / 2.0)
	var vertices: PackedVector3Array = ring_arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = ring_arrays[Mesh.ARRAY_NORMAL]
	for index in vertices.size():
		vertices[index] = ring_rotation * vertices[index]
		normals[index] = ring_rotation * normals[index]
	ring_arrays[Mesh.ARRAY_VERTEX] = vertices
	ring_arrays[Mesh.ARRAY_NORMAL] = normals
	var ring_mesh := ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ring_arrays)
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.no_depth_test = true
	_ring_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_ring_material.billboard_keep_scale = true
	ring_mesh.surface_set_material(0, _ring_material)
	ring.mesh = ring_mesh
	ring.position.y = 0.85
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	_spark_material = StandardMaterial3D.new()
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material = _spark_material
	sparks.mesh = spark_mesh
	sparks.one_shot = true
	sparks.amount = 14
	sparks.lifetime = 0.25
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.0
	_hide_effect()
	if _pending_feedback != null:
		call_deferred("_play_pending")

func play(feedback: ImpactFeedback) -> void:
	if not is_node_ready():
		_pending_feedback = feedback
		return
	reset_for_pool()
	global_position = feedback.world_position
	var strength := clampf(feedback.normalized_strength, 0.0, 1.0)
	var tier := feedback.tier
	var color := Color(0.65, 0.9, 1.0)
	_duration = 0.18
	_ring_size = 0.8
	if tier == ImpactFeedback.Tier.HEAVY:
		color = Color(1.0, 0.76, 0.3)
		_duration = 0.25
		_ring_size = 1.4
	elif tier == ImpactFeedback.Tier.SMASH:
		color = Color(1.0, 0.32, 0.19)
		_duration = 0.34
		_ring_size = 2.0
	_ring_material.albedo_color = color
	_spark_material.albedo_color = color
	ring.scale = Vector3.ONE * (0.10 + 0.10 * strength) * _ring_size
	ring.visible = true
	sparks.amount = 8 + int(18.0 * strength)
	sparks.initial_velocity_min = 1.5 + 2.0 * strength
	sparks.initial_velocity_max = 2.5 + 3.0 * strength
	sparks.restart()
	sparks.emitting = true
	audio.stream = SOUND_FACTORY.get_impact_stream(tier)
	audio.pitch_scale = _next_pitch_scale()
	audio.play()
	visible = true
	set_process(true)

func reset_for_pool() -> void:
	_pending_feedback = null
	_hide_effect()

func _hide_effect() -> void:
	set_process(false)
	_elapsed = 0.0
	visible = false
	if is_node_ready():
		ring.visible = false
		sparks.emitting = false
		audio.stop()
		audio.pitch_scale = 1.0

static func _next_pitch_scale() -> float:
	if not _shared_pitch_rng_seeded:
		_shared_pitch_rng.seed = 0x51A7C0DE
		_shared_pitch_rng_seeded = true
	return _shared_pitch_rng.randf_range(MIN_PITCH_SCALE, MAX_PITCH_SCALE)

func _play_pending() -> void:
	if _pending_feedback != null:
		play(_pending_feedback)

func _process(delta: float) -> void:
	_elapsed += delta
	var progress := minf(1.0, _elapsed / _duration)
	ring.scale = Vector3.ONE * lerpf(0.16, 0.9, progress) * _ring_size
	var color := _ring_material.albedo_color
	color.a = 1.0 - progress
	_ring_material.albedo_color = color
	if _elapsed >= _duration:
		reset_for_pool()
		finished.emit(self)

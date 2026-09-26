class_name ImpactBurst
extends Node3D

const SOUND_FACTORY = preload("res://scripts/audio/arcade_sound_factory.gd")

signal finished(effect: ImpactBurst)

@onready var ring: MeshInstance3D = $Ring
@onready var sparks: CPUParticles3D = $Sparks
@onready var audio: AudioStreamPlayer3D = $Audio

var _elapsed := 0.0
var _duration := 0.0
var _ring_material: StandardMaterial3D
var _spark_material: StandardMaterial3D

func _ready() -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.91
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 24
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mesh.material = _ring_material
	ring.mesh = ring_mesh
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
	reset_for_pool()

func play(feedback: ImpactFeedback) -> void:
	reset_for_pool()
	global_position = feedback.world_position
	var strength := clampf(feedback.normalized_strength, 0.0, 1.0)
	var tier := feedback.tier
	var color := Color(0.65, 0.9, 1.0)
	_duration = 0.18
	if tier == ImpactFeedback.Tier.HEAVY:
		color = Color(1.0, 0.76, 0.3)
		_duration = 0.25
	elif tier == ImpactFeedback.Tier.SMASH:
		color = Color(1.0, 0.32, 0.19)
		_duration = 0.34
	_ring_material.albedo_color = color
	_spark_material.albedo_color = color
	ring.scale = Vector3.ONE * (0.10 + 0.10 * strength)
	ring.visible = true
	sparks.amount = 8 + int(18.0 * strength)
	sparks.initial_velocity_min = 1.5 + 2.0 * strength
	sparks.initial_velocity_max = 2.5 + 3.0 * strength
	sparks.restart()
	sparks.emitting = true
	audio.stream = SOUND_FACTORY.get_impact_stream(tier)
	audio.play()
	visible = true
	set_process(true)

func reset_for_pool() -> void:
	set_process(false)
	_elapsed = 0.0
	visible = false
	if is_node_ready():
		ring.visible = false
		sparks.emitting = false
		audio.stop()

func _process(delta: float) -> void:
	_elapsed += delta
	var progress := minf(1.0, _elapsed / _duration)
	ring.scale = Vector3.ONE * lerpf(0.16, 0.9, progress)
	var color := _ring_material.albedo_color
	color.a = 1.0 - progress
	_ring_material.albedo_color = color
	if _elapsed >= _duration:
		reset_for_pool()
		finished.emit(self)

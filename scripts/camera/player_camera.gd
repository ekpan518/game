extends Node3D

const MOUSE_SENSITIVITY := 0.0025
const MIN_PITCH := deg_to_rad(-60.0)
const MAX_PITCH := deg_to_rad(45.0)
const MAX_SHAKE_RADIANS := deg_to_rad(2.5)
const MAX_FOV_KICK := 4.0
const TRAUMA_DECAY := 1.5
const SHAKE_THRESHOLD := 0.22
const SPEED_LINE_THRESHOLD := 0.58
const MAX_POSITION_OFFSET := 0.18
const FORWARD_PUSH_DECAY := 2.5
const SMASH_PULSE_DECAY := 6.0

@onready var camera_pitch: Node3D = $CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPitch/SpringArm3D/Camera3D
@onready var speed_overlay: ColorRect = get_parent().get_node("SpeedLines/Overlay")

var trauma := 0.0
var _base_yaw := 0.0
var _base_pitch := 0.0
var _base_fov := 70.0
var _base_position := Vector3.ZERO
var _shake_time := 0.0
var _yaw_offset := 0.0
var _pitch_offset := 0.0
var _position_offset := Vector3.ZERO
var _impact_local_direction := Vector3.ZERO
var _forward_push := 0.0
var _smash_pulse := 0.0

func _ready() -> void:
	_base_yaw = rotation.y
	_base_pitch = camera_pitch.rotation.x
	_base_fov = camera.fov
	_base_position = position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var car := get_parent() as CollisionObject3D
	if car != null:
		spring_arm.add_excluded_object(car.get_rid())

func _process(delta: float) -> void:
	trauma = move_toward(trauma, 0.0, TRAUMA_DECAY * maxf(delta, 0.0))
	_forward_push = move_toward(_forward_push, 0.0, FORWARD_PUSH_DECAY * maxf(delta, 0.0))
	_smash_pulse = move_toward(_smash_pulse, 0.0, SMASH_PULSE_DECAY * maxf(delta, 0.0))
	_shake_time += maxf(delta, 0.0)
	_update_feedback_transform()
	var car := get_parent() as BumperCar
	if car == null or not car.alive or car.get("_frozen_for_result"):
		set_speed_ratio(0.0)
		speed_overlay.visible = false
		return
	speed_overlay.visible = true
	var horizontal_speed := Vector2(car.velocity.x, car.velocity.z).length()
	set_speed_ratio(horizontal_speed / BumperCar.MAX_FORWARD_SPEED)

func apply_impact_feedback(strength: float, delivered: bool, received: bool, direction: Vector3 = Vector3.ZERO, tier: int = ImpactFeedback.Tier.HEAVY) -> void:
	var normalized := clampf(strength, 0.0, 1.0)
	if normalized < SHAKE_THRESHOLD or not (delivered or received):
		return
	var weight := 0.9 if delivered and received else (0.75 if received else 0.45)
	trauma = minf(1.0, trauma + normalized * weight)
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if not horizontal_direction.is_zero_approx():
		var local_direction := global_transform.basis.inverse() * horizontal_direction.normalized()
		local_direction.y = 0.0
		_impact_local_direction = local_direction.normalized() if not local_direction.is_zero_approx() else Vector3.ZERO
	if delivered:
		_forward_push = maxf(_forward_push, normalized)
	if tier == ImpactFeedback.Tier.SMASH:
		_smash_pulse = maxf(_smash_pulse, normalized)
	_update_feedback_transform()

func set_speed_ratio(ratio: float) -> void:
	var progress := clampf((ratio - SPEED_LINE_THRESHOLD) / (1.0 - SPEED_LINE_THRESHOLD), 0.0, 1.0)
	var intensity := progress * progress * (3.0 - 2.0 * progress)
	(speed_overlay.material as ShaderMaterial).set_shader_parameter("intensity", intensity)

func reset_feedback() -> void:
	trauma = 0.0
	_yaw_offset = 0.0
	_pitch_offset = 0.0
	_position_offset = Vector3.ZERO
	_impact_local_direction = Vector3.ZERO
	_forward_push = 0.0
	_smash_pulse = 0.0
	position = _base_position
	rotation.y = _base_yaw
	camera_pitch.rotation.x = _base_pitch
	camera.fov = _base_fov
	set_speed_ratio(0.0)

func _update_feedback_transform() -> void:
	var amount := trauma * trauma
	var directional_yaw := _impact_local_direction.x * MAX_SHAKE_RADIANS * amount * 0.8
	var local_noise := sin(_shake_time * 37.0) * MAX_SHAKE_RADIANS * amount * 0.15
	_yaw_offset = clampf(directional_yaw + local_noise, -MAX_SHAKE_RADIANS, MAX_SHAKE_RADIANS)
	_pitch_offset = sin(_shake_time * 49.0 + 1.0) * MAX_SHAKE_RADIANS * amount
	_position_offset.x = clampf(_impact_local_direction.x * amount * 0.12, -MAX_POSITION_OFFSET, MAX_POSITION_OFFSET)
	_position_offset.y = _smash_pulse * 0.025
	_position_offset.z = -minf(MAX_POSITION_OFFSET, _forward_push * 0.12 + _smash_pulse * 0.05)
	if _position_offset.length() > MAX_POSITION_OFFSET:
		_position_offset = _position_offset.normalized() * MAX_POSITION_OFFSET
	position = _base_position + _position_offset
	rotation.y = _base_yaw + _yaw_offset
	camera_pitch.rotation.x = _base_pitch + _pitch_offset
	camera.fov = _base_fov + MAX_FOV_KICK * minf(1.0, amount + _smash_pulse * 0.20)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_captured_mouse_motion(event.relative)

func apply_captured_mouse_motion(relative: Vector2) -> void:
	_base_yaw -= relative.x * MOUSE_SENSITIVITY
	_base_pitch = clamp_pitch_radians(_base_pitch - relative.y * MOUSE_SENSITIVITY)
	rotation.y = _base_yaw + _yaw_offset
	camera_pitch.rotation.x = _base_pitch + _pitch_offset

func clamp_pitch_radians(angle: float) -> float:
	return clampf(angle, MIN_PITCH, MAX_PITCH)

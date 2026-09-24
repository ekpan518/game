class_name BumperCar
extends CharacterBody3D

signal contact_reported(reporter: BumperCar, other: BumperCar, contact_normal: Vector3, reporter_velocity: Vector3, physics_frame: int)

const MAX_FORWARD_SPEED := 12.0
const MAX_REVERSE_SPEED := 5.0
const DRIVE_ACCELERATION := 18.0
const BRAKE_DECELERATION := 24.0
const COAST_DECELERATION := 8.0
const MAX_STEERING_RATE := deg_to_rad(120.0)
const MIN_STEERING_FACTOR := 0.35
const KNOCKBACK_DECAY := 10.0
const MAX_EXTERNAL_SPEED := 18.0

@export var stable_id: int = -1
@export var body_color := Color(0.16, 0.55, 0.95, 1.0)
@export var driver_path: NodePath

var longitudinal_speed := 0.0
var external_velocity := Vector3.ZERO
var power_stacks := 0
var alive := true
var driver: DriverController

var _frozen_for_result := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_snapshot_frame := -1
var _current_snapshot_velocity := Vector3.ZERO
var _previous_snapshot_frame := -1
var _previous_snapshot_velocity := Vector3.ZERO
var _combat_velocity := Vector3.ZERO
var _body_material: StandardMaterial3D

@onready var _body: MeshInstance3D = $Visuals/Body
@onready var _power_label: Label3D = $Visuals/PowerLabel

func _ready() -> void:
	_prepare_body_material()
	_update_power_visuals()
	if not driver_path.is_empty():
		set_driver(get_node_or_null(driver_path) as DriverController)

func _physics_process(delta: float) -> void:
	if not alive or _frozen_for_result:
		return
	var command := DriveCommand.create(0.0, 0.0)
	if is_instance_valid(driver):
		command = driver.get_command(self, delta)
	longitudinal_speed = step_longitudinal_speed(longitudinal_speed, command.throttle, delta)
	rotate_y(-command.steering * steering_rate_for_speed(absf(longitudinal_speed)) * delta)
	external_velocity = external_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	if external_velocity.length() > MAX_EXTERNAL_SPEED:
		external_velocity = external_velocity.normalized() * MAX_EXTERNAL_SPEED
	var vertical_speed := velocity.y
	if is_on_floor():
		vertical_speed = 0.0
	else:
		vertical_speed -= _gravity * delta
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var horizontal_velocity := forward * longitudinal_speed + external_velocity
	velocity = Vector3(horizontal_velocity.x, vertical_speed, horizontal_velocity.z)
	var physics_frame := Engine.get_physics_frames()
	_capture_snapshot(physics_frame, horizontal_velocity)
	move_and_slide()
	_combat_velocity = Vector3(velocity.x, 0.0, velocity.z)
	_report_slide_collisions(physics_frame, horizontal_velocity)

static func step_longitudinal_speed(current_speed: float, throttle: float, delta: float) -> float:
	var clamped_throttle := clampf(throttle, -1.0, 1.0)
	if clamped_throttle > 0.0:
		if current_speed < 0.0:
			return move_toward(current_speed, 0.0, BRAKE_DECELERATION * clamped_throttle * delta)
		return minf(current_speed + DRIVE_ACCELERATION * clamped_throttle * delta, MAX_FORWARD_SPEED)
	if clamped_throttle < 0.0:
		if current_speed > 0.0:
			return move_toward(current_speed, 0.0, BRAKE_DECELERATION * -clamped_throttle * delta)
		return maxf(current_speed + DRIVE_ACCELERATION * clamped_throttle * delta, -MAX_REVERSE_SPEED)
	return move_toward(current_speed, 0.0, COAST_DECELERATION * delta)

static func steering_rate_for_speed(speed: float) -> float:
	var speed_factor := clampf(absf(speed) / MAX_FORWARD_SPEED, 0.0, 1.0)
	return lerpf(MAX_STEERING_RATE * MIN_STEERING_FACTOR, MAX_STEERING_RATE, speed_factor)

func set_driver(new_driver: DriverController) -> void:
	driver = new_driver

func apply_knockback(impulse: Vector3) -> void:
	if not alive or _frozen_for_result:
		return
	var horizontal_impulse := Vector3(impulse.x, 0.0, impulse.z)
	external_velocity += horizontal_impulse
	if external_velocity.length() > MAX_EXTERNAL_SPEED:
		external_velocity = external_velocity.normalized() * MAX_EXTERNAL_SPEED

func set_power_stacks(stacks: int) -> void:
	power_stacks = BumperRules.clamp_stacks(stacks)
	_update_power_visuals()

func eliminate() -> bool:
	if not alive:
		return false
	alive = false
	_stop_motion()
	collision_layer = 0
	collision_mask = 0
	visible = false
	set_physics_process(false)
	return true

func freeze_for_result() -> void:
	if not alive:
		return
	_frozen_for_result = true
	_stop_motion()
	set_physics_process(false)

func get_combat_velocity() -> Vector3:
	return _combat_velocity

func has_snapshot_for_frame(physics_frame: int) -> bool:
	return (_current_snapshot_frame >= 0 and physics_frame == _current_snapshot_frame) or (_previous_snapshot_frame >= 0 and physics_frame == _previous_snapshot_frame)

func get_snapshot_for_frame(physics_frame: int) -> Vector3:
	if physics_frame == _current_snapshot_frame:
		return _current_snapshot_velocity
	if physics_frame == _previous_snapshot_frame:
		return _previous_snapshot_velocity
	return Vector3.ZERO

func _capture_snapshot(physics_frame: int, combat_velocity: Vector3) -> void:
	if physics_frame != _current_snapshot_frame:
		_previous_snapshot_frame = _current_snapshot_frame
		_previous_snapshot_velocity = _current_snapshot_velocity
		_current_snapshot_frame = physics_frame
	_current_snapshot_velocity = combat_velocity

func _report_slide_collisions(physics_frame: int, reporter_velocity: Vector3) -> void:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var other := collision.get_collider() as BumperCar
		if other == null or not other.alive:
			continue
		contact_reported.emit(self, other, -collision.get_normal(), reporter_velocity, physics_frame)

func _prepare_body_material() -> void:
	var source_material := _body.material_override as StandardMaterial3D
	if source_material == null and _body.mesh != null:
		source_material = _body.mesh.surface_get_material(0) as StandardMaterial3D
	if source_material != null:
		_body_material = source_material.duplicate() as StandardMaterial3D
	else:
		_body_material = StandardMaterial3D.new()
	_body.material_override = _body_material

func _update_power_visuals() -> void:
	if _power_label != null:
		_power_label.text = str(power_stacks)
	if _body_material == null:
		return
	_body_material.albedo_color = body_color
	_body_material.emission_enabled = power_stacks > 0
	_body_material.emission = body_color
	_body_material.emission_energy_multiplier = 0.5 + power_stacks * 0.5

func _stop_motion() -> void:
	longitudinal_speed = 0.0
	external_velocity = Vector3.ZERO
	_combat_velocity = Vector3.ZERO
	velocity = Vector3.ZERO

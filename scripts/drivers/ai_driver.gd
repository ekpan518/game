class_name AIDriver
extends DriverController

const ARENA_RADIUS := 12.0
const SAFE_RADIUS := 9.36
const EMERGENCY_RADIUS := 10.8
const TARGET_LEAD_SECONDS := 0.35
const STUCK_SPEED := 0.5
const STUCK_DELAY := 1.25
const RECOVERY_SECONDS := 0.75
const BEHIND_THROTTLE := 0.35
const SAFE_THROTTLE := 0.65

var _match_controller: MatchController
var _arena_center := Vector3.ZERO
var _stuck_elapsed := 0.0
var _recovery_remaining := 0.0

func bind_match(match_controller: MatchController) -> void:
	_match_controller = match_controller
	_reset_recovery()

func set_arena_center(center: Vector3) -> void:
	_arena_center = center

func get_command(car: BumperCar, delta: float) -> DriveCommand:
	if not is_instance_valid(_match_controller) or not is_instance_valid(car) or not car.alive:
		_reset_recovery()
		return DriveCommand.create(0.0, 0.0)
	var target := _nearest_live_opponent(car)
	if target == null:
		_reset_recovery()
		return DriveCommand.create(0.0, 0.0)

	var from_center := car.global_position - _arena_center
	from_center.y = 0.0
	var radius := from_center.length()
	if radius > EMERGENCY_RADIUS or is_equal_approx(radius, EMERGENCY_RADIUS):
		_reset_recovery()
		return _edge_command(car, -from_center, 1.0)
	if radius > SAFE_RADIUS or is_equal_approx(radius, SAFE_RADIUS):
		var outward := from_center / radius
		var radial_velocity := car.get_combat_velocity()
		radial_velocity.y = 0.0
		if radial_velocity.dot(outward) >= 0.0:
			_reset_recovery()
			return _edge_command(car, -from_center, SAFE_THROTTLE)

	var predicted_target := target.global_position + target.get_combat_velocity() * TARGET_LEAD_SECONDS
	var desired := predicted_target - car.global_position
	desired.y = 0.0
	var throttle := 1.0
	if not desired.is_zero_approx():
		var forward := -car.global_transform.basis.z
		forward.y = 0.0
		if not forward.is_zero_approx() and forward.normalized().dot(desired.normalized()) < 0.0:
			throttle = BEHIND_THROTTLE
	var requested := _command_toward(car, desired, throttle)
	return _apply_stuck_recovery(car, requested, maxf(delta, 0.0))

func _nearest_live_opponent(car: BumperCar) -> BumperCar:
	var nearest: BumperCar
	var nearest_distance_squared := INF
	for candidate in _match_controller.get_live_opponents_for(car):
		if not is_instance_valid(candidate) or candidate == car or not candidate.alive:
			continue
		var offset := candidate.global_position - car.global_position
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		if nearest == null or distance_squared < nearest_distance_squared or (is_equal_approx(distance_squared, nearest_distance_squared) and candidate.stable_id < nearest.stable_id):
			nearest = candidate
			nearest_distance_squared = distance_squared
	return nearest

func _command_toward(car: BumperCar, desired: Vector3, throttle: float) -> DriveCommand:
	return DriveCommand.create(throttle, _steering_toward(car, desired))

func _edge_command(car: BumperCar, desired: Vector3, inward_throttle: float) -> DriveCommand:
	var horizontal_desired := Vector3(desired.x, 0.0, desired.z)
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	var throttle := -1.0
	if not horizontal_desired.is_zero_approx() and not forward.is_zero_approx():
		if forward.normalized().dot(horizontal_desired.normalized()) > 0.0:
			throttle = inward_throttle
	return _command_toward(car, horizontal_desired, throttle)

func _steering_toward(car: BumperCar, desired: Vector3) -> float:
	var horizontal_desired := Vector3(desired.x, 0.0, desired.z)
	if horizontal_desired.is_zero_approx():
		return 0.0
	horizontal_desired = horizontal_desired.normalized()
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	var right := car.global_transform.basis.x
	right.y = 0.0
	if forward.is_zero_approx() or right.is_zero_approx():
		return 0.0
	forward = forward.normalized()
	right = right.normalized()
	var angle := atan2(horizontal_desired.dot(right), horizontal_desired.dot(forward))
	return clampf(angle / (PI * 0.5), -1.0, 1.0)

func _apply_stuck_recovery(car: BumperCar, requested: DriveCommand, delta: float) -> DriveCommand:
	if _recovery_remaining > 0.0:
		return _recovery_command(car, delta)
	var combat_velocity := car.get_combat_velocity()
	combat_velocity.y = 0.0
	if requested.throttle > 0.5 and combat_velocity.length() < STUCK_SPEED:
		_stuck_elapsed += delta
		if _stuck_elapsed >= STUCK_DELAY:
			_stuck_elapsed = 0.0
			_recovery_remaining = RECOVERY_SECONDS
			return _recovery_command(car, delta)
	else:
		_stuck_elapsed = 0.0
	return requested

func _recovery_command(car: BumperCar, delta: float) -> DriveCommand:
	var recovery_turn := 1.0 if car.stable_id > 0 and car.stable_id % 2 == 0 else -1.0
	_recovery_remaining = maxf(_recovery_remaining - delta, 0.0)
	if is_zero_approx(_recovery_remaining):
		_recovery_remaining = 0.0
	return DriveCommand.create(-1.0, recovery_turn)

func _reset_recovery() -> void:
	_stuck_elapsed = 0.0
	_recovery_remaining = 0.0

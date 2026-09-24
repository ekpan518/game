class_name BumperRules
extends RefCounted

const IMPACT_RESULT_SCRIPT = preload("res://scripts/bumper/impact_result.gd")

const MAX_POWER_STACKS := 3
const EFFECTIVE_ATTACK_SPEED := 2.0
const IMPULSE_PER_MPS := 0.9
const MAX_KNOCKBACK_SPEED := 14.0

static func clamp_stacks(stacks: int) -> int:
	return clampi(stacks, 0, MAX_POWER_STACKS)

static func outgoing_multiplier(stacks: int) -> float:
	return 1.0 + 0.15 * clamp_stacks(stacks)

static func incoming_multiplier(stacks: int) -> float:
	return 1.0 - 0.08 * clamp_stacks(stacks)

static func pair_key(first_id: int, second_id: int) -> String:
	return "%d:%d" % [mini(first_id, second_id), maxi(first_id, second_id)]

static func calculate_attack(attacker_velocity: Vector3, defender_velocity: Vector3, attacker_to_defender: Vector3, attacker_stacks: int, defender_stacks: int) -> RefCounted:
	var result := IMPACT_RESULT_SCRIPT.new()
	var horizontal_direction := Vector3(attacker_to_defender.x, 0.0, attacker_to_defender.z)
	if horizontal_direction.is_zero_approx():
		return result
	horizontal_direction = horizontal_direction.normalized()
	var approach_speed := attacker_velocity.dot(horizontal_direction)
	var relative_closing_speed := (attacker_velocity - defender_velocity).dot(horizontal_direction)
	result.approach_speed = approach_speed
	if approach_speed <= 0.0:
		return result
	var impulse_magnitude := maxf(relative_closing_speed, 0.0) * IMPULSE_PER_MPS
	impulse_magnitude *= outgoing_multiplier(attacker_stacks) * incoming_multiplier(defender_stacks)
	impulse_magnitude = minf(impulse_magnitude, MAX_KNOCKBACK_SPEED)
	result.impulse = horizontal_direction * impulse_magnitude
	result.effective = approach_speed >= EFFECTIVE_ATTACK_SPEED and relative_closing_speed >= EFFECTIVE_ATTACK_SPEED
	return result
